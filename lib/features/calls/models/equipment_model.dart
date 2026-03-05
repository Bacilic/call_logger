/// Μοντέλο εξοπλισμού (πίνακας equipment).
class EquipmentModel {
  EquipmentModel({
    this.id,
    this.type,
    this.brand,
    this.model,
    this.serialNumber,
    this.userId,
    this.buyDate,
  });

  final int? id;
  final String? type;
  final String? brand;
  final String? model;
  final String? serialNumber;
  final int? userId;
  final String? buyDate;

  factory EquipmentModel.fromMap(Map<String, dynamic> map) {
    return EquipmentModel(
      id: map['id'] as int?,
      type: map['type'] as String?,
      brand: map['brand'] as String?,
      model: map['model'] as String?,
      serialNumber: map['serial_number'] as String?,
      userId: map['user_id'] as int?,
      buyDate: map['buy_date'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (brand != null) 'brand': brand,
      if (model != null) 'model': model,
      if (serialNumber != null) 'serial_number': serialNumber,
      if (userId != null) 'user_id': userId,
      if (buyDate != null) 'buy_date': buyDate,
    };
  }
}
