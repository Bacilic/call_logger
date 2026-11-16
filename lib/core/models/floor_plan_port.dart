import 'dart:convert';

import 'floor_plan_object_kind.dart';

/// Το πρόθεμα της θύρας ενός switch όταν δεν έχει δηλωθεί άλλο.
const String kFloorPlanDefaultPortType = 'Gi';

/// Μία **ομάδα θυρών** μιας συσκευής: π.χ. οι 24 θύρες 1G και, χωριστά, οι 4
/// θύρες uplink 10G (αποφάσεις 14/11/2026). Το πλήθος δεν κρατιέται εδώ —
/// είναι όσες θύρες ανήκουν στην ομάδα.
class FloorPlanPortGroup {
  const FloorPlanPortGroup({this.prefix, this.speed, this.continues = false});

  /// Το πρόθεμα των ονομάτων («Gi», «Te», «SFP»)· `null` = κανένα (στο switch
  /// σημαίνει «Gi»).
  final String? prefix;

  /// Ελεύθερο κείμενο, π.χ. «10G SFP+» — φαίνεται πάνω από το μπλοκ της
  /// πρόσοψης.
  final String? speed;

  /// Κρατά τον μεσαίο αριθμό της προηγούμενης ομάδας και συνεχίζει την
  /// αρίθμησή της («Te1/0/1…8» → «Gi1/0/9…24»). Δεν έχει νόημα στην πρώτη.
  final bool continues;

  @override
  bool operator ==(Object other) =>
      other is FloorPlanPortGroup &&
      other.prefix == prefix &&
      other.speed == speed &&
      other.continues == continues;

  @override
  int get hashCode => Object.hash(prefix, speed, continues);
}

/// Οι ομάδες θυρών από τις δύο στήλες της βάσης: το πρόθεμα της πρώτης
/// ([portType], από πριν υπάρξουν ομάδες) και τα υπόλοιπα ([data], JSON).
/// Πάντα τουλάχιστον μία ομάδα· χαλασμένο JSON διαβάζεται ως μία ομάδα, ώστε
/// οι θύρες να έχουν πάντα όνομα.
List<FloorPlanPortGroup> floorPlanPortGroupsFrom(
  String? portType,
  String? data,
) {
  final first = FloorPlanPortGroup(prefix: _blankToNull(portType));
  if (data == null || data.trim().isEmpty) return [first];
  try {
    final list = jsonDecode(data);
    if (list is! List || list.isEmpty) return [first];
    return [
      for (final (i, e) in list.indexed)
        if (e is Map)
          FloorPlanPortGroup(
            prefix: i == 0 ? first.prefix : _blankToNull(e['p'] as String?),
            speed: _blankToNull(e['s'] as String?),
            continues: i > 0 && e['c'] == true,
          )
        else
          i == 0 ? first : const FloorPlanPortGroup(),
    ];
  } on FormatException {
    return [first];
  }
}

/// Η στήλη `port_groups` για τις [groups]· `null` όταν είναι μία ομάδα χωρίς
/// ταχύτητα — όπως κάθε συσκευή πριν από τις ομάδες. Το πρόθεμα της πρώτης
/// δεν γράφεται εδώ: ζει στο `port_type`.
String? floorPlanPortGroupsData(List<FloorPlanPortGroup> groups) {
  if (groups.isEmpty) return null;
  if (groups.length == 1 && _blankToNull(groups.first.speed) == null) {
    return null;
  }
  return jsonEncode([
    for (final (i, g) in groups.indexed)
      {
        if (i > 0 && _blankToNull(g.prefix) != null) 'p': g.prefix!.trim(),
        if (_blankToNull(g.speed) != null) 's': g.speed!.trim(),
        if (i > 0 && g.continues) 'c': true,
      },
  ]);
}

/// Ο μεσαίος αριθμός (module) της ομάδας [index] στο πρότυπο Cisco: η πρώτη
/// έχει 0, κάθε επόμενη +1 — εκτός από όσες συνεχίζουν την προηγούμενη.
int floorPlanPortGroupModule(List<FloorPlanPortGroup> groups, int index) {
  var module = 0;
  for (var i = 1; i <= index; i++) {
    // Ομάδα που δεν δηλώθηκε (π.χ. θύρα από νεότερη εγγραφή) είναι δική της.
    if (i < groups.length && groups[i].continues) continue;
    module++;
  }
  return module;
}

/// Ταξινόμηση θυρών μιας συσκευής: κατά ομάδα, και μέσα σε αυτήν κατά αριθμό.
int floorPlanComparePorts(FloorPlanPort a, FloorPlanPort b) {
  final group = a.groupIndex.compareTo(b.groupIndex);
  return group != 0 ? group : a.number.compareTo(b.number);
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Το **αυτόματο όνομα** μιας θύρας. Δεν αποθηκεύεται· συντίθεται κάθε φορά.
///
/// - Patch panel σε καμπίνα: καμπίνα + patch panel + διαχωριστικό + αριθμός,
///   «RC6.F17» ή «MC.2.S.Molex 1.1». Το διαχωριστικό το ορίζει η συσκευή
///   ([portSeparator])· όσο δεν το έχει ορίσει, ισχύει το
///   [floorPlanDefaultPortSeparator]. Μία ομάδα πάντα.
/// - Switch: πρότυπο Cisco, πρόθεμα + μέλος / module / θύρα, «SW-2 Gi1/0/14»
///   (απόφαση 04/11/2026). Το module είναι η σειρά της ομάδας [group]
///   ([floorPlanPortGroupModule]): «SW-2 Te1/1/3» για τα uplink.
/// - Οτιδήποτε άλλο: όνομα + πρόθεμα ομάδας + αριθμός, «POE-1 / 14» και
///   «POE-1 / SFP2» (απόφαση 14/11/2026).
///
/// Ό,τι δεν έχει ακόμη όνομα απλώς παραλείπεται, ώστε η θύρα να έχει πάντα
/// κάτι να δείξει.
String floorPlanPortAutoName({
  required FloorPlanSymbol? symbol,
  required String? objectName,
  required String? cabinetName,
  required int number,
  int? stackUnit,
  List<FloorPlanPortGroup> groups = const [],
  int group = 0,
  String? portSeparator,
}) {
  final name = objectName?.trim() ?? '';
  final cabinet = cabinetName?.trim() ?? '';
  if (symbol == FloorPlanSymbol.patchPanel) {
    final separator = name.isEmpty
        ? ''
        : (portSeparator ?? floorPlanDefaultPortSeparator(name));
    final panel = '$name$separator$number';
    return cabinet.isEmpty ? panel : '$cabinet.$panel';
  }
  final prefix = group < groups.length
      ? _blankToNull(groups[group].prefix)
      : null;
  if (symbol == FloorPlanSymbol.networkSwitch) {
    final type = prefix ?? kFloorPlanDefaultPortType;
    final module = floorPlanPortGroupModule(groups, group);
    final cisco = '$type${stackUnit ?? 1}/$module/$number';
    return name.isEmpty ? cisco : '$name $cisco';
  }
  final port = '${prefix ?? ''}$number';
  return name.isEmpty ? 'Θύρα $port' : '$name / $port';
}

/// Το πλείστο μήκος του διαχωριστικού θυρών.
const int kFloorPlanPortSeparatorMaxLength = 3;

/// Το διαχωριστικό που διαλέγει η εφαρμογή για ένα patch panel που δεν έχει
/// ορίσει δικό του: **τελεία** όταν το όνομα τελειώνει σε ψηφίο, ώστε το
/// «Molex 1» να μη δίνει «Molex 11» στη θύρα 1 (η πρακτική του νοσοκομείου,
/// απόφαση 13/11/2026)· αλλιώς **τίποτα**, όπως το «RC6.F17».
/// Το όνομα που απέχει [offset] θέσεις από το [seed] στο μοτίβο του:
/// «MC.2.N01» με +1 → «MC.2.N02», «A-9» με +1 → «A-10». Ο αριθμός κρατά το
/// πλάτος του με μηδενικά μπροστά. `null` όταν το [seed] δεν τελειώνει σε
/// αριθμό.
String? floorPlanPatternName(String seed, int offset) {
  final match = RegExp(r'^(.*?)(\d+)$').firstMatch(seed.trim());
  if (match == null) return null;
  final digits = match.group(2)!;
  final next = int.parse(digits) + offset;
  if (next < 0) return null;
  return '${match.group(1)}${'$next'.padLeft(digits.length, '0')}';
}

/// Οι θύρες μετά την [from], της ίδιας συσκευής και ομάδας, που παίρνουν όνομα από το
/// μοτίβο του [seed] — **μόνο όσες δεν έχουν ήδη γραμμένο όνομα**. Η θύρα
/// [from] + k παίρνει το όνομα που απέχει k από το [seed]. Η ίδια συνάρτηση
/// δίνει την προεπισκόπηση και ό,τι γράφεται.
({List<({FloorPlanPort port, String name})> fill, int kept})
floorPlanPatternFill({
  required String seed,
  required FloorPlanPort from,
  required Iterable<FloorPlanPort> ports,
}) {
  final fill = <({FloorPlanPort port, String name})>[];
  var kept = 0;
  final later = [
    for (final p in ports)
      if (p.objectId == from.objectId &&
          p.groupIndex == from.groupIndex &&
          p.number > from.number)
        p,
  ]..sort((a, b) => a.number.compareTo(b.number));
  for (final p in later) {
    final name = floorPlanPatternName(seed, p.number - from.number);
    if (name == null) break;
    if ((p.writtenName ?? '').trim().isNotEmpty) {
      kept++;
      continue;
    }
    fill.add((port: p, name: name));
  }
  return (fill: fill, kept: kept);
}

/// Ένα γραμμένο όνομα θύρας κάπου στο κτίριο, με το πού βρίσκεται — για
/// την προειδοποίηση «το έχει ήδη άλλη θύρα».
class FloorPlanWrittenPortName {
  const FloorPlanWrittenPortName({
    required this.portId,
    required this.number,
    required this.name,
    required this.objectLabel,
    this.cabinetName,
    this.floorLabel,
  });

  final int portId;
  final int number;
  final String name;

  /// Το όνομα της συσκευής, ή το είδος της όταν δεν έχει όνομα.
  final String objectLabel;
  final String? cabinetName;
  final String? floorLabel;

  /// «θύρα 5 · Patch panel A · καμπίνα MC.2.S · Ισόγειο».
  String get where => [
    'θύρα $number',
    objectLabel,
    if ((cabinetName ?? '').trim().isNotEmpty) 'καμπίνα ${cabinetName!.trim()}',
    if ((floorLabel ?? '').trim().isNotEmpty) floorLabel!.trim(),
  ].join(' · ');
}

String floorPlanDefaultPortSeparator(String? objectName) {
  final name = objectName?.trim() ?? '';
  if (name.isEmpty) return '';
  final last = name.codeUnitAt(name.length - 1);
  return last >= 0x30 && last <= 0x39 ? '.' : '';
}

/// Μία θύρα όπως τη ζητά η αναζήτηση του χάρτη: ό,τι χρειάζεται για να
/// συντεθεί το αυτόματο όνομά της και για να βρεθεί στον χάρτη.
class FloorPlanPortSearchRow {
  const FloorPlanPortSearchRow({
    required this.portId,
    required this.number,
    required this.objectId,
    required this.floorId,
    required this.symbol,
    this.writtenName,
    this.objectName,
    this.kindName,
    this.cabinetId,
    this.cabinetName,
    this.stackUnit,
    this.groupIndex = 0,
    this.portGroups = const [],
    this.portSeparator,
    this.linkedPanelName,
    this.linkedCabinetName,
    this.linkedNumber,
    this.linkedSeparator,
  });

  final int portId;
  final int number;
  final int objectId;
  final int floorId;
  final FloorPlanSymbol? symbol;
  final String? writtenName;

  /// Το όνομα του αντικειμένου — του stack, αν ανήκει σε κάποιο.
  final String? objectName;
  final String? kindName;
  final int? cabinetId;
  final String? cabinetName;
  final int? stackUnit;

  /// Σε ποια από τις [portGroups] της συσκευής ανήκει.
  final int groupIndex;
  final List<FloorPlanPortGroup> portGroups;
  final String? portSeparator;

  /// Θύρα πρίζας: η θύρα patch panel όπου είναι δεμένη.
  final String? linkedPanelName;
  final String? linkedCabinetName;
  final int? linkedNumber;
  final String? linkedSeparator;

  /// Το αυτόματο όνομα· `null` για θύρα πρίζας που δεν έχει δεθεί, που δεν έχει
  /// ακόμη όνομα.
  String? get autoName {
    if (symbol?.isOutlet ?? false) {
      final linked = linkedNumber;
      return linked == null
          ? null
          : floorPlanPortAutoName(
              symbol: FloorPlanSymbol.patchPanel,
              objectName: linkedPanelName,
              cabinetName: linkedCabinetName,
              number: linked,
              portSeparator: linkedSeparator,
            );
    }
    return floorPlanPortAutoName(
      symbol: symbol,
      objectName: objectName,
      cabinetName: cabinetName,
      number: number,
      stackUnit: stackUnit,
      groups: portGroups,
      group: groupIndex,
      portSeparator: portSeparator,
    );
  }
}

/// Μία θύρα ενός αντικειμένου του χάρτη (patch panel, switch, router, POE,
/// πρίζα), όπως ζει στη βάση.
///
/// Το **αυτόματο όνομα** («RC6.F17», «SW-2 / 14») δεν αποθηκεύεται:
/// συντίθεται κάθε φορά από τα ονόματα καμπίνας και αντικειμένου, ώστε να μη
/// μένει μπαγιάτικο όταν κάποιο μετονομάζεται. Αποθηκεύεται μόνο το
/// [writtenName] — ό,τι γράφει πραγματικά η ετικέτα.
class FloorPlanPort {
  const FloorPlanPort({
    required this.id,
    required this.objectId,
    required this.number,
    this.groupIndex = 0,
    this.writtenName,
    this.connectedEquipmentId,
    this.connectedObjectId,
    this.connectedText,
  });

  final int id;
  final int objectId;

  /// Σε ποια ομάδα θυρών της συσκευής ανήκει (0 = η πρώτη).
  final int groupIndex;

  /// Ο αριθμός μέσα στην ομάδα: από το 1, ή συνέχεια της προηγούμενης ομάδας
  /// όταν εκείνη «συνεχίζει» — όπως τον γράφει το όνομα.
  final int number;
  final String? writtenName;

  /// Τι είναι συνδεδεμένο σε θύρα πρίζας: εξοπλισμός του Καταλόγου,
  /// αντικείμενο του χάρτη ή ελεύθερο κείμενο.
  final int? connectedEquipmentId;
  final int? connectedObjectId;
  final String? connectedText;

  static const List<String> columns = [
    'id',
    'object_id',
    'group_index',
    'number',
    'written_name',
    'connected_equipment_id',
    'connected_object_id',
    'connected_text',
  ];

  factory FloorPlanPort.fromMap(Map<String, Object?> row) => FloorPlanPort(
    id: row['id'] as int,
    objectId: row['object_id'] as int,
    groupIndex: row['group_index'] as int? ?? 0,
    number: row['number'] as int,
    writtenName: row['written_name'] as String?,
    connectedEquipmentId: row['connected_equipment_id'] as int?,
    connectedObjectId: row['connected_object_id'] as int?,
    connectedText: row['connected_text'] as String?,
  );

  Map<String, Object?> toInsertMap() => {
    'object_id': objectId,
    'group_index': groupIndex,
    'number': number,
    'written_name': writtenName,
    'connected_equipment_id': connectedEquipmentId,
    'connected_object_id': connectedObjectId,
    'connected_text': connectedText,
  };

  FloorPlanPort copyWith({int? id, int? groupIndex, int? number}) =>
      FloorPlanPort(
        id: id ?? this.id,
        objectId: objectId,
        groupIndex: groupIndex ?? this.groupIndex,
        number: number ?? this.number,
        writtenName: writtenName,
        connectedEquipmentId: connectedEquipmentId,
        connectedObjectId: connectedObjectId,
        connectedText: connectedText,
      );

  /// Ίδια θύρα με άλλο γραμμένο όνομα· κενό γίνεται `null`.
  FloorPlanPort withWrittenName(String? name) {
    final trimmed = name?.trim();
    return FloorPlanPort(
      id: id,
      objectId: objectId,
      groupIndex: groupIndex,
      number: number,
      writtenName: trimmed == null || trimmed.isEmpty ? null : trimmed,
      connectedEquipmentId: connectedEquipmentId,
      connectedObjectId: connectedObjectId,
      connectedText: connectedText,
    );
  }

  /// Τι είναι συνδεδεμένο σε αυτή τη θύρα.
  FloorPlanPortConnection get connection => FloorPlanPortConnection(
    equipmentId: connectedEquipmentId,
    objectId: connectedObjectId,
    text: connectedText,
  );

  /// Ίδια θύρα με άλλη σύνδεση.
  FloorPlanPort withConnection(FloorPlanPortConnection connection) =>
      FloorPlanPort(
        id: id,
        objectId: objectId,
        groupIndex: groupIndex,
        number: number,
        writtenName: writtenName,
        connectedEquipmentId: connection.equipmentId,
        connectedObjectId: connection.objectId,
        connectedText: connection.text,
      );
}

/// Τι είναι συνδεδεμένο σε θύρα πρίζας: εξοπλισμός του Καταλόγου, αντικείμενο
/// του χάρτη ή ελεύθερο κείμενο — ένα από τα τρία, ή τίποτα.
class FloorPlanPortConnection {
  const FloorPlanPortConnection({this.equipmentId, this.objectId, this.text});

  const FloorPlanPortConnection.equipment(int id) : this(equipmentId: id);
  const FloorPlanPortConnection.object(int id) : this(objectId: id);

  /// Κείμενο με μόνο κενά δεν είναι σύνδεση.
  factory FloorPlanPortConnection.freeText(String text) {
    final trimmed = text.trim();
    return FloorPlanPortConnection(text: trimmed.isEmpty ? null : trimmed);
  }

  static const none = FloorPlanPortConnection();

  final int? equipmentId;
  final int? objectId;
  final String? text;

  bool get isEmpty => equipmentId == null && objectId == null && text == null;

  @override
  bool operator ==(Object other) =>
      other is FloorPlanPortConnection &&
      other.equipmentId == equipmentId &&
      other.objectId == objectId &&
      other.text == text;

  @override
  int get hashCode => Object.hash(equipmentId, objectId, text);
}

/// Οι δύο πλευρές ενός άκρου καλωδίου. Η θύρα του patch panel έχει `back` (το
/// μόνιμο καλώδιο προς την πρίζα) και `front` (προς το switch)· οι υπόλοιπες
/// μόνο `front`.
const String kFloorPlanCableBack = 'back';
const String kFloorPlanCableFront = 'front';

/// Οι τύποι καλωδίου που διαλέγονται (απόφαση 14/11/2026).
const List<String> kFloorPlanCableTypes = [
  'Cat 5e',
  'Cat 6',
  'Cat 6A',
  'Cat 7',
];

/// Ο τύπος καλωδίου όταν δεν έχει οριστεί άλλος.
const String kFloorPlanDefaultCableType = 'Cat 5e';

/// Ο τύπος όπως φαίνεται: κενό = [kFloorPlanDefaultCableType].
String floorPlanCableTypeLabel(String? type) {
  final trimmed = type?.trim() ?? '';
  return trimmed.isEmpty ? kFloorPlanDefaultCableType : trimmed;
}

/// Ένα καλώδιο με τα δύο άκρα του, όπως ζει στη βάση.
class FloorPlanCable {
  const FloorPlanCable({
    required this.id,
    required this.portA,
    required this.sideA,
    required this.portB,
    required this.sideB,
    this.type,
  });

  final int id;
  final int portA;
  final String sideA;
  final int portB;
  final String sideB;

  /// Cat 5e, Cat 6…· `null` = [kFloorPlanDefaultCableType]. Η προεπιλογή δεν
  /// γράφεται, ώστε τα καλώδια πριν από τους τύπους να μη μοιάζουν αλλαγμένα.
  final String? type;

  /// Ίδιο καλώδιο με άλλο τύπο· η προεπιλογή γράφεται ως `null`.
  FloorPlanCable withType(String? type) => FloorPlanCable(
    id: id,
    portA: portA,
    sideA: sideA,
    portB: portB,
    sideB: sideB,
    type: floorPlanCableTypeLabel(type) == kFloorPlanDefaultCableType
        ? null
        : type!.trim(),
  );
}

/// Το ένα άκρο ενός καλωδίου, με ό,τι χρειάζεται για να ονομαστεί — και όταν
/// βρίσκεται σε άλλον όροφο.
class FloorPlanCableEnd {
  const FloorPlanCableEnd({
    required this.portId,
    required this.side,
    required this.number,
    required this.objectId,
    required this.floorId,
    this.writtenName,
    this.objectName,
    this.cabinetName,
    this.symbol,
    this.kindName,
    this.stackName,
    this.stackUnit,
    this.groupIndex = 0,
    this.portGroups = const [],
    this.portSeparator,
  });

  final int portId;
  final String side;
  final int number;
  final int objectId;
  final int floorId;
  final String? writtenName;
  final String? objectName;
  final String? cabinetName;
  final FloorPlanSymbol? symbol;
  final String? kindName;

  /// Για switch σε stack: το όνομα του stack και ποιο μέλος είναι.
  final String? stackName;
  final int? stackUnit;

  /// Σε ποια από τις [portGroups] της συσκευής ανήκει η θύρα.
  final int groupIndex;
  final List<FloorPlanPortGroup> portGroups;

  /// Το διαχωριστικό θυρών ενός patch panel (`null` = αυτόματο).
  final String? portSeparator;
}

/// Ένα καλώδιο που αγγίζει τον όροφο, με τα δύο άκρα του.
class FloorPlanCableLine {
  const FloorPlanCableLine({
    required this.cableId,
    required this.a,
    required this.b,
    this.type,
  });

  final int cableId;
  final FloorPlanCableEnd a;
  final FloorPlanCableEnd b;

  /// Ο τύπος του καλωδίου· `null` = [kFloorPlanDefaultCableType].
  final String? type;

  /// Το καλώδιο όπως το γράφει η βάση — για αλλαγή τύπου και αναίρεση.
  FloorPlanCable get cable => FloorPlanCable(
    id: cableId,
    portA: a.portId,
    sideA: a.side,
    portB: b.portId,
    sideB: b.side,
    type: type,
  );
}

/// Η σύνδεση μιας θύρας πρίζας με θύρα patch panel, με ό,τι χρειάζεται για να
/// φανεί από τις δύο μεριές — και όταν το patch panel είναι σε άλλον όροφο.
class FloorPlanPortLink {
  const FloorPlanPortLink({
    required this.outletPortId,
    required this.outletFloorId,
    required this.patchPortId,
    required this.patchNumber,
    required this.panelId,
    required this.panelFloorId,
    this.patchWrittenName,
    this.panelName,
    this.panelSeparator,
    this.cabinetId,
    this.cabinetName,
    this.connection = FloorPlanPortConnection.none,
    this.connectedObjectLabel,
  });

  final int outletPortId;
  final int outletFloorId;
  final int patchPortId;
  final int patchNumber;
  final int panelId;
  final int panelFloorId;
  final String? patchWrittenName;
  final String? panelName;

  /// Το διαχωριστικό θυρών του patch panel (`null` = αυτόματο).
  final String? panelSeparator;
  final int? cabinetId;
  final String? cabinetName;

  /// Τι είναι συνδεδεμένο στην πρίζα, ώστε να το δείχνει και το patch panel.
  final FloorPlanPortConnection connection;

  /// Το όνομα του αντικειμένου της [connection], αν είναι αντικείμενο.
  final String? connectedObjectLabel;
}

/// Μία θύρα patch panel όπως τη δείχνει η επιλογή «Σύνδεση με patch panel…».
class FloorPlanPatchPortOption {
  const FloorPlanPatchPortOption({
    required this.portId,
    required this.number,
    required this.panelId,
    required this.floorId,
    required this.taken,
    this.writtenName,
    this.panelName,
    this.panelSeparator,
    this.cabinetName,
  });

  final int portId;
  final int number;
  final int panelId;
  final int floorId;

  /// Έχει ήδη πίσω καλώδιο.
  final bool taken;
  final String? writtenName;
  final String? panelName;

  /// Το διαχωριστικό θυρών του patch panel (`null` = αυτόματο).
  final String? panelSeparator;
  final String? cabinetName;
}
