// Αφετηρία το ΤΜΗΜΑ: όταν το τμήμα έχει μοναδικό υπάλληλο / μοναδικό εξοπλισμό,
// αυτά είναι απόφαση και συμπληρώνονται — όπως ήδη κάνει το τηλέφωνο.
//
// Πραγματικά σενάρια από τη βάση «Hospital 2.db»:
//   Βιοϊατρική (12) → Ελένη Πλακογιάννη (μοναδική), τηλ. 2834, ΚΑΝΕΝΑΣ εξοπλισμός
//   Βιοχημικό  (59) → Γεωργία Νέζη (μοναδική),      τηλ. 2519, εξοπλισμός 3679
// Και στα δύο το τηλέφωνο/εξοπλισμός κρέμονται από τον ΥΠΑΛΛΗΛΟ, όχι από το τμήμα.
//
//   flutter test test/features/calls/smart_entity_department_first_autofill_test.dart

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

const _kBiomedicalId = 12;
const _kBiomedicalName = 'Βιοϊατρική';
const _kEleniId = 7;
const _kEleniPhone = '2834';

const _kBiochemId = 59;
const _kBiochemName = 'Βιοχημικό';
const _kGeorgiaId = 63;
const _kGeorgiaPhone = '2519';
const _kGeorgiaEquipment = '3679';

// Φρουροί: τμήμα με δύο υπαλλήλους, και τμήμα με έναν υπάλληλο & δύο εξοπλισμούς.
const _kCrowdedId = 90;
const _kCrowdedName = 'Πολυπληθές';
const _kToolboxId = 91;
const _kToolboxName = 'Πολυεργαλειακό';
const _kToolboxUserId = 80;
const _kToolboxPhone = '2900';

Future<ProviderContainer> _container() async {
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: [
      UserModel(
        id: _kEleniId,
        firstName: 'Ελένη',
        lastName: 'Πλακογιάννη',
        phones: PhoneListParser.splitPhones(_kEleniPhone),
        departmentId: _kBiomedicalId,
      ),
      UserModel(
        id: _kGeorgiaId,
        firstName: 'Γεωργία',
        lastName: 'Νέζη',
        phones: PhoneListParser.splitPhones(_kGeorgiaPhone),
        departmentId: _kBiochemId,
      ),
      UserModel(
        id: 70,
        firstName: 'Πρώτος',
        lastName: 'Συνάδελφος',
        phones: PhoneListParser.splitPhones('2801'),
        departmentId: _kCrowdedId,
      ),
      UserModel(
        id: 71,
        firstName: 'Δεύτερος',
        lastName: 'Συνάδελφος',
        phones: PhoneListParser.splitPhones('2802'),
        departmentId: _kCrowdedId,
      ),
      UserModel(
        id: _kToolboxUserId,
        firstName: 'Μόνος',
        lastName: 'Τεχνικός',
        phones: PhoneListParser.splitPhones(_kToolboxPhone),
        departmentId: _kToolboxId,
      ),
    ],
    equipment: [
      EquipmentModel(id: 67, code: _kGeorgiaEquipment, type: 'PC'),
      EquipmentModel(id: 81, code: '4001', type: 'PC'),
      EquipmentModel(id: 82, code: '4002', type: 'Εκτυπωτής'),
    ],
    departmentRows: [
      DepartmentModel(id: _kBiomedicalId, name: _kBiomedicalName),
      DepartmentModel(id: _kBiochemId, name: _kBiochemName),
      DepartmentModel(id: _kCrowdedId, name: _kCrowdedName),
      DepartmentModel(id: _kToolboxId, name: _kToolboxName),
    ],
    userToEquipmentIds: {
      _kGeorgiaId: [67],
      _kToolboxUserId: [81, 82],
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

/// Μονοπρόσωπο τμήμα με **κοινόχρηστα** στοιχεία (δεμένα στο τμήμα, όχι στον
/// υπάλληλο) και μεικτούς συνδυασμούς — η ερώτηση του Διευθυντή Έργου.
Future<ProviderContainer> _containerShared({
  required bool personalPhone,
  required List<String> departmentPhones,
  required bool personalEquipment,
  required bool departmentEquipment,
}) async {
  const deptId = 95;
  const userId = 85;
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: [
      UserModel(
        id: userId,
        firstName: 'Κατερίνα',
        lastName: 'Ορφανουδάκη',
        phones: personalPhone
            ? PhoneListParser.splitPhones('2701')
            : const <String>[],
        departmentId: deptId,
      ),
    ],
    equipment: [
      if (personalEquipment) EquipmentModel(id: 95, code: '5001', type: 'PC'),
      if (departmentEquipment)
        EquipmentModel(
          id: 96,
          code: '5002',
          type: 'Εκτυπωτής',
          departmentId: deptId,
        ),
    ],
    departmentRows: [DepartmentModel(id: deptId, name: 'Γραμματεία Κίνησης')],
    userToEquipmentIds: {
      if (personalEquipment) userId: [95],
    },
    departmentDirectPhones: {deptId: departmentPhones},
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

SmartEntitySelectorState _selectKinisis(ProviderContainer container) {
  container
      .read(callSmartEntityProvider.notifier)
      .selectDepartment(DepartmentModel(id: 95, name: 'Γραμματεία Κίνησης'));
  return container.read(callSmartEntityProvider);
}

void main() {
  group('Μονοπρόσωπο τμήμα με ΚΟΙΝΟΧΡΗΣΤΑ στοιχεία', () {
    test(
      'κοινόχρηστο τηλέφωνο + κοινόχρηστος εξοπλισμός → όλα γεμίζουν',
      () async {
        final container = await _containerShared(
          personalPhone: false,
          departmentPhones: ['2565'],
          personalEquipment: false,
          departmentEquipment: true,
        );
        addTearDown(container.dispose);
        final s = _selectKinisis(container);

        expect(s.selectedCaller?.id, 85);
        expect(
          s.selectedPhone,
          '2565',
          reason: greekExpectMsg(
            'Το κοινόχρηστο τηλέφωνο μετράει σαν τηλέφωνο του τμήματος',
          ),
        );
        expect(
          s.equipmentText,
          '5002',
          reason: greekExpectMsg(
            'Ο κοινόχρηστος εξοπλισμός μετράει σαν εξοπλισμός του τμήματος',
          ),
        );
      },
    );

    test('μεικτό: εξοπλισμός του υπαλλήλου + κοινόχρηστο τηλέφωνο', () async {
      final container = await _containerShared(
        personalPhone: false,
        departmentPhones: ['2565'],
        personalEquipment: true,
        departmentEquipment: false,
      );
      addTearDown(container.dispose);
      final s = _selectKinisis(container);

      expect(s.selectedCaller?.id, 85);
      expect(s.selectedPhone, '2565');
      expect(
        s.equipmentText,
        '5001',
        reason: greekExpectMsg(
          'Ο προσωπικός εξοπλισμός του μοναδικού υπαλλήλου',
        ),
      );
    });

    test(
      'προσωπικό ΚΑΙ κοινόχρηστο τηλέφωνο → δύο υποψήφιοι, καμία απόφαση',
      () async {
        final container = await _containerShared(
          personalPhone: true,
          departmentPhones: ['2565'],
          personalEquipment: true,
          departmentEquipment: false,
        );
        addTearDown(container.dispose);
        final s = _selectKinisis(container);

        expect(
          s.selectedCaller?.id,
          85,
          reason: greekExpectMsg('Ο μοναδικός υπάλληλος γεμίζει κανονικά'),
        );
        expect(
          s.selectedPhone?.trim().isEmpty ?? true,
          isTrue,
          reason: greekExpectMsg(
            'Δύο αριθμοί στο τμήμα = επιλογή του τεχνικού, όχι μαντεψιά',
          ),
        );
        expect(s.phoneCandidates.toSet(), {'2701', '2565'});
      },
    );

    test(
      'προσωπικός ΚΑΙ κοινόχρηστος εξοπλισμός → δύο υποψήφιοι, καμία απόφαση',
      () async {
        final container = await _containerShared(
          personalPhone: false,
          departmentPhones: ['2565'],
          personalEquipment: true,
          departmentEquipment: true,
        );
        addTearDown(container.dispose);
        final s = _selectKinisis(container);

        expect(s.selectedCaller?.id, 85);
        expect(s.selectedPhone, '2565');
        expect(
          s.equipmentText.trim(),
          isEmpty,
          reason: greekExpectMsg('Δύο εξοπλισμοί = επιλογή του τεχνικού'),
        );
        expect(s.equipmentCandidates, hasLength(2));
      },
    );
  });

  group('Επικύρωση τμήματος — το μοναδικό στοιχείο του τμήματος κερδίζει', () {
    test('Βιοχημικό: μοναδικός υπάλληλος + μοναδικός εξοπλισμός', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.selectDepartment(DepartmentModel(id: _kBiochemId, name: _kBiochemName));
      final s = container.read(callSmartEntityProvider);

      expect(
        s.selectedPhone,
        _kGeorgiaPhone,
        reason: greekExpectMsg('Το μοναδικό τηλέφωνο του τμήματος (ήδη ΟΚ)'),
      );
      expect(
        s.selectedCaller?.id,
        _kGeorgiaId,
        reason: greekExpectMsg(
          'Ένας μόνο υπάλληλος στο τμήμα = απόφαση, όχι λίστα ενός στοιχείου',
        ),
      );
      expect(
        s.callerDisplayText.trim(),
        isNotEmpty,
        reason: greekExpectMsg('Το όνομα φαίνεται στο πεδίο, όχι μόνο στο id'),
      );
      expect(
        s.callerCandidates,
        isEmpty,
        reason: greekExpectMsg('Χωρίς λίστα αφού ο καλών αποφασίστηκε'),
      );
      expect(
        s.equipmentText,
        _kGeorgiaEquipment,
        reason: greekExpectMsg(
          'Ένας μόνο εξοπλισμός στο τμήμα = απόφαση, όχι λίστα ενός στοιχείου',
        ),
      );
      expect(s.isEquipmentAmbiguous, isFalse);
    });

    test('Βιοϊατρική: μοναδικός υπάλληλος, ΚΑΝΕΝΑΣ εξοπλισμός', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.selectDepartment(
        DepartmentModel(id: _kBiomedicalId, name: _kBiomedicalName),
      );
      final s = container.read(callSmartEntityProvider);

      expect(s.selectedPhone, _kEleniPhone);
      expect(
        s.selectedCaller?.id,
        _kEleniId,
        reason: greekExpectMsg('Ο μοναδικός υπάλληλος συμπληρώνεται'),
      );
      expect(
        s.equipmentText.trim(),
        isEmpty,
        reason: greekExpectMsg(
          'Τμήμα χωρίς εξοπλισμό αφήνει το πεδίο κενό — δεν εφευρίσκουμε τιμή',
        ),
      );
    });
  });

  group('Φρουροί — πού ΔΕΝ πρέπει να μαντεύουμε', () {
    test('τμήμα με ΔΥΟ υπαλλήλους → ο καλών μένει κενός με λίστα', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.selectDepartment(DepartmentModel(id: _kCrowdedId, name: _kCrowdedName));
      final s = container.read(callSmartEntityProvider);

      expect(
        s.selectedCaller,
        isNull,
        reason: greekExpectMsg('Με δύο υπαλλήλους δεν ξέρουμε ποιος καλεί'),
      );
      expect(s.callerCandidates, hasLength(2));
    });

    test(
      'ένας υπάλληλος αλλά ΔΥΟ εξοπλισμοί → ο καλών γεμίζει, ο εξοπλισμός όχι',
      () async {
        final container = await _container();
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);

        n.selectDepartment(
          DepartmentModel(id: _kToolboxId, name: _kToolboxName),
        );
        final s = container.read(callSmartEntityProvider);

        expect(s.selectedCaller?.id, _kToolboxUserId);
        expect(
          s.equipmentText.trim(),
          isEmpty,
          reason: greekExpectMsg(
            'Δύο εξοπλισμοί = επιλογή του χρήστη, όχι απόφαση',
          ),
        );
        expect(s.equipmentCandidates, hasLength(2));
      },
    );

    // ΣΚΟΠΙΜΗ ΣΥΜΠΕΡΙΦΟΡΑ (απόφαση Διευθυντή Έργου 28/07/2026): ο καθαρισμός
    // του τμήματος ΔΕΝ αδειάζει όσα συμπλήρωσε — ο χειριστής κρατά τα στοιχεία
    // και αλλάζει μόνο το τμήμα. Αν το τεστ γίνει κόκκινο, φταίει ο κώδικας.
    test('καθαρισμός τμήματος → τα συμπληρωμένα πεδία ΜΕΝΟΥΝ', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.selectDepartment(DepartmentModel(id: _kBiochemId, name: _kBiochemName));
      n.updateDepartmentText('');
      final s = container.read(callSmartEntityProvider);

      expect(s.departmentText.trim(), isEmpty);
      expect(s.selectedDepartmentId, isNull);
      expect(
        s.selectedCaller?.id,
        _kGeorgiaId,
        reason: greekExpectMsg('Ο καλών επιβιώνει του καθαρισμού τμήματος'),
      );
      expect(
        s.selectedPhone,
        _kGeorgiaPhone,
        reason: greekExpectMsg('Το τηλέφωνο επιβιώνει του καθαρισμού τμήματος'),
      );
      expect(
        s.equipmentText,
        _kGeorgiaEquipment,
        reason: greekExpectMsg(
          'Ο εξοπλισμός επιβιώνει του καθαρισμού τμήματος',
        ),
      );
    });

    // Το τηλέφωνο είναι η ΜΟΝΗ άγκυρα που παρασύρει τα υπόλοιπα πεδία: το
    // άδειασμά του σπάει τους δεσμούς (ταυτοποίηση καλούντα/εξοπλισμού), αλλά
    // ΔΕΝ σβήνει το ορατό κείμενο — ισχύει ο κανόνας «μη σβήνεις ό,τι φαίνεται
    // συμπληρωμένο».
    test('καθαρισμός τηλεφώνου → σπάνε οι δεσμοί, μένει το κείμενο', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.selectDepartment(DepartmentModel(id: _kBiochemId, name: _kBiochemName));
      n.updatePhone(null);
      final s = container.read(callSmartEntityProvider);

      expect(
        s.selectedCaller,
        isNull,
        reason: greekExpectMsg(
          'Το άδειασμα του τηλεφώνου ξαναχτίζει τις σχέσεις χωρίς αυτό',
        ),
      );
      expect(
        s.callerDisplayText,
        isNotEmpty,
        reason: greekExpectMsg(
          'Το ορατό όνομα δεν σβήνεται από κάτω — μόνο η ταυτοποίηση',
        ),
      );
      expect(
        s.equipmentText,
        _kGeorgiaEquipment,
        reason: greekExpectMsg(
          'Ο συμπληρωμένος εξοπλισμός προστατεύεται: ένα ορατά γεμάτο πεδίο '
          'δεν αδειάζει επειδή πειράχτηκε το τηλέφωνο',
        ),
      );
    });

    test('ήδη συμπληρωμένος καλών → δεν αντικαθίσταται ποτέ', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.updateCallerDisplayText('Κάποιος Άλλος');
      n.selectDepartment(DepartmentModel(id: _kBiochemId, name: _kBiochemName));
      final s = container.read(callSmartEntityProvider);

      expect(
        s.callerDisplayText,
        'Κάποιος Άλλος',
        reason: greekExpectMsg(
          'Το autofill γράφει μόνο σε κενό πεδίο (ιερός κανόνας cascade)',
        ),
      );
    });
  });
}
