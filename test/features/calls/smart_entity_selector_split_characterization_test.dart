// Τεστ χαρακτηρισμού πριν τη διάσπαση του smart_entity_selector_provider.dart.
//
//   flutter test test/features/calls/smart_entity_selector_split_characterization_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../test_setup.dart';

UserModel _u({
  required int id,
  required String first,
  required String last,
  String? phone,
  int? departmentId,
}) {
  return UserModel(
    id: id,
    firstName: first,
    lastName: last,
    phones: phone != null && phone.isNotEmpty ? [phone] : const [],
    departmentId: departmentId,
  );
}

EquipmentModel _e({required int id, required String code}) {
  return EquipmentModel(id: id, code: code, type: 'PC');
}

Future<ProviderContainer> _containerWithCatalog({
  required List<UserModel> users,
  required List<EquipmentModel> equipment,
  required List<DepartmentModel> departments,
  Map<int, List<int>> userToEquipmentIds = const {},
}) async {
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: users,
    equipment: equipment,
    departmentRows: departments,
    userToEquipmentIds: userToEquipmentIds.isEmpty ? null : userToEquipmentIds,
  );
  final container = ProviderContainer(
    overrides: [
      lookupServiceProvider.overrideWith(
        (ref) async => LookupLoadResult(service: svc),
      ),
    ],
  );
  await container.read(lookupServiceProvider.future);
  return container;
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('SmartEntitySelector split characterization', () {
    test('performPhoneLookup: γνωστό τηλέφωνο επιλέγει καλούντα', () async {
      final container = await _containerWithCatalog(
        users: [
          _u(
            id: 1,
            first: 'Γνωστός',
            last: 'Καλών',
            phone: '2345',
            departmentId: 10,
          ),
        ],
        equipment: [_e(id: 100, code: 'PC-1')],
        departments: [DepartmentModel(id: 10, name: 'IT')],
        userToEquipmentIds: {1: [100]},
      );
      addTearDown(container.dispose);

      final n = container.read(callSmartEntityProvider.notifier);
      n.updatePhone('2345');
      n.performPhoneLookup('2345');

      final s = container.read(callSmartEntityProvider);
      expect(s.selectedCaller?.id, 1);
      expect(s.callerNoMatch, isFalse);
      expect(s.departmentText, 'IT');
    });

    test('performPhoneLookup: άγνωστο τηλέφωνο → callerNoMatch', () async {
      final container = await _containerWithCatalog(
        users: [],
        equipment: [],
        departments: [],
      );
      addTearDown(container.dispose);

      final n = container.read(callSmartEntityProvider.notifier);
      n.updatePhone('999');
      n.performPhoneLookup('999');

      final s = container.read(callSmartEntityProvider);
      expect(s.selectedCaller, isNull);
      expect(s.callerNoMatch, isTrue);
    });

    test(
      '_recomputeConflicts: ασυμφωνία εξοπλισμού με καλούντα/τμήμα',
      () async {
        final container = await _containerWithCatalog(
          users: [
            _u(
              id: 521,
              first: 'Ελένη',
              last: 'Α',
              phone: '52111',
              departmentId: 101,
            ),
            _u(
              id: 522,
              first: 'Ζήσης',
              last: 'Β',
              phone: '52222',
              departmentId: 102,
            ),
          ],
          equipment: [
            _e(id: 921, code: 'XF-DEV-01'),
            _e(id: 922, code: 'XF-SALES-01'),
          ],
          departments: [
            DepartmentModel(id: 101, name: 'R&D'),
            DepartmentModel(id: 102, name: 'Sales'),
          ],
          userToEquipmentIds: {521: [921], 522: [922]},
        );
        addTearDown(container.dispose);

        final n = container.read(callSmartEntityProvider.notifier);
        n.updatePhone('52111');
        n.performPhoneLookup('52111');
        n.performEquipmentLookupByCode('XF-SALES-01');

        final s = container.read(callSmartEntityProvider);
        expect(s.selectedCaller?.id, 521);
        expect(s.departmentText, 'R&D');
        expect(s.selectedEquipment?.code, 'XF-SALES-01');
        expect(
          s.conflictSeverityFor(SelectorField.caller),
          ConflictSeverity.mismatch,
        );
        expect(
          s.conflictSeverityFor(SelectorField.department),
          ConflictSeverity.mismatch,
        );
      },
    );

    test('associateCurrentIfNeeded: ορφανός καλούντας δημιουργεί χρήστη', () async {
      final container = await _containerWithCatalog(
        users: [],
        equipment: [],
        departments: [DepartmentModel(id: 1, name: 'Τμήμα Δοκιμής')],
      );
      addTearDown(container.dispose);

      final n = container.read(callSmartEntityProvider.notifier);
      n.updateCallerDisplayText('Ορφανός Καλών');
      n.checkContent(callerText: 'Ορφανός Καλών');
      n.updatePhone('5551');
      n.checkContent(phoneText: '5551');

      expect(
        container.read(callSmartEntityProvider).needsNewCallerCreation,
        isTrue,
      );

      final message = await n.associateCurrentIfNeeded();
      expect(message, isNotNull);
      expect(message!.contains('Σφάλμα'), isFalse);
      expect(container.read(callSmartEntityProvider).selectedCaller?.id, isNotNull);
    });

    test('quickAddOrphanToDepartment: κοινόχρηστο τηλέφωνο σε τμήμα', () async {
      final container = await _containerWithCatalog(
        users: [],
        equipment: [],
        departments: [],
      );
      addTearDown(container.dispose);

      const orphanPhone = '8882';
      const deptName = 'Τμήμα Orphan Split';

      final n = container.read(callSmartEntityProvider.notifier);
      n.updatePhone(orphanPhone);
      n.checkContent(phoneText: orphanPhone);
      n.updateDepartmentText(deptName);
      n.checkContent(departmentText: deptName);

      expect(
        container.read(callSmartEntityProvider).needsOrphanDepartmentQuickAdd,
        isTrue,
      );

      final result = await n.quickAddOrphanToDepartment(
        forceSharedOnConflict: true,
      );
      expect(result, isNotNull);
      expect(result!.requiresConfirmation, isFalse);
      expect(result.successMessage, isNotNull);
      expect(
        container.read(callSmartEntityProvider).departmentText,
        deptName,
      );
    });
  });
}
