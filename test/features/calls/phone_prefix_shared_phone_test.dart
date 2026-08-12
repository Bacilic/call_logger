// Σενάριο πεδίου 12/08/2026 — τηλέφωνα «2240» (της Σωτηρίας) και «2244»
// (κοινόχρηστο της Παθολογικής, χωρίς κάτοχο), ίδιο τμήμα με ΕΝΑΝ υπάλληλο.
//
// Δύο συμβόλαια:
//   1. Η λίστα προτάσεων του τηλεφώνου δείχνει ΚΑΙ τα κοινόχρηστα του τμήματος
//      — αλλιώς μισός κατάλογος είναι αόρατος στην πληκτρολόγηση.
//   2. Γράφοντας ψηφίο-ψηφίο, το ενδιάμεσο «224» δένει τη Σωτηρία· το τελικό
//      «2244» ΔΕΝ είναι δικό της. Το όνομα που έγραψε μόνη της η εφαρμογή δεν
//      επιτρέπεται να μείνει ως ελεύθερο κείμενο χωρίς δεσμό.
//
//   flutter test test/features/calls/phone_prefix_shared_phone_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/phone_list_parser.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _kPathologyId = 28;
const _kPathologyName = 'Παθολογική';
const _kSotiriaId = 56;
const _kSotiriaName = 'Σωτηρία Μπεφάνη';
const _kOwnedPhone = '2240';
const _kSharedPhone = '2244';

Future<ProviderContainer> _container({bool secondEmployee = false}) async {
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: [
      UserModel(
        id: _kSotiriaId,
        firstName: 'Σωτηρία',
        lastName: 'Μπεφάνη',
        phones: PhoneListParser.splitPhones(_kOwnedPhone),
        departmentId: _kPathologyId,
      ),
      if (secondEmployee)
        UserModel(
          id: 57,
          firstName: 'Δεύτερος',
          lastName: 'Συνάδελφος',
          departmentId: _kPathologyId,
        ),
    ],
    equipment: [EquipmentModel(id: 700, code: '3520')],
    departmentRows: [
      DepartmentModel(id: _kPathologyId, name: _kPathologyName),
    ],
    userToEquipmentIds: {
      _kSotiriaId: [700],
    },
    departmentDirectPhones: {
      _kPathologyId: [_kOwnedPhone, _kSharedPhone],
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
  test('η λίστα τηλεφώνων δείχνει και τα κοινόχρηστα του τμήματος', () async {
    final container = await _container();
    addTearDown(container.dispose);

    final proposed = LookupService.instance.searchPhonesByPrefix('224');

    expect(
      proposed,
      containsAll(<String>[_kOwnedPhone, _kSharedPhone]),
      reason:
          'το «2244» είναι κοινόχρηστο της Παθολογικής — χωρίς αυτό ο χρήστης '
          'νομίζει ότι δεν υπάρχει στον κατάλογο',
    );
  });

  test('κοινόχρηστο τηλέφωνο δεν εμφανίζεται δύο φορές', () async {
    final container = await _container();
    addTearDown(container.dispose);

    final proposed = LookupService.instance.searchPhonesByPrefix('2240');

    expect(proposed.where((p) => p == _kOwnedPhone), hasLength(1));
  });

  test(
    'ψηφίο-ψηφίο ως το κοινόχρηστο: ο καλών μένει ΔΕΜΕΝΟΣ, όχι ελεύθερο κείμενο',
    () async {
      final container = await _container();
      addTearDown(container.dispose);
      final notifier = container.read(callSmartEntityProvider.notifier);

      // «224» ταιριάζει υποσυμβολοσειρά με το 2240 → δένει τη Σωτηρία.
      notifier.performPhoneLookup('224');
      expect(
        container.read(callSmartEntityProvider).selectedCaller?.id,
        _kSotiriaId,
        reason: 'το μερικό τηλέφωνο βρίσκει την κάτοχο',
      );

      // Το τέταρτο ψηφίο αλλάζει τον αριθμό: το 2244 ΔΕΝ είναι δικό της.
      notifier.performPhoneLookup(_kSharedPhone);

      final state = container.read(callSmartEntityProvider);
      expect(
        state.callerDisplayText.trim().isEmpty ||
            state.selectedCaller != null,
        isTrue,
        reason:
            'όνομα στο πεδίο χωρίς δεσμό = «ανύπαρκτος» υπάλληλος: η κλήση '
            'φεύγει με ελεύθερο κείμενο και ο αιτών χάνεται',
      );
    },
  );

  test(
    'κοινόχρηστο τηλέφωνο με ΕΝΑΝ υπάλληλο στο τμήμα: δένεται εκείνος',
    () async {
      final container = await _container();
      addTearDown(container.dispose);
      final notifier = container.read(callSmartEntityProvider.notifier);

      notifier.performPhoneLookup('224');
      notifier.performPhoneLookup(_kSharedPhone);

      final state = container.read(callSmartEntityProvider);
      expect(state.selectedCaller?.id, _kSotiriaId);
      expect(state.callerDisplayText.trim(), _kSotiriaName);
      expect(state.departmentText, _kPathologyName);
    },
  );

  test(
    'με ΔΥΟ υπαλλήλους το τμήμα δεν αποφασίζει — καθαρό πεδίο, όχι φάντασμα',
    () async {
      final container = await _container(secondEmployee: true);
      addTearDown(container.dispose);
      final notifier = container.read(callSmartEntityProvider.notifier);

      notifier.performPhoneLookup('224');
      notifier.performPhoneLookup(_kSharedPhone);

      final state = container.read(callSmartEntityProvider);
      expect(state.selectedCaller, isNull);
      expect(
        state.callerDisplayText.trim(),
        isEmpty,
        reason: 'δύο υποψήφιοι = ερώτηση, όχι μπαγιάτικο όνομα του πρώτου',
      );
    },
  );

  test('ό,τι έγραψε ο ΧΡΗΣΤΗΣ δεν σβήνεται από αλλαγή τηλεφώνου', () async {
    final container = await _container();
    addTearDown(container.dispose);
    final notifier = container.read(callSmartEntityProvider.notifier);

    notifier.updateCallerDisplayText('Κάποιος Άλλος');
    notifier.performPhoneLookup(_kSharedPhone);

    expect(
      container.read(callSmartEntityProvider).callerDisplayText.trim(),
      'Κάποιος Άλλος',
    );
  });
}
