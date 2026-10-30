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
}
