// Φωτογραφία της αναζήτησης τηλεφώνου στη φόρμα κλήσης, ανά περίπτωση:
// ένας κάτοχος (με/χωρίς ήδη γραμμένο καλούντα ή τμήμα) και κοινό τηλέφωνο
// πολλών κατόχων (ίδιου/διαφορετικού τμήματος, με/χωρίς δεμένο καλούντα).
// Το τηλέφωνο τμήματος χωρίς κάτοχο φυλάγεται στο
// department_phone_caller_candidates_test.dart.
//
//   flutter test test/features/calls/phone_lookup_branches_characterization_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

const _kRadiology = 10;
const _kPathology = 20;

UserModel _u(int id, String first, String last, String phone, int deptId) {
  return UserModel(
    id: id,
    firstName: first,
    lastName: last,
    phones: [phone],
    departmentId: deptId,
  );
}

final _psarra = _u(1, 'Άννα', 'Ψαρρά', '2565', _kRadiology);
final _shiftA = _u(2, 'Βάσω', 'Αλεξίου', '2400', _kPathology);
final _shiftB = _u(3, 'Γιώτα', 'Βλάχου', '2400', _kPathology);
final _mixedA = _u(4, 'Δήμος', 'Γκίκας', '2500', _kRadiology);
final _mixedB = _u(5, 'Ελένη', 'Δούκα', '2500', _kPathology);

Future<ProviderContainer> _container() async {
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: [_psarra, _shiftA, _shiftB, _mixedA, _mixedB],
    equipment: [EquipmentModel(id: 100, code: 'PC-100', type: 'PC')],
    departmentRows: [
      DepartmentModel(id: _kRadiology, name: 'Ακτινολογικό'),
      DepartmentModel(id: _kPathology, name: 'Παθολογική'),
    ],
    userToEquipmentIds: {
      1: [100],
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

SmartEntitySelectorState _lookup(ProviderContainer c, String phone) {
  final n = c.read(callSmartEntityProvider.notifier);
  n.updatePhone(phone);
  n.performPhoneLookup(phone);
  return c.read(callSmartEntityProvider);
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Ένας κάτοχος τηλεφώνου', () {
    test(
      'άδεια φόρμα: συμπληρώνονται καλούντας, τμήμα και εξοπλισμός',
      () async {
        final c = await _container();
        addTearDown(c.dispose);

        final s = _lookup(c, '2565');

        expect(s.selectedCaller?.id, 1);
        expect(s.callerDisplayText, 'Άννα Ψαρρά');
        expect(s.departmentText, 'Ακτινολογικό');
        expect(s.selectedDepartmentId, _kRadiology);
        expect(s.selectedEquipment?.id, 100);
        expect(s.callerCandidates, isEmpty);
        expect(s.phoneCandidates, isEmpty);
        expect(s.isPhoneAmbiguous, isFalse);
        expect(s.callerNoMatch, isFalse);
      },
    );

    test(
      'γραμμένος καλούντας: μένει ανέγγιχτος, το τμήμα συμπληρώνεται',
      () async {
        final c = await _container();
        addTearDown(c.dispose);
        c
            .read(callSmartEntityProvider.notifier)
            .updateCallerDisplayText('Κάποιος');

        final s = _lookup(c, '2565');

        expect(s.callerDisplayText, 'Κάποιος');
        expect(s.selectedCaller, isNull);
        expect(s.departmentText, 'Ακτινολογικό');
        expect(s.selectedDepartmentId, _kRadiology);
        expect(s.callerCandidates, isEmpty);
        expect(s.callerNoMatch, isFalse);
      },
    );

    test(
      'γραμμένος καλούντας και τμήμα: κανένα από τα δύο δεν αλλάζει',
      () async {
        final c = await _container();
        addTearDown(c.dispose);
        final n = c.read(callSmartEntityProvider.notifier);
        n.updateCallerDisplayText('Κάποιος');
        n.updateDepartmentText('Άλλο τμήμα');

        final s = _lookup(c, '2565');

        expect(s.callerDisplayText, 'Κάποιος');
        expect(s.selectedCaller, isNull);
        expect(s.departmentText, 'Άλλο τμήμα');
        expect(s.selectedDepartmentId, isNull);
        expect(s.callerCandidates, isEmpty);
        expect(s.isPhoneAmbiguous, isFalse);
        expect(s.callerNoMatch, isFalse);
      },
    );
  });

  group('Κοινό τηλέφωνο πολλών κατόχων', () {
    test(
      'ίδιο τμήμα, χωρίς καλούντα: λίστα κατόχων και συμπλήρωση τμήματος',
      () async {
        final c = await _container();
        addTearDown(c.dispose);

        final s = _lookup(c, '2400');

        expect(s.callerCandidates.map((u) => u.id).toSet(), {2, 3});
        expect(s.selectedCaller, isNull);
        expect(s.isPhoneAmbiguous, isTrue);
        expect(s.callerNoMatch, isFalse);
        expect(s.departmentText, 'Παθολογική');
        expect(s.selectedDepartmentId, _kPathology);
      },
    );

    test('διαφορετικά τμήματα: λίστα κατόχων, το τμήμα μένει κενό', () async {
      final c = await _container();
      addTearDown(c.dispose);

      final s = _lookup(c, '2500');

      expect(s.callerCandidates.map((u) => u.id).toSet(), {4, 5});
      expect(s.isPhoneAmbiguous, isTrue);
      expect(s.departmentText, isEmpty);
      expect(s.selectedDepartmentId, isNull);
    });

    test('ο δεμένος καλούντας είναι κάτοχος: μένει, χωρίς λίστα', () async {
      final c = await _container();
      addTearDown(c.dispose);
      // Χωρίς updatePhone: η πληκτρολόγηση λύνει τον καλούντα. Η περίπτωση
      // αφορά τηλέφωνο που μπήκε αυτόματα, π.χ. μετά από επιλογή εξοπλισμού.
      final n = c.read(callSmartEntityProvider.notifier);
      n.updateSelectedCaller(_shiftB);
      n.performPhoneLookup('2400');

      final s = c.read(callSmartEntityProvider);

      expect(s.selectedCaller?.id, 3);
      expect(s.callerCandidates, isEmpty);
      expect(s.isPhoneAmbiguous, isFalse);
      expect(s.callerNoMatch, isFalse);
      expect(s.departmentText, 'Παθολογική');
      expect(s.selectedDepartmentId, _kPathology);
    });
  });
}
