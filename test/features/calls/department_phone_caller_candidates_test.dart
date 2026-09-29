// Τηλέφωνο τμήματος (χωρίς προσωπικό κάτοχο): οι υπάλληλοι του τμήματος
// γίνονται υποψήφιοι καλούντες — ένας = συμπλήρωση, δύο και πάνω = λίστα.
//
//   flutter test test/features/calls/department_phone_caller_candidates_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

const _kDeptId = 30;
const _kDeptName = 'Χρηματικό';
const _kDeptPhone = '2858';

UserModel _u(int id, String first, String last, {String? phone}) {
  return UserModel(
    id: id,
    firstName: first,
    lastName: last,
    phones: phone == null ? const [] : [phone],
    departmentId: _kDeptId,
  );
}

Future<ProviderContainer> _containerWithDepartmentUsers(
  List<UserModel> users,
) async {
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: users,
    equipment: const [],
    departmentRows: [DepartmentModel(id: _kDeptId, name: _kDeptName)],
    departmentDirectPhones: {
      _kDeptId: [_kDeptPhone],
    },
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

  group('Τηλέφωνο τμήματος → υποψήφιοι καλούντες', () {
    test(
      'δύο και πάνω υπάλληλοι: γίνονται λίστα, όχι «Καμία αντιστοιχία»',
      () async {
        final container = await _containerWithDepartmentUsers([
          _u(1, 'Σούλα', 'Σουλιώτη'),
          _u(2, 'Τίνα', 'Γεωργάκη', phone: '2975'),
          _u(3, 'Μαρία', 'Κυζιρίδου'),
        ]);
        addTearDown(container.dispose);

        final n = container.read(callSmartEntityProvider.notifier);
        n.updatePhone(_kDeptPhone);
        n.performPhoneLookup(_kDeptPhone);

        final s = container.read(callSmartEntityProvider);
        expect(s.selectedDepartmentId, _kDeptId);
        expect(s.departmentText, _kDeptName);
        expect(s.callerCandidates.map((u) => u.id).toSet(), {
          1,
          2,
          3,
        }, reason: 'όλοι οι υπάλληλοι του τμήματος πρέπει να προσφέρονται');
        expect(s.callerNoMatch, isFalse);
        expect(
          s.selectedCaller,
          isNull,
          reason: 'με πολλούς υποψηφίους δεν διαλέγει κανέναν μόνη της',
        );
        expect(s.callerDisplayText, isEmpty);
      },
    );

    test('ένας υπάλληλος: συμπληρώνεται όπως πριν', () async {
      final container = await _containerWithDepartmentUsers([
        _u(1, 'Σούλα', 'Σουλιώτη'),
      ]);
      addTearDown(container.dispose);

      final n = container.read(callSmartEntityProvider.notifier);
      n.updatePhone(_kDeptPhone);
      n.performPhoneLookup(_kDeptPhone);

      final s = container.read(callSmartEntityProvider);
      expect(s.selectedCaller?.id, 1);
      expect(s.callerNoMatch, isFalse);
    });

    test('κανένας υπάλληλος: μένει «Καμία αντιστοιχία»', () async {
      final container = await _containerWithDepartmentUsers(const []);
      addTearDown(container.dispose);

      final n = container.read(callSmartEntityProvider.notifier);
      n.updatePhone(_kDeptPhone);
      n.performPhoneLookup(_kDeptPhone);

      final s = container.read(callSmartEntityProvider);
      expect(s.selectedDepartmentId, _kDeptId);
      expect(s.callerCandidates, isEmpty);
      expect(s.callerNoMatch, isTrue);
    });

    test('όνομα που έγραψε ο χρήστης δεν αγγίζεται', () async {
      final container = await _containerWithDepartmentUsers([
        _u(1, 'Σούλα', 'Σουλιώτη'),
        _u(2, 'Τίνα', 'Γεωργάκη'),
      ]);
      addTearDown(container.dispose);

      final n = container.read(callSmartEntityProvider.notifier);
      n.updateCallerDisplayText('Παπαδόπουλος');
      n.updatePhone(_kDeptPhone);
      n.performPhoneLookup(_kDeptPhone);

      final s = container.read(callSmartEntityProvider);
      expect(s.callerDisplayText, 'Παπαδόπουλος');
      expect(s.selectedCaller, isNull);
    });
  });
}
