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
const _kCardiologyId = 30;
const _kCardiologyName = 'Καρδιολογική';
const _kGiorgosId = 60;
const _kGiorgosName = 'Γιώργος Καρδίτσας';
const _kGiorgosPhone = '3333';
const _kEleniId = 61;
const _kEleniPhone = '4444';
const _kEleniEquipment = '4410';

/// Όπως στην οθόνη: κάθε πλήκτρο περνά από το `updatePhone`, και η αναζήτηση
/// τρέχει όταν ο χρήστης φύγει από το πεδίο.
void _typePhoneAndLeave(SmartEntitySelectorNotifier notifier, String digits) {
  notifier.updatePhone(digits);
  notifier.performPhoneLookup(digits);
}

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
      UserModel(
        id: _kGiorgosId,
        firstName: 'Γιώργος',
        lastName: 'Καρδίτσας',
        phones: PhoneListParser.splitPhones(_kGiorgosPhone),
        departmentId: _kCardiologyId,
      ),
      UserModel(
        id: _kEleniId,
        firstName: 'Ελένη',
        lastName: 'Καρδιακού',
        phones: PhoneListParser.splitPhones(_kEleniPhone),
        departmentId: _kCardiologyId,
      ),
    ],
    equipment: [
      EquipmentModel(id: 700, code: '3520'),
      EquipmentModel(id: 800, code: _kEleniEquipment),
    ],
    departmentRows: [
      DepartmentModel(id: _kPathologyId, name: _kPathologyName),
      DepartmentModel(id: _kCardiologyId, name: _kCardiologyName),
    ],
    userToEquipmentIds: {
      _kSotiriaId: [700],
      _kEleniId: [800],
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

  test('ψηφίο-ψηφίο ως το κοινόχρηστο: ο καλών μένει ΔΕΜΕΝΟΣ, όχι ελεύθερο κείμενο', () async {
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
      state.callerDisplayText.trim().isEmpty || state.selectedCaller != null,
      isTrue,
      reason:
          'όνομα στο πεδίο χωρίς δεσμό = «ανύπαρκτος» υπάλληλος: η κλήση '
          'φεύγει με ελεύθερο κείμενο και ο αιτών χάνεται',
    );
  });

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

  group('διόρθωση τηλεφώνου όπως στην οθόνη (πλήκτρο → έξοδος από πεδίο)', () {
    test('2240 → 2244 (κοινόχρηστο, δύο υπάλληλοι): το όνομα της Σωτηρίας '
        'φεύγει', () async {
      final container = await _container(secondEmployee: true);
      addTearDown(container.dispose);
      final notifier = container.read(callSmartEntityProvider.notifier);

      _typePhoneAndLeave(notifier, _kOwnedPhone);
      expect(
        container.read(callSmartEntityProvider).callerDisplayText.trim(),
        _kSotiriaName,
      );

      _typePhoneAndLeave(notifier, _kSharedPhone);

      final state = container.read(callSmartEntityProvider);
      expect(state.selectedCaller, isNull);
      expect(
        state.callerDisplayText.trim(),
        isEmpty,
        reason:
            'το όνομα το έγραψε η εφαρμογή από το 2240· με το 2244 η πηγή του '
            'έπαψε να ισχύει — αλλιώς η κλήση φεύγει με «ανύπαρκτο» αιτούντα',
      );
    });

    test('2240 → τηλέφωνο άλλου τμήματος: έρχονται ο νέος κάτοχος και το '
        'τμήμα του', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final notifier = container.read(callSmartEntityProvider.notifier);

      _typePhoneAndLeave(notifier, _kOwnedPhone);
      _typePhoneAndLeave(notifier, _kGiorgosPhone);

      final state = container.read(callSmartEntityProvider);
      expect(state.selectedCaller?.id, _kGiorgosId);
      expect(state.callerDisplayText.trim(), _kGiorgosName);
      expect(
        state.departmentText,
        _kCardiologyName,
        reason:
            'η Παθολογική ήρθε από το 2240 — μένοντας, κρύβει τον σωστό '
            'κάτοχο του νέου αριθμού',
      );
    });

    test('όνομα και τμήμα που έγραψε ο ΧΡΗΣΤΗΣ μένουν όταν αλλάζει το '
        'τηλέφωνο', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final notifier = container.read(callSmartEntityProvider.notifier);

      _typePhoneAndLeave(notifier, _kOwnedPhone);
      notifier.updateCallerDisplayText('Κάποιος Άλλος');
      _typePhoneAndLeave(notifier, _kGiorgosPhone);

      final state = container.read(callSmartEntityProvider);
      expect(state.callerDisplayText.trim(), 'Κάποιος Άλλος');
    });

    test('ο εξοπλισμός που έφερε το παλιό τηλέφωνο φεύγει μαζί του', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final notifier = container.read(callSmartEntityProvider.notifier);

      _typePhoneAndLeave(notifier, _kOwnedPhone);
      expect(container.read(callSmartEntityProvider).equipmentText, '3520');

      _typePhoneAndLeave(notifier, _kGiorgosPhone);

      final state = container.read(callSmartEntityProvider);
      expect(
        state.equipmentText,
        isNot('3520'),
        reason:
            'το 3520 είναι της Σωτηρίας — όχι του Γιώργου ή του τμήματός του',
      );
      expect(state.selectedEquipment?.code, isNot('3520'));
    });

    test(
      'εξοπλισμός που άλλαξε ο ΧΡΗΣΤΗΣ μένει όταν αλλάζει το τηλέφωνο',
      () async {
        final container = await _container();
        addTearDown(container.dispose);
        final notifier = container.read(callSmartEntityProvider.notifier);

        _typePhoneAndLeave(notifier, _kOwnedPhone);
        notifier.updateEquipmentText('9999');
        _typePhoneAndLeave(notifier, _kGiorgosPhone);

        expect(container.read(callSmartEntityProvider).equipmentText, '9999');
      },
    );
  });

  group('αδελφές πηγές: ό,τι συμπλήρωσε ο καλών ή ο εξοπλισμός', () {
    test('το σκέτο άδειασμα της πηγής κρατά τα υπόλοιπα· η νέα τιμή τα '
        'αντικαθιστά', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final notifier = container.read(callSmartEntityProvider.notifier);

      _typePhoneAndLeave(notifier, _kOwnedPhone);
      notifier.updatePhone(null);
      expect(
        container.read(callSmartEntityProvider).departmentText,
        _kPathologyName,
        reason:
            'άδειο τηλέφωνο: το τμήμα μένει και δείχνει τους υπαλλήλους του',
      );

      _typePhoneAndLeave(notifier, _kGiorgosPhone);
      expect(
        container.read(callSmartEntityProvider).departmentText,
        _kCardiologyName,
      );
    });

    test('αλλαγή καλούντα: φεύγουν τηλέφωνο, τμήμα και εξοπλισμός του '
        'προηγούμενου', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final notifier = container.read(callSmartEntityProvider.notifier);
      final lookup = LookupService.instance;

      _pickCaller(notifier, lookup.findUserById(_kSotiriaId)!);
      var state = container.read(callSmartEntityProvider);
      expect(state.selectedPhone, _kOwnedPhone);
      expect(state.departmentText, _kPathologyName);
      expect(state.equipmentText, '3520');

      _pickCaller(notifier, lookup.findUserById(_kEleniId)!);

      state = container.read(callSmartEntityProvider);
      expect(state.selectedCaller?.id, _kEleniId);
      expect(state.selectedPhone, _kEleniPhone);
      expect(state.departmentText, _kCardiologyName);
      expect(state.equipmentText, _kEleniEquipment);
    });

    test('αλλαγή εξοπλισμού: φεύγουν καλών, τηλέφωνο και τμήμα του '
        'προηγούμενου', () async {
      final container = await _container();
      addTearDown(container.dispose);
      final notifier = container.read(callSmartEntityProvider.notifier);

      _pickEquipment(notifier, '3520');
      var state = container.read(callSmartEntityProvider);
      expect(state.selectedCaller?.id, _kSotiriaId);
      expect(state.selectedPhone, _kOwnedPhone);

      _pickEquipment(notifier, _kEleniEquipment);

      state = container.read(callSmartEntityProvider);
      expect(state.selectedCaller?.id, _kEleniId);
      expect(state.callerDisplayText.trim(), 'Ελένη Καρδιακού');
      expect(state.selectedPhone, _kEleniPhone);
      expect(state.departmentText, _kCardiologyName);
    });
  });
}

/// Όπως στην οθόνη: επιλογή καλούντα από τη λίστα του πεδίου.
void _pickCaller(SmartEntitySelectorNotifier notifier, UserModel user) {
  final name = user.name!;
  notifier.updateSelectedCaller(user);
  notifier.updateCallerDisplayText(name);
  notifier.performCallerLookup(name, phoneFieldDigits: '');
}

/// Όπως στην οθόνη: επιλογή εξοπλισμού από τη λίστα του πεδίου.
void _pickEquipment(SmartEntitySelectorNotifier notifier, String code) {
  final equipment = LookupService.instance.findEquipmentByCode(code)!;
  notifier.setEquipment(equipment);
  notifier.checkContent(equipmentText: code);
  notifier.performEquipmentLookupByCode(code);
}
