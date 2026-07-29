// Το μοναδικό τηλέφωνο κερδίζει, και το κλειδωμένο τμήμα δεν μπλοκάρει
// τον κάτοχο που ανήκει σε αυτό.
//
// Συμβόλαια που φυλάει το αρχείο:
//   1. Ακριβώς ένα υποψήφιο τηλέφωνο σε κενό πεδίο = απόφαση (μπαίνει στο
//      πεδίο)· δύο και πάνω = λίστα υποψηφίων.
//   2. Ο φραγμός του κλειδωμένου τμήματος κρίνει τη ΣΧΕΣΗ (είναι ο κάτοχος
//      εκτός του τμήματος;) και όχι την ύπαρξη κλειδώματος.
//
//   flutter test test/features/calls/smart_entity_single_phone_autofill_test.dart

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

// Τμήμα με ΔΥΟ αριθμούς — ο κάτοχος όμως έχει έναν (σενάριο «Βιοχημικό»).
const _kBiochemId = 1;
const _kBiochemName = 'Βιοχημικό';
const _kEleniId = 20;
const _kEleniPhone = '2601';
const _kNikosId = 21;
const _kNikosPhone = '2602';
const _kEleniEquipmentCode = '4501';

// Τμήμα εκτός του κλειδωμένου — ο κάτοχός του δεν επιτρέπεται να γεμίσει.
const _kSurgeryId = 2;
const _kSurgeryName = 'Χειρουργείο';
const _kGiorgosId = 22;
const _kGiorgosPhone = '2777';
const _kGiorgosEquipmentCode = '4502';

// Τμήμα με ΕΝΑΝ κοινόχρηστο αριθμό, εξοπλισμός χωρίς κάτοχο (σενάριο 3974→2554).
const _kRadiologyId = 3;
const _kRadiologyName = 'Ακτινολογικό';
const _kRadiologyPhone = '2554';
const _kOrphanEquipmentCode = '3974';

// Τμήμα με ΔΥΟ κοινόχρηστους αριθμούς — φρουρός μη-παλινδρόμησης.
const _kMicroId = 4;
const _kMicroName = 'Μικροβιολογικό';
const _kMicroPhoneA = '2560';
const _kMicroPhoneB = '2561';
const _kMicroEquipmentCode = '3676';

UserModel _user({
  required int id,
  required String first,
  required String last,
  required String phone,
  required int departmentId,
}) {
  return UserModel(
    id: id,
    firstName: first,
    lastName: last,
    phones: PhoneListParser.splitPhones(phone),
    departmentId: departmentId,
  );
}

Future<ProviderContainer> _container() async {
  final equipment = [
    EquipmentModel(
      id: 4501,
      code: _kEleniEquipmentCode,
      type: 'PC',
      departmentId: _kBiochemId,
    ),
    EquipmentModel(
      id: 4502,
      code: _kGiorgosEquipmentCode,
      type: 'PC',
      departmentId: _kSurgeryId,
    ),
    EquipmentModel(
      id: 3974,
      code: _kOrphanEquipmentCode,
      type: 'Εκτυπωτής',
      departmentId: _kRadiologyId,
    ),
    EquipmentModel(
      id: 3676,
      code: _kMicroEquipmentCode,
      type: 'Εκτυπωτής',
      departmentId: _kMicroId,
    ),
  ];

  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: [
      _user(
        id: _kEleniId,
        first: 'Ελένη',
        last: 'Παπαδάκη',
        phone: _kEleniPhone,
        departmentId: _kBiochemId,
      ),
      _user(
        id: _kNikosId,
        first: 'Νίκος',
        last: 'Βλάχος',
        phone: _kNikosPhone,
        departmentId: _kBiochemId,
      ),
      _user(
        id: _kGiorgosId,
        first: 'Γιώργος',
        last: 'Δήμου',
        phone: _kGiorgosPhone,
        departmentId: _kSurgeryId,
      ),
    ],
    equipment: equipment,
    departmentRows: [
      DepartmentModel(id: _kBiochemId, name: _kBiochemName),
      DepartmentModel(id: _kSurgeryId, name: _kSurgeryName),
      DepartmentModel(id: _kRadiologyId, name: _kRadiologyName),
      DepartmentModel(id: _kMicroId, name: _kMicroName),
    ],
    userToEquipmentIds: {
      _kEleniId: [4501],
      _kGiorgosId: [4502],
    },
    departmentDirectPhones: {
      _kRadiologyId: [_kRadiologyPhone],
      _kMicroId: [_kMicroPhoneA, _kMicroPhoneB],
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

/// Σενάριο πεδίου «Βιοχημικό»: το τηλέφωνο είναι **κοινόχρηστο του τμήματος**
/// (κανένας προσωπικός κάτοχος), το τμήμα έχει **έναν** υπάλληλο, και ο
/// εξοπλισμός κρέμεται από τον υπάλληλο — όχι από το τμήμα.
const _kBiochemSharedPhone = '2519';
const _kGeorgiaId = 63;
const _kGeorgiaEquipmentCode = '3679';

Future<ProviderContainer> _containerSharedDepartmentPhone({
  required bool secondEmployee,
}) async {
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: [
      UserModel(
        id: _kGeorgiaId,
        firstName: 'Γεωργία',
        lastName: 'Νέζη',
        departmentId: _kBiochemId,
      ),
      if (secondEmployee)
        UserModel(
          id: 64,
          firstName: 'Δεύτερος',
          lastName: 'Συνάδελφος',
          departmentId: _kBiochemId,
        ),
    ],
    equipment: [EquipmentModel(id: 67, code: _kGeorgiaEquipmentCode)],
    departmentRows: [DepartmentModel(id: _kBiochemId, name: _kBiochemName)],
    userToEquipmentIds: {
      _kGeorgiaId: [67],
    },
    departmentDirectPhones: {
      _kBiochemId: [_kBiochemSharedPhone],
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

/// Η στενότερη πηγή κερδίζει: κάτοχος εξοπλισμού με ΔΥΟ τηλέφωνα, μέσα σε
/// τμήμα που συνολικά έχει τέσσερα (τα δύο ανήκουν σε συναδέλφους του).
const _kOwnerWithTwoPhonesId = 30;
const _kOwnerPhoneA = '2101';
const _kOwnerPhoneB = '2102';
const _kColleaguePhoneA = '2103';
const _kColleaguePhoneB = '2104';
const _kTwoPhoneOwnerEquipment = '5000';

Future<ProviderContainer> _containerOwnerWithTwoPhones() async {
  const deptId = 40;
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: [
      UserModel(
        id: _kOwnerWithTwoPhonesId,
        firstName: 'Μαρία',
        lastName: 'Κατόχου',
        phones: PhoneListParser.splitPhones('$_kOwnerPhoneA, $_kOwnerPhoneB'),
        departmentId: deptId,
      ),
      UserModel(
        id: 31,
        firstName: 'Νίκος',
        lastName: 'Συνάδελφος',
        phones: PhoneListParser.splitPhones(_kColleaguePhoneA),
        departmentId: deptId,
      ),
      UserModel(
        id: 32,
        firstName: 'Ελένη',
        lastName: 'Συναδέλφισσα',
        phones: PhoneListParser.splitPhones(_kColleaguePhoneB),
        departmentId: deptId,
      ),
    ],
    equipment: [
      EquipmentModel(
        id: 50,
        code: _kTwoPhoneOwnerEquipment,
        type: 'PC',
        departmentId: deptId,
      ),
    ],
    departmentRows: [DepartmentModel(id: deptId, name: 'Ακτινολογικό')],
    userToEquipmentIds: {
      _kOwnerWithTwoPhonesId: [50],
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
  group('Η στενότερη πηγή υποψηφίων κερδίζει', () {
    test(
      'κάτοχος με 2 τηλέφωνα σε τμήμα με 4 → μόνο τα δικά του στη λίστα',
      () async {
        final container = await _containerOwnerWithTwoPhones();
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);

        n.performEquipmentLookupByCode(_kTwoPhoneOwnerEquipment);
        final s = container.read(callSmartEntityProvider);

        expect(
          s.selectedCaller?.id,
          _kOwnerWithTwoPhonesId,
          reason: greekExpectMsg('Ο κάτοχος του εξοπλισμού συμπληρώνεται'),
        );
        expect(
          s.phoneCandidates.toSet(),
          {_kOwnerPhoneA, _kOwnerPhoneB},
          reason: greekExpectMsg(
            'Οι υποψήφιοι αριθμοί είναι ΜΟΝΟ του κατόχου — η λίστα του τμήματος '
            'θα περιείχε αριθμούς άλλων ανθρώπων και θα οδηγούσε σε λάθος επιλογή',
          ),
        );
        expect(s.isPhoneAmbiguous, isTrue);
      },
    );

    test(
      'εξοπλισμός χωρίς κάτοχο → η λίστα του τμήματος μπαίνει κανονικά',
      () async {
        final container = await _containerOwnerWithTwoPhones();
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);

        // Χωρίς προηγούμενη λίστα δεν υπάρχει «στενότερη πηγή» να προστατευτεί:
        // η επαναφορά υποψηφίων τμήματος πρέπει να εξακολουθεί να δουλεύει.
        n.selectDepartment(DepartmentModel(id: 40, name: 'Ακτινολογικό'));
        final s = container.read(callSmartEntityProvider);

        expect(s.phoneCandidates.toSet(), {
          _kOwnerPhoneA,
          _kOwnerPhoneB,
          _kColleaguePhoneA,
          _kColleaguePhoneB,
        });
      },
    );
  });

  group('Κοινόχρηστο τηλέφωνο τμήματος — ο μοναδικός υπάλληλος κερδίζει', () {
    test(
      'τμήμα με ΕΝΑΝ υπάλληλο → γεμίζουν καλών, τμήμα και εξοπλισμός',
      () async {
        final container = await _containerSharedDepartmentPhone(
          secondEmployee: false,
        );
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);

        n.updatePhone(_kBiochemSharedPhone);
        n.performPhoneLookup(_kBiochemSharedPhone);
        final s = container.read(callSmartEntityProvider);

        expect(
          s.selectedDepartmentId,
          _kBiochemId,
          reason: greekExpectMsg('Το κοινόχρηστο τηλέφωνο δίνει το τμήμα'),
        );
        expect(
          s.selectedCaller?.id,
          _kGeorgiaId,
          reason: greekExpectMsg(
            'Ένας μόνο υπάλληλος στο τμήμα = απόφαση, όχι λίστα προς επιλογή',
          ),
        );
        expect(s.callerDisplayText.trim(), isNotEmpty);
        expect(
          s.callerNoMatch,
          isFalse,
          reason: greekExpectMsg(
            'Δεν λέμε «Καμία αντιστοιχία» αφού βρήκαμε τον καλούντα',
          ),
        );
        expect(
          s.equipmentText,
          _kGeorgiaEquipmentCode,
          reason: greekExpectMsg('Ο μοναδικός εξοπλισμός του τμήματος γεμίζει'),
        );
      },
    );

    test('τμήμα με ΔΥΟ υπαλλήλους → ο καλών μένει κενός', () async {
      final container = await _containerSharedDepartmentPhone(
        secondEmployee: true,
      );
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.updatePhone(_kBiochemSharedPhone);
      n.performPhoneLookup(_kBiochemSharedPhone);
      final s = container.read(callSmartEntityProvider);

      expect(s.selectedDepartmentId, _kBiochemId);
      expect(
        s.selectedCaller,
        isNull,
        reason: greekExpectMsg(
          'Το κοινόχρηστο τηλέφωνο δεν λέει ποιος από τους δύο καλεί — '
          'δεν μαντεύουμε',
        ),
      );
    });
  });

  group('Κλειδωμένο τμήμα — ο φραγμός κρίνει τη σχέση', () {
    test(
      'κάτοχος ΜΕΣΑ στο κλειδωμένο τμήμα → γεμίζει και ο καλών και το τηλέφωνο',
      () async {
        final container = await _container();
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);

        n.updateDepartmentText(_kBiochemName);
        expect(
          container.read(callSmartEntityProvider).selectedDepartmentId,
          _kBiochemId,
          reason: greekExpectMsg('Προϋπόθεση: το τμήμα είναι κλειδωμένο'),
        );

        n.performEquipmentLookupByCode(_kEleniEquipmentCode);
        final s = container.read(callSmartEntityProvider);

        expect(
          s.selectedCaller?.id,
          _kEleniId,
          reason: greekExpectMsg('Ο κάτοχος του εξοπλισμού πρέπει να γεμίζει'),
        );
        expect(
          s.selectedPhone,
          _kEleniPhone,
          reason: greekExpectMsg(
            'Το τηλέφωνο του κατόχου είναι έγκυρο όταν ανήκει στο κλειδωμένο '
            'τμήμα — δεν μπλοκάρεται από το κλείδωμα',
          ),
        );
        expect(s.isPhoneAmbiguous, isFalse);
        expect(s.phoneCandidates, isEmpty);
      },
    );

    test(
      'κάτοχος ΕΚΤΟΣ του κλειδωμένου τμήματος → ούτε καλών ούτε τηλέφωνο',
      () async {
        final container = await _container();
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);

        n.updateDepartmentText(_kBiochemName);
        n.performEquipmentLookupByCode(_kGiorgosEquipmentCode);
        final s = container.read(callSmartEntityProvider);

        expect(
          s.selectedCaller,
          isNull,
          reason: greekExpectMsg(
            'Κάτοχος άλλου τμήματος δεν γεμίζει τον καλούντα',
          ),
        );
        expect(
          s.selectedPhone,
          isNot(_kGiorgosPhone),
          reason: greekExpectMsg(
            'Το τηλέφωνο κατόχου εκτός του κλειδωμένου τμήματος δεν περνά',
          ),
        );
        expect(
          s.selectedDepartmentId,
          _kBiochemId,
          reason: greekExpectMsg('Το κλειδωμένο τμήμα μένει ανέγγιχτο'),
        );
      },
    );
  });

  group('Εξοπλισμός χωρίς κάτοχο — το μοναδικό τηλέφωνο κερδίζει', () {
    test('τμήμα με ΕΝΑΝ αριθμό → προσυμπληρώνεται (3974 → 2554)', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.performEquipmentLookupByCode(_kOrphanEquipmentCode);
      final s = container.read(callSmartEntityProvider);

      expect(s.selectedEquipment?.code, _kOrphanEquipmentCode);
      expect(s.selectedDepartmentId, _kRadiologyId);
      expect(
        s.selectedPhone,
        _kRadiologyPhone,
        reason: greekExpectMsg(
          'Ένα μόνο τηλέφωνο στο τμήμα = απόφαση, όχι λίστα υποψηφίων',
        ),
      );
      expect(s.phoneCandidates, isEmpty);
      expect(s.isPhoneAmbiguous, isFalse);
    });

    test('τμήμα με ΔΥΟ αριθμούς → λίστα υποψηφίων, καμία επιλογή', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.performEquipmentLookupByCode(_kMicroEquipmentCode);
      final s = container.read(callSmartEntityProvider);

      expect(s.selectedDepartmentId, _kMicroId);
      expect(
        s.selectedPhone?.trim().isEmpty ?? true,
        isTrue,
        reason: greekExpectMsg(
          'Με δύο υποψήφιους αριθμούς η επιλογή ανήκει στον χρήστη',
        ),
      );
      expect(s.phoneCandidates.toSet(), {_kMicroPhoneA, _kMicroPhoneB});
      expect(s.isPhoneAmbiguous, isTrue);
    });
  });

  group('Ρητή επιλογή τμήματος — ίδιο συμβόλαιο', () {
    test('τμήμα με ΕΝΑΝ αριθμό → προσυμπληρώνεται', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.selectDepartment(
        DepartmentModel(id: _kRadiologyId, name: _kRadiologyName),
      );
      final s = container.read(callSmartEntityProvider);

      expect(s.selectedDepartmentId, _kRadiologyId);
      expect(
        s.selectedPhone,
        _kRadiologyPhone,
        reason: greekExpectMsg(
          'Η επιλογή τμήματος με έναν μόνο αριθμό τον συμπληρώνει',
        ),
      );
      expect(s.phoneCandidates, isEmpty);
    });

    test('τμήμα με ΔΥΟ αριθμούς → λίστα υποψηφίων', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.selectDepartment(DepartmentModel(id: _kMicroId, name: _kMicroName));
      final s = container.read(callSmartEntityProvider);

      expect(s.phoneCandidates.toSet(), {_kMicroPhoneA, _kMicroPhoneB});
      expect(s.selectedPhone?.trim().isEmpty ?? true, isTrue);
    });

    test('γεμάτο πεδίο τηλεφώνου → δεν αντικαθίσταται ποτέ', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.updatePhone(_kNikosPhone);
      n.selectDepartment(
        DepartmentModel(id: _kRadiologyId, name: _kRadiologyName),
      );
      final s = container.read(callSmartEntityProvider);

      expect(
        s.selectedPhone,
        _kNikosPhone,
        reason: greekExpectMsg(
          'Το autofill γράφει μόνο σε κενό πεδίο (ιερός κανόνας cascade)',
        ),
      );
    });
  });
}
