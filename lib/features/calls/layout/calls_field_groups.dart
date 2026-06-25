import '../../../core/services/lookup_service.dart';
import '../provider/smart_entity_selector_provider.dart';
import 'calls_field_confirmations.dart';
import 'calls_layout_template.dart';
import 'calls_map_gate.dart';

/// Equipment group activation tier (free text vs matched catalog record).
enum EquipmentGroupTier { none, freeTextOnly, matchedRecord }

/// Active field groups derived from header state + field confirmations.
class CallsFieldGroups {
  const CallsFieldGroups({
    required this.isPhoneGroupActive,
    required this.equipmentTier,
    required this.isCallerGroupActive,
    required this.isMapActive,
    required this.template,
  });

  final bool isPhoneGroupActive;
  final EquipmentGroupTier equipmentTier;
  final bool isCallerGroupActive;
  final bool isMapActive;
  final CallsLayoutTemplate template;

  bool get isEquipmentGroupActive => equipmentTier != EquipmentGroupTier.none;

  /// Πρότυπο Α με μόνο ΟΕ (χωρίς ΟΚ/ΟΞ): σημειώσεις σε δική τους γραμμή.
  bool get isPhoneOnlyTemplateA =>
      template == CallsLayoutTemplate.a &&
      isPhoneGroupActive &&
      !isCallerGroupActive &&
      !isEquipmentGroupActive;

  bool get anyGroupActive =>
      isPhoneGroupActive ||
      isEquipmentGroupActive ||
      isCallerGroupActive ||
      isMapActive;

  bool get isExpanded => anyGroupActive;
  bool get isCompact => !anyGroupActive;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallsFieldGroups &&
          isPhoneGroupActive == other.isPhoneGroupActive &&
          equipmentTier == other.equipmentTier &&
          isCallerGroupActive == other.isCallerGroupActive &&
          isMapActive == other.isMapActive &&
          template == other.template;

  @override
  int get hashCode =>
      Object.hash(isPhoneGroupActive, equipmentTier, isCallerGroupActive, isMapActive, template);
}

/// Pure resolver — no Riverpod / Flutter imports.
class CallsFieldGroupsResolver {
  const CallsFieldGroupsResolver._();

  static CallsFieldGroups resolve(
    SmartEntitySelectorState header,
    CallsFieldConfirmations confirmations, [
    LookupService? lookup,
  ]) {
    final phoneValue = header.selectedPhone?.trim() ?? '';
    final isPhoneGroupActive =
        confirmations.phone && phoneValue.isNotEmpty;

    final equipmentText = header.equipmentText.trim();
    final EquipmentGroupTier equipmentTier;
    if (confirmations.equipment && equipmentText.isNotEmpty) {
      equipmentTier = header.selectedEquipment != null
          ? EquipmentGroupTier.matchedRecord
          : EquipmentGroupTier.freeTextOnly;
    } else {
      equipmentTier = EquipmentGroupTier.none;
    }

    final callerId = header.selectedCaller?.id;
    final isCallerGroupActive =
        confirmations.caller && callerId != null;

    final isMapActive = CallsMapGate.isMapActive(header, lookup, confirmations);

    final template = CallsLayoutTemplateSelector.select(
      isPhoneGroupActive: isPhoneGroupActive,
      isCallerGroupActive: isCallerGroupActive,
      equipmentTier: equipmentTier,
      isMapActive: isMapActive,
    );

    return CallsFieldGroups(
      isPhoneGroupActive: isPhoneGroupActive,
      equipmentTier: equipmentTier,
      isCallerGroupActive: isCallerGroupActive,
      isMapActive: isMapActive,
      template: template,
    );
  }
}

/// Screen title per design doc section 2 — independent from group gates.
class CallsScreenTitleResolver {
  const CallsScreenTitleResolver._();

  static String resolve(SmartEntitySelectorState header) {
    final phone = header.selectedPhone?.trim() ?? '';
    final caller = header.callerDisplayText.trim();
    final dept = header.departmentText.trim();
    final equip = header.equipmentText.trim();

    final allEmpty =
        phone.isEmpty &&
        caller.isEmpty &&
        dept.isEmpty &&
        equip.isEmpty &&
        header.selectedCaller == null &&
        header.selectedEquipment == null;

    if (allEmpty) return '';

    if (phone.isEmpty) return 'Πληροφορίες';

    return 'Νέα Κλήση';
  }
}
