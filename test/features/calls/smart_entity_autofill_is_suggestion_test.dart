// Η αυτόματη συμπλήρωση είναι ΥΠΟΔΕΙΞΗ, όχι κλείδωμα.
//
// Συμβόλαιο: ό,τι συμπληρώθηκε αυτόματα, ο χρήστης μπορεί να το σβήσει και να
// γράψει άλλο — η εφαρμογή σημαδεύει την παρατυπία με ✱, δεν την εμποδίζει.
// Το άδειασμα ενός πεδίου είναι ρητή πρόθεση και ΔΕΝ αναιρείται από μόνο του·
// αναιρείται μόνο αν ο χρήστης επικυρώσει ξανά κάποια οντότητα.
//
// Σενάριο πεδίου: η Σοφία της Αιμοδοσίας τηλεφωνεί ΑΠΟ ΤΟ ΧΕΙΡΟΥΡΓΕΙΟ για τον
// υπολογιστή του Χειρουργείου. Ο τεχνικός πρέπει να μπορεί να το καταγράψει.
//
//   flutter test test/features/calls/smart_entity_autofill_is_suggestion_test.dart

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

// Πραγματικά δεδομένα από τη βάση «Hospital 2.db».
const _kAimodosiaId = 46;
const _kAimodosiaName = 'Αιμοδοσία';
const _kSofiaId = 40;
const _kSofiaName = 'Σοφία Σπυροπούλου';
const _kSofiaPhone = '2511';

const _kOrthopedikoId = 45;
const _kOrthopedikoName = 'ΤΕΙ Ορθοπεδικό';
const _kOrthopedikoPhone = '2580';
const _kOrthopedikoEquipment = '3856';

const _kCheirourgeioId = 70;
const _kCheirourgeioName = 'Χειρουργείο';
const _kCheirourgeioPhone = '2999';

Future<ProviderContainer> _container() async {
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: [
      UserModel(
        id: _kSofiaId,
        firstName: 'Σοφία',
        lastName: 'Σπυροπούλου',
        phones: PhoneListParser.splitPhones(_kSofiaPhone),
        departmentId: _kAimodosiaId,
      ),
    ],
    equipment: [
      // Το ΤΕΙ Ορθοπεδικό δεν έχει υπαλλήλους: ο εξοπλισμός κρέμεται από το τμήμα.
      EquipmentModel(
        id: 91,
        code: _kOrthopedikoEquipment,
        departmentId: _kOrthopedikoId,
      ),
    ],
    departmentRows: [
      DepartmentModel(id: _kAimodosiaId, name: _kAimodosiaName),
      DepartmentModel(id: _kOrthopedikoId, name: _kOrthopedikoName),
      DepartmentModel(id: _kCheirourgeioId, name: _kCheirourgeioName),
    ],
    departmentDirectPhones: {
      _kAimodosiaId: [_kSofiaPhone],
      _kOrthopedikoId: [_kOrthopedikoPhone],
      _kCheirourgeioId: [_kCheirourgeioPhone],
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

void _commitSofia(SmartEntitySelectorNotifier n) {
  n.updateCallerDisplayText(_kSofiaName);
  n.performCallerLookup(_kSofiaName);
}

/// Η Αιμοδοσία με **δύο** υπαλλήλους — για τη λίστα υποψηφίων καλούντα.
Future<ProviderContainer> _containerTwoEmployees() async {
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: [
      UserModel(
        id: _kSofiaId,
        firstName: 'Σοφία',
        lastName: 'Σπυροπούλου',
        phones: PhoneListParser.splitPhones(_kSofiaPhone),
        departmentId: _kAimodosiaId,
      ),
      UserModel(
        id: 41,
        firstName: 'Χριστίνα',
        lastName: 'Παπαδοπούλου',
        phones: PhoneListParser.splitPhones(_kSofiaPhone),
        departmentId: _kAimodosiaId,
      ),
    ],
    equipment: const [],
    departmentRows: [
      DepartmentModel(id: _kAimodosiaId, name: _kAimodosiaName),
    ],
    departmentDirectPhones: {
      _kAimodosiaId: [_kSofiaPhone],
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

/// Κόσμος «Χριστίνα Παππά»: υπάλληλος ΧΩΡΙΣ δικό της τηλέφωνο ή εξοπλισμό,
/// δίπλα στη Σοφία που έχει δικά της (2511 και μηχάνημα 1002)· το τμήμα έχει
/// και κοινόχρηστο μηχάνημα 1001.
Future<ProviderContainer> _containerChristinaNoAssets({
  required List<String> sharedPhones,
}) async {
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: [
      UserModel(
        id: _kSofiaId,
        firstName: 'Σοφία',
        lastName: 'Σπυροπούλου',
        phones: PhoneListParser.splitPhones(_kSofiaPhone),
        departmentId: _kAimodosiaId,
      ),
      UserModel(
        id: 41,
        firstName: 'Χριστίνα',
        lastName: 'Παππά',
        departmentId: _kAimodosiaId,
      ),
    ],
    equipment: [
      EquipmentModel(id: 1, code: '1001', departmentId: _kAimodosiaId),
      EquipmentModel(id: 2, code: '1002'),
    ],
    departmentRows: [DepartmentModel(id: _kAimodosiaId, name: _kAimodosiaName)],
    userToEquipmentIds: {
      _kSofiaId: [2],
    },
    departmentDirectPhones: {_kAimodosiaId: sharedPhones},
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

void _commitChristina(SmartEntitySelectorNotifier n) {
  n.updateCallerDisplayText('Χριστίνα Παππά');
  n.performCallerLookup('Χριστίνα Παππά');
}

void main() {
  group('Κενή στενή πηγή — τα κοινόχρηστα του τμήματος αναλαμβάνουν', () {
    // Συμβόλαιο: η στενότερη πηγή υπερισχύει, αλλά όταν είναι ΚΕΝΗ ισχύει η
    // επόμενη — ο υπάλληλος χωρίς προσωπικό αριθμό καλεί από το κοινόχρηστο.

    test('Χριστίνα χωρίς τηλέφωνο + ΕΝΑΣ αριθμός τμήματος → γεμίζει', () async {
      // Το κοινόχρηστο ταυτίζεται με της Σοφίας: μοναδικός αριθμός τμήματος.
      final container = await _containerChristinaNoAssets(
        sharedPhones: [_kSofiaPhone],
      );
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      _commitChristina(n);
      final s = container.read(callSmartEntityProvider);

      expect(s.selectedDepartmentId, _kAimodosiaId);
      expect(
        s.selectedPhone,
        _kSofiaPhone,
        reason: greekExpectMsg(
          'Χωρίς δικό της αριθμό, ο μοναδικός του τμήματος είναι απόφαση',
        ),
      );
    });

    test('ΔΥΟ αριθμοί τμήματος → λίστα, καμία απόφαση', () async {
      final container = await _containerChristinaNoAssets(
        sharedPhones: [_kSofiaPhone, '2520'],
      );
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      _commitChristina(n);
      final s = container.read(callSmartEntityProvider);

      expect(s.selectedPhone?.trim().isEmpty ?? true, isTrue);
      expect(
        s.phoneCandidates.toSet(),
        {_kSofiaPhone, '2520'},
        reason: greekExpectMsg('Το πεδίο τηλεφώνου δεν μένει χωρίς καμία λίστα'),
      );
    });

    test(
      'χωρίς δικό εξοπλισμό → λίστα τμήματος, ΟΧΙ «Καμία αντιστοιχία»',
      () async {
        final container = await _containerChristinaNoAssets(
          sharedPhones: [_kSofiaPhone],
        );
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);

        _commitChristina(n);
        final s = container.read(callSmartEntityProvider);

        expect(
          s.equipmentNoMatch,
          isFalse,
          reason: greekExpectMsg(
            'Δεν λέμε «Καμία αντιστοιχία» όταν το τμήμα έχει διαθέσιμα μηχανήματα',
          ),
        );
        expect(
          s.equipmentCandidates,
          hasLength(2),
          reason: greekExpectMsg('Κοινόχρηστο 1001 + της Σοφίας 1002'),
        );
      },
    );

    test('αντιπαράδειγμα: η Σοφία με δικά της → η στενή πηγή κερδίζει', () async {
      final container = await _containerChristinaNoAssets(
        sharedPhones: [_kSofiaPhone, '2520'],
      );
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.updateCallerDisplayText(_kSofiaName);
      n.performCallerLookup(_kSofiaName);
      final s = container.read(callSmartEntityProvider);

      expect(
        s.selectedPhone,
        _kSofiaPhone,
        reason: greekExpectMsg('Ο δικός της αριθμός, όχι λίστα του τμήματος'),
      );
      expect(
        s.equipmentText,
        '1002',
        reason: greekExpectMsg('Το δικό της μηχάνημα, όχι λίστα του τμήματος'),
      );
    });

    test('ΕΝΑ μόνο μηχάνημα στο τμήμα → γεμίζει για τη Χριστίνα', () async {
      final svc = LookupService.instance;
      svc.resetForReload();
      svc.injectInMemoryCatalogForTests(
        users: [
          UserModel(
            id: 41,
            firstName: 'Χριστίνα',
            lastName: 'Παππά',
            departmentId: _kAimodosiaId,
          ),
        ],
        equipment: [
          EquipmentModel(id: 1, code: '1001', departmentId: _kAimodosiaId),
        ],
        departmentRows: [
          DepartmentModel(id: _kAimodosiaId, name: _kAimodosiaName),
        ],
        departmentDirectPhones: {
          _kAimodosiaId: ['2520', '2521'],
        },
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

      _commitChristina(n);
      final s = container.read(callSmartEntityProvider);

      expect(
        s.equipmentText,
        '1001',
        reason: greekExpectMsg('Μοναδικό μηχάνημα τμήματος = απόφαση'),
      );
      expect(
        s.phoneCandidates.toSet(),
        {'2520', '2521'},
        reason: greekExpectMsg('Δύο κοινόχρηστοι αριθμοί = λίστα'),
      );
    });

    test(
      'αδελφή ροή: κατοχύρωση εξοπλισμού με άφωνο κάτοχο → τηλέφωνο τμήματος',
      () async {
        final svc = LookupService.instance;
        svc.resetForReload();
        svc.injectInMemoryCatalogForTests(
          users: [
            UserModel(
              id: 41,
              firstName: 'Χριστίνα',
              lastName: 'Παππά',
              departmentId: _kAimodosiaId,
            ),
          ],
          equipment: [EquipmentModel(id: 3, code: '1003')],
          departmentRows: [
            DepartmentModel(id: _kAimodosiaId, name: _kAimodosiaName),
          ],
          userToEquipmentIds: {
            41: [3],
          },
          departmentDirectPhones: {
            _kAimodosiaId: ['2520'],
          },
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

        n.performEquipmentLookupByCode('1003');
        final s = container.read(callSmartEntityProvider);

        expect(s.selectedCaller?.id, 41);
        expect(
          s.selectedPhone,
          '2520',
          reason: greekExpectMsg(
            'Ο κάτοχος δεν έχει δικό του αριθμό — αναλαμβάνει το κοινόχρηστο',
          ),
        );
      },
    );
  });

  group('Διαγραφή καλούντα — η λίστα του τμήματος επανέρχεται', () {
    test('επιλογή Χριστίνας → διαγραφή με «×» → ξανά οι δύο υπάλληλοι', () async {
      final container = await _containerTwoEmployees();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.selectDepartment(
        DepartmentModel(id: _kAimodosiaId, name: _kAimodosiaName),
      );
      final candidates = container
          .read(callSmartEntityProvider)
          .callerCandidates;
      expect(
        candidates,
        hasLength(2),
        reason: greekExpectMsg('Προϋπόθεση: δύο υπάλληλοι στη λίστα'),
      );

      n.setCaller(
        candidates.firstWhere((u) => (u.name ?? '').contains('Χριστίνα')),
      );
      expect(
        container.read(callSmartEntityProvider).callerCandidates,
        isEmpty,
        reason: greekExpectMsg('Μετά την επιλογή η λίστα κλείνει'),
      );

      n.clearCaller();
      final s = container.read(callSmartEntityProvider);

      expect(
        s.callerCandidates,
        hasLength(2),
        reason: greekExpectMsg(
          'Με συμπληρωμένο τμήμα, το άδειο πεδίο ξαναδείχνει τους υπαλλήλους του',
        ),
      );
      expect(
        s.selectedDepartmentId,
        _kAimodosiaId,
        reason: greekExpectMsg('Το τμήμα μένει ανέγγιχτο'),
      );
      expect(
        s.selectedPhone,
        _kSofiaPhone,
        reason: greekExpectMsg('Το τηλέφωνο μένει ανέγγιχτο'),
      );
    });

    test('η ίδια ροή με backspace μέχρι το κενό', () async {
      final container = await _containerTwoEmployees();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.selectDepartment(
        DepartmentModel(id: _kAimodosiaId, name: _kAimodosiaName),
      );
      n.setCaller(
        container.read(callSmartEntityProvider).callerCandidates.firstWhere(
          (u) => (u.name ?? '').contains('Χριστίνα'),
        ),
      );

      n.updateCallerDisplayText('');
      final s = container.read(callSmartEntityProvider);

      expect(s.callerCandidates, hasLength(2));
      expect(
        s.selectedCaller,
        isNull,
        reason: greekExpectMsg(
          'Κενό ορατό πεδίο σημαίνει «κανένας καλών» — λύνεται η ταυτοποίηση',
        ),
      );
    });

    test(
      'φρουρός: μονοπρόσωπο τμήμα → η διαγραφή ΔΕΝ ξαναγράφει το όνομα',
      () async {
        final container = await _container();
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);

        n.selectDepartment(
          DepartmentModel(id: _kAimodosiaId, name: _kAimodosiaName),
        );
        expect(
          container.read(callSmartEntityProvider).selectedCaller?.id,
          _kSofiaId,
          reason: greekExpectMsg('Προϋπόθεση: μονοπρόσωπη υπόδειξη'),
        );

        n.clearCaller();
        final s = container.read(callSmartEntityProvider);

        expect(
          s.callerDisplayText.trim(),
          isEmpty,
          reason: greekExpectMsg(
            'Η επαναφορά δίνει προτάσεις, ΠΟΤΕ όνομα — αλλιώς ο μοναδικός '
            'υπάλληλος θα ήταν αδύνατο να σβηστεί',
          ),
        );
        expect(
          s.callerCandidates,
          hasLength(1),
          reason: greekExpectMsg('Ο υπάλληλος μένει διαθέσιμος ως υπόδειξη'),
        );
      },
    );
  });

  group('Συμμετρία λιστών — το σβήσιμο ενός πεδίου δεν ορφανεύει τα άλλα', () {
    // Συμβόλαιο: όσο το τμήμα μένει συμπληρωμένο, κάθε άδειο πεδίο ξαναδείχνει
    // τους υποψήφιους του τμήματος — όποιο πεδίο κι αν προκάλεσε το σβήσιμο.

    test('σβήσιμο τηλεφώνου → η λίστα υπαλλήλων επανέρχεται', () async {
      final container = await _containerTwoEmployees();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.selectDepartment(
        DepartmentModel(id: _kAimodosiaId, name: _kAimodosiaName),
      );
      expect(
        container.read(callSmartEntityProvider).callerCandidates,
        hasLength(2),
        reason: greekExpectMsg('Προϋπόθεση: δύο υπάλληλοι στη λίστα'),
      );

      n.updatePhone(null);
      final s = container.read(callSmartEntityProvider);

      expect(
        s.callerCandidates,
        hasLength(2),
        reason: greekExpectMsg(
          'Το σβήσιμο του τηλεφώνου δεν αφήνει το πεδίο καλούντα χωρίς λίστα',
        ),
      );
      expect(
        s.callerDisplayText.trim(),
        isEmpty,
        reason: greekExpectMsg('Η επαναφορά δίνει προτάσεις, ποτέ όνομα'),
      );
    });

    test('καθαρισμός καλούντα → η λίστα αριθμών επανέρχεται', () async {
      final container = await _containerTwoEmployees();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.selectDepartment(
        DepartmentModel(id: _kAimodosiaId, name: _kAimodosiaName),
      );
      // Αδειάζουμε το τηλέφωνο ώστε να ζει από τη λίστα υποψηφίων του.
      n.updatePhone(null);
      n.setCaller(
        container.read(callSmartEntityProvider).callerCandidates.firstWhere(
          (u) => (u.name ?? '').contains('Χριστίνα'),
        ),
      );

      n.clearCaller();
      final s = container.read(callSmartEntityProvider);

      expect(
        s.phoneCandidates,
        isNotEmpty,
        reason: greekExpectMsg(
          'Ο καθαρισμός του καλούντα δεν αφήνει το πεδίο τηλεφώνου χωρίς λίστα',
        ),
      );
      expect(
        s.selectedPhone?.trim().isEmpty ?? true,
        isTrue,
        reason: greekExpectMsg('Η επαναφορά δίνει προτάσεις, ποτέ τιμή'),
      );
    });
  });

  group('Σβήσιμο τηλεφώνου — η πρόθεση του χρήστη υπερισχύει', () {
    test('Σοφία → σβήνω το 2511 → το πεδίο ΜΕΝΕΙ κενό', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      _commitSofia(n);
      expect(
        container.read(callSmartEntityProvider).selectedPhone,
        _kSofiaPhone,
        reason: greekExpectMsg('Προϋπόθεση: το τηλέφωνο συμπληρώθηκε αυτόματα'),
      );

      n.updatePhone(null);
      final s = container.read(callSmartEntityProvider);

      expect(
        s.selectedPhone?.trim().isEmpty ?? true,
        isTrue,
        reason: greekExpectMsg(
          'Το άδειασμα είναι ρητή πρόθεση — ο αριθμός δεν ξαναγράφεται μόνος του',
        ),
      );
      expect(
        s.phoneCandidates,
        contains(_kSofiaPhone),
        reason: greekExpectMsg(
          'Ο αριθμός παραμένει διαθέσιμος ως υπόδειξη, όχι ως τιμή',
        ),
      );
    });

    test('ΤΕΙ Ορθοπεδικό → σβήνω το 2580 → το πεδίο ΜΕΝΕΙ κενό', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.selectDepartment(
        DepartmentModel(id: _kOrthopedikoId, name: _kOrthopedikoName),
      );
      expect(
        container.read(callSmartEntityProvider).selectedPhone,
        _kOrthopedikoPhone,
        reason: greekExpectMsg('Προϋπόθεση: μονοπρόσωπη υπόδειξη τμήματος'),
      );

      n.updatePhone(null);
      expect(
        container.read(callSmartEntityProvider).selectedPhone?.trim().isEmpty ??
            true,
        isTrue,
        reason: greekExpectMsg(
          'Το κοινόχρηστο τηλέφωνο του τμήματος δεν κλειδώνει το πεδίο',
        ),
      );
    });

    test(
      'σβήνω ψηφίο-ψηφίο μέχρι το κενό → καμία αυτόματη επαναφορά',
      () async {
        final container = await _container();
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);

        _commitSofia(n);
        for (final partial in ['251', '25', '2', '']) {
          n.updatePhone(partial.isEmpty ? null : partial);
          n.performPhoneLookup(partial);
          expect(
            container.read(callSmartEntityProvider).selectedPhone ?? '',
            partial,
            reason: greekExpectMsg(
              'Μετά το backspace το πεδίο δείχνει «$partial», όχι τον παλιό αριθμό',
            ),
          );
        }
      },
    );
  });

  group('Το σενάριο του Χειρουργείου — παρατυπία με ευθύνη του χρήστη', () {
    test(
      'Σοφία (Αιμοδοσία) + τηλέφωνο Χειρουργείου → επιτρέπεται',
      () async {
        final container = await _container();
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);

        _commitSofia(n);
        n.updatePhone(null);
        n.updatePhone(_kCheirourgeioPhone);
        n.performPhoneLookup(_kCheirourgeioPhone);
        final s = container.read(callSmartEntityProvider);

        expect(
          s.selectedPhone,
          _kCheirourgeioPhone,
          reason: greekExpectMsg(
            'Η Σοφία μπορεί να τηλεφωνεί από άλλο τμήμα — το καταγράφουμε',
          ),
        );
      },
    );
  });

  group('Επανεπικύρωση οντότητας — η υπόδειξη ξαναδίνεται', () {
    test(
      'άδειο τηλέφωνο + ξανα-επικύρωση της Σοφίας → συμπληρώνεται το 2511',
      () async {
        final container = await _container();
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);

        _commitSofia(n);
        n.updatePhone(null);
        expect(
          container.read(callSmartEntityProvider).selectedPhone?.trim().isEmpty ??
              true,
          isTrue,
          reason: greekExpectMsg('Προϋπόθεση: το πεδίο άδειασε'),
        );

        // Κλικ στο πεδίο καλούντα και Enter, χωρίς καμία αλλαγή κειμένου.
        _commitSofia(n);

        expect(
          container.read(callSmartEntityProvider).selectedPhone,
          _kSofiaPhone,
          reason: greekExpectMsg(
            'Η ρητή επικύρωση οντότητας ξαναδίνει την υπόδειξη σε κενό πεδίο',
          ),
        );
      },
    );

    test(
      'φρουρός: κατοχύρωση εξοπλισμού χωρίς κάτοχο → τηλέφωνο τμήματος',
      () async {
        final container = await _container();
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);

        n.performEquipmentLookupByCode(_kOrthopedikoEquipment);
        final s = container.read(callSmartEntityProvider);

        expect(s.selectedDepartmentId, _kOrthopedikoId);
        expect(
          s.selectedPhone,
          _kOrthopedikoPhone,
          reason: greekExpectMsg(
            'Η κατοχύρωση κωδικού είναι επικύρωση οντότητας — η υπόδειξη ισχύει',
          ),
        );
      },
    );
  });
}
