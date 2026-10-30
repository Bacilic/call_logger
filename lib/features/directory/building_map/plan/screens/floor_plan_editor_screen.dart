// Αξιολογήθηκε για διάσπαση 29/10/2026 — μένει ως έχει.
//
// Ρόλος: μεταφράζει ποντίκι και πληκτρολόγιο σε «τι σχεδιάζεται τώρα» για
// κάθε εργαλείο, και δείχνει το πρόχειρο σχέδιο και τις οδηγίες της γραμμής
// κατάστασης. Αποθήκευση και αναίρεση, γεωμετρία, ζωγραφική, επιλογή,
// διάλογοι και πάνελ ζουν ήδη σε δικά τους αρχεία.
//
// Γιατί δεν σπάει: όλα τα παραπάνω μοιράζονται την ίδια κατάσταση του
// προχείρου (αρχή τοίχου, πληκτρολογημένο μήκος, γωνίες χώρου, σημεία
// διάστασης, μέτρηση, άνοιγμα). Το ποντίκι και το πληκτρολόγιο τη γράφουν, η
// ζωγραφική και οι οδηγίες τη διαβάζουν· κομμένα, θα χρειάζονταν 7–8 τιμές το
// καθένα.
//
// Ξανακρίθηκε 29/10/2026 με τα αντικείμενα του χάρτη: το εργαλείο
// «Αντικείμενο» (έπιπλο σε δύο γωνίες, πληκτρολόγηση διαστάσεων) και το
// πλαίσιο στοιχείων είναι ο ίδιος ρόλος — ποντίκι σε πρόχειρο. Η γεωμετρία
// τους ζει στο floor_plan_objects.dart, το πλαίσιο σε δικό του widget.
//
// Τι θα το άλλαζε: υπολογισμός που δεν εξαρτάται από το πρόχειρο, εγγραφές
// στη βάση πέρα από τις κλήσεις του ελεγκτή και του Καταλόγου, ή μια δεύτερη
// ροή αρχείων πέρα από τη φόρτωση πατρόν.

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/database/building_map_repository.dart';
import '../../../../../core/database/database_helper.dart';
import '../../../../../core/database/department_repository.dart';
import '../../../../../core/database/floor_plan_objects_repository.dart';
import '../../../../../core/database/floor_plan_placements_repository.dart';
import '../../../../../core/database/floor_plan_ports_repository.dart';
import '../../../../../core/database/floor_plan_repository.dart';
import '../../../../../core/models/building_map_floor.dart';
import '../../../../../core/utils/file_picker_session.dart';
import '../../../../../core/utils/picker_location_memory.dart';
import '../../../models/department_model.dart';
import '../../services/floor_plan_image_encoder.dart';
import '../floor_plan_cabinet.dart';
import '../floor_plan_editor_controller.dart';
import '../floor_plan_geometry.dart';
import '../floor_plan_measure.dart';
import '../../../../../core/models/floor_plan_element.dart';
import '../../../../../core/models/floor_plan_object.dart';
import '../../../../../core/models/floor_plan_placement.dart';
import '../../../../../core/models/floor_plan_port.dart';
import '../floor_plan_item_info.dart';
import '../floor_plan_objects.dart';
import '../floor_plan_ports.dart';
import '../floor_plan_rooms.dart';
import '../floor_plan_select_interaction.dart';
import '../floor_plan_selection.dart';
import '../floor_plan_view_transform.dart';
import '../services/floor_plan_catalog.dart';
import '../widgets/floor_plan_activation_dialog.dart';
import '../services/floor_plan_layers_preference.dart';
import '../widgets/floor_plan_cabinet_panel.dart';
import '../widgets/floor_plan_cabinet_window.dart';
import '../services/floor_plan_cabinet_preferences.dart';
import '../widgets/floor_plan_port_facade.dart';
import '../widgets/floor_plan_item_card.dart';
import '../widgets/floor_plan_layers_button.dart';
import '../widgets/floor_plan_measure_painter.dart';
import '../widgets/floor_plan_object_editor.dart';
import '../widgets/floor_plan_object_kinds_dialog.dart';
import '../widgets/floor_plan_placement_panel.dart';
import '../widgets/floor_plan_painter.dart';
import '../widgets/floor_plan_pattern_panel.dart';
import '../widgets/floor_plan_calibration_dialog.dart';
import '../widgets/floor_plan_room_flow.dart';
import '../widgets/floor_plan_room_label_bar.dart';
import '../widgets/floor_plan_room_views.dart';
import '../widgets/floor_plan_text_editor.dart';
import '../widgets/floor_plan_tool_rail.dart';

/// Ανοίγει την οθόνη σχεδίασης του νέου χάρτη για τον [floor].
///
/// Το [afterDepartmentChange] ανανεώνει όσες οθόνες δείχνουν τμήματα, όταν η
/// σχεδίαση ενός χώρου μεταφέρει τμήμα σε άλλον όροφο. Το [onActivated]
/// ανανεώνει τον χάρτη όταν ο όροφος περάσει στον νέο χάρτη.
Future<void> openFloorPlanEditor(
  BuildContext context,
  BuildingMapFloor floor, {
  required Future<void> Function() afterDepartmentChange,
  required VoidCallback onActivated,
}) async {
  final db = await DatabaseHelper.instance.database;
  if (!context.mounted) return;
  final maps = BuildingMapRepository(db);
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => FloorPlanEditorScreen(
        floor: floor,
        repository: FloorPlanRepository(db),
        objectsRepository: FloorPlanObjectsRepository(db),
        placementsRepository: FloorPlanPlacementsRepository(db),
        portsRepository: FloorPlanPortsRepository(db),
        catalog: DatabaseFloorPlanCatalog(
          departmentRepository: DepartmentRepository(db),
          buildingMapRepository: maps,
          afterDepartmentChange: afterDepartmentChange,
        ),
        readFloorPlanImage: () async =>
            (await maps.readFloorImage(floor.id))?.bytes,
        onActivated: onActivated,
        openObjectKinds: (context) async {
          final floors = {
            for (final f in await maps.listBuildingMapFloors()) f.id: f.label,
          };
          if (!context.mounted) return;
          await showFloorPlanObjectKindsDialog(
            context,
            repository: FloorPlanObjectsRepository(db),
            floorLabel: (id) => floors[id] ?? 'όροφος που διαγράφηκε',
          );
        },
      ),
    ),
  );
}

/// Η οθόνη σχεδίασης ενός ορόφου στον νέο χάρτη.
///
/// Ό,τι σχεδιάζεται εδώ **δεν το βλέπουν ακόμη οι συνάδελφοι**: συνεχίζουν
/// με τον παλιό χάρτη ώσπου ο όροφος να ενεργοποιηθεί.
class FloorPlanEditorScreen extends StatefulWidget {
  const FloorPlanEditorScreen({
    super.key,
    required this.floor,
    required this.repository,
    required this.catalog,
    required this.readFloorPlanImage,
    this.onActivated,
    this.openObjectKinds,
    this.objectsRepository,
    this.placementsRepository,
    this.portsRepository,
  });

  final BuildingMapFloor floor;
  final FloorPlanRepository repository;

  /// Τα αντικείμενα του χάρτη· χωρίς αυτό η σχεδίαση δεν έχει αντικείμενα.
  final FloorPlanObjectsRepository? objectsRepository;

  /// Οι θέσεις του Καταλόγου· χωρίς αυτό η σχεδίαση δεν τοποθετεί τίποτα.
  final FloorPlanPlacementsRepository? placementsRepository;

  /// Οι θύρες· χωρίς αυτό η σχεδίαση δεν δείχνει θύρες.
  final FloorPlanPortsRepository? portsRepository;
  final FloorPlanCatalog catalog;

  /// Ο όροφος μόλις πέρασε στον νέο χάρτη.
  final VoidCallback? onActivated;

  /// Η σημερινή εικόνα κάτοψης του ορόφου, για «Από την κάτοψη του ορόφου».
  final Future<Uint8List?> Function() readFloorPlanImage;

  /// Ανοίγει το παράθυρο «Είδη αντικειμένων»· χωρίς αυτό το κουμπί δεν
  /// εμφανίζεται.
  final Future<void> Function(BuildContext context)? openObjectKinds;

  @override
  State<FloorPlanEditorScreen> createState() => _FloorPlanEditorScreenState();
}

class _FloorPlanEditorScreenState extends State<FloorPlanEditorScreen> {
  late final FloorPlanEditorController _controller;
  final FocusNode _canvasFocus = FocusNode(debugLabel: 'floor-plan-canvas');

  FloorPlanViewTransform? _view;
  Size _canvasSize = Size.zero;

  /// Πού βρίσκεται ο δείκτης, σε συντεταγμένες σχεδίου.
  Offset? _hoverWorld;

  /// Η αρχή του τοίχου που σχεδιάζεται τώρα· `null` όταν δεν σχεδιάζεται.
  Offset? _wallStart;

  /// Ό,τι έχει πληκτρολογηθεί ως μήκος (σε μέτρα) για τον επόμενο τοίχο.
  String _typedLength = '';

  // Κατάσταση ενός πατήματος ποντικιού.
  Offset? _downScreen;
  Offset? _lastScreen;
  bool _dragged = false;
  bool _panning = false;
  DateTime? _lastClickAt;
  Offset? _lastClickScreen;

  FloorPlanSegment? _openingWall;
  Offset? _openingDragStart;
  ({double start, double end})? _openingRange;

  Offset? _measureStart;
  Offset? _measureEnd;

  /// Οι γωνίες του χώρου που σχεδιάζεται με κλικ.
  List<Offset> _roomCorners = const [];

  /// Τα σημεία της διάστασης που σχεδιάζεται: άκρα, και μετά η απόσταση.
  List<Offset> _dimensionPoints = const [];

  /// Η μέτρηση απόστασης του εργαλείου «Μέτρηση» — δεν αποθηκεύεται.
  FloorPlanMeasure _measure = FloorPlanMeasure.empty;

  /// Η πρώτη γωνία του επίπλου που σχεδιάζεται· `null` όταν δεν σχεδιάζεται.
  Offset? _volumeStart;

  /// Οι διαστάσεις του επίπλου όπως πληκτρολογούνται (π.χ. «1,60 x 0,80»).
  String _typedVolume = '';

  final FloorPlanLabelCache _labelCache = FloorPlanLabelCache();

  /// Το αντικείμενο του οποίου τα στοιχεία γράφονται τώρα στο πλαίσιο.
  int? _objectDraftId;
  final GlobalKey<FloorPlanObjectEditorState> _objectEditorKey = GlobalKey();

  late final FloorPlanSelectInteraction _select = FloorPlanSelectInteraction(
    _controller,
    roomLabelAt: _roomLabelAt,
  );

  /// Ο χώρος του οποίου το όνομα βρίσκεται στο [screen]· το πιο πρόσφατο
  /// πρώτο, όπως ζωγραφίζεται από πάνω.
  int? _roomLabelAt(Offset screen, FloorPlanViewTransform view) {
    final rooms = buildFloorPlanRoomViews(_controller.rooms, _departments);
    for (final room in rooms.reversed) {
      final label = floorPlanRoomLabelRect(room, view);
      if (label != null && label.inflate(2).contains(screen)) return room.id;
    }
    return null;
  }

  /// Τα τμήματα του Καταλόγου, για τα ονόματα και τα χρώματα των χώρων.
  Map<int, DepartmentModel> _departments = const {};

  /// Ένας διάλογος χώρου είναι ανοιχτός — δεύτερο κλικ δεν ανοίγει δεύτερο.
  bool _roomDialogOpen = false;

  /// Το κείμενο που γράφεται τώρα στο πλαίσιο πάνω στον χάρτη· `null` όταν
  /// δεν γράφεται κανένα.
  _TextDraft? _textDraft;
  final GlobalKey _textFieldKey = GlobalKey();
  final GlobalKey<FloorPlanTextEditorState> _textEditorKey = GlobalKey();
  final GlobalKey _canvasKey = GlobalKey();

  /// Το μέγεθος ονόματος χώρου που ζητήθηκε με A− / A+ και δεν έχει γραφτεί
  /// ακόμη: το επόμενο γρήγορο πάτημα ξεκινά από εδώ, όχι από την παλιά τιμή.
  ({int id, double sizeCm})? _labelSizePending;
  bool _labelSizeWriting = false;

  /// Γράφει το μέγεθος ονόματος που ζητήθηκε **τελευταίο**. Ο ελεγκτής
  /// αγνοεί αλλαγή όσο γράφεται άλλη· γι' αυτό τα γρήγορα πατήματα
  /// μαζεύονται εδώ και γράφονται μόλις τελειώσει η προηγούμενη εγγραφή.
  Future<void> _setRoomLabelSize(int id, double sizeCm) async {
    setState(() => _labelSizePending = (id: id, sizeCm: sizeCm));
    if (_labelSizeWriting) return;
    _labelSizeWriting = true;
    try {
      while (mounted) {
        final want = _labelSizePending;
        if (want == null) break;
        await _controller.setRoomLabel(want.id, sizeCm: want.sizeCm);
        if (_labelSizePending == want) {
          _labelSizePending = null;
          break;
        }
      }
    } finally {
      _labelSizeWriting = false;
      if (mounted) setState(() {});
    }
  }

  /// Το κλικ που έκλεισε το πλαίσιο κειμένου δεν κάνει τίποτε άλλο.
  bool _swallowClick = false;

  /// Το πάνελ του πατρόν φαίνεται μόνο όταν το ανοίξει ο χρήστης: τον
  /// περισσότερο χρόνο σχεδιάζει, και ο καμβάς θέλει όλο το πλάτος.
  bool _patternPanelOpen = false;

  static const double _clickSlop = 5;
  static const double _pickPixels = 10;

  double get _floorRotation => widget.floor.rotationDegrees * math.pi / 180;

  @override
  void initState() {
    super.initState();
    _controller = FloorPlanEditorController(
      floorId: widget.floor.id,
      repository: widget.repository,
      objectsRepository: widget.objectsRepository,
      placementsRepository: widget.placementsRepository,
      portsRepository: widget.portsRepository,
      onError: _showMessage,
    )..addListener(_onControllerChanged);
    _controller.load();
    _loadDepartments();
    _loadFloorLabels();
    FloorPlanLayersPreference.read().then((hidden) {
      if (mounted) _controller.setHiddenLayers(hidden);
    });
  }

  /// Τα ονόματα των ορόφων, για το «έχει ήδη θέση στο …».
  Map<int, String> _floorLabels = const {};

  /// Η εγγραφή του Καταλόγου που περιμένει κλικ στον χάρτη.
  FloorPlanCatalogEntry? _armedEntry;

  Future<void> _loadFloorLabels() async {
    try {
      final floors = await widget.catalog.floors();
      if (!mounted) return;
      setState(() => _floorLabels = {for (final f in floors) f.id: f.label});
    } catch (_) {
      // Χωρίς ονόματα ορόφων το πάνελ γράφει «άλλος όροφος» — δεν σταματά.
    }
  }

  String _floorLabel(int floorId) => _floorLabels[floorId] ?? 'άλλος όροφος';

  Future<void> _loadDepartments() async {
    try {
      final list = await widget.catalog.departments();
      if (!mounted) return;
      setState(() {
        _departments = {
          for (final d in list)
            if (d.id != null) d.id!: d,
        };
      });
    } catch (e) {
      _showMessage('Τα τμήματα δεν διαβάστηκαν: $e');
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _canvasFocus.dispose();
    _labelCache.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    // Άλλο εργαλείο = τέλος γραψίματος, όπως ένα κλικ έξω από το πλαίσιο.
    final draft = _textDraft;
    if (draft != null && _controller.tool != draft.tool) {
      _commitTextFromOutside();
    }
    // Αλλαγή εργαλείου κόβει ό,τι σχεδιαζόταν με το προηγούμενο.
    if (_controller.tool != FloorPlanTool.wall) {
      _wallStart = null;
      _typedLength = '';
    }
    if (_controller.tool != FloorPlanTool.room) _roomCorners = const [];
    if (_controller.tool != FloorPlanTool.measure) {
      _measure = FloorPlanMeasure.empty;
    }
    if (_controller.tool != FloorPlanTool.dimension) {
      _dimensionPoints = const [];
    }
    if (_controller.tool != FloorPlanTool.object) {
      _volumeStart = null;
      _typedVolume = '';
    }
    if (_controller.tool != FloorPlanTool.place) _armedEntry = null;
    final objectDraft = _objectDraftId;
    if (objectDraft != null && _controller.objectById(objectDraft) == null) {
      _objectDraftId = null;
    }
    setState(() {});
  }

  /// «Ενεργοποίηση νέου χάρτη»: δείχνει ποια τμήματα του ορόφου θα έλειπαν,
  /// και μετά από ρητό «ναι» ο όροφος περνά στον νέο χάρτη για όλους.
  Future<void> _activate() async {
    final List<DepartmentModel> departments;
    try {
      departments = await widget.catalog.departments();
    } catch (e) {
      _showMessage('Τα τμήματα δεν διαβάστηκαν: $e');
      return;
    }
    if (!mounted) return;
    final ok = await confirmFloorPlanActivation(
      context,
      floorLabel: widget.floor.label,
      missing: departmentsMissingFromFloorPlan(
        floorId: widget.floor.id,
        departments: departments,
        elements: _controller.elements,
      ),
    );
    if (!ok) return;
    try {
      // Πρώτα ο νέος χάρτης γίνεται ενεργός, μετά σβήνει ο παλιός: αν κάτι
      // αποτύχει στη μέση, ο όροφος δεν μένει χωρίς κανέναν χάρτη.
      await widget.repository.setActive(widget.floor.id);
      await widget.catalog.retireOldMap(widget.floor.id);
    } catch (e) {
      _showMessage('Η ενεργοποίηση δεν ολοκληρώθηκε: $e');
    }
    await _controller.load();
    widget.onActivated?.call();
    _showMessage('Ο όροφος «${widget.floor.label}» πέρασε στον νέο χάρτη.');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Θέαση ─────────────────────────────────────────────────────────────

  FloorPlanViewTransform _ensureView(Size size) {
    final existing = _view;
    if (existing != null) return existing;
    final fitted = FloorPlanViewTransform.fit(
      worldRect: _contentBounds(),
      viewport: size,
      rotationRadians: _floorRotation,
    );
    // Μόνο αφού φορτώσει: ως τότε δεν ξέρουμε τι πρέπει να χωρέσει.
    if (!_controller.loading) _view = fitted;
    return fitted;
  }

  /// Το πλαίσιο που περιέχει σχέδιο και πατρόν· ένα 40×30 μ. γύρω από την
  /// αρχή όταν ο όροφος είναι ακόμη άδειος.
  Rect _contentBounds() {
    Rect? bounds;
    void include(Rect r) =>
        bounds = bounds == null ? r : bounds!.expandToInclude(r);
    for (final w in _controller.wallSegments) {
      include(Rect.fromPoints(w.a, w.b));
    }
    for (final o in _controller.objectViews) {
      include(Rect.fromCircle(center: o.center, radius: o.size.longestSide));
    }
    final image = _controller.patternImage;
    final state = _controller.state;
    if (image != null && !state.patternHidden) {
      final half = math.max(image.width, image.height) * state.cmPerPixel / 2;
      include(Rect.fromCircle(center: state.patternCenter, radius: half));
    }
    return bounds ??
        Rect.fromCenter(center: Offset.zero, width: 4000, height: 3000);
  }

  void _fitAll() {
    setState(() {
      _view = FloorPlanViewTransform.fit(
        worldRect: _contentBounds(),
        viewport: _canvasSize,
        rotationRadians: _floorRotation,
      );
    });
  }

  // ── Ποντίκι ───────────────────────────────────────────────────────────

  bool get _magnetOff => HardwareKeyboard.instance.isShiftPressed;

  FloorPlanSnap _snap(Offset world, {Offset? from}) {
    final view = _view!;
    return snapWallPoint(
      raw: world,
      walls: _controller.wallSegments,
      toleranceCm: view.screenToCm(_pickPixels),
      from: from,
      magnetOff: _magnetOff,
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    final view = _view;
    if (event is! PointerScrollEvent || view == null) return;
    final factor = math.exp(-event.scrollDelta.dy / 400);
    setState(() => _view = view.zoomAt(event.localPosition, factor));
  }

  void _onPointerDown(PointerDownEvent event) {
    final view = _view;
    if (view == null) return;
    if (_textDraft != null) {
      _swallowClick = true;
      _commitTextFromOutside();
      return;
    }
    if (_objectDraftId != null) {
      _swallowClick = true;
      _commitObjectFromOutside();
      return;
    }
    _canvasFocus.requestFocus();
    _downScreen = event.localPosition;
    _lastScreen = event.localPosition;
    _dragged = false;
    _panning = false;

    if (event.buttons & kMiddleMouseButton != 0) {
      _panning = true;
      return;
    }
    if (event.buttons & kPrimaryMouseButton == 0) return;

    final world = view.toWorld(event.localPosition);
    switch (_controller.tool) {
      case FloorPlanTool.opening:
        final wall = nearestWall(
          world,
          _controller.wallSegments,
          view.screenToCm(_pickPixels),
        );
        if (wall == null) {
          _panning = true;
        } else {
          _openingWall = wall;
          _openingDragStart = world;
          _openingRange = null;
        }
      case FloorPlanTool.calibrate:
        if (_controller.patternImage == null) {
          _showMessage('Φορτώστε πρώτα ένα πατρόν.');
          return;
        }
        _measureStart = world;
        _measureEnd = world;
      case FloorPlanTool.movePattern:
        break;
      case FloorPlanTool.select:
        _select.down(event.localPosition, view);
      case FloorPlanTool.wall:
      case FloorPlanTool.room:
      case FloorPlanTool.text:
      case FloorPlanTool.dimension:
      case FloorPlanTool.measure:
      case FloorPlanTool.object:
      case FloorPlanTool.place:
        // Το κλικ κρίνεται στο άφημα· ένα σύρσιμο μετακινεί τον καμβά —
        // εκτός από το έπιπλο, που σχεδιάζεται και με σύρσιμο.
        break;
    }
    setState(() {});
  }

  bool get _placingVolume =>
      _controller.tool == FloorPlanTool.object &&
      (_controller.objectKind?.symbol?.isVolume ?? false);

  void _onPointerMove(PointerMoveEvent event) {
    final view = _view;
    final down = _downScreen;
    final last = _lastScreen;
    if (view == null || down == null || last == null) return;
    if ((event.localPosition - down).distance > _clickSlop) _dragged = true;
    final delta = event.localPosition - last;
    _lastScreen = event.localPosition;
    final world = view.toWorld(event.localPosition);
    _hoverWorld = world;

    if (_panning) {
      setState(() => _view = view.panBy(delta));
      return;
    }
    switch (_controller.tool) {
      case FloorPlanTool.opening:
        final wall = _openingWall;
        final start = _openingDragStart;
        if (wall != null && start != null) {
          setState(() => _openingRange = openingFromDrag(wall, start, world));
        }
      case FloorPlanTool.calibrate:
        if (_measureStart != null) setState(() => _measureEnd = world);
      case FloorPlanTool.movePattern:
        final worldDelta = world - view.toWorld(last);
        final state = _controller.state;
        _controller.previewPattern(
          state.copyWith(patternCenter: state.patternCenter + worldDelta),
        );
      case FloorPlanTool.select:
        _select.move(
          event.localPosition,
          view,
          dragged: _dragged,
          freeAngle: _magnetOff,
        );
        setState(() {});
      case FloorPlanTool.object when _placingVolume:
        // Σύρσιμο από γωνία σε γωνία: η πρώτη γωνία είναι εκεί που πατήθηκε.
        if (_dragged && _volumeStart == null) {
          _volumeStart = _snap(view.toWorld(down)).point;
        }
        setState(() {});
      case FloorPlanTool.wall:
      case FloorPlanTool.room:
      case FloorPlanTool.text:
      case FloorPlanTool.dimension:
      case FloorPlanTool.measure:
      case FloorPlanTool.object:
      case FloorPlanTool.place:
        if (_dragged) {
          _panning = true;
          setState(() => _view = view.panBy(event.localPosition - down));
        }
    }
  }

  Future<void> _onPointerUp(PointerUpEvent event) async {
    if (_swallowClick) {
      _swallowClick = false;
      return;
    }
    final view = _view;
    final wasDrag = _dragged;
    final wasPanning = _panning;
    _downScreen = null;
    _lastScreen = null;
    _panning = false;
    if (view == null || wasPanning) return;
    final world = view.toWorld(event.localPosition);

    switch (_controller.tool) {
      case FloorPlanTool.wall:
        if (!wasDrag) await _wallClick(event.localPosition, world);
      case FloorPlanTool.room:
        if (!wasDrag) await _roomClick(event.localPosition, world);
      case FloorPlanTool.select:
        await _selectUp(event.localPosition, view, wasDrag);
      case FloorPlanTool.text:
        if (!wasDrag) await _textClick(event.localPosition, world);
      case FloorPlanTool.dimension:
        if (!wasDrag) await _dimensionClick(world);
      case FloorPlanTool.measure:
        if (!wasDrag) _measureClick(event.localPosition, world);
      case FloorPlanTool.object:
        await _objectUp(world, wasDrag);
      case FloorPlanTool.place:
        final armed = _armedEntry;
        if (!wasDrag && armed != null) await _placeEntry(armed, world);
      case FloorPlanTool.opening:
        final wall = _openingWall;
        final range = _openingRange;
        _openingWall = null;
        _openingDragStart = null;
        _openingRange = null;
        setState(() {});
        if (wall?.id != null && range != null) {
          await _controller.addOpening(wall!.id!, range.start, range.end);
        }
      case FloorPlanTool.calibrate:
        final a = _measureStart;
        final b = _measureEnd;
        if (a != null && b != null && (b - a).distance > 0) {
          await _askCalibration(a, b);
        }
        setState(() {
          _measureStart = null;
          _measureEnd = null;
        });
      case FloorPlanTool.movePattern:
        await _controller.commitPattern();
    }
  }

  /// Το κλικ στο [screen] είναι το δεύτερο ενός διπλού κλικ — μισό δευτερόλεπτο,
  /// όσο και η προεπιλογή των Windows.
  bool _isDoubleClick(Offset screen) {
    final now = DateTime.now();
    final isDouble =
        _lastClickAt != null &&
        now.difference(_lastClickAt!) < const Duration(milliseconds: 500) &&
        _lastClickScreen != null &&
        (screen - _lastClickScreen!).distance <= _clickSlop;
    // Μετά από διπλό, το επόμενο κλικ ξεκινά από την αρχή — όχι τριπλό.
    _lastClickAt = isDouble ? null : now;
    _lastClickScreen = screen;
    return isDouble;
  }

  Future<void> _wallClick(Offset screen, Offset world) async {
    if (_isDoubleClick(screen)) {
      // Το πρώτο κλικ του διπλού έχει ήδη κλείσει τον τελευταίο τοίχο.
      setState(() {
        _wallStart = null;
        _typedLength = '';
      });
      return;
    }

    final start = _wallStart;
    final point = _snap(world, from: start).point;
    if (start == null) {
      setState(() => _wallStart = point);
      return;
    }
    await _commitWall(start, point);
  }

  // ── Χώροι ─────────────────────────────────────────────────────────────

  /// Κλικ με το εργαλείο «Χώρος»: κάθε κλικ μια γωνία· κλικ στην πρώτη γωνία
  /// κλείνει τον χώρο. Διπλό κλικ **χωρίς** γωνίες βρίσκει μόνο του τον χώρο
  /// μέσα στους τοίχους γύρω από το σημείο.
  Future<void> _roomClick(Offset screen, Offset world) async {
    if (_isDoubleClick(screen)) {
      // Το πρώτο κλικ του διπλού έβαλε μία γωνία· αν ήταν η μόνη, ο χρήστης
      // ήθελε τον αυτόματο χώρο.
      if (_roomCorners.length <= 1) {
        setState(() => _roomCorners = const []);
        await _autoRoom(world);
      } else {
        await _finishRoomCorners();
      }
      return;
    }
    final view = _view!;
    final corners = _roomCorners;
    if (corners.length >= 3 &&
        (view.toScreen(corners.first) - screen).distance <= _pickPixels) {
      await _finishRoomCorners();
      return;
    }
    final from = corners.isEmpty ? null : corners.last;
    final point = _snap(world, from: from).point;
    setState(() => _roomCorners = [...corners, point]);
  }

  Future<void> _autoRoom(Offset world) async {
    final corners = enclosingRoom(world, _controller.wallSegments);
    if (corners == null) {
      _showMessage(
        'Το σημείο δεν είναι κλεισμένο από τοίχους. Κλείστε τους τοίχους ή '
        'ορίστε τον χώρο με κλικ στις γωνίες του.',
      );
      return;
    }
    await _createRoom(corners);
  }

  Future<void> _finishRoomCorners() async {
    final corners = _roomCorners;
    setState(() => _roomCorners = const []);
    if (corners.length < 3) return;
    await _createRoom(corners);
  }

  Future<void> _createRoom(List<Offset> corners) async {
    if (_roomDialogOpen) return;
    _roomDialogOpen = true;
    try {
      final choice = await chooseRoomIdentity(
        context,
        catalog: widget.catalog,
        repository: widget.repository,
        floor: widget.floor,
        title: 'Νέος χώρος',
        inform: _showMessage,
      );
      if (choice == null) return;
      await _controller.addRoom(
        corners,
        name: choice.name,
        departmentId: choice.departmentId,
      );
      await _loadDepartments();
    } finally {
      _roomDialogOpen = false;
    }
  }

  Future<void> _renameRoom(int id) async {
    final room = _controller.elementById(id);
    if (room == null || _roomDialogOpen) return;
    _roomDialogOpen = true;
    try {
      final choice = await chooseRoomIdentity(
        context,
        catalog: widget.catalog,
        repository: widget.repository,
        floor: widget.floor,
        title: 'Αλλαγή χώρου',
        inform: _showMessage,
        currentDepartmentId: room.departmentId,
        currentName: room.name,
      );
      if (choice == null) return;
      await _controller.renameRoom(
        id,
        name: choice.name,
        departmentId: choice.departmentId,
      );
      await _loadDepartments();
    } finally {
      _roomDialogOpen = false;
    }
  }

  /// Άφημα με το εργαλείο «Επιλογή». Διπλό κλικ σε χώρο αλλάζει το όνομά
  /// του, σε κείμενο το περιεχόμενο και το μέγεθός του.
  Future<void> _selectUp(
    Offset screen,
    FloorPlanViewTransform view,
    bool wasDrag,
  ) async {
    final doubleClick = !wasDrag && _isDoubleClick(screen);
    await _select.up(
      screen,
      view,
      dragged: wasDrag,
      additive: HardwareKeyboard.instance.isControlPressed,
    );
    if (mounted) setState(() {});
    if (!doubleClick) return;
    final hitObject = _select.lastHitObject;
    if (hitObject != null) {
      if (hitObject.source == FloorPlanItemSource.object) {
        _editObject(hitObject.id);
      }
      return;
    }
    final hit = _select.lastHit;
    if (hit == null) return;
    switch (hit.kind) {
      case FloorPlanElementKind.room:
        await _renameRoom(hit.id);
      case FloorPlanElementKind.text:
        _editText(hit);
      case FloorPlanElementKind.wall:
      case FloorPlanElementKind.opening:
      case FloorPlanElementKind.dimension:
        break;
    }
  }

  // ── Αντικείμενα ───────────────────────────────────────────────────────

  /// Άφημα με το εργαλείο «Αντικείμενο». Σύμβολο: κλικ = νέο αντικείμενο.
  /// Έπιπλο: κλικ στη μία γωνία και κλικ στην άλλη, ή σύρσιμο από γωνία σε
  /// γωνία. Μόλις μπει, ανοίγει το πλαίσιο στοιχείων του.
  Future<void> _objectUp(Offset world, bool wasDrag) async {
    final kind = _controller.objectKind;
    if (kind == null) return;
    if (!_placingVolume) {
      if (wasDrag) return;
      final placed = await _controller.addObject(kind.id, world);
      if (placed != null) _editObject(placed.id);
      return;
    }
    // Χωρίς μαγνήτη γωνίας: η διαγώνιος ενός γραφείου δεν κουμπώνει ανά 15°.
    final start = _volumeStart;
    final point = _snap(world).point;
    if (start == null) {
      setState(() => _volumeStart = point);
      return;
    }
    await _finishVolume(start, point);
  }

  Future<void> _finishVolume(Offset start, Offset toward) async {
    final kind = _controller.objectKind;
    if (kind == null) return;
    final volume = floorPlanVolumeToward(
      start,
      toward,
      parseVolumeSizeMeters(_typedVolume),
    );
    setState(() {
      _volumeStart = null;
      _typedVolume = '';
    });
    final placed = await _controller.addObject(
      kind.id,
      volume.center,
      size: volume.size,
    );
    if (placed != null) _editObject(placed.id);
  }

  /// Οι γωνίες του επίπλου που σχεδιάζεται, ως εκεί που δείχνει ο δείκτης.
  List<Offset> _volumeDraftCorners() {
    final start = _volumeStart;
    final hover = _hoverWorld;
    if (start == null || hover == null) return const [];
    final volume = floorPlanVolumeToward(
      start,
      _snap(hover).point,
      parseVolumeSizeMeters(_typedVolume),
    );
    return rotatedRectCorners(volume.center, volume.size, 0);
  }

  void _editObject(int id) {
    if (_controller.objectById(id) == null) return;
    setState(() => _objectDraftId = id);
  }

  Future<void> _commitObject(FloorPlanObjectDetails details) async {
    final id = _objectDraftId;
    if (id == null) return;
    setState(() => _objectDraftId = null);
    _canvasFocus.requestFocus();
    await _controller.updateObjectDetails(
      id,
      name: details.name,
      ip: details.ip,
      lansweeperName: details.lansweeperName,
      notes: details.notes,
    );
    await _commitPortCount(id, details.portCount);
  }

  /// Το πλήθος θυρών όπως γράφτηκε στο πλαίσιο. Κενό = καμία θύρα. Θύρες με
  /// καλώδιο που θα έφευγαν: ερώτηση πρώτα.
  Future<void> _commitPortCount(int id, String typed) async {
    final object = _controller.objectById(id);
    if (object == null ||
        !(_controller.kinds[object.kindId]?.symbol?.hasPortCount ?? false)) {
      return;
    }
    final count = int.tryParse(typed.trim()) ?? 0;
    if (count == _controller.portsOf(id).length) return;
    final cabled = _controller.cabledPortsBeyond(id, count);
    if (cabled.isNotEmpty) {
      final names = [for (final p in cabled) _portName(object, p)].join(', ');
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Λιγότερες θύρες'),
          content: Text(
            'Οι θύρες $names έχουν καλώδιο. Αν μειωθεί το πλήθος, φεύγουν '
            'μαζί με τα καλώδιά τους.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Ακύρωση'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Μείωση'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      _canvasFocus.requestFocus();
    }
    await _controller.setPortCount(id, count);
  }

  /// Το αυτόματο όνομα της θύρας [port] του [object] («RC6.F17»).
  String _portName(FloorPlanObject object, FloorPlanPort port) {
    final cabinetId = object.cabinetId;
    return floorPlanPortAutoName(
      symbol: _controller.kinds[object.kindId]?.symbol,
      objectName: object.name,
      cabinetName: cabinetId == null
          ? null
          : _controller.objectById(cabinetId)?.name,
      number: port.number,
    );
  }

  Future<void> _editWrittenName(
    FloorPlanObject object,
    FloorPlanPort port,
  ) async {
    final name = await showFloorPlanWrittenNameDialog(
      context,
      portName: _portName(object, port),
      current: port.writtenName,
    );
    if (name == null || !mounted) return;
    _canvasFocus.requestFocus();
    await _controller.setPortWrittenName(port.id, name);
  }

  void _commitObjectFromOutside() {
    final current = _objectEditorKey.currentState?.current;
    if (current == null) {
      setState(() => _objectDraftId = null);
      return;
    }
    _commitObject(current);
  }

  void _cancelObject() {
    setState(() => _objectDraftId = null);
    _canvasFocus.requestFocus();
  }

  /// Το πλαίσιο στοιχείων του αντικειμένου, δίπλα του στην οθόνη.
  Widget? _objectEditor(FloorPlanViewTransform view) {
    final id = _objectDraftId;
    final object = id == null ? null : _controller.objectById(id);
    if (object == null) return null;
    final kind = _controller.kinds[object.kindId];
    // Ό,τι είναι σε καμπίνα δεν φαίνεται στον χάρτη: το πλαίσιο ανοίγει
    // αριστερά από το πάνελ της καμπίνας.
    final panel =
        (FloorPlanCabinetPreferences.cachedLayout ??
                FloorPlanCabinetLayout.defaultFor(_canvasSize))
            .fittedTo(_canvasSize)
            .rect;
    // Αριστερά από το παράθυρο της καμπίνας αν χωρά, αλλιώς δεξιά του.
    final besidePanel = panel.left - kFloorPlanObjectEditorWidth - 8 >= 0
        ? Offset(panel.left - kFloorPlanObjectEditorWidth - 32, panel.top + 40)
        : Offset(panel.right - 16, panel.top + 40);
    final at = object.inCabinet ? besidePanel : view.toScreen(object.center);
    return Positioned(
      left: (at.dx + 24).clamp(
        0,
        math.max(0, _canvasSize.width - kFloorPlanObjectEditorWidth),
      ),
      top: (at.dy - 40).clamp(0, math.max(0, _canvasSize.height - 330)),
      child: FloorPlanObjectEditor(
        key: _objectEditorKey,
        title: kind?.name ?? 'Αντικείμενο',
        volume: kind?.symbol?.isVolume ?? false,
        initial: _detailsOf(object),
        onCommit: _commitObject,
        onCancel: _cancelObject,
        portCount: kind?.symbol?.hasPortCount ?? false,
        // Ό,τι είναι σε καμπίνα δείχνει την πρόσοψή του στο πάνελ της.
        footer: (kind?.symbol?.hasPortCount ?? false) && !object.inCabinet
            ? FloorPlanPortFacade(
                title: 'Πρόσοψη',
                symbol: kind?.symbol,
                ports: _controller.portsOf(object.id),
                occupied: _controller.occupiedPortIds,
                autoName: (port) => _portName(object, port),
                onEditWrittenName: (port) => _editWrittenName(object, port),
              )
            : null,
      ),
    );
  }

  // ── Καμπίνες ──────────────────────────────────────────────────────────

  /// Η καμπίνα που είναι η μόνη επιλογή — τότε φαίνεται το πάνελ της.
  FloorPlanObject? _selectedCabinet() {
    if (_controller.tool != FloorPlanTool.select ||
        _controller.selectedIds.isNotEmpty ||
        _controller.selectedPlacementIds.isNotEmpty ||
        _controller.selectedObjectIds.length != 1) {
      return null;
    }
    final cabinet = _controller.objectById(
      _controller.selectedObjectIds.single,
    );
    if (cabinet == null) return null;
    final symbol = _controller.kinds[cabinet.kindId]?.symbol;
    return (symbol?.isCabinet ?? false) ? cabinet : null;
  }

  Widget? _cabinetPanel() {
    final cabinet = _selectedCabinet();
    if (cabinet == null) return null;
    final kinds = _controller.kinds;
    final name = cabinet.name?.trim() ?? '';
    final room = _roomAt(cabinet.center);
    final addable = [
      for (final k in kinds.values)
        if (k.symbol?.fitsInCabinet ?? false) k,
    ]..sort((a, b) => a.name.compareTo(b.name));
    return FloorPlanCabinetWindow(
      key: const ValueKey('cabinet-window'),
      bounds: _canvasSize,
      builder: (context, hooks) => FloorPlanCabinetPanel(
        cabinetId: cabinet.id,
        facadeHeight: hooks.facadeHeight,
        onFacadeResize: hooks.onFacadeResize,
        onTitleDrag: hooks.onTitleDrag,
        onLayoutDone: hooks.onLayoutDone,
        title: name.isEmpty ? null : name,
        where: [
          if (room != null) ?_roomName(room),
          _floorLabel(widget.floor.id),
        ].join(', '),
        units: floorPlanCabinetUnits(cabinet),
        contents: _controller.cabinetContents(cabinet.id),
        kinds: kinds,
        ports: _controller.ports,
        occupiedPortIds: _controller.occupiedPortIds,
        portAutoName: _portName,
        onClose: () => _controller.select(null),
        actions: FloorPlanCabinetActions(
          addableKinds: addable,
          onAdd: (kindId) async {
            final placed = await _controller.addToCabinet(cabinet.id, kindId);
            if (placed != null) _editObject(placed.id);
          },
          onMove: _controller.moveInCabinet,
          onEdit: _editObject,
          onSetHeight: _controller.setRackHeight,
          onTakeOut: _controller.takeOutOfCabinet,
          onDelete: (id) => _controller.deleteObjects({id}),
          onSetUnits: (units) => _controller.setCabinetUnits(cabinet.id, units),
          onEditWrittenName: _editWrittenName,
        ),
      ),
    );
  }

  /// Delete ή Ctrl+X. Καμπίνα με περιεχόμενο ρωτά πρώτα: σβήνει μαζί ό,τι
  /// έχει μέσα (και η αναίρεση τα φέρνει όλα πίσω).
  Future<void> _deleteSelected({bool cut = false}) async {
    final cabinets = [
      for (final id in _controller.selectedObjectIds)
        if (_controller.objectById(id) case final o?
            when _controller.kinds[o.kindId]?.symbol?.isCabinet ?? false)
          o,
    ];
    final inside = [
      for (final c in cabinets) ..._controller.cabinetContents(c.id),
    ];
    if (inside.isNotEmpty) {
      final what = cabinets.length == 1
          ? 'Η καμπίνα έχει'
          : 'Οι καμπίνες έχουν';
      final count = inside.length == 1
          ? '1 αντικείμενο'
          : '${inside.length} αντικείμενα';
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(cut ? 'Αποκοπή καμπίνας' : 'Διαγραφή καμπίνας'),
          content: Text(
            '$what $count μέσα· να σβηστούν όλα μαζί;'
            '${cut ? ' Η επικόλληση φέρνει μόνο την καμπίνα, άδεια.' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Ακύρωση'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(cut ? 'Αποκοπή όλων' : 'Διαγραφή όλων'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      _canvasFocus.requestFocus();
    }
    if (cut) {
      await _controller.cutSelected();
    } else {
      await _controller.deleteSelected();
    }
  }

  FloorPlanObjectDetails _detailsOf(FloorPlanObject o) {
    final ports = _controller.portsOf(o.id).length;
    return (
      name: o.name ?? '',
      ip: o.ip ?? '',
      lansweeperName: o.lansweeperName ?? '',
      notes: o.notes ?? '',
      portCount: ports == 0 ? '' : '$ports',
    );
  }

  // ── Θέσεις του Καταλόγου ──────────────────────────────────────────────

  /// Ο μικρότερος χώρος του ορόφου που περιέχει το [world].
  FloorPlanElement? _roomAt(Offset world) {
    FloorPlanElement? best;
    var area = double.infinity;
    for (final room in _controller.rooms) {
      if (!polygonContains(room.points, world)) continue;
      final a = signedPolygonArea(room.points).abs();
      if (a < area) {
        area = a;
        best = room;
      }
    }
    return best;
  }

  String? _roomName(FloorPlanElement room) {
    final department = room.departmentId;
    return department == null ? room.name : _departments[department]?.name;
  }

  /// «στο «Γραφείο υλικού» (Ισόγειο)» — πού βρίσκεται μια θέση.
  String _whereIs(FloorPlanPlacement p) {
    final floor = _floorLabel(p.floorId);
    if (p.floorId != widget.floor.id) return 'στον όροφο «$floor»';
    final room = _roomAt(p.center);
    final name = room == null ? null : _roomName(room);
    return name == null ? 'αλλού στον ίδιο όροφο' : 'στο «$name»';
  }

  /// Τοποθετεί την [entry] στο [world]. Τηλέφωνο ή εξοπλισμός με θέση: ρωτά
  /// πρώτα για μεταφορά. Υπάλληλος σε δεύτερη θέση και διαφωνία τμήματος με
  /// τον χώρο: μόνο ενημέρωση, ποτέ εμπόδιο.
  Future<void> _placeEntry(FloorPlanCatalogEntry entry, Offset world) async {
    setState(() => _armedEntry = null);
    final existing = _controller.placementsOf(entry);
    if (entry.type.single && existing.isNotEmpty) {
      final move = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Έχει ήδη θέση'),
          content: Text(
            '«${entry.label}» βρίσκεται ${_whereIs(existing.first)}. '
            'Μεταφορά από εκεί εδώ;',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Άκυρο'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Μεταφορά'),
            ),
          ],
        ),
      );
      if (move != true || !mounted) return;
    }
    final notes = <String>[
      if (!entry.type.single && existing.isNotEmpty)
        'Ο υπάλληλος βρίσκεται ήδη ${_whereIs(existing.first)}.',
      ?_departmentMismatch(entry, world),
    ];
    final placed = await _controller.placeEntry(entry, world);
    if (placed == null || notes.isEmpty) return;
    _showMessage(notes.join(' '));
  }

  /// Η προειδοποίηση όταν το τμήμα της εγγραφής διαφέρει από το τμήμα του
  /// χώρου. Χώρος χωρίς τμήμα (διάδρομος) ή εγγραφή χωρίς τμήμα: τίποτα.
  String? _departmentMismatch(FloorPlanCatalogEntry entry, Offset world) {
    final roomDepartment = _roomAt(world)?.departmentId;
    if (roomDepartment == null || entry.departmentIds.isEmpty) return null;
    if (entry.departmentIds.contains(roomDepartment)) return null;
    final own = [
      for (final id in entry.departmentIds) _departments[id]?.name ?? 'τμήμα',
    ].join(', ');
    final room = _departments[roomDepartment]?.name ?? 'άλλου τμήματος';
    return '«${entry.label}» ανήκει στο «$own» · ο χώρος είναι του «$room».';
  }

  /// Ρίξιμο από το πάνελ στον καμβά: το σημείο είναι εκεί που αφέθηκε.
  Future<void> _onDrop(DragTargetDetails<FloorPlanCatalogEntry> details) async {
    final view = _view;
    final canvas = _canvasKey.currentContext?.findRenderObject();
    if (view == null || canvas is! RenderBox) return;
    final local = canvas.globalToLocal(details.offset);
    await _placeEntry(details.data, view.toWorld(local));
  }

  Widget _placementPanel() {
    return FloorPlanPlacementPanel(
      entries: _controller.catalog.values.toList(),
      placements: _controller.allPlacements,
      floorDepartmentIds: {
        for (final d in _departments.values)
          if (d.floorId == widget.floor.id && d.id != null) d.id!,
      },
      departmentName: (id) => _departments[id]?.name,
      floorLabel: _floorLabel,
      armed: _armedEntry,
      onArm: (entry) => setState(() => _armedEntry = entry),
    );
  }

  Future<void> _openKinds() async {
    final open = widget.openObjectKinds;
    if (open == null) return;
    await open(context);
    await _controller.reloadKinds();
  }

  // ── Κείμενο και διαστάσεις ────────────────────────────────────────────

  /// Κλικ με το εργαλείο «Κείμενο»: πάνω σε υπάρχον κείμενο το ανοίγει για
  /// αλλαγή, πάνω στο όνομα ενός χώρου ανοίγει την αλλαγή χώρου· αλλού
  /// ανοίγει άδειο πλαίσιο για νέο κείμενο. Με κλειδωμένο σχέδιο τίποτα
  /// υπάρχον δεν πιάνεται.
  Future<void> _textClick(Offset screen, Offset world) async {
    if (!_controller.locked) {
      for (final text in _controller.texts.reversed) {
        if (polygonContains(textBoxCorners(text), world)) {
          _editText(text);
          return;
        }
      }
      final room = _roomLabelAt(screen, _view!);
      if (room != null) {
        await _renameRoom(room);
        return;
      }
    }
    setState(
      () => _textDraft = _TextDraft(
        id: null,
        center: world,
        text: '',
        sizeCm: kFloorPlanDefaultTextSizeCm,
        tool: _controller.tool,
      ),
    );
  }

  void _editText(FloorPlanElement text) {
    if (text.points.isEmpty) return;
    setState(
      () => _textDraft = _TextDraft(
        id: text.id,
        center: text.points.first,
        text: text.name ?? '',
        sizeCm: text.fontSize ?? kFloorPlanDefaultTextSizeCm,
        tool: _controller.tool,
      ),
    );
  }

  /// Αποθηκεύει το πλαίσιο κειμένου. Το κέντρο του κειμένου είναι εκεί που
  /// βρίσκεται το πεδίο **τώρα**, ώστε το κείμενο να μείνει όπου το είδατε
  /// να γράφεται.
  Future<void> _commitText(String text, double sizeCm) async {
    final draft = _textDraft;
    if (draft == null) return;
    final center = _textFieldCenterWorld() ?? draft.center;
    setState(() => _textDraft = null);
    _canvasFocus.requestFocus();
    final id = draft.id;
    if (id == null) {
      await _controller.addText(center, text, sizeCm);
      return;
    }
    await _controller.updateText(id, text, sizeCm, center: center);
  }

  void _commitTextFromOutside() {
    final current = _textEditorKey.currentState?.current;
    if (current == null) {
      setState(() => _textDraft = null);
      return;
    }
    _commitText(current.text, current.sizeCm);
  }

  void _cancelText() {
    setState(() => _textDraft = null);
    _canvasFocus.requestFocus();
  }

  Offset? _textFieldCenterWorld() {
    final view = _view;
    final field = _textFieldKey.currentContext?.findRenderObject();
    final canvas = _canvasKey.currentContext?.findRenderObject();
    if (view == null || field is! RenderBox || canvas is! RenderBox) {
      return null;
    }
    final global = field.localToGlobal(field.size.center(Offset.zero));
    return view.toWorld(canvas.globalToLocal(global));
  }

  /// Κλικ με το εργαλείο «Μέτρηση»: ένα σημείο ακόμη, με μαγνήτη· διπλό
  /// κλικ κλείνει τη διαδρομή.
  void _measureClick(Offset screen, Offset world) {
    if (_isDoubleClick(screen)) {
      setState(() => _measure = _measure.finish());
      return;
    }
    final last = _measure.finished || _measure.isEmpty
        ? null
        : _measure.points.last;
    setState(() => _measure = _measure.add(_snap(world, from: last).point));
  }

  /// Πρώτο και δεύτερο κλικ: τα άκρα που μετριούνται (με μαγνήτη). Τρίτο:
  /// πόσο απέχει η γραμμή από αυτά.
  Future<void> _dimensionClick(Offset world) async {
    final points = _dimensionPoints;
    if (points.length < 2) {
      final from = points.isEmpty ? null : points.first;
      setState(
        () => _dimensionPoints = [...points, _snap(world, from: from).point],
      );
      return;
    }
    setState(() => _dimensionPoints = const []);
    await _controller.addDimension(points[0], points[1], world);
  }

  Future<void> _commitWall(Offset start, Offset end) async {
    if ((end - start).distance < 1) return;
    setState(() {
      _wallStart = end;
      _typedLength = '';
    });
    await _controller.addWall(start, end);
  }

  void _onHover(PointerHoverEvent event) {
    final view = _view;
    if (view == null) return;
    final world = view.toWorld(event.localPosition);
    // Υπόδειξη μόνο με την «Επιλογή»: με τα εργαλεία σχεδίασης θα κάλυπτε
    // ό,τι σχεδιάζεται.
    final item = _controller.tool == FloorPlanTool.select
        ? hitTestFloorPlanObject(world, [
            for (final v in floorPlanObjectsAtZoom(
              _controller.objectViews,
              view.pixelsPerCm,
            ))
              if (floorPlanItemHasInfo(v, _controller.kinds)) v,
          ])
        : null;
    setState(() {
      _hoverWorld = world;
      _hoveredItem = item;
      _hoverScreen = event.localPosition;
    });
  }

  FloorPlanObjectView? _hoveredItem;
  Offset _hoverScreen = Offset.zero;

  /// Η υπόδειξη του συμβόλου κάτω από τον δείκτη· `null` όταν δεν υπάρχει.
  Widget? _hoverTooltip() {
    final item = _hoveredItem;
    if (item == null ||
        _downScreen != null ||
        _controller.tool != FloorPlanTool.select) {
      return null;
    }
    final maps = _controller.infoMaps;
    final info = floorPlanItemInfo(
      item,
      FloorPlanInfoSources(
        objects: maps.objects,
        kinds: _controller.kinds,
        catalog: _controller.catalog,
        placements: maps.placements,
        departmentName: (id) => _departments[id]?.name,
        roomAt: floorPlanRoomLookup(_controller.elements),
      ),
    );
    if (info == null) return null;
    return Positioned(
      left: (_hoverScreen.dx + 16).clamp(
        0,
        math.max(0, _canvasSize.width - 320),
      ),
      top: (_hoverScreen.dy + 16).clamp(
        0,
        math.max(0, _canvasSize.height - 160),
      ),
      child: FloorPlanItemTooltip(info: info),
    );
  }

  void _setHiddenLayers(Set<String> hidden) {
    _controller.setHiddenLayers(hidden);
    FloorPlanLayersPreference.write(hidden);
  }

  Future<void> _askCalibration(Offset a, Offset b) async {
    final realCm = await showFloorPlanCalibrationDialog(
      context,
      hasWalls: _controller.wallSegments.isNotEmpty,
    );
    if (realCm == null) return;
    await _controller.calibrate(a, b, realCm);
    if (mounted) _controller.setTool(FloorPlanTool.wall);
  }

  // ── Πληκτρολόγιο ──────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;

    if (ctrl && key == LogicalKeyboardKey.keyZ) {
      _cancelDraft();
      _controller.undo();
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyY) {
      _cancelDraft();
      _controller.redo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_wallStart == null &&
          _measure.isEmpty &&
          _measureStart == null &&
          _roomCorners.isEmpty &&
          _dimensionPoints.isEmpty &&
          _volumeStart == null) {
        return KeyEventResult.ignored;
      }
      setState(_cancelDraft);
      return KeyEventResult.handled;
    }
    if (_controller.tool == FloorPlanTool.select) {
      final handled = _onSelectionKey(key, ctrl);
      if (handled) return KeyEventResult.handled;
    }
    if (_controller.tool == FloorPlanTool.measure && !_measure.isEmpty) {
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        setState(() => _measure = _measure.finish());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.backspace) {
        setState(() => _measure = _measure.removeLast());
        return KeyEventResult.handled;
      }
    }
    if (_controller.tool == FloorPlanTool.object && _volumeStart != null) {
      final handled = _onVolumeKey(event, key);
      if (handled) return KeyEventResult.handled;
    }
    if (_controller.tool == FloorPlanTool.room && _roomCorners.isNotEmpty) {
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        _finishRoomCorners();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.backspace) {
        setState(
          () => _roomCorners = _roomCorners.sublist(0, _roomCorners.length - 1),
        );
        return KeyEventResult.handled;
      }
    }

    // Πληκτρολόγηση μήκους, μόνο όσο σχεδιάζεται τοίχος.
    if (_controller.tool != FloorPlanTool.wall || _wallStart == null) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _commitTypedLength();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (_typedLength.isEmpty) return KeyEventResult.handled;
      setState(
        () => _typedLength = _typedLength.substring(0, _typedLength.length - 1),
      );
      return KeyEventResult.handled;
    }
    final ch = event.character;
    if (ch != null && RegExp(r'^[0-9.,]$').hasMatch(ch)) {
      setState(() => _typedLength += ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Πληκτρολόγηση διαστάσεων του επίπλου που σχεδιάζεται, π.χ. «1,60 x
  /// 0,80» και Enter.
  bool _onVolumeKey(KeyEvent event, LogicalKeyboardKey key) {
    final start = _volumeStart;
    if (start == null) return false;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (parseVolumeSizeMeters(_typedVolume) == null) return true;
      _finishVolume(start, _hoverWorld ?? start + const Offset(1, 1));
      return true;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (_typedVolume.isNotEmpty) {
        setState(
          () =>
              _typedVolume = _typedVolume.substring(0, _typedVolume.length - 1),
        );
      }
      return true;
    }
    final ch = event.character;
    if (ch != null && RegExp(r'^[0-9.,xX×*χΧ ]$').hasMatch(ch)) {
      setState(() => _typedVolume += ch);
      return true;
    }
    return false;
  }

  /// Πλήκτρα της επιλογής: Delete, Ctrl+C / Ctrl+X / Ctrl+V και βελάκια
  /// (10 εκ. το πάτημα, 1 εκ. με Shift).
  bool _onSelectionKey(LogicalKeyboardKey key, bool ctrl) {
    if (key == LogicalKeyboardKey.delete) {
      _deleteSelected();
      return true;
    }
    if (ctrl && key == LogicalKeyboardKey.keyC) {
      _controller.copySelected();
      return true;
    }
    if (ctrl && key == LogicalKeyboardKey.keyX) {
      _deleteSelected(cut: true);
      return true;
    }
    if (ctrl && key == LogicalKeyboardKey.keyV) {
      _paste();
      return true;
    }
    final step = HardwareKeyboard.instance.isShiftPressed ? 1.0 : 10.0;
    final delta = switch (key) {
      LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
      LogicalKeyboardKey.arrowRight => Offset(step, 0),
      LogicalKeyboardKey.arrowUp => Offset(0, -step),
      LogicalKeyboardKey.arrowDown => Offset(0, step),
      _ => null,
    };
    if (delta == null || !_controller.hasSelection) return false;
    // Τα βελάκια κινούν «όπως φαίνεται»: σε περιστραμμένο όροφο το πάνω της
    // οθόνης δεν είναι το πάνω του σχεδίου.
    final view = _view;
    final world = view == null
        ? delta
        : view.toWorld(view.toScreen(Offset.zero) + delta * view.pixelsPerCm);
    _controller.nudgeSelected(world);
    return true;
  }

  Future<void> _paste() async {
    final departments = await _controller.paste();
    if (departments.isEmpty) return;
    final names = [
      for (final id in departments) _departments[id]?.name ?? 'τμήμα',
    ].join(', ');
    _showMessage(
      'Επικολλήθηκε και δεύτερος χώρος στον ίδιο όροφο για: $names.',
    );
  }

  void _cancelDraft() {
    _volumeStart = null;
    _typedVolume = '';
    _measure = FloorPlanMeasure.empty;
    _dimensionPoints = const [];
    _select.cancel();
    _roomCorners = const [];
    _wallStart = null;
    _typedLength = '';
    _measureStart = null;
    _measureEnd = null;
  }

  void _commitTypedLength() {
    final start = _wallStart;
    final hover = _hoverWorld;
    final cm = parseMetersToCm(_typedLength);
    if (start == null || cm == null) return;
    // Η κατεύθυνση είναι αυτή που δείχνει ο δείκτης, με τον μαγνήτη γωνίας.
    final toward = hover ?? start + const Offset(100, 0);
    final direction = _magnetOff
        ? toward
        : snapAngleAndLength(start, toward, lengthStepCm: 0);
    _commitWall(start, pointAtLength(start, direction, cm));
  }

  // ── Φόρτωση πατρόν ────────────────────────────────────────────────────

  Offset get _viewCenterWorld {
    final view = _view;
    if (view == null) return Offset.zero;
    return view.toWorld(Offset(_canvasSize.width / 2, _canvasSize.height / 2));
  }

  Future<void> _loadFromFloorPlan() async {
    final bytes = await widget.readFloorPlanImage();
    if (!mounted) return;
    if (bytes == null) {
      _showMessage('Ο όροφος δεν έχει κάτοψη αποθηκευμένη στη βάση.');
      return;
    }
    await _controller.setPatternImage(bytes, center: _viewCenterWorld);
    _fitAll();
  }

  Future<void> _loadFromFile() async {
    final session = await FilePickerSession.run(() async {
      const memory = PickerLocationMemory('building_map_image');
      final picked = await FilePicker.pickFile(
        type: FileType.image,
        initialDirectory: await memory.initialDirectory(),
      );
      final path = picked?.path;
      if (path == null) return null;
      await memory.remember(path);
      return path;
    });
    final path = session.value;
    if (session.refocusedExisting || path == null || !mounted) return;
    final Uint8List encoded;
    try {
      final source = await File(path).readAsBytes();
      encoded = await Isolate.run(() => encodeFloorPlanImage(source));
    } on FloorPlanImageUnreadable catch (e) {
      _showMessage(e.toString());
      return;
    } on FileSystemException catch (e) {
      _showMessage(
        'Η εικόνα δεν διαβάστηκε: ${e.osError?.message ?? e.message}',
      );
      return;
    }
    if (!mounted) return;
    await _controller.setPatternImage(encoded, center: _viewCenterWorld);
    _fitAll();
  }

  // ── Διάταξη ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(child: Text('Σχεδίαση χάρτη — ${widget.floor.label}')),
            if (_controller.state.isActive) ...[
              const SizedBox(width: 16),
              const Chip(
                avatar: Icon(Icons.check_circle_outline, size: 18),
                label: Text('Ενεργός: τον βλέπουν όλοι'),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Αναίρεση (Ctrl+Z)',
            onPressed: _controller.canUndo ? _controller.undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Επανάληψη (Ctrl+Y)',
            onPressed: _controller.canRedo ? _controller.redo : null,
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            tooltip: _controller.locked
                ? 'Ξεκλείδωμα σχεδίου'
                : 'Κλείδωμα σχεδίου (τίποτα δεν πιάνεται με το ποντίκι)',
            isSelected: _controller.locked,
            onPressed: _controller.toggleLock,
            icon: Icon(
              _controller.locked ? Icons.lock_outline : Icons.lock_open,
            ),
          ),
          IconButton(
            tooltip: _controller.gridVisible ? 'Απόκρυψη πλέγματος' : 'Πλέγμα',
            isSelected: _controller.gridVisible,
            onPressed: _controller.toggleGrid,
            icon: const Icon(Icons.grid_4x4),
          ),
          IconButton(
            tooltip: 'Προβολή όλου του σχεδίου',
            onPressed: _fitAll,
            icon: const Icon(Icons.fit_screen_outlined),
          ),
          FloorPlanLayersButton(
            kinds: _controller.kinds.values.toList(),
            hidden: _controller.hiddenLayers,
            onChanged: _setHiddenLayers,
          ),
          if (widget.openObjectKinds != null)
            IconButton(
              tooltip: 'Είδη αντικειμένων',
              onPressed: _openKinds,
              icon: const Icon(Icons.category_outlined),
            ),
          IconButton(
            tooltip: _patternPanelOpen
                ? 'Κλείσιμο πατρόν'
                : 'Πατρόν (εικόνα στο φόντο)',
            isSelected: _patternPanelOpen,
            onPressed: () =>
                setState(() => _patternPanelOpen = !_patternPanelOpen),
            icon: const Icon(Icons.wallpaper_outlined),
          ),
          if (!_controller.state.isActive) ...[
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _controller.loading ? null : _activate,
              icon: const Icon(Icons.publish_outlined),
              label: const Text('Ενεργοποίηση νέου χάρτη'),
            ),
          ],
          const SizedBox(width: 12),
        ],
      ),
      body: _controller.loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                FloorPlanToolRail(controller: _controller),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _buildCanvas()),
                      FloorPlanStatusBar(text: _statusText()),
                    ],
                  ),
                ),
                if (_controller.tool == FloorPlanTool.place) ...[
                  const VerticalDivider(width: 1),
                  SizedBox(width: 340, child: _placementPanel()),
                ],
                if (_patternPanelOpen) ...[
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 280,
                    child: FloorPlanPatternPanel(
                      controller: _controller,
                      onLoadFromFloorPlan: _loadFromFloorPlan,
                      onLoadFromFile: _loadFromFile,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Πάντα Stack, με ή χωρίς πάνελ: αν άλλαζε η δομή, ο καμβάς θα
        // ξαναστηνόταν και θα έπαιρνε την εστίαση από το πλαίσιο στοιχείων.
        return Stack(
          children: [_canvasLayers(context, constraints), ?_cabinetPanel()],
        );
      },
    );
  }

  Widget _canvasLayers(BuildContext context, BoxConstraints constraints) {
    _canvasSize = constraints.biggest;
    final view = _ensureView(_canvasSize);
    final draft = _textDraft;
    final canvas = Focus(
      focusNode: _canvasFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: _cursor(),
        onHover: _onHover,
        onExit: (_) {
          if (_hoveredItem != null) setState(() => _hoveredItem = null);
        },
        child: DragTarget<FloorPlanCatalogEntry>(
          onAcceptWithDetails: _onDrop,
          builder: (context, candidates, rejected) => Listener(
            key: _canvasKey,
            onPointerSignal: _onPointerSignal,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            child: CustomPaint(
              size: _canvasSize,
              foregroundPainter: _controller.tool == FloorPlanTool.measure
                  ? FloorPlanMeasurePainter(
                      view: view,
                      measure: _measure,
                      hover: _measureHover(),
                    )
                  : null,
              painter: FloorPlanPainter(
                view: view,
                walls: _controller.wallSegments,
                openingsByWall: _controller.openingsByWall,
                rooms: buildFloorPlanRoomViews(_controller.rooms, _departments),
                state: _controller.state,
                patternImage: _controller.patternImage,
                gridVisible: _controller.gridVisible,
                selectedIds: _controller.selectedIds,
                openingSegments: _openingSegments(),
                texts: [
                  for (final t in _controller.texts)
                    if (t.id != draft?.id || draft?.id == null) t,
                ],
                dimensions: _controller.dimensions,
                overlay: _overlay(),
                colors: Theme.of(context).colorScheme,
                objects: _controller.objectViews,
                selectedObjectIds: _controller.selectedObjectIds,
                selectedPlacementIds: _controller.selectedPlacementIds,
                labelCache: _labelCache,
              ),
            ),
          ),
        ),
      ),
    );
    final objectEditor = _objectEditor(view);
    if (objectEditor != null) {
      return Stack(children: [canvas, objectEditor]);
    }
    final tooltip = draft == null ? _hoverTooltip() : null;
    if (tooltip != null) {
      final bar = _roomLabelBar(view);
      return Stack(children: [canvas, ?bar, tooltip]);
    }
    final labelBar = draft == null ? _roomLabelBar(view) : null;
    // Πάντα μέσα σε Stack και πρώτος: αν ο καμβάς άλλαζε θέση στο δέντρο
    // όταν ανοίγει ένα πλαίσιο, θα ξαναστηνόταν και θα έπαιρνε πίσω την
    // εστίαση — το «Όνομα» του νέου αντικειμένου δεν θα δεχόταν γράμματα.
    if (draft == null && labelBar == null) return Stack(children: [canvas]);
    if (draft == null) return Stack(children: [canvas, labelBar!]);
    final fontPx = floorPlanTextEditFontPx(draft.sizeCm, view.pixelsPerCm);
    final topLeft = floorPlanTextEditorTopLeft(
      view.toScreen(draft.center),
      draft.text,
      fontPx,
    );
    return Stack(
      children: [
        canvas,
        Positioned(
          left: topLeft.dx.clamp(0, math.max(0, _canvasSize.width - 200)),
          top: topLeft.dy.clamp(0, math.max(0, _canvasSize.height - 120)),
          child: FloorPlanTextEditor(
            key: _textEditorKey,
            fieldKey: _textFieldKey,
            initialText: draft.text,
            initialSizeCm: draft.sizeCm,
            pixelsPerCm: view.pixelsPerCm,
            onCommit: _commitText,
            onCancel: _cancelText,
          ),
        ),
      ],
    );
  }

  /// Η μπάρα A− / A+ / «στο κέντρο» πάνω από το όνομα του χώρου, όταν με
  /// την «Επιλογή» είναι επιλεγμένος ένας μόνο χώρος· `null` αλλιώς.
  Widget? _roomLabelBar(FloorPlanViewTransform view) {
    if (_controller.tool != FloorPlanTool.select || _controller.locked) {
      return null;
    }
    final ids = _controller.selectedIds;
    if (ids.length != 1) return null;
    final room = _controller.elementById(ids.single);
    if (room == null || room.kind != FloorPlanElementKind.room) return null;
    final roomView = buildFloorPlanRoomViews([room], _departments).firstOrNull;
    final rect = roomView == null
        ? null
        : floorPlanRoomLabelRect(roomView, view);
    if (roomView == null || rect == null) return null;
    final pending = _labelSizePending;
    final sizeCm = pending != null && pending.id == room.id
        ? pending.sizeCm
        : roomView.labelSizeCm;
    final top = rect.top - kFloorPlanRoomLabelBarHeight - 6;
    return Positioned(
      left: (rect.center.dx - 110).clamp(
        0,
        math.max(0, _canvasSize.width - 230),
      ),
      top: top.clamp(0, math.max(0, _canvasSize.height - 50)),
      child: FloorPlanRoomLabelBar(
        sizeCm: sizeCm,
        onSize: (cm) => _setRoomLabelSize(room.id, cm),
        onCenter: room.labelOffset == null
            ? null
            : () => _controller.setRoomLabel(room.id, toCenter: true),
      ),
    );
  }

  /// Πού θα έπεφτε το επόμενο σημείο της μέτρησης, με τον μαγνήτη.
  Offset? _measureHover() {
    final hover = _hoverWorld;
    if (hover == null || _view == null || _measure.finished) return null;
    final from = _measure.isEmpty ? null : _measure.points.last;
    return _snap(hover, from: from).point;
  }

  MouseCursor _cursor() => switch (_controller.tool) {
    FloorPlanTool.wall ||
    FloorPlanTool.room ||
    FloorPlanTool.dimension ||
    FloorPlanTool.measure ||
    FloorPlanTool.calibrate ||
    FloorPlanTool.object ||
    FloorPlanTool.opening => SystemMouseCursors.precise,
    FloorPlanTool.place =>
      _armedEntry == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.precise,
    FloorPlanTool.movePattern => SystemMouseCursors.move,
    FloorPlanTool.text => SystemMouseCursors.text,
    FloorPlanTool.select => SystemMouseCursors.basic,
  };

  FloorPlanOverlay _overlay() {
    final hover = _hoverWorld;
    final view = _view;
    if (view == null) return const FloorPlanOverlay();
    switch (_controller.tool) {
      case FloorPlanTool.wall:
        if (hover == null) return const FloorPlanOverlay();
        final start = _wallStart;
        final snap = _snap(hover, from: start);
        var end = snap.point;
        final typed = parseMetersToCm(_typedLength);
        if (start != null && typed != null) {
          end = pointAtLength(start, end, typed);
        }
        return FloorPlanOverlay(
          rubberStart: start,
          rubberEnd: start == null ? null : end,
          snapPoint: snap.point,
          snapKind: snap.kind,
        );
      case FloorPlanTool.opening:
        return FloorPlanOverlay(
          openingWall: _openingWall,
          openingRange: _openingRange,
        );
      case FloorPlanTool.calibrate:
        return FloorPlanOverlay(
          measureStart: _measureStart,
          measureEnd: _measureEnd,
        );
      case FloorPlanTool.room:
        if (hover == null) return FloorPlanOverlay(roomCorners: _roomCorners);
        final from = _roomCorners.isEmpty ? null : _roomCorners.last;
        final snap = _snap(hover, from: from);
        return FloorPlanOverlay(
          roomCorners: _roomCorners,
          snapPoint: snap.point,
          snapKind: snap.kind,
        );
      case FloorPlanTool.dimension:
        final points = _dimensionPoints;
        if (hover == null) return const FloorPlanOverlay();
        final from = points.isEmpty ? null : points.first;
        final snap = points.length < 2
            ? _snap(hover, from: from)
            : FloorPlanSnap(hover, FloorPlanSnapKind.none);
        return FloorPlanOverlay(
          dimensionDraft: points.isEmpty ? null : [...points, snap.point],
          snapPoint: points.length < 2 ? snap.point : null,
          snapKind: snap.kind,
        );
      case FloorPlanTool.select:
        return FloorPlanOverlay(
          selectionRectScreen: _select.selectionRectScreen,
          selectionFrameScreen: _select.selectionFrame(view),
          rotationHandleScreen: _select.rotationHandle(view),
          resizeHandlesScreen: _select.resizeHandles(view),
        );
      case FloorPlanTool.place:
        return const FloorPlanOverlay();
      case FloorPlanTool.object:
        if (!_placingVolume || hover == null) return const FloorPlanOverlay();
        final snap = _snap(hover);
        return FloorPlanOverlay(
          volumeDraft: _volumeDraftCorners(),
          snapPoint: snap.point,
          snapKind: snap.kind,
        );
      case FloorPlanTool.measure:
        if (hover == null || _measure.finished) return const FloorPlanOverlay();
        final from = _measure.isEmpty ? null : _measure.points.last;
        final snap = _snap(hover, from: from);
        return FloorPlanOverlay(snapPoint: snap.point, snapKind: snap.kind);
      case FloorPlanTool.text:
      case FloorPlanTool.movePattern:
        return const FloorPlanOverlay();
    }
  }

  /// Κάθε άνοιγμα ως τμήμα πάνω στον τοίχο του — για την επισήμανσή του.
  Map<int, FloorPlanSegment> _openingSegments() {
    final elements = _controller.elements;
    final walls = {
      for (final e in elements)
        if (e.kind == FloorPlanElementKind.wall) e.id: e,
    };
    return {
      for (final e in elements)
        if (e.kind == FloorPlanElementKind.opening)
          if (elementWorldPoints(e, walls) case [final a, final b])
            e.id: FloorPlanSegment(a, b),
    };
  }

  String _statusText() {
    switch (_controller.tool) {
      case FloorPlanTool.wall:
        if (_wallStart == null) {
          return 'Τοίχος: κλικ στην αρχή. Shift = χωρίς μαγνήτη.';
        }
        final typed = _typedLength.isEmpty
            ? ''
            : ' · Μήκος: $_typedLength μ. (Enter)';
        return 'Κλικ σε κάθε γωνία · διπλό κλικ ή Esc για τέλος · '
            'πληκτρολογήστε μήκος σε μέτρα$typed';
      case FloorPlanTool.opening:
        return 'Άνοιγμα: σύρετε πάνω σε έναν τοίχο, από τη μία άκρη της '
            'πόρτας ως την άλλη.';
      case FloorPlanTool.calibrate:
        final a = _measureStart;
        final b = _measureEnd;
        final now = a != null && b != null
            ? ' · Τώρα: ${formatCmAsMeters((b - a).distance)}'
            : '';
        return 'Βαθμονόμηση: σύρετε μια γραμμή πάνω σε κάτι με γνωστό μήκος.$now';
      case FloorPlanTool.movePattern:
        return 'Μετακίνηση πατρόν: σύρετε την εικόνα ώστε να ταιριάξει.';
      case FloorPlanTool.room:
        if (_roomCorners.isEmpty) {
          return 'Χώρος: διπλό κλικ μέσα σε κλειστούς τοίχους, ή κλικ σε '
              'κάθε γωνία.';
        }
        return 'Κλικ σε κάθε γωνία · κλικ στην πρώτη γωνία, διπλό κλικ ή '
            'Enter για τέλος · Backspace σβήνει την τελευταία · Esc ακύρωση';
      case FloorPlanTool.text:
        return 'Κείμενο: κλικ εκεί που θα μπει το κείμενο.';
      case FloorPlanTool.measure:
        return floorPlanMeasureHint(_measure);
      case FloorPlanTool.dimension:
        return switch (_dimensionPoints.length) {
          0 => 'Διάσταση: κλικ στο πρώτο άκρο.',
          1 => 'Κλικ στο δεύτερο άκρο · Esc ακύρωση',
          _ => 'Κλικ για το πόσο απέχει η γραμμή από αυτό που μετρά.',
        };
      case FloorPlanTool.place:
        final armed = _armedEntry;
        if (armed != null) {
          return 'Κλικ στον χάρτη εκεί που βρίσκεται «${armed.label}».';
        }
        return 'Τοποθέτηση: σύρετε από τη λίστα στα δεξιά στον χάρτη, ή κλικ '
            'στη λίστα και κλικ στον χάρτη. Μετακίνηση και αφαίρεση (Delete) '
            'με την «Επιλογή»· ο Κατάλογος δεν αλλάζει.';
      case FloorPlanTool.object:
        final kind = _controller.objectKind?.name ?? 'Αντικείμενο';
        if (!_placingVolume) {
          return '$kind: κλικ εκεί που βρίσκεται.';
        }
        if (_volumeStart == null) {
          return '$kind: κλικ στη μία γωνία, ή σύρσιμο από γωνία σε γωνία.';
        }
        final typed = _typedVolume.isEmpty
            ? ''
            : ' · Διαστάσεις: $_typedVolume μ. (Enter)';
        return 'Κλικ στην απέναντι γωνία · πληκτρολογήστε διαστάσεις σε '
            'μέτρα, π.χ. 1,60 x 0,80 · Esc ακύρωση$typed';
      case FloorPlanTool.select:
        if (_controller.locked) {
          return 'Το σχέδιο είναι κλειδωμένο: πιάνονται μόνο τα αντικείμενα. '
              'Ξεκλειδώστε το από το λουκέτο επάνω δεξιά.';
        }
        return 'Επιλογή: κλικ ή ορθογώνιο · Ctrl+κλικ προσθέτει · σύρσιμο '
            'μετακινεί · η λαβή επάνω γυρίζει (Shift: ελεύθερα) · διπλό κλικ '
            'αλλάζει χώρο, κείμενο ή αντικείμενο · Ctrl+C/X/V · Delete · '
            'μεσαίο κουμπί μετακινεί τον καμβά.';
    }
  }
}

/// Ένα κείμενο που γράφεται τώρα: νέο ([id] `null`) ή υπάρχον.
class _TextDraft {
  const _TextDraft({
    required this.id,
    required this.center,
    required this.text,
    required this.sizeCm,
    required this.tool,
  });

  final int? id;
  final Offset center;
  final String text;
  final double sizeCm;

  /// Το εργαλείο από το οποίο άνοιξε· αλλαγή εργαλείου το αποθηκεύει.
  final FloorPlanTool tool;
}
