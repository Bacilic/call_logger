import '../../../../core/models/floor_plan_object.dart';
import '../../../../core/models/floor_plan_object_kind.dart';
import '../../../../core/models/floor_plan_port.dart';
import 'floor_plan_stack.dart';

export '../../../../core/models/floor_plan_port.dart'
    show floorPlanPortAutoName, kFloorPlanDefaultPortType;

/// Καθαρή λογική των θυρών: πώς λέγονται, πώς στοιχίζονται στην πρόσοψη, και
/// τι αλλάζει όταν αλλάζει το πλήθος τους.

/// Το μεγαλύτερο πλήθος θυρών που δέχεται ένα αντικείμενο — περιθώριο για
/// μεγάλα patch panel, χωρίς να επιτρέπει τυπογραφικό λάθος χιλιάδων θυρών.
const int kFloorPlanMaxPorts = 96;

/// Τα προθέματα που διαλέγει κανείς, με το τι σημαίνει το καθένα.
const Map<String, String> kFloorPlanPortTypes = {
  'Fa': 'FastEthernet: θύρα 100 Mbps',
  'Gi': 'GigabitEthernet: θύρα 1 Gbps',
  'Te': 'TenGigabitEthernet: θύρα 10 Gbps',
};

/// Το αυτόματο όνομα της θύρας [port] του [object], μέσα στα [objects] του
/// ορόφου. Κοινό για σχεδίαση και προβολή, ώστε να μη διαφέρουν ποτέ.
String floorPlanObjectPortName({
  required FloorPlanObject object,
  required FloorPlanPort port,
  required FloorPlanSymbol? symbol,
  required Map<int, FloorPlanObject> objects,
}) {
  final cabinetId = object.cabinetId;
  return floorPlanPortAutoName(
    symbol: symbol,
    objectName: floorPlanStackName(object, objects.values),
    cabinetName: cabinetId == null ? null : objects[cabinetId]?.name,
    number: port.number,
    stackUnit: object.stackUnit,
    portType: object.portType,
  );
}

/// Το όνομα που παίρνει μια θύρα πρίζας από τη θύρα patch panel όπου δένεται.
String floorPlanLinkName(FloorPlanPortLink link) => floorPlanPortAutoName(
  symbol: FloorPlanSymbol.patchPanel,
  objectName: link.panelName,
  cabinetName: link.cabinetName,
  number: link.patchNumber,
);

/// Το ίδιο, για μια θύρα της λίστας επιλογής.
String floorPlanPatchOptionName(FloorPlanPatchPortOption option) =>
    floorPlanPortAutoName(
      symbol: FloorPlanSymbol.patchPanel,
      objectName: option.panelName,
      cabinetName: option.cabinetName,
      number: option.number,
    );

/// Η ένδειξη θύρας πρίζας που δεν έχει δεθεί ακόμη.
const String kFloorPlanOutletUnlinked = 'χωρίς σύνδεση';

/// Με πόσες θύρες ξεκινά μια νέα πρίζα (απόφαση 04/11/2026).
const int kFloorPlanOutletDefaultPorts = 2;

/// Πόσο κοντά σε τοίχο πρέπει να αφεθεί μια πρίζα για να κουμπώσει πάνω του.
/// Πιο μακριά μένει εκεί που αφέθηκε.
const double kFloorPlanOutletSnapCm = 100;

/// Ποιο κείμενο λέει τι είναι συνδεδεμένο· `null` όταν δεν είναι τίποτα ή όταν
/// η εγγραφή δεν υπάρχει πια (π.χ. διαγράφηκε ο εξοπλισμός από τον Κατάλογο).
String? floorPlanConnectionLabel(
  FloorPlanPortConnection connection, {
  required String? Function(int equipmentId) equipmentLabel,
  required String? Function(int objectId) objectLabel,
}) {
  if (connection.equipmentId case final id?) return equipmentLabel(id);
  if (connection.objectId case final id?) return objectLabel(id);
  return connection.text;
}

/// Η διαδρομή μιας θύρας πρίζας, από τη συσκευή ως το switch:
/// «PC-0412 → πρίζα → RC6.F17 («Κάμερα 7») → SW-2 / 14». Το [switchEnd] είναι
/// ό,τι βρίσκεται μπροστά από τη θύρα του patch panel.
String floorPlanOutletPortLine({
  required FloorPlanPortLink? link,
  required String? writtenName,
  required String? connected,
  FloorPlanCableEnd? switchEnd,
  String? otherFloor,
}) {
  final written = writtenName == null ? '' : ' («$writtenName»)';
  final floor = otherFloor == null ? '' : ' · $otherFloor';
  if (link == null) {
    final name = '$kFloorPlanOutletUnlinked$written';
    return connected == null ? name : '$connected → πρίζα → $name';
  }
  return [
    ?connected,
    'πρίζα',
    '${floorPlanLinkName(link)}$written$floor',
    switchEnd == null ? 'χωρίς switch' : floorPlanCableEndName(switchEnd),
  ].join(' → ');
}

/// Τι βλέπει η θύρα του patch panel πίσω της: η πρίζα και, αν υπάρχει, η
/// συσκευή που είναι συνδεδεμένη εκεί. Το [otherFloor] γράφει τον όροφο της
/// πρίζας, όταν δεν είναι ο όροφος της καμπίνας.
String floorPlanPatchPortBehind(String? connected, {String? otherFloor}) {
  final where = otherFloor == null ? 'πρίζα' : 'πρίζα ($otherFloor)';
  return connected == null ? 'Πίσω: $where' : 'Πίσω: $where → $connected';
}

/// Το σήμα μιας διαδρομής προς άλλον όροφο: «↑ RC6 · 1ος». Χωρίς γνωστή σειρά
/// ορόφων, το βέλος δείχνει απλώς μακριά.
String floorPlanOtherFloorBadge({
  required String target,
  required String floorLabel,
  required int? hereLevel,
  required int? thereLevel,
}) {
  final arrow =
      hereLevel == null || thereLevel == null || hereLevel == thereLevel
      ? '→'
      : (thereLevel > hereLevel ? '↑' : '↓');
  return '$arrow $target · $floorLabel';
}

/// Το όνομα ενός άκρου καλωδίου: όπως κάθε θύρα, εκτός από τις συσκευές με
/// μία μόνο θύρα (access point, εκτυπωτής), όπου αρκεί το όνομά τους.
String floorPlanCableEndName(FloorPlanCableEnd end) {
  final symbol = end.symbol;
  final name = end.objectName?.trim() ?? '';
  if (symbol != null && !symbol.hasPortCount && !symbol.isOutlet) {
    return name.isEmpty ? (end.kindName ?? 'Θύρα ${end.number}') : name;
  }
  return floorPlanPortAutoName(
    symbol: symbol,
    objectName: end.stackName ?? end.objectName,
    cabinetName: end.cabinetName,
    number: end.number,
    stackUnit: end.stackUnit,
    portType: end.portType,
  );
}

/// Με πόσες θύρες γεννιέται ένα αντικείμενο: η πρίζα με δύο, ό,τι έχει
/// «έχει θύρες» χωρίς δικό του πλήθος (access point, εκτυπωτής δικτύου) με
/// μία. Τα υπόλοιπα τις δηλώνει ο χρήστης.
int floorPlanDefaultPortCount(FloorPlanObjectKind? kind) {
  final symbol = kind?.symbol;
  if (kind == null || symbol == null) return 0;
  if (symbol.isOutlet) return kFloorPlanOutletDefaultPorts;
  return kind.hasPorts && floorPlanHasSinglePort(kind) ? 1 : 0;
}

/// Δέχεται ακριβώς ένα καλώδιο, χωρίς πρόσοψη (απόφαση 30/10/2026).
bool floorPlanHasSinglePort(FloorPlanObjectKind kind) {
  final symbol = kind.symbol;
  return symbol != null &&
      kind.hasPorts &&
      !symbol.hasPortCount &&
      !symbol.isOutlet &&
      !symbol.isVolume;
}

/// Ποια καλώδια έχει κάθε θύρα του ορόφου.
class FloorPlanPortCables {
  FloorPlanPortCables(this.lines) {
    for (final line in lines) {
      _other[(line.a.portId, line.a.side)] = (line.cableId, line.b);
      _other[(line.b.portId, line.b.side)] = (line.cableId, line.a);
      (line.a.side == kFloorPlanCableBack ? back : front).add(line.a.portId);
      (line.b.side == kFloorPlanCableBack ? back : front).add(line.b.portId);
    }
  }

  static final empty = FloorPlanPortCables(const []);

  final List<FloorPlanCableLine> lines;

  /// Θύρες με καλώδιο στην πίσω πλευρά (μόνο patch panel, προς πρίζα).
  final Set<int> back = {};

  /// Θύρες με καλώδιο στην μπροστινή πλευρά.
  final Set<int> front = {};

  final Map<(int, String), (int, FloorPlanCableEnd)> _other = {};

  /// Το άλλο άκρο του καλωδίου της θύρας [portId], από την πλευρά [side].
  FloorPlanCableEnd? otherEnd(int portId, String side) =>
      _other[(portId, side)]?.$2;

  int? cableIdAt(int portId, String side) => _other[(portId, side)]?.$1;

  /// Πόσα διαφορετικά καλώδια αγγίζουν τα αντικείμενα [objectIds]: ένα καλώδιο
  /// ανάμεσα σε δύο συσκευές της ίδιας καμπίνας μετρά μία φορά.
  int countTouching(Set<int> objectIds) => lines
      .where(
        (l) =>
            objectIds.contains(l.a.objectId) ||
            objectIds.contains(l.b.objectId),
      )
      .length;
}

/// Γιατί δεν γίνεται καλώδιο από το [from] στο [to]· `null` όταν γίνεται. Το
/// [frontTaken] λέει αν μια θύρα έχει ήδη καλώδιο μπροστά.
String? floorPlanCableProblem({
  required FloorPlanPort from,
  required FloorPlanPort to,
  required FloorPlanSymbol? toSymbol,
  required String toName,
  required bool Function(int portId) frontTaken,
}) {
  if (from.objectId == to.objectId) {
    return 'Το καλώδιο δεν γίνεται να ξεκινά και να καταλήγει στην ίδια '
        'συσκευή.';
  }
  if (toSymbol?.isOutlet ?? false) {
    return 'Η πρίζα δένεται με patch panel από το πλαίσιό της, με διπλό κλικ.';
  }
  if (frontTaken(to.id)) return 'Η θύρα $toName έχει ήδη καλώδιο.';
  if (frontTaken(from.id)) return 'Η αρχική θύρα έχει ήδη καλώδιο.';
  return null;
}

/// Οι θύρες της πλάκας όπως τις γράφει το πλαίσιο της πρίζας — τίποτα δεν
/// πηγαίνει στη βάση πριν από το ✓.
class FloorPlanOutletPortDraft {
  const FloorPlanOutletPortDraft({
    required this.number,
    this.writtenName,
    this.patchPortId,
    this.patchPortName,
    this.connection = FloorPlanPortConnection.none,
    this.connectionLabel,
  });

  final int number;
  final String? writtenName;

  /// Η θύρα του patch panel όπου δένεται· `null` = χωρίς σύνδεση.
  final int? patchPortId;
  final String? patchPortName;
  final FloorPlanPortConnection connection;

  /// Πώς φαίνεται η [connection] στο πλαίσιο.
  final String? connectionLabel;

  FloorPlanOutletPortDraft copyWith({
    String? Function()? writtenName,
    ({int? id, String? name})? patchPort,
    ({FloorPlanPortConnection value, String? label})? connection,
  }) => FloorPlanOutletPortDraft(
    number: number,
    writtenName: writtenName == null ? this.writtenName : writtenName(),
    patchPortId: patchPort == null ? patchPortId : patchPort.id,
    patchPortName: patchPort == null ? patchPortName : patchPort.name,
    connection: connection == null ? this.connection : connection.value,
    connectionLabel: connection == null ? connectionLabel : connection.label,
  );
}

/// Τι πρέπει να γραφτεί για να γίνει η πλάκα όπως το [FloorPlanOutletPortDraft].
class FloorPlanOutletChange {
  const FloorPlanOutletChange({
    this.insert = const [],
    this.remove = const [],
    this.update = const [],
    this.disconnect = const [],
    this.connect = const [],
  });

  /// Νέες θύρες (χωρίς id ακόμη).
  final List<FloorPlanPort> insert;

  /// Θύρες που φεύγουν, με ό,τι είχαν.
  final List<FloorPlanPort> remove;

  /// Νέες εκδοχές θυρών που μένουν.
  final List<FloorPlanPort> update;

  /// Θύρες που μένουν αλλά χάνουν το καλώδιό τους προς το patch panel.
  final List<int> disconnect;

  /// Ποια θύρα της πλάκας (κατά αριθμό) δένεται με ποια θύρα patch panel.
  final List<({int number, int patchPortId})> connect;

  bool get isEmpty =>
      insert.isEmpty &&
      remove.isEmpty &&
      update.isEmpty &&
      disconnect.isEmpty &&
      connect.isEmpty;
}

/// Συγκρίνει τις θύρες της πρίζας [objectId] με το [drafts] και λέει τι
/// αλλάζει. Ό,τι έμεινε ίδιο δεν αγγίζεται.
FloorPlanOutletChange floorPlanOutletChange({
  required int objectId,
  required List<FloorPlanPort> existing,
  required Map<int, int> patchPortOfOutletPort,
  required List<FloorPlanOutletPortDraft> drafts,
}) {
  final byNumber = {for (final p in existing) p.number: p};
  final wanted = {for (final d in drafts) d.number};
  final insert = <FloorPlanPort>[];
  final update = <FloorPlanPort>[];
  final disconnect = <int>[];
  final connect = <({int number, int patchPortId})>[];
  for (final d in drafts) {
    final patch = d.patchPortId;
    final old = byNumber[d.number];
    if (old == null) {
      insert.add(
        FloorPlanPort(
          id: 0,
          objectId: objectId,
          number: d.number,
        ).withWrittenName(d.writtenName).withConnection(d.connection),
      );
      if (patch != null) connect.add((number: d.number, patchPortId: patch));
      continue;
    }
    final next = old
        .withWrittenName(d.writtenName)
        .withConnection(d.connection);
    if (next.writtenName != old.writtenName ||
        next.connection != old.connection) {
      update.add(next);
    }
    final oldPatch = patchPortOfOutletPort[old.id];
    if (oldPatch != patch) {
      if (oldPatch != null) disconnect.add(old.id);
      if (patch != null) connect.add((number: d.number, patchPortId: patch));
    }
  }
  return FloorPlanOutletChange(
    insert: insert,
    remove: [
      for (final p in existing)
        if (!wanted.contains(p.number)) p,
    ],
    update: update,
    disconnect: disconnect,
    connect: connect,
  );
}

/// Ένα patch panel με τις θύρες που μπορεί να διαλέξει κανείς.
class FloorPlanPatchPanelGroup {
  const FloorPlanPatchPanelGroup({
    required this.floorId,
    required this.cabinetName,
    required this.panelName,
    required this.ports,
  });

  final int floorId;
  final String? cabinetName;
  final String? panelName;
  final List<FloorPlanPatchPortOption> ports;
}

/// Τι προσφέρει το «Σύνδεση με patch panel…»: **πρώτα ο όροφος της πρίζας**,
/// και σε κάθε patch panel μόνο οι ελεύθερες θύρες, συν όσες κρατά ήδη το
/// πλαίσιο ([keep]). Οι [exclude] (η άλλη θύρα της ίδιας πλάκας) δεν
/// προσφέρονται. Patch panel χωρίς καμία διαθέσιμη θύρα παραλείπεται.
List<FloorPlanPatchPanelGroup> floorPlanPatchPanelGroups(
  List<FloorPlanPatchPortOption> options, {
  required int currentFloorId,
  Set<int> keep = const {},
  Set<int> exclude = const {},
}) {
  final byPanel = <int, List<FloorPlanPatchPortOption>>{};
  for (final o in options) {
    if (exclude.contains(o.portId)) continue;
    if (o.taken && !keep.contains(o.portId)) continue;
    (byPanel[o.panelId] ??= []).add(o);
  }
  String key(String? s) => s?.trim().toLowerCase() ?? '';
  final groups = [
    for (final ports in byPanel.values)
      FloorPlanPatchPanelGroup(
        floorId: ports.first.floorId,
        cabinetName: ports.first.cabinetName,
        panelName: ports.first.panelName,
        ports: ports..sort((a, b) => a.number.compareTo(b.number)),
      ),
  ];
  groups.sort((a, b) {
    final here = (b.floorId == currentFloorId ? 1 : 0).compareTo(
      a.floorId == currentFloorId ? 1 : 0,
    );
    if (here != 0) return here;
    final floor = a.floorId.compareTo(b.floorId);
    if (floor != 0) return floor;
    final cabinet = key(a.cabinetName).compareTo(key(b.cabinetName));
    return cabinet != 0
        ? cabinet
        : key(a.panelName).compareTo(key(b.panelName));
  });
  return groups;
}

/// Πόσες θύρες χωρούν το πολύ σε μία σειρά της πρόσοψης — όσες έχει ένα
/// τυπικό patch panel, ώστε να φαίνεται ολόκληρο σε μία γραμμή.
const int kFloorPlanFacadeMaxColumns = 24;

/// Οι γραμμές της πρόσοψης, κάθε μία με τους αριθμούς της, για [columns]
/// θύρες ανά σειρά.
///
/// Patch panel: στη σειρά, 1…24 και ξανά από κάτω — όπως είναι τυπωμένα. Τα
/// υπόλοιπα (switch, router, POE): σε ζεύγη, μονές από πάνω και ζυγές από
/// κάτω, όπως στο εγκεκριμένο σκαρίφημα του switch.
List<List<int>> floorPlanFacadeRows(
  FloorPlanSymbol? symbol,
  int count, {
  int columns = kFloorPlanFacadeMaxColumns,
}) {
  if (count <= 0 || columns <= 0) return const [];
  if (symbol == FloorPlanSymbol.patchPanel) {
    return [
      for (var start = 1; start <= count; start += columns)
        [for (var n = start; n <= count && n < start + columns; n++) n],
    ];
  }
  final rows = <List<int>>[];
  for (var start = 1; start <= count; start += 2 * columns) {
    final end = start + 2 * columns - 1 > count
        ? count
        : start + 2 * columns - 1;
    rows.add([for (var n = start; n <= end; n += 2) n]);
    final evens = [for (var n = start + 1; n <= end; n += 2) n];
    if (evens.isNotEmpty) rows.add(evens);
  }
  return rows;
}

/// Πόσες θύρες ανά σειρά χωρούν σε πλάτος [width], με θύρα τουλάχιστον
/// [minBox] pixel — ποτέ πάνω από [kFloorPlanFacadeMaxColumns], ποτέ κάτω
/// από 1. Ό,τι δεν χωρά πάει σε επόμενη σειρά αντί να κρυφτεί.
int floorPlanFacadeColumns(double width, {double minBox = 16, double gap = 2}) {
  final fit = ((width + gap) / (minBox + gap)).floor();
  return fit.clamp(1, kFloorPlanFacadeMaxColumns);
}

/// Τι γίνεται όταν το πλήθος θυρών αλλάζει σε [count]: ποιοι αριθμοί
/// προστίθενται, και ποιες θύρες φεύγουν (οι μεγαλύτεροι αριθμοί). Οι
/// υπόλοιπες μένουν ανέγγιχτες, με το γραμμένο τους όνομα.
({List<int> add, List<FloorPlanPort> remove}) floorPlanPortCountChange(
  List<FloorPlanPort> existing,
  int count,
) {
  final have = {for (final p in existing) p.number};
  return (
    add: [
      for (var n = 1; n <= count; n++)
        if (!have.contains(n)) n,
    ],
    remove: [
      for (final p in existing)
        if (p.number > count) p,
    ],
  );
}
