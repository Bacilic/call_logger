// Αυτόματη συμπλήρωση τμήματος όταν πολλοί χρήστες μοιράζονται το ίδιο τμήμα.
//
//   flutter test test/features/calls/smart_entity_phone_shared_department_autofill_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/phone_list_parser.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _kPhone = '2531';
const _kDeptA = 1;
const _kDeptB = 2;
const _kDeptAName = 'Φαρμακείο';
const _kDeptBName = 'Χειρουργείο';

UserModel _u({
  required int id,
  required String first,
  required String last,
  required int? departmentId,
}) {
  return UserModel(
    id: id,
    firstName: first,
    lastName: last,
    phones: PhoneListParser.splitPhones(_kPhone),
    departmentId: departmentId,
  );
}

Future<ProviderContainer> _containerWithUsers(List<UserModel> users) async {
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: users,
    equipment: const [],
    departmentRows: [
      DepartmentModel(id: _kDeptA, name: _kDeptAName),
      DepartmentModel(id: _kDeptB, name: _kDeptBName),
    ],
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
  group('performPhoneLookup — κοινόχρηστο τμήμα σε πολλούς χρήστες', () {
    test(
      '2 χρήστες ίδιου τμήματος → τμήμα γεμίζει και οι υποψήφιοι εμφανίζονται',
      () async {
        final container = await _containerWithUsers([
          _u(id: 1, first: 'Πρωινή', last: 'Βάρδια', departmentId: _kDeptA),
          _u(id: 2, first: 'Απογευματινή', last: 'Βάρδια', departmentId: _kDeptA),
        ]);
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);
        n.updatePhone(_kPhone);
        n.performPhoneLookup(_kPhone);
        final s = container.read(callSmartEntityProvider);

        expect(s.isPhoneAmbiguous, isTrue);
        expect(s.callerCandidates, hasLength(2));
        expect(s.selectedDepartmentId, _kDeptA);
        expect(s.departmentText, _kDeptAName);
      },
    );

    test(
      'χρήστες διαφορετικών τμημάτων → το τμήμα δεν γεμίζει',
      () async {
        final container = await _containerWithUsers([
          _u(id: 1, first: 'Α', last: 'Φαρμ', departmentId: _kDeptA),
          _u(id: 2, first: 'Β', last: 'Χειρ', departmentId: _kDeptB),
        ]);
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);
        n.updatePhone(_kPhone);
        n.performPhoneLookup(_kPhone);
        final s = container.read(callSmartEntityProvider);

        expect(s.isPhoneAmbiguous, isTrue);
        expect(s.callerCandidates, hasLength(2));
        expect(s.selectedDepartmentId, isNull);
        expect(s.departmentText.trim(), isEmpty);
      },
    );

    test(
      'γεμάτο πεδίο τμήματος → δεν επικαλύπτεται ποτέ',
      () async {
        final container = await _containerWithUsers([
          _u(id: 1, first: 'Πρωινή', last: 'Βάρδια', departmentId: _kDeptA),
          _u(id: 2, first: 'Απογευματινή', last: 'Βάρδια', departmentId: _kDeptA),
        ]);
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);
        n.updateDepartmentText(_kDeptBName);
        expect(
          container.read(callSmartEntityProvider).selectedDepartmentId,
          _kDeptB,
        );
        n.updatePhone(_kPhone);
        n.performPhoneLookup(_kPhone);
        final s = container.read(callSmartEntityProvider);

        expect(s.selectedDepartmentId, _kDeptB);
        expect(s.departmentText, _kDeptBName);
        expect(s.callerCandidates, hasLength(2));
      },
    );
  });
}
