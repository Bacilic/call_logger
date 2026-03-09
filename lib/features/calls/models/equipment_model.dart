/// Μοντέλο εξοπλισμού (πίνακας equipment): id, code_equipment, type, user_id, notes.
class EquipmentModel {
  EquipmentModel({
    this.id,
    this.code,
    this.type,
    this.notes,
    this.userId,
  });

  final int? id;
  /// Κωδικός εξοπλισμού (από στήλη code_equipment).
  final String? code;
  final String? type;
  final String? notes;
  final int? userId;

  /// Για εμφάνιση σε λίστες (κωδικός + τύπος).
  String get displayLabel {
    final c = code?.trim() ?? '';
    final t = type?.trim() ?? '';
    return t.isEmpty ? c : (c.isEmpty ? t : '$c ($t)');
  }

  factory EquipmentModel.fromMap(Map<String, dynamic> map) {
    return EquipmentModel(
      id: map['id'] as int?,
      code: (map['code_equipment'] ?? map['code']) as String?,
      type: map['type'] as String?,
      notes: map['notes'] as String?,
      userId: map['user_id'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (code != null) 'code_equipment': code,
      if (type != null) 'type': type,
      if (notes != null) 'notes': notes,
      if (userId != null) 'user_id': userId,
    };
  }
}
