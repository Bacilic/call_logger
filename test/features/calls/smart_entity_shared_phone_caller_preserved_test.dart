// Διατήρηση δεμένου καλούντα σε κοινόχρηστο τηλέφωνο βάρδιας (πολλοί κάτοχοι).
//
//   flutter test test/features/calls/smart_entity_shared_phone_caller_preserved_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/phone_list_parser.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

const _kPhone = '2531';
const _kDeptA = 1;
const _kDeptAName = 'Φαρμακείο';
const _kEqCode = 'EQ-2531';
const _kCallerNotFound = 'Ο καλούντας δεν βρέθηκε στη βάση';

UserModel _owner({
  required int id,
  required String first,
  required String last,
}) {
  return UserModel(
    id: id,
    firstName: first,
    lastName: last,
    phones: PhoneListParser.splitPhones(_kPhone),
    departmentId: _kDeptA,
  );
}

bool _hasCallerNotFoundWarning(SmartEntitySelectorState s) {
  return s
      .conflictsFor(SelectorField.caller)
      .any((c) => c.message == _kCallerNotFound);
}

Future<ProviderContainer> _containerWithSharedPhoneOwners({
  Map<int, List<int>>? userToEquipmentIds,
  List<EquipmentModel> equipment = const [],
}) async {
  final owners = [
    _owner(id: 10, first: 'Πρωινή', last: 'Βάρδια'),
    _owner(id: 20, first: 'Απογευματινή', last: 'Βάρδια'),
  ];
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: owners,
    equipment: equipment,
    departmentRows: [
      DepartmentModel(id: _kDeptA, name: _kDeptAName),
    ],
    userToEquipmentIds: userToEquipmentIds,
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
  group('κοινόχρηστο τηλέφωνο · διατήρηση δεμένου καλούντα', () {
    test(
      'α) προ-επιλεγμένος κάτοχος + lookup τηλεφώνου → διατήρηση, χωρίς ασάφεια/προειδοποίηση',
      () async {
        final container = await _containerWithSharedPhoneOwners();
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);
        final owner = LookupService.instance.findUsersByPhone(_kPhone).first;

        n.setCaller(owner);
        expect(
          container.read(callSmartEntityProvider).selectedCaller?.id,
          owner.id,
        );

        // setPhone (όχι updatePhone): όπως όταν το τηλέφωνο έχει ήδη οριστεί
        // από autofill εξοπλισμού και μετά τρέχει μόνο το lookup.
        n.setPhone(_kPhone);
        n.performPhoneLookup(_kPhone);
        final s = container.read(callSmartEntityProvider);

        expect(
          s.selectedCaller?.id,
          owner.id,
          reason: greekExpectMsg(
            'Ο ήδη δεμένος κάτοχος πρέπει να διατηρείται μετά το lookup τηλεφώνου',
          ),
        );
        expect(
          s.isPhoneAmbiguous,
          isFalse,
          reason: greekExpectMsg(
            'Δεν πρέπει να εμφανίζεται ασάφεια τηλεφώνου όταν ο δεμένος είναι κάτοχος',
          ),
        );
        expect(s.callerCandidates, isEmpty);
        expect(
          _hasCallerNotFoundWarning(s),
          isFalse,
          reason: greekExpectMsg(
            'Δεν πρέπει να εμφανίζεται «Ο καλούντας δεν βρέθηκε στη βάση»',
          ),
        );
      },
    );

    test(
      'β) τμήμα → εξοπλισμός (δεσμός καλούντα) → lookup τηλεφώνου → καμία προειδοποίηση',
      () async {
        final eq = EquipmentModel(id: 100, code: _kEqCode, type: 'PC');
        final container = await _containerWithSharedPhoneOwners(
          equipment: [eq],
          userToEquipmentIds: {
            10: [100],
          },
        );
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);

        n.updateDepartmentText(_kDeptAName);
        n.performEquipmentLookupByCode(_kEqCode);
        final afterEq = container.read(callSmartEntityProvider);
        expect(
          afterEq.selectedCaller?.id,
          10,
          reason: greekExpectMsg(
            'Ο εξοπλισμός πρέπει να δεσμεύει τον μοναδικό κάτοχο',
          ),
        );
        expect(afterEq.selectedEquipment?.id, 100);

        n.setPhone(_kPhone);
        n.performPhoneLookup(_kPhone);
        final s = container.read(callSmartEntityProvider);

        expect(s.selectedCaller?.id, 10);
        expect(s.selectedEquipment?.id, 100);
        expect(s.isPhoneAmbiguous, isFalse);
        expect(
          _hasCallerNotFoundWarning(s),
          isFalse,
          reason: greekExpectMsg(
            'Μετά εξοπλισμό + κοινόχρηστο τηλέφωνο δεν πρέπει να υπάρχει προειδοποίηση',
          ),
        );
      },
    );

    test(
      'γ) κενή φόρμα + lookup κοινόχρηστου → υποψήφιοι και isPhoneAmbiguous',
      () async {
        final container = await _containerWithSharedPhoneOwners();
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);

        n.updatePhone(_kPhone);
        n.performPhoneLookup(_kPhone);
        final s = container.read(callSmartEntityProvider);

        expect(s.isPhoneAmbiguous, isTrue);
        expect(s.callerCandidates, hasLength(2));
        expect(s.selectedCaller, isNull);
      },
    );

    test(
      'δ) προ-επιλεγμένος μη-κάτοχος → καθαρισμός επιλογής όπως σήμερα',
      () async {
        final outsider = UserModel(
          id: 99,
          firstName: 'Άλλος',
          lastName: 'Χρήστης',
          phones: PhoneListParser.splitPhones('2999'),
          departmentId: _kDeptA,
        );
        final owners = [
          _owner(id: 10, first: 'Πρωινή', last: 'Βάρδια'),
          _owner(id: 20, first: 'Απογευματινή', last: 'Βάρδια'),
        ];
        final svc = LookupService.instance;
        svc.resetForReload();
        svc.injectInMemoryCatalogForTests(
          users: [...owners, outsider],
          equipment: const [],
          departmentRows: [
            DepartmentModel(id: _kDeptA, name: _kDeptAName),
          ],
        );
        final container = ProviderContainer(
          overrides: [
            lookupServiceProvider.overrideWith(
              (ref) async => LookupLoadResult(service: svc),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(lookupServiceProvider.future);

        final n = container.read(callSmartEntityProvider.notifier);
        n.setCaller(outsider);
        expect(
          container.read(callSmartEntityProvider).selectedCaller?.id,
          99,
        );

        n.setPhone(_kPhone);
        n.performPhoneLookup(_kPhone);
        final s = container.read(callSmartEntityProvider);

        expect(s.selectedCaller, isNull);
        expect(s.isPhoneAmbiguous, isTrue);
        expect(s.callerCandidates, hasLength(2));
      },
    );
  });
}
