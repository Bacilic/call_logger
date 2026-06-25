import 'package:call_logger/features/calls/layout/calls_field_confirmations.dart';
import 'package:call_logger/features/calls/layout/calls_field_groups.dart';
import 'package:call_logger/features/calls/layout/calls_layout_template.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:flutter_test/flutter_test.dart';

SmartEntitySelectorState _header({
  String? phone,
  UserModel? caller,
  EquipmentModel? equipment,
  String equipmentText = '',
  String departmentText = '',
  int? departmentId,
}) {
  return SmartEntitySelectorState(
    selectedPhone: phone,
    selectedCaller: caller,
    selectedEquipment: equipment,
    equipmentText: equipmentText,
    departmentText: departmentText,
    selectedDepartmentId: departmentId,
  );
}

void main() {
  group('CallsFieldGroupsResolver', () {
    test('confirmed phone without DB record activates phone group', () {
      const confirmations = CallsFieldConfirmations(phone: true);
      final groups = CallsFieldGroupsResolver.resolve(
        _header(phone: '210'),
        confirmations,
      );
      expect(groups.isPhoneGroupActive, isTrue);
      expect(groups.template, CallsLayoutTemplate.a);
      expect(groups.isExpanded, isTrue);
    });

    test('equipment free text only → freeTextOnly tier', () {
      const confirmations = CallsFieldConfirmations(equipment: true);
      final groups = CallsFieldGroupsResolver.resolve(
        _header(equipmentText: 'PC-1'),
        confirmations,
      );
      expect(groups.equipmentTier, EquipmentGroupTier.freeTextOnly);
      expect(groups.isEquipmentGroupActive, isTrue);
    });

    test('equipment with selectedEquipment → matchedRecord', () {
      const confirmations = CallsFieldConfirmations(equipment: true);
      final groups = CallsFieldGroupsResolver.resolve(
        _header(
          equipmentText: 'PC-1',
          equipment: EquipmentModel(code: 'PC-1', id: 1),
        ),
        confirmations,
      );
      expect(groups.equipmentTier, EquipmentGroupTier.matchedRecord);
    });

    test('caller with DB id activates caller group', () {
      const confirmations = CallsFieldConfirmations(caller: true);
      final groups = CallsFieldGroupsResolver.resolve(
        _header(caller: UserModel(id: 5, firstName: 'Test')),
        confirmations,
      );
      expect(groups.isCallerGroupActive, isTrue);
    });

    test('caller display text only does not activate caller group', () {
      const confirmations = CallsFieldConfirmations(caller: true);
      final groups = CallsFieldGroupsResolver.resolve(
        SmartEntitySelectorState(callerDisplayText: 'Unknown'),
        confirmations,
      );
      expect(groups.isCallerGroupActive, isFalse);
    });

    test('department id activates map', () {
      final groups = CallsFieldGroupsResolver.resolve(
        _header(departmentId: 3),
        CallsFieldConfirmations.empty,
      );
      expect(groups.isMapActive, isTrue);
    });

    test('no active groups → compact', () {
      final groups = CallsFieldGroupsResolver.resolve(
        _header(),
        CallsFieldConfirmations.empty,
      );
      expect(groups.isCompact, isTrue);
      expect(groups.anyGroupActive, isFalse);
    });

    test('phone only → isPhoneOnlyTemplateA', () {
      const confirmations = CallsFieldConfirmations(phone: true);
      final groups = CallsFieldGroupsResolver.resolve(
        _header(phone: '123'),
        confirmations,
      );
      expect(groups.isPhoneOnlyTemplateA, isTrue);
    });

    test('phone + caller → not phone-only template A', () {
      const confirmations = CallsFieldConfirmations(phone: true, caller: true);
      final groups = CallsFieldGroupsResolver.resolve(
        _header(phone: '123', caller: UserModel(id: 1, firstName: 'A')),
        confirmations,
      );
      expect(groups.isPhoneOnlyTemplateA, isFalse);
    });

    test('phone only → expanded template A', () {
      const confirmations = CallsFieldConfirmations(phone: true);
      final groups = CallsFieldGroupsResolver.resolve(
        _header(phone: '123'),
        confirmations,
      );
      expect(groups.isExpanded, isTrue);
      expect(groups.template, CallsLayoutTemplate.a);
    });

    test('caller + equipment without phone → template B', () {
      const confirmations = CallsFieldConfirmations(
        caller: true,
        equipment: true,
      );
      final groups = CallsFieldGroupsResolver.resolve(
        _header(
          caller: UserModel(id: 1, firstName: 'A'),
          equipmentText: 'E1',
          equipment: EquipmentModel(code: 'E1', id: 2),
        ),
        confirmations,
      );
      expect(groups.template, CallsLayoutTemplate.b);
    });

    test('caller only → template C', () {
      const confirmations = CallsFieldConfirmations(caller: true);
      final groups = CallsFieldGroupsResolver.resolve(
        _header(caller: UserModel(id: 1, firstName: 'A')),
        confirmations,
      );
      expect(groups.template, CallsLayoutTemplate.c);
    });

    test('equipment only → template D', () {
      const confirmations = CallsFieldConfirmations(equipment: true);
      final groups = CallsFieldGroupsResolver.resolve(
        _header(
          equipmentText: 'E1',
          equipment: EquipmentModel(code: 'E1', id: 2),
        ),
        confirmations,
      );
      expect(groups.template, CallsLayoutTemplate.d);
    });
  });

  group('CallsScreenTitleResolver', () {
    test('empty when all fields empty', () {
      expect(CallsScreenTitleResolver.resolve(_header()), '');
    });

    test('Πληροφορίες when phone empty but department filled', () {
      expect(
        CallsScreenTitleResolver.resolve(_header(departmentText: 'IT')),
        'Πληροφορίες',
      );
    });

    test('Νέα Κλήση when phone has value', () {
      expect(
        CallsScreenTitleResolver.resolve(_header(phone: '210')),
        'Νέα Κλήση',
      );
    });
  });
}
