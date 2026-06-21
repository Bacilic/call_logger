import 'calls_field_groups.dart';

/// Layout templates from design doc section 8 (Α/Β/Γ/Δ).
enum CallsLayoutTemplate { a, b, c, d }

/// Selects template from active groups (design doc 8.6).
class CallsLayoutTemplateSelector {
  const CallsLayoutTemplateSelector._();

  static CallsLayoutTemplate select({
    required bool isPhoneGroupActive,
    required bool isCallerGroupActive,
    required EquipmentGroupTier equipmentTier,
    required bool isMapActive,
  }) {
    if (isPhoneGroupActive) return CallsLayoutTemplate.a;

    final hasEquipment = equipmentTier != EquipmentGroupTier.none;
    final hasCaller = isCallerGroupActive;

    if (hasCaller && hasEquipment) return CallsLayoutTemplate.b;
    if (hasCaller) return CallsLayoutTemplate.c;
    if (hasEquipment) return CallsLayoutTemplate.d;
    if (isMapActive) return CallsLayoutTemplate.b;
    return CallsLayoutTemplate.b;
  }
}
