import '../../models/equipment_model.dart';

/// Πρόταση εξοπλισμού στην αρχική overlay λίστα (εξοπλισμός + πηγή).
class SmartEntityEquipmentSuggestion {
  const SmartEntityEquipmentSuggestion({
    required this.equipment,
    required this.sourceLabel,
  });

  final EquipmentModel equipment;
  final String sourceLabel;
}
