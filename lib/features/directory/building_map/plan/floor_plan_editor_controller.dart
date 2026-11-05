import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset, Size;

import '../../../../core/database/floor_plan_objects_repository.dart';
import '../../../../core/database/floor_plan_placements_repository.dart';
import '../../../../core/database/floor_plan_ports_repository.dart';
import '../../../../core/database/floor_plan_repository.dart';
import '../../../../core/models/floor_plan_element.dart';
import '../../../../core/models/floor_plan_object.dart';
import '../../../../core/models/floor_plan_object_kind.dart';
import '../../../../core/models/floor_plan_placement.dart';
import '../../../../core/models/floor_plan_port.dart';
import '../../../../core/models/floor_plan_state.dart';
import 'floor_plan_cabinet.dart';
import 'floor_plan_geometry.dart';
import 'floor_plan_layers.dart';
import 'floor_plan_objects.dart';
import 'floor_plan_ports.dart';
import 'floor_plan_rooms.dart' show polygonContains;
import 'floor_plan_selection.dart';
import 'floor_plan_stack.dart';
import 'services/floor_plan_pattern_cache.dart';

/// Τα εργαλεία της οθόνης σχεδίασης.
enum FloorPlanTool {
  /// Κλικ σε στοιχείο για επιλογή· σύρσιμο στο κενό μετακινεί τον καμβά.
  select,
  wall,
  opening,

  /// Χώρος: διπλό κλικ μέσα σε κλειστούς τοίχους ή κλικ στις γωνίες.
  room,

  /// Ελεύθερο κείμενο: κλικ και πληκτρολόγηση.
  text,

  /// Γραμμή διάστασης: κλικ στα δύο άκρα και τρίτο κλικ για την απόσταση.
  dimension,

  /// Μέτρηση απόστασης της στιγμής (π.χ. μήκος καλωδίου): κλικ σε κάθε
  /// στροφή, Enter ή διπλό κλικ για τέλος. Δεν αποθηκεύεται.
  measure,

  /// Γραμμή πάνω σε κάτι γνωστό, για την κλίμακα του πατρόν.
  calibrate,

  /// Σύρσιμο του πατρόν ώστε να ταιριάξει με το σχέδιο.
  movePattern,

  /// Τοποθέτηση αντικειμένου του είδους που διαλέχτηκε: κλικ για σύμβολο,
  /// δύο γωνίες για έπιπλο.
  object,

  /// Τοποθέτηση υπαλλήλων, τηλεφώνων και εξοπλισμού από τον Κατάλογο, με το
  /// πάνελ στα δεξιά.
  place,
}

/// Μία ενέργεια στη στοίβα αναίρεσης: πώς ήταν τα στοιχεία που άγγιξε
/// ([before]) και πώς έγιναν ([after]). Νέο στοιχείο υπάρχει μόνο στο
/// [after], σβησμένο μόνο στο [before], αλλαγμένο και στα δύο με το ίδιο id.
/// Τα αντικείμενα ([objectsBefore], [objectsAfter]) με τον ίδιο τρόπο: μία
/// μετακίνηση στοιχείων και αντικειμένων μαζί είναι μία αναίρεση.
/// Η αναίρεση γράφει κι αυτή αμέσως στη βάση.
class _PlanChange {
  const _PlanChange({
    this.before = const [],
    this.after = const [],
    this.objectsBefore = const [],
    this.objectsAfter = const [],
    this.placementsBefore = const [],
    this.placementsAfter = const [],
    this.portsBefore = const [],
    this.portsAfter = const [],
    this.cablesBefore = const [],
    this.cablesAfter = const [],
  });

  final List<FloorPlanElement> before;
  final List<FloorPlanElement> after;
  final List<FloorPlanObject> objectsBefore;
  final List<FloorPlanObject> objectsAfter;
  final List<FloorPlanPlacement> placementsBefore;
  final List<FloorPlanPlacement> placementsAfter;

  /// Οι θύρες με τον ίδιο τρόπο: η διαγραφή ενός switch παίρνει και τις
  /// θύρες του, και η αναίρεση τις φέρνει πίσω.
  final List<FloorPlanPort> portsBefore;
  final List<FloorPlanPort> portsAfter;

  /// Και τα καλώδια: η πρίζα που σβήνεται επιστρέφει δεμένη με το patch panel.
  final List<FloorPlanCable> cablesBefore;
  final List<FloorPlanCable> cablesAfter;

  _PlanChange get inverse => _PlanChange(
    cablesBefore: cablesAfter,
    cablesAfter: cablesBefore,
    before: after,
    after: before,
    objectsBefore: objectsAfter,
    objectsAfter: objectsBefore,
    placementsBefore: placementsAfter,
    placementsAfter: placementsBefore,
    portsBefore: portsAfter,
    portsAfter: portsBefore,
  );
}

/// Η κατάσταση και οι ενέργειες της οθόνης σχεδίασης ενός ορόφου.
///
/// **Κάθε ολοκληρωμένη κίνηση γράφεται αμέσως** στη βάση (απόφαση: χωρίς
/// κουμπί «Αποθήκευση»): ο τοίχος με κάθε κλικ γωνίας, το άνοιγμα όταν αφήσετε
/// το ποντίκι, το πατρόν όταν τελειώσει η μετακίνηση ή η ρύθμιση. Ό,τι είναι
/// ακόμη «στον αέρα» (το κομμάτι που ακολουθεί τον δείκτη) δεν γράφεται.
class FloorPlanEditorController extends ChangeNotifier {
  FloorPlanEditorController({
    required this.floorId,
    required FloorPlanRepository repository,
    required this.onError,
    FloorPlanObjectsRepository? objectsRepository,
    FloorPlanPlacementsRepository? placementsRepository,
    FloorPlanPortsRepository? portsRepository,
    FloorPlanPatternCache? patternCache,
  }) : _repo = repository,
       _objectsRepo = objectsRepository,
       _placementsRepo = placementsRepository,
       _portsRepo = portsRepository,
       _patternCache = patternCache ?? FloorPlanPatternCache.instance;

  final int floorId;
  final FloorPlanRepository _repo;

  /// Η εικόνα πατρόν που δεν ξανακατεβαίνει όσο δεν άλλαξε.
  ///
  /// Κοινή για όλη την εφαρμογή επειδή ο ελεγκτής φτιάχνεται από την αρχή σε
  /// κάθε άνοιγμα ορόφου· ρητή εξάρτηση ώστε τα τεστ να μπορούν να **δουν** τι
  /// ζητήθηκε από το δίκτυο και τι όχι.
  final FloorPlanPatternCache _patternCache;

  /// Τα αντικείμενα του χάρτη· χωρίς αυτό η σχεδίαση δεν έχει αντικείμενα.
  final FloorPlanObjectsRepository? _objectsRepo;

  /// Οι θέσεις του Καταλόγου· χωρίς αυτό η σχεδίαση δεν τοποθετεί τίποτα.
  final FloorPlanPlacementsRepository? _placementsRepo;

  /// Οι θύρες· χωρίς αυτό η σχεδίαση δεν έχει θύρες.
  final FloorPlanPortsRepository? _portsRepo;

  /// Μήνυμα προς τον χρήστη όταν μια εγγραφή αποτύχει.
  final void Function(String message) onError;

  bool _loading = true;
  bool get loading => _loading;

  List<FloorPlanElement> _elements = const [];

  /// Τα στοιχεία όπως φαίνονται τώρα: όσο σύρεται ή γυρίζει μια επιλογή,
  /// με τη θέση που έχουν «στον αέρα».
  List<FloorPlanElement> get elements {
    final preview = _preview;
    if (preview == null) return _elements;
    return [for (final e in _elements) preview[e.id] ?? e];
  }

  /// Οι θέσεις «στον αέρα» των επιλεγμένων, ως την εγγραφή τους.
  Map<int, FloorPlanElement>? _preview;

  List<FloorPlanObject> _objects = const [];

  /// Τα αντικείμενα όπως φαίνονται τώρα, με όσα σύρονται «στον αέρα».
  List<FloorPlanObject> get objects {
    final preview = _objectPreview;
    if (preview == null) return _objects;
    return [for (final o in _objects) preview[o.id] ?? o];
  }

  Map<int, FloorPlanObject>? _objectPreview;

  Map<int, FloorPlanObjectKind> _kinds = const {};

  List<FloorPlanPort> _ports = const [];

  /// Οι θύρες των αντικειμένων του ορόφου.
  List<FloorPlanPort> get ports => _ports;

  Set<int> _occupiedPorts = const {};

  /// Οι θύρες με καλώδιο· οι υπόλοιπες είναι ελεύθερες.
  Set<int> get occupiedPortIds => _occupiedPorts;

  List<FloorPlanPortLink> _portLinks = const [];

  /// Οι συνδέσεις πρίζας — patch panel που αγγίζουν αυτόν τον όροφο.
  List<FloorPlanPortLink> get portLinks => _portLinks;

  FloorPlanPortCables _portCables = FloorPlanPortCables.empty;

  /// Ποια καλώδια έχει κάθε θύρα που αγγίζει αυτόν τον όροφο.
  FloorPlanPortCables get portCables => _portCables;

  /// Όλες οι θύρες patch panel του κτιρίου, για το «Σύνδεση με patch panel…».
  Future<List<FloorPlanPatchPortOption>> patchPortOptions() async =>
      await _portsRepo?.patchPortOptions() ?? const [];

  /// Οι θύρες του αντικειμένου [objectId], με τη σειρά των αριθμών τους.
  List<FloorPlanPort> portsOf(int objectId) => [
    for (final p in _ports)
      if (p.objectId == objectId) p,
  ];

  /// Τα είδη αντικειμένων, κατά id.
  Map<int, FloorPlanObjectKind> get kinds => _kinds;

  /// Τα αντικείμενα **και** οι θέσεις του Καταλόγου, έτοιμα για σχεδίαση και
  /// για το ποντίκι — οι θέσεις τελευταίες, ώστε να πιάνονται πρώτες.
  ///
  /// Ό,τι ανήκει σε κρυμμένη στρώση λείπει — ούτε φαίνεται ούτε πιάνεται.
  List<FloorPlanObjectView> get objectViews => visibleFloorPlanLayers([
    ...buildFloorPlanObjectViews(objects, _kinds),
    ...buildFloorPlanPlacementViews(placements, _catalog),
  ], _hiddenLayers);

  Set<String> _hiddenLayers = const {};
  Set<String> get hiddenLayers => _hiddenLayers;

  /// Κρύβει τις στρώσεις [hidden]· ό,τι κρύφτηκε βγαίνει και από την
  /// επιλογή, ώστε να μη σβηστεί ή μετακινηθεί αθέατο.
  void setHiddenLayers(Set<String> hidden) {
    _hiddenLayers = Set.unmodifiable(hidden);
    final visible = objectViews;
    bool shown(FloorPlanItemSource source, int id) =>
        visible.any((v) => v.source == source && v.id == id);
    _selectedObjects = {
      for (final id in _selectedObjects)
        if (shown(FloorPlanItemSource.object, id)) id,
    };
    _selectedPlacements = {
      for (final id in _selectedPlacements)
        if (shown(FloorPlanItemSource.placement, id)) id,
    };
    notifyListeners();
  }

  /// Όσα χρειάζεται η υπόδειξη για να περιγράψει ένα σύμβολο.
  ({Map<int, FloorPlanObject> objects, Map<int, FloorPlanPlacement> placements})
  get infoMaps => (
    objects: {for (final o in _objects) o.id: o},
    placements: {for (final p in _placements) p.id: p},
  );

  List<FloorPlanPlacement> _placements = const [];

  /// Οι θέσεις του Καταλόγου σε αυτόν τον όροφο, όπως φαίνονται τώρα.
  List<FloorPlanPlacement> get placements {
    final preview = _placementPreview;
    if (preview == null) return _placements;
    return [for (final p in _placements) preview[p.id] ?? p];
  }

  Map<int, FloorPlanPlacement>? _placementPreview;

  Map<(FloorPlanPlacementType, int), FloorPlanCatalogEntry> _catalog = const {};

  /// Οι εγγραφές του Καταλόγου που τοποθετούνται, κατά (τύπο, id).
  Map<(FloorPlanPlacementType, int), FloorPlanCatalogEntry> get catalog =>
      _catalog;

  List<FloorPlanPlacement> _allPlacements = const [];

  /// Οι θέσεις όλων των ορόφων — για το «έχει ήδη θέση, και πού».
  List<FloorPlanPlacement> get allPlacements => _allPlacements;

  Set<int> _selectedPlacements = const {};
  Set<int> get selectedPlacementIds => _selectedPlacements;

  /// Το είδος που τοποθετεί το εργαλείο «Αντικείμενο».
  int? _objectKindId;
  FloorPlanObjectKind? get objectKind => _kinds[_objectKindId];

  Set<int> _selectedObjects = const {};
  Set<int> get selectedObjectIds => _selectedObjects;

  bool get hasSelection =>
      _selected.isNotEmpty ||
      _selectedObjects.isNotEmpty ||
      _selectedPlacements.isNotEmpty;

  FloorPlanState _state = const FloorPlanState(floorId: 0);
  FloorPlanState get state => _state;

  ui.Image? _patternImage;
  ui.Image? get patternImage => _patternImage;

  FloorPlanTool _tool = FloorPlanTool.wall;
  FloorPlanTool get tool => _tool;

  bool _gridVisible = true;
  bool get gridVisible => _gridVisible;

  Set<int> _selected = const {};
  Set<int> get selectedIds => _selected;

  /// Κλείδωμα σχεδίου: τοίχοι, ανοίγματα, χώροι, κείμενα και διαστάσεις δεν
  /// πιάνονται με το ποντίκι, ώστε να μη μετακινηθεί κάτι κατά λάθος. Τα
  /// αντικείμενα κινούνται κανονικά — γι' αυτό υπάρχει το κλείδωμα.
  bool _locked = false;
  bool get locked => _locked;

  /// Ό,τι αντιγράφηκε με Ctrl+C ή Ctrl+X.
  List<FloorPlanElement> _clipboard = const [];
  List<FloorPlanObject> _objectClipboard = const [];
  bool get canPaste => _clipboard.isNotEmpty || _objectClipboard.isNotEmpty;

  /// Πόσες φορές επικολλήθηκε το ίδιο περιεχόμενο — κάθε επικόλληση πέφτει
  /// λίγο πιο πέρα, για να μην κρύβεται κάτω από την προηγούμενη.
  int _pasteCount = 0;

  final List<_PlanChange> _undo = [];
  final List<_PlanChange> _redo = [];
  bool get canUndo => _undo.isNotEmpty && !_busy;
  bool get canRedo => _redo.isNotEmpty && !_busy;

  /// Μία εγγραφή τη φορά: δύο γρήγορα Ctrl+Z δεν πρέπει να τρέξουν μαζί.
  bool _busy = false;

  // ── Δεδομένα ──────────────────────────────────────────────────────────

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _elements = await _repo.listElements(floorId);
      _state = await _repo.readState(floorId);
      await _reloadObjects();
      await _reloadPatternImage();
    } catch (e) {
      onError('Ο χάρτης δεν διαβάστηκε: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _reloadObjects() async {
    final repo = _objectsRepo;
    if (repo != null) {
      _kinds = await repo.kinds();
      _objects = await repo.listObjects(floorId);
    }
    await _reloadPorts();
    final placements = _placementsRepo;
    if (placements != null) {
      _catalog = {for (final e in await placements.catalogEntries()) e.key: e};
      _placements = await placements.listPlacements(floorId);
      _allPlacements = await placements.allPlacements();
    }
  }

  /// Ξαναδιαβάζει τα είδη — μετά από αλλαγές στο παράθυρο «Είδη
  /// αντικειμένων». Είδος που σβήστηκε παύει να είναι το είδος του εργαλείου.
  Future<void> reloadKinds() async {
    final repo = _objectsRepo;
    if (repo == null) return;
    try {
      _kinds = await repo.kinds();
    } catch (e) {
      onError('Τα είδη δεν διαβάστηκαν: $e');
    }
    if (!_kinds.containsKey(_objectKindId)) {
      _objectKindId = null;
      if (_tool == FloorPlanTool.object) _tool = FloorPlanTool.select;
    }
    notifyListeners();
  }

  Future<void> _reloadPatternImage() async {
    _patternImage?.dispose();
    _patternImage = null;
    if (!_state.hasPattern) return;
    // Το αποτύπωμα της εικόνας έχει ήδη έρθει με την κατάσταση του ορόφου, και
    // απαντά «είναι η ίδια εικόνα που κατέβασα την προηγούμενη φορά;». Όσο
    // είναι ίδιο, η κάτοψη δεν ξανακατεβαίνει από το δίκτυο — και όταν ο
    // συνάδελφος φορτώσει άλλη, το αποτύπωμα αλλάζει και η μνήμη δεν απαντά.
    final hash = _state.patternHash;
    var bytes = _patternCache.get(hash);
    if (bytes == null) {
      bytes = await _repo.readPatternImage(floorId);
      if (bytes == null) return;
      _patternCache.put(hash, bytes);
    }
    _patternImage = await _decode(bytes);
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  /// Οι τοίχοι ως τμήματα, για γεωμετρία και σχεδίαση.
  List<FloorPlanSegment> get wallSegments => [
    for (final e in elements)
      if (e.kind == FloorPlanElementKind.wall && e.points.length >= 2)
        FloorPlanSegment(e.points[0], e.points[1], id: e.id),
  ];

  /// Τα ανοίγματα κάθε τοίχου, ως αποστάσεις από την αρχή του.
  Map<int, List<({double start, double end})>> get openingsByWall {
    final map = <int, List<({double start, double end})>>{};
    for (final e in elements) {
      final parent = e.parentId;
      if (e.kind != FloorPlanElementKind.opening || parent == null) continue;
      if (e.points.length < 2) continue;
      (map[parent] ??= []).add((start: e.points[0].dx, end: e.points[1].dx));
    }
    return map;
  }

  // ── Εργαλεία ──────────────────────────────────────────────────────────

  void setTool(FloorPlanTool tool) {
    if (_tool == tool) return;
    _tool = tool;
    if (tool != FloorPlanTool.select) {
      _selected = const {};
      _selectedObjects = const {};
      _selectedPlacements = const {};
    }
    notifyListeners();
  }

  /// Το εργαλείο «Αντικείμενο» με το είδος [kindId].
  void setObjectTool(int kindId) {
    if (!_kinds.containsKey(kindId)) return;
    _objectKindId = kindId;
    _tool = FloorPlanTool.object;
    _selected = const {};
    _selectedObjects = const {};
    _selectedPlacements = const {};
    notifyListeners();
  }

  void toggleLock() {
    _locked = !_locked;
    if (_locked) _selected = const {};
    notifyListeners();
  }

  void toggleGrid() {
    _gridVisible = !_gridVisible;
    notifyListeners();
  }

  /// Επιλέγει μόνο το στοιχείο [id] (ή τίποτα, με `null`).
  void select(int? id) => selectMany(id == null ? const {} : {id});

  /// Επιλέγει μόνο το αντικείμενο [id].
  void selectObject(int id) => selectMany(const {}, objects: {id});

  /// Επιλέγει μόνο το σύμβολο [view] — αντικείμενο ή θέση του Καταλόγου.
  void selectItem(FloorPlanObjectView view) =>
      view.source == FloorPlanItemSource.object
      ? selectMany(const {}, objects: {view.id})
      : selectMany(const {}, placements: {view.id});

  /// Επιλέγει τα στοιχεία [ids], τα αντικείμενα [objects] και τις θέσεις
  /// [placements]. Με κλειδωμένο σχέδιο τα στοιχεία δεν επιλέγονται· τα
  /// αντικείμενα και οι θέσεις ναι.
  void selectMany(
    Set<int> ids, {
    Set<int> objects = const {},
    Set<int> placements = const {},
  }) {
    _selected = _locked ? const {} : Set.unmodifiable(ids);
    _selectedObjects = Set.unmodifiable(objects);
    _selectedPlacements = Set.unmodifiable(placements);
    notifyListeners();
  }

  /// Ctrl+κλικ: προσθέτει ή αφαιρεί το στοιχείο [id] από την επιλογή.
  void toggleSelected(int id) {
    final next = {..._selected};
    if (!next.remove(id)) next.add(id);
    selectMany(
      next,
      objects: _selectedObjects,
      placements: _selectedPlacements,
    );
  }

  /// Ctrl+κλικ σε αντικείμενο ή θέση.
  void toggleSelectedItem(FloorPlanObjectView view) {
    final objects = {..._selectedObjects};
    final placements = {..._selectedPlacements};
    final set = view.source == FloorPlanItemSource.object
        ? objects
        : placements;
    if (!set.remove(view.id)) set.add(view.id);
    selectMany(_selected, objects: objects, placements: placements);
  }

  /// Το σύμβολο [view] είναι στην επιλογή.
  bool isItemSelected(FloorPlanObjectView view) =>
      (view.source == FloorPlanItemSource.object
              ? _selectedObjects
              : _selectedPlacements)
          .contains(view.id);

  // ── Σχεδίαση ──────────────────────────────────────────────────────────

  Future<void> addWall(Offset a, Offset b) async {
    if ((b - a).distance < 1) return;
    await _add([
      FloorPlanElement(
        id: 0,
        floorId: floorId,
        kind: FloorPlanElementKind.wall,
        points: [a, b],
      ),
    ]);
  }

  Future<void> addOpening(int wallId, double start, double end) async {
    await _add([
      FloorPlanElement(
        id: 0,
        floorId: floorId,
        kind: FloorPlanElementKind.opening,
        points: [Offset(start, 0), Offset(end, 0)],
        parentId: wallId,
      ),
    ]);
  }

  /// Νέος χώρος με γωνίες [corners] — τμήμα **ή** ελεύθερο όνομα.
  Future<void> addRoom(
    List<Offset> corners, {
    String? name,
    int? departmentId,
  }) async {
    if (corners.length < 3) return;
    await _add([
      FloorPlanElement(
        id: 0,
        floorId: floorId,
        kind: FloorPlanElementKind.room,
        points: corners,
      ).withRoomIdentity(name: name, departmentId: departmentId),
    ]);
  }

  /// Αλλάζει το τμήμα ή το όνομα ενός υπάρχοντος χώρου.
  Future<void> renameRoom(int id, {String? name, int? departmentId}) async {
    final old = elementById(id);
    if (old == null || old.kind != FloorPlanElementKind.room) return;
    await _replace([
      old.withRoomIdentity(name: name, departmentId: departmentId),
    ]);
  }

  Future<void> addText(Offset center, String text, double sizeCm) async {
    final content = text.trim();
    if (content.isEmpty) return;
    await _add([
      FloorPlanElement(
        id: 0,
        floorId: floorId,
        kind: FloorPlanElementKind.text,
        points: [center],
        name: content,
        fontSize: sizeCm,
      ),
    ]);
  }

  /// Αλλάζει το περιεχόμενο, το μέγεθος και —αν δοθεί [center]— τη θέση ενός
  /// κειμένου, σε μία κίνηση αναίρεσης. Κείμενο που έμεινε άδειο διαγράφεται
  /// — και επιστρέφει με την αναίρεση.
  Future<void> updateText(
    int id,
    String text,
    double sizeCm, {
    Offset? center,
  }) async {
    final old = elementById(id);
    final content = text.trim();
    if (old == null || old.kind != FloorPlanElementKind.text) return;
    if (content.isEmpty) {
      await _run(() async {
        final removed = await _repo.deleteElements({id});
        if (removed.isEmpty) return;
        _record(_PlanChange(before: removed));
        _selected = _selected.difference({id});
        await _refreshElements();
      });
      return;
    }
    await _replace([
      old.copyWith(
        name: content,
        fontSize: sizeCm,
        points: center == null ? null : [center],
      ),
    ]);
  }

  /// Γραμμή διάστασης από το [a] στο [b], σε απόσταση που ορίζει το [offset].
  Future<void> addDimension(Offset a, Offset b, Offset offset) async {
    if ((b - a).distance < 1) return;
    await _add([
      FloorPlanElement(
        id: 0,
        floorId: floorId,
        kind: FloorPlanElementKind.dimension,
        points: [a, b, offset],
      ),
    ]);
  }

  // ── Αντικείμενα ───────────────────────────────────────────────────────

  /// Νέο αντικείμενο του είδους [kindId] με κέντρο [center] — και μέγεθος
  /// [size] για έπιπλο. Επιστρέφει το αντικείμενο όπως γράφτηκε.
  Future<FloorPlanObject?> addObject(
    int kindId,
    Offset center, {
    Size? size,
  }) async {
    final repo = _objectsRepo;
    if (repo == null) return null;
    final isOutlet = _kinds[kindId]?.symbol?.isOutlet ?? false;
    final draft = FloorPlanObject(
      id: 0,
      floorId: floorId,
      kindId: kindId,
      // Η πρίζα κουμπώνει στον πλησιέστερο τοίχο, αν υπάρχει κοντά.
      center: isOutlet
          ? snapToNearestWall(center, wallSegments, kFloorPlanOutletSnapCm)
          : center,
      size: size,
      // Η καμπίνα ξέρει από την αρχή πόσα U έχει, ώστε να μην αλλάξει
      // μέγεθος αν αλλάξει κάποτε η προεπιλογή.
      rackUnits: (_kinds[kindId]?.symbol?.isCabinet ?? false)
          ? kFloorPlanDefaultCabinetUnits
          : null,
    );
    FloorPlanObject? stored;
    await _run(() async {
      final id = await repo.insertObject(draft);
      stored = draft.copyWith(id: id);
      final ports = await _defaultPortsOf(stored!);
      _record(_PlanChange(objectsAfter: [stored!], portsAfter: ports));
      _objects = [..._objects, stored!];
      if (ports.isNotEmpty) await _reloadPorts();
    });
    return stored;
  }

  /// Οι θύρες που έχει ένα αντικείμενο από τη γέννησή του.
  Future<List<FloorPlanPort>> _defaultPortsOf(FloorPlanObject object) async {
    final portsRepo = _portsRepo;
    final count = floorPlanDefaultPortCount(_kinds[object.kindId]);
    if (portsRepo == null || count == 0) return const [];
    return portsRepo.insertPorts([
      for (var n = 1; n <= count; n++)
        FloorPlanPort(id: 0, objectId: object.id, number: n),
    ]);
  }

  /// Αλλάζει όνομα, IP, όνομα Lansweeper και σημειώσεις — μία κίνηση
  /// αναίρεσης. Τίποτα δεν γράφεται όταν τίποτα δεν άλλαξε.
  Future<void> updateObjectDetails(
    int id, {
    String? name,
    String? ip,
    String? lansweeperName,
    String? notes,
    String? portType,
  }) async {
    final old = objectById(id);
    if (old == null) return;
    final next = old
        .withDetails(
          name: name,
          ip: ip,
          lansweeperName: lansweeperName,
          notes: notes,
        )
        // Το Gi είναι η προεπιλογή: δεν γράφεται, ώστε να μη μοιάζει με αλλαγή.
        .withPortType(portType == kFloorPlanDefaultPortType ? null : portType);
    if (next.name == old.name &&
        next.ip == old.ip &&
        next.lansweeperName == old.lansweeperName &&
        next.notes == old.notes &&
        next.portType == old.portType) {
      return;
    }
    await _replaceObjects([next]);
  }

  // ── Καμπίνες ──────────────────────────────────────────────────────────

  /// Ό,τι είναι μέσα στην καμπίνα [cabinetId], από πάνω προς τα κάτω.
  List<FloorPlanObject> cabinetContents(int cabinetId) =>
      floorPlanCabinetContents(cabinetId, objects);

  String _objectLabel(FloorPlanObject o) {
    final name = o.name?.trim() ?? '';
    return name.isNotEmpty ? name : (_kinds[o.kindId]?.name ?? 'Αντικείμενο');
  }

  FloorPlanObject? _cabinetOf(FloorPlanObject? o) {
    final id = o?.cabinetId;
    return id == null ? null : objectById(id);
  }

  /// Νέο αντικείμενο του είδους [kindId] μέσα στην καμπίνα [cabinetId], στο
  /// πρώτο ελεύθερο U από πάνω. Χωρίς ελεύθερο U δεν μπαίνει τίποτα και ο
  /// χρήστης το μαθαίνει.
  Future<FloorPlanObject?> addToCabinet(int cabinetId, int kindId) async {
    final repo = _objectsRepo;
    final cabinet = objectById(cabinetId);
    if (repo == null || cabinet == null) return null;
    final u = floorPlanFirstFreeRackU(
      units: floorPlanCabinetUnits(cabinet),
      contents: cabinetContents(cabinetId),
    );
    if (u == null) {
      onError('Η καμπίνα «${_objectLabel(cabinet)}» δεν έχει ελεύθερο U.');
      return null;
    }
    final draft = FloorPlanObject(
      id: 0,
      floorId: floorId,
      kindId: kindId,
      center: cabinet.center,
      cabinetId: cabinetId,
      rackU: u,
    );
    FloorPlanObject? stored;
    await _run(() async {
      final id = await repo.insertObject(draft);
      stored = draft.copyWith(id: id);
      final ports = await _defaultPortsOf(stored!);
      _record(_PlanChange(objectsAfter: [stored!], portsAfter: ports));
      _objects = [..._objects, stored!];
      if (ports.isNotEmpty) await _reloadPorts();
    });
    return stored;
  }

  /// Το αντικείμενο [id] στη θέση [u] της καμπίνας του. Δύο αντικείμενα δεν
  /// πιάνουν το ίδιο U: όταν δεν χωρά, μένει όπου ήταν.
  Future<bool> moveInCabinet(int id, int u) async {
    final object = objectById(id);
    final cabinet = _cabinetOf(object);
    if (object == null || cabinet == null) return false;
    if (object.rackU == u) return true;
    final fits = floorPlanRackFits(
      units: floorPlanCabinetUnits(cabinet),
      contents: cabinetContents(cabinet.id),
      u: u,
      height: object.heightU,
      exceptId: id,
    );
    if (!fits) {
      onError(
        '«${_objectLabel(object)}» δεν χωρά στο U$u: πιάνεται ή ξεπερνά '
        'το κάτω μέρος της καμπίνας.',
      );
      return false;
    }
    await _replaceObjects([
      object.withRack(
        cabinetId: cabinet.id,
        rackU: u,
        rackUnits: object.rackUnits,
      ),
    ]);
    return true;
  }

  /// Πόσα U πιάνει το [id] μέσα στην καμπίνα του. Μεγαλώνει προς τα κάτω·
  /// αν πατά κάτι ή βγαίνει έξω, δεν αλλάζει.
  Future<bool> setRackHeight(int id, int height) async {
    final object = objectById(id);
    final cabinet = _cabinetOf(object);
    if (object == null || cabinet == null || height < 1) return false;
    if (object.heightU == height) return true;
    final u = object.rackU ?? 1;
    final units = floorPlanCabinetUnits(cabinet);
    final fits = floorPlanRackFits(
      units: units,
      contents: cabinetContents(cabinet.id),
      u: u,
      height: height,
      exceptId: id,
    );
    if (!fits) {
      onError(
        u + height - 1 > units
            ? '«${_objectLabel(object)}» με $height U ξεπερνά το κάτω μέρος '
                  'της καμπίνας (U$units).'
            : '«${_objectLabel(object)}» με $height U πατά πάνω σε άλλο '
                  'αντικείμενο.',
      );
      return false;
    }
    await _replaceObjects([
      object.withRack(
        cabinetId: cabinet.id,
        rackU: u,
        rackUnits: height == 1 ? null : height,
      ),
    ]);
    return true;
  }

  /// Βγάζει το [id] από την καμπίνα του και το αφήνει δίπλα της στον χάρτη.
  Future<void> takeOutOfCabinet(int id) async {
    final object = objectById(id);
    if (object == null || !object.inCabinet) return;
    final cabinet = _cabinetOf(object);
    final beside = cabinet == null
        ? object.center
        : floorPlanBesideCabinet(
            cabinet.center,
            floorPlanObjectSize(cabinet, _kinds[cabinet.kindId]?.symbol),
            cabinet.rotationDegrees,
          );
    // Το stack ζει μέσα σε μία καμπίνα: όποιο βγαίνει, βγαίνει και από αυτό.
    final leaving = floorPlanStackLeave(object, _objects);
    await _replaceObjects([
      object
          .withRack(
            cabinetId: null,
            rackU: null,
            rackUnits: null,
            center: beside,
          )
          .withStack(stackId: null, stackUnit: null),
      for (final o in leaving)
        if (o.id != object.id) o,
    ]);
  }

  /// Αλλάζει πόσα U έχει η καμπίνα — και με περιεχόμενο μέσα. Δεν μικραίνει
  /// κάτω από ό,τι έχει: τότε λέει τι εμποδίζει, για να μετακινηθεί πρώτα.
  Future<bool> setCabinetUnits(int cabinetId, int units) async {
    final cabinet = objectById(cabinetId);
    if (cabinet == null) return false;
    if (units < 1 || units > kFloorPlanMaxCabinetUnits) {
      onError('Η καμπίνα δέχεται από 1 ως $kFloorPlanMaxCabinetUnits U.');
      return false;
    }
    if (cabinet.rackUnits == units) return true;
    final blocking = floorPlanContentsBeyond(units, cabinetContents(cabinetId));
    if (blocking.isNotEmpty) {
      final names = [
        for (final o in blocking)
          '«${_objectLabel(o)}» (U${o.rackU ?? 1}'
              '${o.heightU > 1 ? '–U${(o.rackU ?? 1) + o.heightU - 1}' : ''})',
      ].join(', ');
      onError(
        'Η καμπίνα δεν μικραίνει σε $units U: πιο κάτω βρίσκονται $names. '
        'Μετακινήστε τα πρώτα πιο πάνω.',
      );
      return false;
    }
    await _replaceObjects([
      cabinet.withRack(
        cabinetId: cabinet.cabinetId,
        rackU: cabinet.rackU,
        rackUnits: units,
      ),
    ]);
    return true;
  }

  /// Σβήνει τα αντικείμενα [ids] (π.χ. από τη λίστα της καμπίνας) — μία
  /// κίνηση αναίρεσης.
  Future<void> deleteObjects(Set<int> ids) async {
    final repo = _objectsRepo;
    if (repo == null || ids.isEmpty) return;
    await _run(() async {
      final removed = await repo.deleteObjects(ids);
      if (removed.isEmpty) return;
      final removedPorts = await _deletePortsOf(removed);
      _record(
        _PlanChange(
          objectsBefore: removed,
          portsBefore: removedPorts.ports,
          cablesBefore: removedPorts.cables,
        ),
      );
      _selectedObjects = _selectedObjects.difference({
        for (final o in removed) o.id,
      });
      await _refreshElements();
    });
  }

  /// Οι πρίζες που σύρθηκαν κουμπώνουν στον πλησιέστερο τοίχο, αν υπάρχει
  /// κοντά· αλλιώς μένουν εκεί που αφέθηκαν.
  List<FloorPlanObject> _snapOutletsToWalls(List<FloorPlanObject> moved) {
    final walls = wallSegments;
    return [
      for (final o in moved)
        (_kinds[o.kindId]?.symbol?.isOutlet ?? false) && !o.inCabinet
            ? o.copyWith(
                center: snapToNearestWall(
                  o.center,
                  walls,
                  kFloorPlanOutletSnapCm,
                ),
              )
            : o,
    ];
  }

  /// Τα αντικείμενα που η μετακίνηση άφησε **πάνω σε καμπίνα** μπαίνουν μέσα
  /// της, στο πρώτο ελεύθερο U· ό,τι δεν χωρά μένει εκεί που αφέθηκε.
  List<FloorPlanObject> _dropIntoCabinets(List<FloorPlanObject> moved) {
    final cabinets = [
      for (final v in buildFloorPlanObjectViews(_objects, _kinds))
        if (v.isCabinet && !_selectedObjects.contains(v.id)) v,
    ];
    if (cabinets.isEmpty) return moved;
    final filling = <int, List<FloorPlanObject>>{};
    final full = <String>{};
    final result = <FloorPlanObject>[];
    for (final o in moved) {
      final fits = _kinds[o.kindId]?.symbol?.fitsInCabinet ?? false;
      final target = fits && !o.inCabinet
          ? _smallestCabinetAt(o.center, cabinets)
          : null;
      final cabinet = target == null ? null : objectById(target.id);
      if (cabinet == null) {
        result.add(o);
        continue;
      }
      final inside = filling[cabinet.id] ??= cabinetContents(cabinet.id);
      final u = floorPlanFirstFreeRackU(
        units: floorPlanCabinetUnits(cabinet),
        contents: inside,
        height: o.heightU,
      );
      if (u == null) {
        full.add('«${_objectLabel(cabinet)}»');
        result.add(o);
        continue;
      }
      final placed = o.withRack(
        cabinetId: cabinet.id,
        rackU: u,
        rackUnits: o.rackUnits,
        center: cabinet.center,
      );
      inside.add(placed);
      result.add(placed);
    }
    if (full.isNotEmpty) {
      onError(
        'Η καμπίνα ${full.join(', ')} δεν έχει ελεύθερο U· το αντικείμενο '
        'έμεινε πάνω της στον χάρτη.',
      );
    }
    return result;
  }

  static FloorPlanObjectView? _smallestCabinetAt(
    Offset p,
    List<FloorPlanObjectView> cabinets,
  ) {
    FloorPlanObjectView? best;
    var area = double.infinity;
    for (final c in cabinets) {
      if (!polygonContains(c.corners, p)) continue;
      final a = c.size.width * c.size.height;
      if (a < area) {
        area = a;
        best = c;
      }
    }
    return best;
  }

  // ── Θύρες ─────────────────────────────────────────────────────────────

  /// Οι θύρες των σβησμένων αντικειμένων φεύγουν μαζί τους, με τα καλώδιά
  /// τους.
  Future<FloorPlanPortsRemoval> _deletePortsOf(
    List<FloorPlanObject> objects,
  ) async {
    final portsRepo = _portsRepo;
    if (portsRepo == null || objects.isEmpty) {
      return const (ports: <FloorPlanPort>[], cables: <FloorPlanCable>[]);
    }
    return portsRepo.deletePortsOfObjects([for (final o in objects) o.id]);
  }

  /// Πόσα καλώδια έχουν οι θύρες των [objects] — για την ερώτηση πριν σβηστεί
  /// μια καμπίνα.
  int cableCountOf(Iterable<FloorPlanObject> objects) =>
      _portCables.countTouching({for (final o in objects) o.id});

  FloorPlanPort? _portById(int id) {
    for (final p in _ports) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Το αυτόματο όνομα της θύρας [port].
  String portName(FloorPlanPort port) {
    final object = objectById(port.objectId);
    if (object == null) return 'Θύρα ${port.number}';
    return floorPlanObjectPortName(
      object: object,
      port: port,
      symbol: _kinds[object.kindId]?.symbol,
      objects: infoMaps.objects,
    );
  }

  // ── Stack ─────────────────────────────────────────────────────────────

  /// Το switch [objectId] ενώνεται με το [otherId] της ίδιας καμπίνας σε ένα
  /// stack — μία κίνηση αναίρεσης.
  Future<void> joinStack(int objectId, int otherId) async {
    final object = objectById(objectId);
    final other = objectById(otherId);
    if (object == null || other == null || object.id == other.id) return;
    final isSwitch =
        _kinds[object.kindId]?.symbol == FloorPlanSymbol.networkSwitch &&
        _kinds[other.kindId]?.symbol == FloorPlanSymbol.networkSwitch;
    if (!isSwitch || object.cabinetId != other.cabinetId) {
      onError('Σε stack ενώνονται μόνο switches της ίδιας καμπίνας.');
      return;
    }
    final changes = floorPlanStackJoin(object, other, _objects);
    if (changes.any((o) => (o.stackUnit ?? 1) > kFloorPlanMaxStackUnit)) {
      onError('Ένα stack έχει το πολύ $kFloorPlanMaxStackUnit μέλη.');
      return;
    }
    await _replaceObjects(changes);
  }

  /// Το [objectId] φεύγει από το stack του. Οι θύρες και τα καλώδιά του μένουν.
  Future<void> leaveStack(int objectId) async {
    final object = objectById(objectId);
    if (object == null) return;
    final changes = floorPlanStackLeave(object, _objects);
    if (changes.isNotEmpty) await _replaceObjects(changes);
  }

  /// Το [objectId] γίνεται μέλος [unit] του stack του· αν το μέλος υπάρχει, οι
  /// δύο ανταλλάσσουν αριθμούς.
  Future<void> setStackUnit(int objectId, int unit) async {
    final object = objectById(objectId);
    if (object == null || unit < 1 || unit > kFloorPlanMaxStackUnit) return;
    final changes = floorPlanStackSetUnit(object, unit, _objects);
    if (changes.isNotEmpty) await _replaceObjects(changes);
  }

  /// Νέο καλώδιο ανάμεσα στις μπροστινές πλευρές δύο θυρών — μία κίνηση
  /// αναίρεσης. Όταν δεν γίνεται, ο χρήστης μαθαίνει γιατί και επιστρέφεται
  /// `false`.
  Future<bool> addCable(int fromPortId, int toPortId) async {
    final from = _portById(fromPortId);
    final to = _portById(toPortId);
    if (from == null || to == null) return false;
    return _connect(from, to);
  }

  /// Καλώδιο προς το αντικείμενο [objectId] με μία θύρα. Όσα μπήκαν πριν
  /// γεννιούνται τα αντικείμενα με τη θύρα τους την αποκτούν τώρα, στην ίδια
  /// κίνηση.
  Future<bool> addCableToObject(int fromPortId, int objectId) async {
    final portsRepo = _portsRepo;
    final from = _portById(fromPortId);
    if (portsRepo == null || from == null) return false;
    final existing = portsOf(objectId);
    if (existing.isNotEmpty) return _connect(from, existing.first);
    var connected = false;
    await _run(() async {
      final inserted = await portsRepo.insertPorts([
        FloorPlanPort(id: 0, objectId: objectId, number: 1),
      ]);
      final cable = await portsRepo.connectPorts(
        from.id,
        kFloorPlanCableFront,
        inserted.single.id,
        kFloorPlanCableFront,
      );
      connected = cable != null;
      _record(_PlanChange(portsAfter: inserted, cablesAfter: [?cable]));
      await _reloadPorts();
      if (!connected) onError('Η αρχική θύρα έχει ήδη καλώδιο.');
    });
    return connected;
  }

  Future<bool> _connect(FloorPlanPort from, FloorPlanPort to) async {
    final portsRepo = _portsRepo;
    if (portsRepo == null) return false;
    final problem = floorPlanCableProblem(
      from: from,
      to: to,
      toSymbol: _kinds[objectById(to.objectId)?.kindId]?.symbol,
      toName: portName(to),
      frontTaken: _portCables.front.contains,
    );
    if (problem != null) {
      onError(problem);
      return false;
    }
    var connected = false;
    await _run(() async {
      final cable = await portsRepo.connectPorts(
        from.id,
        kFloorPlanCableFront,
        to.id,
        kFloorPlanCableFront,
      );
      if (cable == null) {
        onError('Η θύρα πιάστηκε στο μεταξύ.');
      } else {
        connected = true;
        _record(_PlanChange(cablesAfter: [cable]));
      }
      await _reloadPorts();
    });
    return connected;
  }

  /// Αφαιρεί το καλώδιο [cableId] — μία κίνηση αναίρεσης.
  Future<void> removeCable(int cableId) async {
    final portsRepo = _portsRepo;
    if (portsRepo == null) return;
    await _run(() async {
      final removed = await portsRepo.deleteCables([cableId]);
      if (removed.isEmpty) return;
      _record(_PlanChange(cablesBefore: removed));
      await _reloadPorts();
    });
  }

  /// Αποθηκεύει το πλαίσιο της πρίζας [objectId]: πλήθος θυρών, γραμμένα
  /// ονόματα, σύνδεση με patch panel και τι είναι συνδεδεμένο — **μία** κίνηση
  /// αναίρεσης.
  Future<void> saveOutlet(
    int objectId,
    List<FloorPlanOutletPortDraft> drafts,
  ) async {
    final portsRepo = _portsRepo;
    if (portsRepo == null || objectById(objectId) == null) return;
    final existing = portsOf(objectId);
    final change = floorPlanOutletChange(
      objectId: objectId,
      existing: existing,
      patchPortOfOutletPort: {
        for (final l in _portLinks) l.outletPortId: l.patchPortId,
      },
      drafts: drafts,
    );
    if (change.isEmpty) return;
    await _run(() async {
      final disconnected = await portsRepo.deleteCablesOfPorts(
        change.disconnect,
      );
      final removal = await portsRepo.deletePorts([
        for (final p in change.remove) p.id,
      ]);
      final inserted = await portsRepo.insertPorts(change.insert);
      await portsRepo.restorePorts(change.update);
      final idOfNumber = {
        for (final p in [...existing, ...inserted]) p.number: p.id,
      };
      final connected = <FloorPlanCable>[];
      final taken = <int>[];
      for (final c in change.connect) {
        final cable = await portsRepo.connectOutletPort(
          idOfNumber[c.number]!,
          c.patchPortId,
        );
        if (cable == null) {
          taken.add(c.number);
        } else {
          connected.add(cable);
        }
      }
      final updatedIds = {for (final p in change.update) p.id};
      _record(
        _PlanChange(
          portsBefore: [
            ...removal.ports,
            for (final p in existing)
              if (updatedIds.contains(p.id)) p,
          ],
          portsAfter: [...inserted, ...change.update],
          cablesBefore: [...disconnected, ...removal.cables],
          cablesAfter: connected,
        ),
      );
      await _reloadPorts();
      if (taken.isNotEmpty) {
        onError(
          'Η θύρα ${taken.join(', ')} της πρίζας έμεινε χωρίς σύνδεση: η θύρα '
          'του patch panel που διαλέξατε πιάστηκε στο μεταξύ.',
        );
      }
    });
  }

  /// Οι θύρες που θα έφευγαν αν το [objectId] γινόταν [count] θυρών και
  /// έχουν καλώδιο — γι' αυτές ρωτά η οθόνη πριν.
  List<FloorPlanPort> cabledPortsBeyond(int objectId, int count) => [
    for (final p in floorPlanPortCountChange(portsOf(objectId), count).remove)
      if (_occupiedPorts.contains(p.id)) p,
  ];

  /// Το [objectId] αποκτά [count] θύρες: οι νέες αριθμούνται συνέχεια, όσες
  /// περισσεύουν φεύγουν με τα καλώδιά τους. Μία κίνηση αναίρεσης.
  Future<void> setPortCount(int objectId, int count) async {
    final portsRepo = _portsRepo;
    if (portsRepo == null || objectById(objectId) == null) return;
    if (count < 0 || count > kFloorPlanMaxPorts) {
      onError('Οι θύρες είναι από 0 ως $kFloorPlanMaxPorts.');
      return;
    }
    final change = floorPlanPortCountChange(portsOf(objectId), count);
    if (change.add.isEmpty && change.remove.isEmpty) return;
    await _run(() async {
      final removed = await portsRepo.deletePorts([
        for (final p in change.remove) p.id,
      ]);
      final added = await portsRepo.insertPorts([
        for (final n in change.add)
          FloorPlanPort(id: 0, objectId: objectId, number: n),
      ]);
      _record(
        _PlanChange(
          portsBefore: removed.ports,
          portsAfter: added,
          cablesBefore: removed.cables,
        ),
      );
      await _reloadPorts();
    });
  }

  /// Το γραμμένο όνομα της θύρας [portId] — ό,τι γράφει πραγματικά η
  /// ετικέτα. Κενό το σβήνει. Μία κίνηση αναίρεσης.
  Future<void> setPortWrittenName(int portId, String? name) async {
    final portsRepo = _portsRepo;
    FloorPlanPort? old;
    for (final p in _ports) {
      if (p.id == portId) old = p;
    }
    if (portsRepo == null || old == null) return;
    final next = old.withWrittenName(name);
    if (next.writtenName == old.writtenName) return;
    final before = old;
    await _run(() async {
      await portsRepo.restorePorts([next]);
      _record(_PlanChange(portsBefore: [before], portsAfter: [next]));
      await _reloadPorts();
    });
  }

  // ── Θέσεις του Καταλόγου ──────────────────────────────────────────────

  /// Οι θέσεις της εγγραφής [entry] σε όλους τους ορόφους.
  List<FloorPlanPlacement> placementsOf(FloorPlanCatalogEntry entry) => [
    for (final p in _allPlacements)
      if (p.type == entry.type && p.entityId == entry.entityId) p,
  ];

  /// Τοποθετεί την [entry] στο [center] αυτού του ορόφου. Τηλέφωνο ή
  /// εξοπλισμός που έχει ήδη θέση **μεταφέρεται** — η ερώτηση γίνεται πριν,
  /// από την οθόνη. Μία κίνηση αναίρεσης.
  Future<FloorPlanPlacement?> placeEntry(
    FloorPlanCatalogEntry entry,
    Offset center,
  ) async {
    final repo = _placementsRepo;
    if (repo == null) return null;
    final existing = entry.type.single ? placementsOf(entry) : const [];
    FloorPlanPlacement? stored;
    await _run(() async {
      if (existing.isNotEmpty) {
        final moved = existing.first.copyWith(floorId: floorId, center: center);
        await repo.restorePlacements([moved]);
        _record(
          _PlanChange(
            placementsBefore: [existing.first],
            placementsAfter: [moved],
          ),
        );
        stored = moved;
      } else {
        final draft = FloorPlanPlacement(
          id: 0,
          type: entry.type,
          entityId: entry.entityId,
          floorId: floorId,
          center: center,
        );
        final id = await repo.insertPlacement(draft);
        stored = draft.copyWith(id: id);
        _record(_PlanChange(placementsAfter: [stored!]));
      }
      await _refreshElements();
    });
    return stored;
  }

  FloorPlanPlacement? placementById(int id) {
    for (final p in _placements) {
      if (p.id == id) return p;
    }
    return null;
  }

  FloorPlanObject? objectById(int id) {
    for (final o in _objects) {
      if (o.id == id) return o;
    }
    return null;
  }

  FloorPlanElement? elementById(int id) {
    for (final e in _elements) {
      if (e.id == id) return e;
    }
    return null;
  }

  List<FloorPlanElement> get rooms => [
    for (final e in elements)
      if (e.kind == FloorPlanElementKind.room && e.points.length >= 3) e,
  ];

  List<FloorPlanElement> get texts => [
    for (final e in elements)
      if (e.kind == FloorPlanElementKind.text && e.points.isNotEmpty) e,
  ];

  List<FloorPlanElement> get dimensions => [
    for (final e in elements)
      if (e.kind == FloorPlanElementKind.dimension && e.points.length >= 3) e,
  ];

  // ── Επιλογή: μετακίνηση, περιστροφή, διαγραφή ─────────────────────────

  /// Μετακινεί την επιλογή κατά [delta] **μόνο στην οθόνη** — όσο κρατά το
  /// σύρσιμο. Η εγγραφή γίνεται με [commitPreview].
  void previewMove(Offset delta) {
    _preview = {
      for (final e in _elements)
        if (_selected.contains(e.id)) e.id: translateElement(e, delta),
    };
    _objectPreview = {
      for (final o in _objects)
        if (_selectedObjects.contains(o.id))
          o.id: translateFloorPlanObject(o, delta),
    };
    _placementPreview = {
      for (final p in _placements)
        if (_selectedPlacements.contains(p.id))
          p.id: p.copyWith(center: p.center + delta),
    };
    notifyListeners();
  }

  /// Γυρίζει την επιλογή κατά [radians] γύρω από το [center], μόνο στην
  /// οθόνη.
  void previewRotate(Offset center, double radians) {
    _preview = {
      for (final e in _elements)
        if (_selected.contains(e.id)) e.id: rotateElement(e, center, radians),
    };
    _objectPreview = {
      for (final o in _objects)
        if (_selectedObjects.contains(o.id))
          o.id: rotateFloorPlanObject(o, center, radians),
    };
    _placementPreview = {
      for (final p in _placements)
        if (_selectedPlacements.contains(p.id))
          p.id: rotateFloorPlanPlacement(p, center, radians),
    };
    notifyListeners();
  }

  /// Αλλάζει το μέγεθος του επίπλου [id] σέρνοντας τη γωνία [corner] στο
  /// [to], μόνο στην οθόνη· γράφεται με το [commitPreview].
  void previewResize(int id, int corner, Offset to) {
    final object = objectById(id);
    if (object == null) return;
    final size = floorPlanObjectSize(object, _kinds[object.kindId]?.symbol);
    _objectPreview = {id: resizeFloorPlanVolume(object, size, corner, to)};
    notifyListeners();
  }

  /// Σέρνει το όνομα του χώρου [id] στη θέση [offset] από το κέντρο του,
  /// μόνο στην οθόνη· γράφεται με το [commitPreview].
  void previewRoomLabel(int id, Offset offset) {
    final room = elementById(id);
    if (room == null || room.kind != FloorPlanElementKind.room) return;
    _preview = {id: room.copyWith(labelOffset: offset)};
    notifyListeners();
  }

  /// Αλλάζει το όνομα του χώρου [id]: μέγεθος γραμμάτων ([sizeCm]) ή
  /// επιστροφή στο κέντρο ([toCenter]). Μία κίνηση αναίρεσης.
  Future<void> setRoomLabel(
    int id, {
    double? sizeCm,
    bool toCenter = false,
  }) async {
    final room = elementById(id);
    if (room == null || room.kind != FloorPlanElementKind.room) return;
    await _replace([room.copyWith(fontSize: sizeCm, labelToCenter: toCenter)]);
  }

  void cancelPreview() {
    if (_preview == null &&
        _objectPreview == null &&
        _placementPreview == null) {
      return;
    }
    _preview = null;
    _objectPreview = null;
    _placementPreview = null;
    notifyListeners();
  }

  /// Γράφει τη μετακίνηση ή την περιστροφή ως **μία** κίνηση — μία εγγραφή,
  /// μία αναίρεση, όσα κι αν ήταν τα στοιχεία και τα αντικείμενα.
  ///
  /// Με [dropIntoCabinets] (σύρσιμο με το ποντίκι) ό,τι αφέθηκε πάνω σε
  /// καμπίνα μπαίνει μέσα της, στην ίδια κίνηση.
  Future<void> commitPreview({bool dropIntoCabinets = false}) async {
    final preview = _preview;
    final objectPreview = _objectPreview;
    final placementPreview = _placementPreview;
    _preview = null;
    _objectPreview = null;
    _placementPreview = null;
    final changed = [
      for (final e in preview?.values ?? const <FloorPlanElement>[])
        if (!_samePlace(e, elementById(e.id))) e,
    ];
    var changedObjects = [
      for (final o in objectPreview?.values ?? const <FloorPlanObject>[])
        if (objectById(o.id) case final old? when !o.samePlaceAs(old)) o,
    ];
    if (dropIntoCabinets) {
      changedObjects = _snapOutletsToWalls(_dropIntoCabinets(changedObjects));
    }
    final changedPlacements = [
      for (final p in placementPreview?.values ?? const <FloorPlanPlacement>[])
        if (placementById(p.id) case final old?
            when old.center != p.center ||
                old.rotationDegrees != p.rotationDegrees)
          p,
    ];
    if (changed.isEmpty &&
        changedObjects.isEmpty &&
        changedPlacements.isEmpty) {
      notifyListeners();
      return;
    }
    await _replace(
      changed,
      objects: changedObjects,
      placements: changedPlacements,
    );
  }

  /// Μετακίνηση της επιλογής με τα βελάκια.
  Future<void> nudgeSelected(Offset delta) async {
    if (!hasSelection) return;
    previewMove(delta);
    await commitPreview();
  }

  static bool _samePlace(FloorPlanElement a, FloorPlanElement? b) {
    if (b == null || a.points.length != b.points.length) return false;
    for (var i = 0; i < a.points.length; i++) {
      if (a.points[i] != b.points[i]) return false;
    }
    return a.rotationDegrees == b.rotationDegrees &&
        a.labelOffset == b.labelOffset;
  }

  Future<void> deleteSelected() async {
    if (!hasSelection) return;
    final ids = _selected;
    final objectIds = _selectedObjects;
    final placementIds = _selectedPlacements;
    await _run(() async {
      final removed = await _repo.deleteElements(ids);
      final removedObjects =
          await _objectsRepo?.deleteObjects(objectIds) ?? const [];
      final removedPorts = await _deletePortsOf(removedObjects);
      final removedPlacements =
          await _placementsRepo?.deletePlacements(placementIds) ?? const [];
      if (removed.isEmpty &&
          removedObjects.isEmpty &&
          removedPlacements.isEmpty) {
        return;
      }
      _record(
        _PlanChange(
          before: removed,
          objectsBefore: removedObjects,
          placementsBefore: removedPlacements,
          portsBefore: removedPorts.ports,
          cablesBefore: removedPorts.cables,
        ),
      );
      _selected = const {};
      _selectedObjects = const {};
      _selectedPlacements = const {};
      await _refreshElements();
    });
  }

  // ── Αντιγραφή / αποκοπή / επικόλληση ─────────────────────────────────

  /// Κρατά την επιλογή — μαζί με τα ανοίγματα των τοίχων της — για
  /// επικόλληση. Οι θέσεις του Καταλόγου δεν αντιγράφονται: τηλέφωνο και
  /// εξοπλισμός έχουν μία μόνο θέση.
  void copySelected() {
    if (!hasSelection) return;
    _clipboard = withOwnedOpenings(_selected, _elements);
    _objectClipboard = [
      for (final o in _objects)
        if (_selectedObjects.contains(o.id)) o,
    ];
    _pasteCount = 0;
    notifyListeners();
  }

  Future<void> cutSelected() async {
    copySelected();
    await deleteSelected();
  }

  /// Επικολλά ό,τι αντιγράφηκε, μετατοπισμένο κατά [step] για κάθε
  /// επικόλληση, και επιλέγει τα νέα στοιχεία.
  ///
  /// Επιστρέφει τα τμήματα που απέκτησαν δεύτερο χώρο, για ενημέρωση.
  ///
  /// Τα αντικείμενα επικολλώνται **χωρίς όνομα, IP και όνομα Lansweeper**:
  /// δύο εκτυπωτές δεν έχουν το ίδιο όνομα.
  Future<Set<int>> paste({Offset step = const Offset(100, 100)}) async {
    if (!canPaste) return const {};
    _pasteCount++;
    final delta = step * _pasteCount.toDouble();
    final source = _clipboard;
    final objectSource = _objectClipboard;
    final departments = <int>{};
    await _run(() async {
      final stored = <FloorPlanElement>[];
      final newIds = <int, int>{};
      // Πρώτα οι τοίχοι, ώστε τα ανοίγματά τους να ξέρουν τον νέο τοίχο.
      final ordered = [
        ...source.where((e) => e.kind != FloorPlanElementKind.opening),
        ...source.where((e) => e.kind == FloorPlanElementKind.opening),
      ];
      for (final e in ordered) {
        var copy = translateElement(e, delta);
        if (e.kind == FloorPlanElementKind.opening) {
          final parent = newIds[e.parentId];
          if (parent == null) continue;
          copy = copy.copyWith(parentId: parent);
        }
        final id = await _repo.insertElement(copy);
        newIds[e.id] = id;
        stored.add(copy.copyWith(id: id));
        final department = e.departmentId;
        if (department != null) departments.add(department);
      }
      final storedObjects = <FloorPlanObject>[];
      final storedPorts = <FloorPlanPort>[];
      final objectsRepo = _objectsRepo;
      if (objectsRepo != null) {
        for (final o in objectSource) {
          // Χωρίς stack: το αντίγραφο είναι άλλο μηχάνημα, όχι δεύτερο μέλος
          // με τον ίδιο αριθμό.
          final copy = translateFloorPlanObject(
            o
                .withDetails(notes: o.notes)
                .withStack(stackId: null, stackUnit: null),
            delta,
          );
          final id = await objectsRepo.insertObject(copy);
          storedObjects.add(copy.copyWith(id: id));
          // Ίδιο πλήθος θυρών, χωρίς γραμμένα ονόματα: είναι άλλη συσκευή.
          final count = portsOf(o.id).length;
          if (count > 0 && _portsRepo != null) {
            storedPorts.addAll(
              await _portsRepo.insertPorts([
                for (var n = 1; n <= count; n++)
                  FloorPlanPort(id: 0, objectId: id, number: n),
              ]),
            );
          }
        }
      }
      _record(
        _PlanChange(
          after: stored,
          objectsAfter: storedObjects,
          portsAfter: storedPorts,
        ),
      );
      _elements = [..._elements, ...stored];
      _objects = [..._objects, ...storedObjects];
      if (storedPorts.isNotEmpty) await _reloadPorts();
      _selected = {
        for (final e in stored)
          if (e.kind != FloorPlanElementKind.opening) e.id,
      };
      _selectedObjects = {for (final o in storedObjects) o.id};
      _selectedPlacements = const {};
    });
    return departments;
  }

  Future<void> _add(List<FloorPlanElement> drafts) async {
    await _run(() async {
      final stored = <FloorPlanElement>[];
      for (final d in drafts) {
        final id = await _repo.insertElement(d);
        stored.add(d.copyWith(id: id));
      }
      _record(_PlanChange(after: stored));
      _elements = [..._elements, ...stored];
    });
  }

  /// Γράφει νέες εκδοχές υπαρχόντων στοιχείων και αντικειμένων (ίδια id)
  /// ως μία κίνηση.
  Future<void> _replace(
    List<FloorPlanElement> next, {
    List<FloorPlanObject> objects = const [],
    List<FloorPlanPlacement> placements = const [],
  }) async {
    final before = [for (final e in next) ?elementById(e.id)];
    final objectsBefore = [for (final o in objects) ?objectById(o.id)];
    final placementsBefore = [for (final p in placements) ?placementById(p.id)];
    await _run(() async {
      await _repo.restoreElements(next);
      if (objects.isNotEmpty) await _objectsRepo?.restoreObjects(objects);
      if (placements.isNotEmpty) {
        await _placementsRepo?.restorePlacements(placements);
      }
      _record(
        _PlanChange(
          before: before,
          after: next,
          objectsBefore: objectsBefore,
          objectsAfter: objects,
          placementsBefore: placementsBefore,
          placementsAfter: placements,
        ),
      );
      await _refreshElements();
    });
  }

  Future<void> _replaceObjects(List<FloorPlanObject> next) =>
      _replace(const [], objects: next);

  void _record(_PlanChange change) {
    _undo.add(change);
    _redo.clear();
  }

  Future<void> undo() async {
    if (!canUndo) return;
    final change = _undo.removeLast();
    await _run(() async {
      final applied = await _apply(change.inverse);
      _redo.add(applied.inverse);
    });
  }

  Future<void> redo() async {
    if (!canRedo) return;
    final change = _redo.removeLast();
    await _run(() async {
      final applied = await _apply(change);
      _undo.add(applied);
    });
  }

  /// Φέρνει τη βάση από το [_PlanChange.before] στο [_PlanChange.after] και
  /// επιστρέφει την αλλαγή όπως πραγματικά έγινε — η διαγραφή ενός τοίχου
  /// παίρνει μαζί και τα ανοίγματά του, που πρέπει να επιστρέψουν όλα με την
  /// αντίστροφη κίνηση.
  Future<_PlanChange> _apply(_PlanChange change) async {
    final keep = {for (final e in change.after) e.id};
    final removed = await _repo.deleteElements([
      for (final e in change.before)
        if (!keep.contains(e.id)) e.id,
    ]);
    await _repo.restoreElements(change.after);
    final removedIds = {for (final e in removed) e.id};
    if (_selected.any(removedIds.contains)) {
      _selected = _selected.difference(removedIds);
    }

    final keepObjects = {for (final o in change.objectsAfter) o.id};
    final objectsRepo = _objectsRepo;
    var removedObjects = const <FloorPlanObject>[];
    if (objectsRepo != null) {
      removedObjects = await objectsRepo.deleteObjects([
        for (final o in change.objectsBefore)
          if (!keepObjects.contains(o.id)) o.id,
      ]);
      await objectsRepo.restoreObjects(change.objectsAfter);
    }
    final removedObjectIds = {for (final o in removedObjects) o.id};
    if (_selectedObjects.any(removedObjectIds.contains)) {
      _selectedObjects = _selectedObjects.difference(removedObjectIds);
    }

    // Οι θύρες: όσες σβήστηκαν μαζί με τα αντικείμενά τους πριν, και όσες
    // ζητά ρητά η αλλαγή.
    final keepPorts = {for (final p in change.portsAfter) p.id};
    final portsRepo = _portsRepo;
    var removedPorts = const <FloorPlanPort>[];
    final keepCables = {for (final c in change.cablesAfter) c.id};
    final removedCables = <int, FloorPlanCable>{};
    if (portsRepo != null) {
      for (final c in await portsRepo.deleteCables([
        for (final c in change.cablesBefore)
          if (!keepCables.contains(c.id)) c.id,
      ])) {
        removedCables[c.id] = c;
      }
      final ofObjects = await portsRepo.deletePortsOfObjects(removedObjectIds);
      final explicit = await portsRepo.deletePorts([
        for (final p in change.portsBefore)
          if (!keepPorts.contains(p.id)) p.id,
      ]);
      removedPorts = [...ofObjects.ports, ...explicit.ports];
      for (final c in [...ofObjects.cables, ...explicit.cables]) {
        removedCables[c.id] = c;
      }
      await portsRepo.restorePorts(change.portsAfter);
      // Οι θύρες πρώτα: το καλώδιο θέλει και τα δύο του άκρα.
      final skipped = await portsRepo.restoreCables(change.cablesAfter);
      if (skipped.isNotEmpty) {
        onError(
          'Μία σύνδεση με patch panel δεν επανήλθε: η θύρα του έχει πια άλλη '
          'σύνδεση ή δεν υπάρχει.',
        );
      }
    }
    final removedPortIds = {for (final p in removedPorts) p.id};

    final keepPlacements = {for (final p in change.placementsAfter) p.id};
    final placementsRepo = _placementsRepo;
    var removedPlacements = const <FloorPlanPlacement>[];
    if (placementsRepo != null) {
      removedPlacements = await placementsRepo.deletePlacements([
        for (final p in change.placementsBefore)
          if (!keepPlacements.contains(p.id)) p.id,
      ]);
      await placementsRepo.restorePlacements(change.placementsAfter);
    }
    final removedPlacementIds = {for (final p in removedPlacements) p.id};
    _selectedPlacements = _selectedPlacements.difference({
      ...removedPlacementIds,
      // Θέση που η αναίρεση γύρισε σε άλλον όροφο δεν είναι πια εδώ.
      for (final p in change.placementsAfter)
        if (p.floorId != floorId) p.id,
    });
    await _refreshElements();
    return _PlanChange(
      before: [
        ...removed,
        for (final e in change.before)
          if (keep.contains(e.id) && !removedIds.contains(e.id)) e,
      ],
      after: change.after,
      objectsBefore: [
        ...removedObjects,
        for (final o in change.objectsBefore)
          if (keepObjects.contains(o.id) && !removedObjectIds.contains(o.id)) o,
      ],
      objectsAfter: change.objectsAfter,
      placementsBefore: [
        ...removedPlacements,
        for (final p in change.placementsBefore)
          if (keepPlacements.contains(p.id) &&
              !removedPlacementIds.contains(p.id))
            p,
      ],
      placementsAfter: change.placementsAfter,
      portsBefore: [
        ...removedPorts,
        for (final p in change.portsBefore)
          if (keepPorts.contains(p.id) && !removedPortIds.contains(p.id)) p,
      ],
      portsAfter: change.portsAfter,
      cablesBefore: removedCables.values.toList(),
      cablesAfter: change.cablesAfter,
    );
  }

  Future<void> _reloadPorts() async {
    final portsRepo = _portsRepo;
    if (portsRepo == null) return;
    _ports = await portsRepo.listForFloor(floorId);
    _occupiedPorts = await portsRepo.occupiedPortIds([
      for (final p in _ports) p.id,
    ]);
    _portLinks = await portsRepo.linksForFloor(floorId);
    _portCables = FloorPlanPortCables(
      await portsRepo.cableLinesForFloor(floorId),
    );
  }

  Future<void> _refreshElements() async {
    _elements = await _repo.listElements(floorId);
    final objectsRepo = _objectsRepo;
    if (objectsRepo != null) _objects = await objectsRepo.listObjects(floorId);
    await _reloadPorts();
    final placementsRepo = _placementsRepo;
    if (placementsRepo != null) {
      _placements = await placementsRepo.listPlacements(floorId);
      _allPlacements = await placementsRepo.allPlacements();
    }
  }

  /// Τρέχει μια εγγραφή· σε αποτυχία ενημερώνει τον χρήστη και ξαναδιαβάζει
  /// τη βάση, ώστε η οθόνη να δείχνει ό,τι πραγματικά γράφτηκε.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    try {
      await action();
    } catch (e) {
      onError('Η αλλαγή δεν αποθηκεύτηκε: $e');
      try {
        await _refreshElements();
      } catch (_) {
        // Η βάση δεν απαντά καθόλου· το μήνυμα έχει ήδη δοθεί.
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ── Πατρόν ────────────────────────────────────────────────────────────

  /// Φορτώνει νέα εικόνα πατρόν, κεντραρισμένη στο [center].
  ///
  /// Αν ο όροφος έχει ήδη βαθμονομηθεί, η κλίμακα κρατιέται: το νέο σχέδιο
  /// της Τεχνικής Υπηρεσίας του ίδιου ορόφου πιθανότατα έχει άλλη, αλλά
  /// είναι καλύτερη αφετηρία από το «ένα pixel = ένα εκατοστό».
  Future<void> setPatternImage(
    Uint8List bytes, {
    required Offset center,
  }) async {
    await _run(() async {
      final placement = _state.copyWith(
        patternCenter: center,
        patternRotationDegrees: 0,
        patternHidden: false,
      );
      await _repo.setPattern(floorId, bytes, placement);
      _state = await _repo.readState(floorId);
      // Τα bytes είναι ήδη εδώ — μόλις τα γράψαμε. Χωρίς αυτό, η φόρτωση
      // κάτοψης θα κατέβαζε αμέσως από το δίκτυο ό,τι μόλις ανέβασε.
      _patternCache.put(_state.patternHash, bytes);
      await _reloadPatternImage();
    });
  }

  Future<void> removePattern() async {
    await _run(() async {
      await _repo.clearPattern(floorId);
      _state = await _repo.readState(floorId);
      await _reloadPatternImage();
    });
  }

  /// Αλλάζει την τοποθέτηση **μόνο στην οθόνη** — για όσο κρατά ένα σύρσιμο
  /// ή η κίνηση ενός ρυθμιστή. Η εγγραφή γίνεται με [commitPattern].
  void previewPattern(FloorPlanState next) {
    _state = next;
    notifyListeners();
  }

  Future<void> commitPattern() async {
    await _run(() => _repo.savePatternPlacement(_state));
  }

  Future<void> updatePattern(FloorPlanState next) async {
    _state = next;
    notifyListeners();
    await commitPattern();
  }

  /// Βαθμονόμηση: η γραμμή [a]–[b] είναι στην πραγματικότητα [realCm]. Το
  /// [a] μένει ακίνητο, και η εικόνα μεγαλώνει ή μικραίνει γύρω του.
  Future<void> calibrate(Offset a, Offset b, double realCm) async {
    final measured = (b - a).distance;
    if (measured <= 0 || realCm <= 0) return;
    final factor = realCm / measured;
    await updatePattern(
      _state.copyWith(
        cmPerPixel: calibratedCmPerPixel(
          currentCmPerPixel: _state.cmPerPixel,
          measuredCm: measured,
          realCm: realCm,
        ),
        patternCenter: scaleCenterAbout(
          center: _state.patternCenter,
          anchor: a,
          factor: factor,
        ),
        patternCalibrated: true,
      ),
    );
  }

  @override
  void dispose() {
    _patternImage?.dispose();
    super.dispose();
  }
}
