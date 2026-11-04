import 'floor_plan_object_kind.dart';

/// Το πρόθεμα της θύρας ενός switch όταν δεν έχει δηλωθεί άλλο.
const String kFloorPlanDefaultPortType = 'Gi';

/// Το **αυτόματο όνομα** μιας θύρας. Δεν αποθηκεύεται· συντίθεται κάθε φορά.
///
/// - Patch panel σε καμπίνα: καμπίνα + patch panel + αριθμός, «RC6.F17».
/// - Switch: πρότυπο Cisco, πρόθεμα + μέλος / module / θύρα, «SW-2 Gi2/0/14»
///   (απόφαση 04/11/2026). Το module είναι πάντα 0: οι θύρες uplink γράφονται
///   ως γραμμένο όνομα.
/// - Οτιδήποτε άλλο: όνομα + αριθμός θύρας, «POE-1 / 14».
///
/// Ό,τι δεν έχει ακόμη όνομα απλώς παραλείπεται, ώστε η θύρα να έχει πάντα
/// κάτι να δείξει.
String floorPlanPortAutoName({
  required FloorPlanSymbol? symbol,
  required String? objectName,
  required String? cabinetName,
  required int number,
  int? stackUnit,
  String? portType,
}) {
  final name = objectName?.trim() ?? '';
  final cabinet = cabinetName?.trim() ?? '';
  if (symbol == FloorPlanSymbol.patchPanel) {
    final panel = '$name$number';
    return cabinet.isEmpty ? panel : '$cabinet.$panel';
  }
  if (symbol == FloorPlanSymbol.networkSwitch) {
    final type = portType ?? kFloorPlanDefaultPortType;
    final cisco = '$type${stackUnit ?? 1}/0/$number';
    return name.isEmpty ? cisco : '$name $cisco';
  }
  return name.isEmpty ? 'Θύρα $number' : '$name / $number';
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
    this.portType,
    this.linkedPanelName,
    this.linkedCabinetName,
    this.linkedNumber,
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
  final String? portType;

  /// Θύρα πρίζας: η θύρα patch panel όπου είναι δεμένη.
  final String? linkedPanelName;
  final String? linkedCabinetName;
  final int? linkedNumber;

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
            );
    }
    return floorPlanPortAutoName(
      symbol: symbol,
      objectName: objectName,
      cabinetName: cabinetName,
      number: number,
      stackUnit: stackUnit,
      portType: portType,
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
    this.writtenName,
    this.connectedEquipmentId,
    this.connectedObjectId,
    this.connectedText,
  });

  final int id;
  final int objectId;

  /// Από το 1, μέσα στο αντικείμενο.
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
    'number',
    'written_name',
    'connected_equipment_id',
    'connected_object_id',
    'connected_text',
  ];

  factory FloorPlanPort.fromMap(Map<String, Object?> row) => FloorPlanPort(
    id: row['id'] as int,
    objectId: row['object_id'] as int,
    number: row['number'] as int,
    writtenName: row['written_name'] as String?,
    connectedEquipmentId: row['connected_equipment_id'] as int?,
    connectedObjectId: row['connected_object_id'] as int?,
    connectedText: row['connected_text'] as String?,
  );

  Map<String, Object?> toInsertMap() => {
    'object_id': objectId,
    'number': number,
    'written_name': writtenName,
    'connected_equipment_id': connectedEquipmentId,
    'connected_object_id': connectedObjectId,
    'connected_text': connectedText,
  };

  FloorPlanPort copyWith({int? id}) => FloorPlanPort(
    id: id ?? this.id,
    objectId: objectId,
    number: number,
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

/// Ένα καλώδιο με τα δύο άκρα του, όπως ζει στη βάση.
class FloorPlanCable {
  const FloorPlanCable({
    required this.id,
    required this.portA,
    required this.sideA,
    required this.portB,
    required this.sideB,
  });

  final int id;
  final int portA;
  final String sideA;
  final int portB;
  final String sideB;
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
    this.portType,
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

  /// Το πρόθεμα των θυρών ενός switch (Fa, Gi, Te).
  final String? portType;
}

/// Ένα καλώδιο που αγγίζει τον όροφο, με τα δύο άκρα του.
class FloorPlanCableLine {
  const FloorPlanCableLine({
    required this.cableId,
    required this.a,
    required this.b,
  });

  final int cableId;
  final FloorPlanCableEnd a;
  final FloorPlanCableEnd b;
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
  final String? cabinetName;
}
