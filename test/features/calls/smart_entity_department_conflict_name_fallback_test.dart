// Εφεδρικός έλεγχος ονόματος τμήματος όταν selectedDepartmentId είναι null.
//
//   flutter test test/features/calls/smart_entity_department_conflict_name_fallback_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/phone_list_parser.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _kTeiId = 10;
const _kTeiName = 'ΤΕΙ Γαστρεντερολογικό';
const _kOtherId = 20;
const _kOtherName = 'Χειρουργείο';
const _kPhone = '2545';

UserModel _teiUser() {
  return UserModel(
    id: 1,
    firstName: 'Νίκος',
    lastName: 'Τεστ',
    phones: PhoneListParser.splitPhones(_kPhone),
    departmentId: _kTeiId,
  );
}

List<DepartmentModel> _departments() => [
      DepartmentModel(id: _kTeiId, name: _kTeiName),
      DepartmentModel(id: _kOtherId, name: _kOtherName),
    ];

Future<ProviderContainer> _containerWithCatalog() async {
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: [_teiUser()],
    equipment: const [],
    departmentRows: _departments(),
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

Future<void> _loadEditCallWithDepartmentText(
  ProviderContainer container, {
  required String departmentText,
}) async {
  final notifier = container.read(callSmartEntityProvider.notifier);
  await notifier.loadFromCall(
    CallModel(
      phoneText: _kPhone,
      departmentText: departmentText,
    ),
  );
  final afterLoad = container.read(callSmartEntityProvider);
  expect(
    afterLoad.selectedDepartmentId,
    isNull,
    reason: 'loadFromCall δεν δένει selectedDepartmentId (παλιά κλήση)',
  );
  expect(afterLoad.departmentText, departmentText);
  notifier.performPhoneLookup(_kPhone);
}

void main() {
  group('σύγκρουση τμήματος — εφεδρικός έλεγχος ονόματος', () {
    test(
      'α) ίδιο όνομα τμήματος με selectedDepartmentId null → χωρίς ασυμφωνία',
      () async {
        final container = await _containerWithCatalog();
        addTearDown(container.dispose);

        await _loadEditCallWithDepartmentText(container, departmentText: _kTeiName);

        expect(
          container
              .read(callSmartEntityProvider)
              .conflictSeverityFor(SelectorField.department),
          isNull,
          reason: 'Ίδιο τμήμα ως κείμενο — όχι ψευδής ασυμφωνία',
        );
      },
    );

    test(
      'α2) ίδιο όνομα με τόνους/κεφαλαία διαφορετικά → χωρίς ασυμφωνία',
      () async {
        final container = await _containerWithCatalog();
        addTearDown(container.dispose);

        await _loadEditCallWithDepartmentText(
          container,
          departmentText: 'τει γαστρεντερολογικο',
        );

        expect(
          container
              .read(callSmartEntityProvider)
              .conflictSeverityFor(SelectorField.department),
          isNull,
          reason: 'Κανονικοποιημένη σύγκριση ονόματος',
        );
      },
    );

    test(
      'β) διαφορετικό κείμενο τμήματος με selectedDepartmentId null → ασυμφωνία',
      () async {
        final container = await _containerWithCatalog();
        addTearDown(container.dispose);

        await _loadEditCallWithDepartmentText(
          container,
          departmentText: 'Άγνωστο Τμήμα',
        );

        expect(
          container
              .read(callSmartEntityProvider)
              .conflictSeverityFor(SelectorField.department),
          ConflictSeverity.mismatch,
          reason: 'Πραγματικά διαφορετικό τμήμα — ασυμφωνία',
        );
        expect(
          container
              .read(callSmartEntityProvider)
              .conflictTooltipFor(SelectorField.department),
          contains(_kTeiName),
        );
      },
    );

    test(
      'γ) selectedDepartmentId δεμένο σε άλλο τμήμα → ασυμφωνία',
      () async {
        final container = await _containerWithCatalog();
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);

        n.selectDepartment(
          DepartmentModel(id: _kOtherId, name: _kOtherName),
        );
        expect(
          container.read(callSmartEntityProvider).selectedDepartmentId,
          _kOtherId,
        );
        n.updatePhone(_kPhone);
        n.performPhoneLookup(_kPhone);

        final s = container.read(callSmartEntityProvider);
        expect(s.selectedDepartmentId, _kOtherId);
        expect(
          s.conflictSeverityFor(SelectorField.department),
          ConflictSeverity.mismatch,
          reason: 'Δεμένο id διαφορετικού τμήματος — ασυμφωνία ακόμα κι αν υπάρχει κείμενο',
        );
      },
    );
  });
}
