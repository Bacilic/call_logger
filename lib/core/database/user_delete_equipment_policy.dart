/// Εξοπλισμός σε κίνδυνο ορφανοποίησης τμήματος πριν από soft delete χρήστη.
///
/// Μόνο όταν `equipment.department_id IS NULL` και δεν μένει άλλος ενεργός
/// κάτοχος εκτός των διαγραφόμενων χρηστών.
class ExclusiveEquipmentForUserDelete {
  const ExclusiveEquipmentForUserDelete({
    required this.equipmentId,
    required this.codeEquipment,
    required this.userId,
    this.departmentId,
    this.departmentName,
  });

  final int equipmentId;
  final String codeEquipment;
  final int userId;
  final int? departmentId;
  final String? departmentName;
}
