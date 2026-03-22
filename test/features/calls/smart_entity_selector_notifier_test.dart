import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/phone_list_parser.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../test_reporter.dart';

/*
 * =============================================================================
 * Αρχείο δοκιμών: SmartEntitySelectorNotifier (μονάδα / unit tests)
 * =============================================================================
 *
 * Αντικείμενο δοκιμής
 *   Ο notifier [SmartEntitySelectorNotifier] συγκεντρώνει την κατάσταση της
 *   κεφαλίδας κλήσης: τηλέφωνο (phone), καλών (caller), εξοπλισμός (equipment)
 *   και τμήμα (department), καθώς και σημαίες ασάφειας (ambiguous) και
 *   «κανένα ταίριασμα» (no-match).
 *
 * Τι καλύπτουν τα τεστ του αρχείου
 *   • Βασικές ροές lookup (τηλέφωνο, καλών, κωδικός εξοπλισμού).
 *   • Περιπτώσεις ασάφειας (πολλαπλοί υποψήφιοι) και καθαρισμούς κατάστασης.
 *   • Ειδική ομάδα «Sequential Field Mutations & Cross-Field Reactions»:
 *     εκτελεί διαδοχικές τροποποιήσεις πεδίων (sequential mutations) και
 *     ελέγχει τις διασταυρούμενες αντιδράσεις (cross-field reactions), π.χ.
 *     αλλαγή εξοπλισμού που επιβάλλει ή όχι ενημέρωση καλούντα/τμήματος,
 *     χειροκίνητες σημάνσεις (manual flags) που μπλοκάρουν αυτόματη συμπλήρωση
 *     (autofill), αλλαγή τηλεφώνου που καθαρίζει συσχετισμένες επιλογές.
 *
 * Αναφορά και εντοπισμός σφαλμάτων (bugs)
 *   Στη νέα ομάδα καταγράφονται βήματα με [printStateSnapshot] και στο τέλος
 *   της ομάδας εκτυπώνεται συγκεντρωτική αναφορά (περασμένα/αποτυχημένα
 *   σενάρια, αστοχίες, προτεινόμενες διορθώσεις), ώστε να εντοπίζονται
 *   λάθη στις αλληλεπιδράσεις μεταξύ τηλεφώνου, καλούντα, εξοπλισμού και
 *   τμήματος χωρίς να απαιτείται χειροκίνητο ξεσκόνισμα ολόκληρου του log.
 *
 * Σημείωση: τα σενάρια βασίζονται σε ελεγχόμενο κατάλογο μέσω
 * [_containerWithCatalog] (in-memory inject στο [LookupService]).
 *
 * Εντολές flutter test (από ρίζα έργου)
 *   Ολόκληρο αρχείο:
 *     flutter test test/features/calls/smart_entity_selector_notifier_test.dart
 *   Ομάδα provider (εξάντληση λογικής):
 *     flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "SmartEntitySelectorNotifier — provider (εξάντληση λογικής)"
 *   Ομάδα cross-field (sequential mutations):
 *     flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "Sequential Field Mutations & Cross-Field Reactions"
 *   Κάθε δοκιμή: δείτε το ζεύγος γραμμών // αμέσως πριν από το αντίστοιχο test( … ).
 * =============================================================================
 */

/// Υποκατάστατο [LookupService]: ελεγχόμενη [findUsersByPhone] (γρήγορα τεστ χωρίς πλήρες catalog).
class _StubPhoneLookupService extends LookupService {
  _StubPhoneLookupService() : super.forTest();

  final Map<String, List<UserModel>> stubUsersByDigits = <String, List<UserModel>>{};

  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  @override
  List<UserModel> findUsersByPhone(String phone) {
    final d = _digitsOnly(phone);
    if (stubUsersByDigits.containsKey(d)) {
      return List<UserModel>.from(stubUsersByDigits[d]!);
    }
    return super.findUsersByPhone(phone);
  }
}

UserModel _u({
  required int id,
  required String first,
  required String last,
  String? phone,
  int? departmentId,
}) {
  return UserModel(
    id: id,
    firstName: first,
    lastName: last,
    phones: phone != null && phone.isNotEmpty
        ? PhoneListParser.splitPhones(phone)
        : const [],
    departmentId: departmentId,
  );
}

EquipmentModel _e({
  required int id,
  required String code,
}) {
  return EquipmentModel(id: id, code: code, type: 'PC');
}

Future<ProviderContainer> _containerWithCatalog({
  required List<UserModel> users,
  required List<EquipmentModel> equipment,
  required List<DepartmentModel> departments,
  Map<int, List<int>> userToEquipmentIds = const {},
}) async {
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: users,
    equipment: equipment,
    departmentRows: departments,
    userToEquipmentIds: userToEquipmentIds.isEmpty ? null : userToEquipmentIds,
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

Future<ProviderContainer> _containerWithLookupService(LookupService service) async {
  final container = ProviderContainer(
    overrides: [
      lookupServiceProvider.overrideWith(
        (ref) async => LookupLoadResult(service: service),
      ),
    ],
  );
  await container.read(lookupServiceProvider.future);
  return container;
}

/// Εκτυπώνει αναγνώσιμο στιγμιότυπο κατάστασης μετά από κάθε βήμα ροής.
void printStateSnapshot(String step, SmartEntitySelectorState state) {
  final caller = state.selectedCaller;
  final callerLine = caller == null
      ? '(κανένας)'
      : 'id=${caller.id} όνομα=${caller.name ?? caller.fullNameWithDepartment}';
  final eqCode = state.selectedEquipment?.code ?? '(κανένας)';
  // ignore: avoid_print
  print('');
  // ignore: avoid_print
  print('────────── SmartEntitySelector ──────────');
  // ignore: avoid_print
  print('▶ Βήμα: $step');
  // ignore: avoid_print
  print('  selectedCaller: $callerLine');
  // ignore: avoid_print
  print('  selectedEquipment.code: $eqCode');
  // ignore: avoid_print
  print('  departmentText: "${state.departmentText}"');
  // ignore: avoid_print
  print(
    '  manual flags — phone: ${state.phoneIsManual}, caller: ${state.callerIsManual}, '
    'equipment: ${state.equipmentIsManual}, department: ${state.departmentIsManual}',
  );
  // ignore: avoid_print
  print(
    '  σημαίες — isPhoneAmbiguous: ${state.isPhoneAmbiguous}, isEquipmentAmbiguous: ${state.isEquipmentAmbiguous}, '
    'callerNoMatch: ${state.callerNoMatch}, equipmentNoMatch: ${state.equipmentNoMatch}',
  );
  // ignore: avoid_print
  print('  hasAnyContent: ${state.hasAnyContent}');
  // ignore: avoid_print
  print(
    '  candidates — phone: ${state.phoneCandidates.length}, equipment: ${state.equipmentCandidates.length}',
  );
  // ignore: avoid_print
  print('─────────────────────────────────────────');
}

class _CrossFieldScenarioRecord {
  _CrossFieldScenarioRecord({
    required this.index,
    required this.title,
    required this.passed,
    this.failures = const [],
  });

  final int index;
  final String title;
  final bool passed;
  final List<String> failures;
}

final List<_CrossFieldScenarioRecord> _crossFieldScenarioRecords = [];

void _recordCrossFieldScenario(
  int index,
  String title, {
  required bool passed,
  List<String> failures = const [],
}) {
  _crossFieldScenarioRecords.add(
    _CrossFieldScenarioRecord(
      index: index,
      title: title,
      passed: passed,
      failures: List<String>.from(failures),
    ),
  );
}

void _printCrossFieldGroupSummary() {
  final total = _crossFieldScenarioRecords.length;
  final passed = _crossFieldScenarioRecords.where((r) => r.passed).length;
  final failed = total - passed;
  final buf = StringBuffer()
    ..writeln('')
    ..writeln('═══════════════════════════════════════════════════════════')
    ..writeln('📊 Συγκεντρωτική αναφορά — Cross-field / sequential scenarios')
    ..writeln('═══════════════════════════════════════════════════════════')
    ..writeln('✅ Πέρασαν: $passed / $total σενάρια')
    ..writeln('❌ Αποτυχίες: $failed / $total σενάρια');

  if (failed > 0) {
    buf.writeln('');
    buf.writeln('🔍 Λίστα αστοχιών (ανά σενάριο):');
    for (final r in _crossFieldScenarioRecords.where((e) => !e.passed)) {
      buf.writeln('  • Σενάριο ${r.index}: ${r.title}');
      for (final f in r.failures) {
        buf.writeln('    — $f');
      }
    }
    buf.writeln('');
    buf.writeln('🛠️ Προτεινόμενες διορθώσεις:');
    buf.writeln(
      '  • Ελέγξτε [SmartEntitySelectorNotifier.updatePhone], [performPhoneLookup], '
      '[performEquipmentLookupByCode] και τους κανόνες manual/autofill για caller/department.',
    );
    buf.writeln(
      '  • Επαληθεύστε ότι οι σημαίες ambiguous/no-match μηδενίζονται όταν αλλάζει πεδίο-πρωταγωνιστής.',
    );
    buf.writeln(
      '  • Για stress σενάριο: αναζητήστε βρόχους ενημέρωσης κατάστασης ή ασυνεπείς manual flags.',
    );
  } else if (total > 0) {
    buf.writeln('');
    buf.writeln('🎉 Όλα τα σενάρια της ομάδας ολοκληρώθηκαν επιτυχώς.');
  }
  buf.writeln('═══════════════════════════════════════════════════════════');
  // ignore: avoid_print
  print(buf.toString());
}

void main() {
  group('SmartEntitySelectorNotifier — provider (εξάντληση λογικής)', () {
    // Λιγότερα από 3 ψηφία: όχι ambiguous / callerNoMatch από πρόωρο lookup.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "performPhoneLookup: λιγότερα από 3 ψηφία καθαρίζει candidates"
    test(
      'performPhoneLookup: λιγότερα από 3 ψηφία καθαρίζει candidates',
      () async {
        final container = await _containerWithCatalog(
          users: [_u(id: 1, first: 'Α', last: 'Β', phone: '2345')],
          equipment: [],
          departments: [DepartmentModel(id: 1, name: 'Τμήμα')],
        );
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);
        n.performPhoneLookup('23');
        final s = container.read(callSmartEntityProvider);
        expect(s.isPhoneAmbiguous, isFalse, reason: greekExpectMsg('Δεν πρέπει να εμφανίζεται ασάφεια τηλεφώνου για <3 ψηφία'));
        expect(s.callerNoMatch, isFalse, reason: greekExpectMsg('Δεν πρέπει σημαία callerNoMatch πριν πλήρες lookup'));
      },
    );

    // Δεν βρέθηκε χρήστης για το τηλέφωνο → callerNoMatch, χωρίς επιλεγμένο καλούντα.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "performPhoneLookup: κανένας χρήστης → callerNoMatch"
    test('performPhoneLookup: κανένας χρήστης → callerNoMatch', () async {
      final container = await _containerWithCatalog(
        users: [],
        equipment: [],
        departments: [],
      );
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);
      n.updatePhone('999');
      n.performPhoneLookup('999');
      final s = container.read(callSmartEntityProvider);
      expect(s.callerNoMatch, isTrue, reason: greekExpectMsg('Αναμενόταν ένδειξη «Καμία αντιστοιχία» καλούντα'));
      expect(s.selectedCaller, isNull, reason: greekExpectMsg('Δεν πρέπει να έχει επιλεγεί καλώντας'));
    });

    // Μοναδικός χρήστης: επιλογή caller + τηλεφώνου, χωρίς σφάλμα αντιστοίχισης.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "performPhoneLookup: ένας χρήστης → επιλογή καλούντα και τηλεφώνου"
    test('performPhoneLookup: ένας χρήστης → επιλογή καλούντα και τηλεφώνου', () async {
      final container = await _containerWithCatalog(
        users: [
          _u(id: 1, first: 'Νίκος', last: 'Δοκιμής', phone: '2345', departmentId: 1),
        ],
        equipment: [_e(id: 10, code: 'PC1')],
        departments: [DepartmentModel(id: 1, name: 'IT')],
        userToEquipmentIds: {1: [10]},
      );
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);
      n.updatePhone('2345');
      n.performPhoneLookup('2345');
      final s = container.read(callSmartEntityProvider);
      expect(s.selectedCaller?.id, 1, reason: greekExpectMsg('Πρέπει να επιλεγεί ο μοναδικός χρήστης'));
      expect(s.selectedPhone, contains('2345'), reason: greekExpectMsg('Το τηλέφωνο πρέπει να παραμείνει συσχετισμένο'));
      expect(s.callerNoMatch, isFalse, reason: greekExpectMsg('Δεν πρέπει σφάλμα αντιστοίχισης'));
    });

    // Πολλοί χρήστες στο ίδιο τηλέφωνο → isPhoneAmbiguous + λίστα callerCandidates.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "performPhoneLookup: πολλοί χρήστες → ασάφεια τηλεφώνου"
    test('performPhoneLookup: πολλοί χρήστες → ασάφεια τηλεφώνου', () async {
      final container = await _containerWithCatalog(
        users: [
          _u(id: 1, first: 'Α', last: 'Ένα', phone: '2345'),
          _u(id: 2, first: 'Β', last: 'Δύο', phone: '2345-999'),
        ],
        equipment: [],
        departments: [],
      );
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);
      n.updatePhone('2345');
      n.performPhoneLookup('2345');
      final s = container.read(callSmartEntityProvider);
      expect(s.isPhoneAmbiguous, isTrue, reason: greekExpectMsg('Αναμενόταν ασάφεια όταν πολλοί χρήστες ταιριάζουν'));
      expect(s.callerCandidates.length, 2, reason: greekExpectMsg('Λίστα υποψηφίων καλούντων'));
    });

    // Αλλαγή τηλεφώνου μετά από επιλεγμένο καλούντα → καθαρίζει selectedCaller.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "updatePhone καθαρίζει πλαίσιο καλούντα (regression)"
    test('updatePhone καθαρίζει πλαίσιο καλούντα (regression)', () async {
      final container = await _containerWithCatalog(
        users: [
          _u(id: 10, first: 'Σταματίνα', last: 'Γεωργάκη', phone: '2551'),
        ],
        equipment: [],
        departments: [],
      );
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);
      n.updateSelectedCaller(
        _u(id: 10, first: 'Σταματίνα', last: 'Γεωργάκη', phone: '2551'),
      );
      n.updateCallerDisplayText('Σταματίνα Γεωργάκη');
      n.updatePhone('2551');
      final s = container.read(callSmartEntityProvider);
      expect(s.selectedCaller, isNull, reason: greekExpectMsg('Η αλλαγή τηλεφώνου πρέπει να καθαρίζει τον επιλεγμένο καλούντα'));
    });

    // Επιλογή υποψηφίου αριθμού: διατηρείται ο caller, αδειάζουν phoneCandidates.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "selectPhoneFromCandidates διατηρεί καλούντα όταν υπάρχει λίστα τηλεφώνων"
    test('selectPhoneFromCandidates διατηρεί καλούντα όταν υπάρχει λίστα τηλεφώνων', () async {
      final user = _u(
        id: 10,
        first: 'Σταματίνα',
        last: 'Γεωργάκη',
        phone: '2551 2564',
      );
      final container = await _containerWithCatalog(
        users: [user],
        equipment: [],
        departments: [],
      );
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);
      n.updateSelectedCaller(user);
      n.updateCallerDisplayText('Σταματίνα Γεωργάκη');
      n.selectPhoneFromCandidates('2551');
      final s = container.read(callSmartEntityProvider);
      expect(s.selectedPhone, '2551', reason: greekExpectMsg('Επιλεγμένο τηλέφωνο από λίστα'));
      expect(s.selectedCaller?.id, 10, reason: greekExpectMsg('Ο καλώντας παραμένει μετά την επιλογή τηλεφώνου'));
      expect(s.phoneCandidates, isEmpty, reason: greekExpectMsg('Μετά την επιλογή αδειάζουν οι υποψήφιοι αριθμοί'));
    });

    // Κενό query αναζήτησης καλούντα → δεν σηματοδοτεί callerNoMatch.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "performCallerLookup: κενό query δεν αλλάζει κατάσταση"
    test('performCallerLookup: κενό query δεν αλλάζει κατάσταση', () async {
      final container = await _containerWithCatalog(
        users: [_u(id: 1, first: 'Α', last: 'Β', phone: '1')],
        equipment: [],
        departments: [],
      );
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);
      n.performCallerLookup('');
      expect(
        container.read(callSmartEntityProvider).callerNoMatch,
        isFalse,
        reason: greekExpectMsg('Κενό query δεν σημαίνει αποτυχία αντιστοίχισης'),
      );
    });

    test('performCallerLookup: χωρίς αποτελέσματα → callerNoMatch', () async {
      final container = await _containerWithCatalog(
        users: [_u(id: 1, first: 'Α', last: 'Β', phone: '111')],
        equipment: [],
        departments: [],
      );
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);
      n.performCallerLookup('ΔενΥπάρχειΤέτοιοΌνομα123');
      expect(
        container.read(callSmartEntityProvider).callerNoMatch,
        isTrue,
        reason: greekExpectMsg('Αναμενόταν αποτυχία αναζήτησης καλούντα'),
      );
    });

    // Άγνωστος κωδικός εξοπλισμού → equipmentNoMatch.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "performEquipmentLookupByCode: χωρίς αποτελέσματα → equipmentNoMatch"
    test('performEquipmentLookupByCode: χωρίς αποτελέσματα → equipmentNoMatch', () async {
      final container = await _containerWithCatalog(
        users: [],
        equipment: [],
        departments: [],
      );
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);
      n.performEquipmentLookupByCode('ΧΧΧ');
      expect(
        container.read(callSmartEntityProvider).equipmentNoMatch,
        isTrue,
        reason: greekExpectMsg('Κωδικός χωρίς αντιστοίχιση'),
      );
    });

    // Μοναδικός εξοπλισμός: επιλογή equipment + συμπλήρωση καλούντα από κάτοχο.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "performEquipmentLookupByCode: ένας εξοπλισμός → επιλογή + καλώντας"
    test('performEquipmentLookupByCode: ένας εξοπλισμός → επιλογή + καλώντας', () async {
      final container = await _containerWithCatalog(
        users: [
          _u(id: 5, first: 'Μαρία', last: 'Τέστ', phone: '1000', departmentId: 2),
        ],
        equipment: [_e(id: 99, code: 'EQ-1')],
        departments: [DepartmentModel(id: 2, name: 'Λογιστήριο')],
        userToEquipmentIds: {5: [99]},
      );
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);
      n.performEquipmentLookupByCode('EQ-1');
      final s = container.read(callSmartEntityProvider);
      expect(s.selectedEquipment?.code, 'EQ-1', reason: greekExpectMsg('Επιλογή εξοπλισμού'));
      expect(s.selectedCaller?.id, 5, reason: greekExpectMsg('Συμπλήρωση καλούντα από κάτοχο'));
      expect(s.equipmentNoMatch, isFalse, reason: greekExpectMsg('Όχι σφάλμα εξοπλισμού'));
    });

    // Prefix που ταιριάζει σε πολλούς εξοπλισμούς → isEquipmentAmbiguous + candidates.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "performEquipmentLookupByCode: πολλαπλά → ασάφεια εξοπλισμού"
    test('performEquipmentLookupByCode: πολλαπλά → ασάφεια εξοπλισμού', () async {
      final container = await _containerWithCatalog(
        users: [
          _u(id: 1, first: 'Α', last: 'Α', phone: '1'),
          _u(id: 2, first: 'Β', last: 'Β', phone: '2'),
        ],
        equipment: [
          _e(id: 1, code: 'PC-X'),
          _e(id: 2, code: 'PC-X2'),
        ],
        departments: [],
        userToEquipmentIds: {1: [1], 2: [2]},
      );
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);
      n.performEquipmentLookupByCode('PC');
      final s = container.read(callSmartEntityProvider);
      expect(s.isEquipmentAmbiguous, isTrue, reason: greekExpectMsg('Πολλαπλοί εξοπλισμοί για το ίδιο prefix'));
      expect(s.equipmentCandidates.length, greaterThan(1), reason: greekExpectMsg('Λίστα υποψηφίων εξοπλισμού'));
    });

    // canSubmitCall: false με κενή φόρμα· true μόνο για «καθαρό» εσωτερικό (ψηφία· όχι γράμματα).
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "canSubmitCall απαιτεί μη κενό τηλέφωνο"
    test('canSubmitCall απαιτεί μη κενό τηλέφωνο', () async {
      final container = await _containerWithCatalog(
        users: [_u(id: 1, first: 'Α', last: 'Β', phone: '123')],
        equipment: [],
        departments: [],
      );
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);
      n.clearAll();
      expect(
        container.read(callSmartEntityProvider).canSubmitCall,
        isFalse,
        reason: greekExpectMsg('Χωρίς τηλέφωνο δεν επιτρέπεται υποβολή'),
      );
      n.updatePhone('123');
      expect(
        container.read(callSmartEntityProvider).canSubmitCall,
        isTrue,
        reason: greekExpectMsg('Με τηλέφωνο επιτρέπεται υποβολή'),
      );
      n.updatePhone('210-LAB');
      expect(
        container.read(callSmartEntityProvider).canSubmitCall,
        isFalse,
        reason: greekExpectMsg(
          'Γράμματα στο εσωτερικό τηλέφωνο κρατούν την υποβολή ανενεργή',
        ),
      );
    });

    // Χρήστης χωρίς εξοπλισμό στο catalog: επιλογή caller αλλά equipmentNoMatch.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "performPhoneLookup: ένας χρήστης χωρίς εξοπλισμό → equipmentNoMatch"
    test(
      'performPhoneLookup: ένας χρήστης χωρίς εξοπλισμό → equipmentNoMatch',
      () async {
        final container = await _containerWithCatalog(
          users: [
            _u(id: 3, first: 'Μόνος', last: 'ΧωρίςPC', phone: '3000', departmentId: 1),
          ],
          equipment: [],
          departments: [DepartmentModel(id: 1, name: 'IT')],
        );
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);
        n.updatePhone('3000');
        n.performPhoneLookup('3000');
        final s = container.read(callSmartEntityProvider);
        expect(s.selectedCaller?.id, 3, reason: greekExpectMsg('Επιλογή καλούντα'));
        expect(s.equipmentNoMatch, isTrue, reason: greekExpectMsg('Χωρίς εξοπλισμό στον κάτοχο'));
        expect(s.isEquipmentAmbiguous, isFalse, reason: greekExpectMsg('Όχι ασάφεια εξοπλισμού'));
      },
    );

    // Δύο εξοπλισμοί στον ίδιο χρήστη → ασάφεια + δύο equipmentCandidates.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "performPhoneLookup: ένας χρήστης με δύο εξοπλισμούς → ασάφεια εξοπλισμού"
    test(
      'performPhoneLookup: ένας χρήστης με δύο εξοπλισμούς → ασάφεια εξοπλισμού',
      () async {
        final container = await _containerWithCatalog(
          users: [
            _u(id: 4, first: 'Διπλός', last: 'Εξοπλισμός', phone: '4000', departmentId: 1),
          ],
          equipment: [
            _e(id: 401, code: 'PC-A'),
            _e(id: 402, code: 'PC-B'),
          ],
          departments: [DepartmentModel(id: 1, name: 'IT')],
          userToEquipmentIds: {4: [401, 402]},
        );
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);
        n.updatePhone('4000');
        n.performPhoneLookup('4000');
        final s = container.read(callSmartEntityProvider);
        expect(s.isEquipmentAmbiguous, isTrue, reason: greekExpectMsg('Δύο εξοπλισμοί για τον ίδιο χρήστη'));
        expect(s.equipmentCandidates.length, 2, reason: greekExpectMsg('Δύο υποψήφιοι εξοπλισμοί'));
      },
    );

    // Ένας χρήστης από όνομα: επιλογή caller + departmentText από departmentId.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "performCallerLookup: μοναδικό ταίριασμα → καλώντας και αυτόματο τμήμα"
    test(
      'performCallerLookup: μοναδικό ταίριασμα → καλώντας και αυτόματο τμήμα',
      () async {
        final container = await _containerWithCatalog(
          users: [
            _u(id: 8, first: 'Ελένη', last: 'Κλήση', phone: '8000', departmentId: 5),
          ],
          equipment: [],
          departments: [DepartmentModel(id: 5, name: 'Υποστήριξη')],
        );
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);
        n.performCallerLookup('Ελένη');
        final s = container.read(callSmartEntityProvider);
        expect(s.selectedCaller?.id, 8, reason: greekExpectMsg('Μοναδικός καλώντας'));
        expect(
          s.departmentText,
          'Υποστήριξη',
          reason: greekExpectMsg('Συμπλήρωση τμήματος από lookup (departmentId 5)'),
        );
        expect(s.callerNoMatch, isFalse, reason: greekExpectMsg('Επιτυχής αντιστοίχιση'));
      },
    );

    // Πολλοί χρήστες με ίδιο query: callerCandidates, χωρίς αυτόματη επιλογή caller.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "performCallerLookup: πολλαπλά ταυτίσεις → λίστα υποψηφίων καλούντων"
    test(
      'performCallerLookup: πολλαπλά ταυτίσεις → λίστα υποψηφίων καλούντων',
      () async {
        final container = await _containerWithCatalog(
          users: [
            _u(id: 11, first: 'Γιάννης', last: 'Παπαδόπουλος', phone: '101'),
            _u(id: 12, first: 'Γιάννης', last: 'Κώστας', phone: '102'),
          ],
          equipment: [],
          departments: [],
        );
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);
        n.performCallerLookup('Γιάννης');
        final s = container.read(callSmartEntityProvider);
        expect(s.callerCandidates.length, 2, reason: greekExpectMsg('Δύο χρήστες με κοινό όνομα'));
        expect(s.selectedCaller, isNull, reason: greekExpectMsg('Δεν επιλέγεται αυτόματα όταν υπάρχει ασάφεια'));
      },
    );

    // performCallerLookup με phoneFieldDigits: γεμίζει selectedPhone όταν ήταν κενό.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "performCallerLookup: phoneFieldDigits συμπληρώνει κενό selectedPhone"
    test(
      'performCallerLookup: phoneFieldDigits συμπληρώνει κενό selectedPhone',
      () async {
        final container = await _containerWithCatalog(
          users: [
            _u(id: 20, first: 'Τηλέφωνο', last: 'Πεδίο', phone: '9090', departmentId: 1),
          ],
          equipment: [],
          departments: [DepartmentModel(id: 1, name: 'Α')],
        );
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);
        n.clearAll();
        n.performCallerLookup('Τηλέφωνο', phoneFieldDigits: '9090');
        final s = container.read(callSmartEntityProvider);
        expect(s.selectedPhone, '9090', reason: greekExpectMsg('Συγχώνευση ψηφίων από πεδίο τηλεφώνου'));
      },
    );

    // checkContent με μη κενό equipmentText → hasAnyContent true.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "checkContent: ενημερώνει hasAnyContent για κείμενο εξοπλισμού"
    test('checkContent: ενημερώνει hasAnyContent για κείμενο εξοπλισμού', () async {
      final container = await _containerWithCatalog(
        users: [],
        equipment: [],
        departments: [],
      );
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);
      n.checkContent(
        phoneText: '',
        callerText: '',
        equipmentText: 'PC-123',
        departmentText: '',
      );
      expect(
        container.read(callSmartEntityProvider).hasAnyContent,
        isTrue,
        reason: greekExpectMsg('Μη κενός εξοπλισμός σημαίνει περιεχόμενο φόρμας'),
      );
    });

    // Επιλογή τμήματος χωρίς caller: όλοι οι χρήστες του τμήματος ως callerCandidates.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "selectDepartment: κενός καλώντας → προ-συμπλήρωση λίστας χρηστών τμήματος"
    test(
      'selectDepartment: κενός καλώντας → προ-συμπλήρωση λίστας χρηστών τμήματος',
      () async {
        final container = await _containerWithCatalog(
          users: [
            _u(id: 31, first: 'Χ1', last: 'Τμήμα', phone: '1', departmentId: 9),
            _u(id: 32, first: 'Χ2', last: 'Τμήμα', phone: '2', departmentId: 9),
          ],
          equipment: [],
          departments: [DepartmentModel(id: 9, name: 'Κοινό')],
        );
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);
        n.clearAll();
        n.selectDepartment(DepartmentModel(id: 9, name: 'Κοινό'));
        final s = container.read(callSmartEntityProvider);
        expect(s.callerCandidates.length, 2, reason: greekExpectMsg('Όλοι οι χρήστες του τμήματος ως υποψήφιοι'));
        expect(s.departmentText, 'Κοινό', reason: greekExpectMsg('Κείμενο τμήματος'));
      },
    );

    // markPhoneAsManual μετά από updatePhone → phoneIsManual == true.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "markPhoneAsManual: ορίζει phoneIsManual"
    test('markPhoneAsManual: ορίζει phoneIsManual', () async {
      final container = await _containerWithCatalog(
        users: [],
        equipment: [],
        departments: [],
      );
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);
      n.updatePhone('111');
      n.markPhoneAsManual();
      expect(
        container.read(callSmartEntityProvider).phoneIsManual,
        isTrue,
        reason: greekExpectMsg('Σήμα χειροκίνητου τηλεφώνου'),
      );
    });

    // Stub findUsersByPhone: επαλήθευση ότι χρησιμοποιείται το stub, όχι κενός in-memory catalog.
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "Ψεύτικο LookupService: ελεγχόμενη findUsersByPhone χωρίς χρήστες στο cache"
    test(
      'Ψεύτικο LookupService: ελεγχόμενη findUsersByPhone χωρίς χρήστες στο cache',
      () async {
        final stub = _StubPhoneLookupService();
        stub.injectInMemoryCatalogForTests(
          users: <UserModel>[],
          equipment: <EquipmentModel>[],
          departmentRows: <DepartmentModel>[DepartmentModel(id: 1, name: 'Ελεγχόμενο Τμήμα')],
        );
        stub.stubUsersByDigits['888'] = <UserModel>[
          _u(
            id: 99,
            first: 'Ελεγχόμενος',
            last: 'Καλών',
            phone: '888',
            departmentId: 1,
          ),
        ];
        final container = await _containerWithLookupService(stub);
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);
        n.updatePhone('888');
        n.performPhoneLookup('888');
        final s = container.read(callSmartEntityProvider);
        expect(s.selectedCaller?.id, 99, reason: greekExpectMsg('Απάντηση από stub, όχι από κενό _users'));
        expect(s.departmentText, 'Ελεγχόμενο Τμήμα', reason: greekExpectMsg('Τμήμα από departmentIdToName'));
      },
    );

    // 100× performPhoneLookup στον ίδιο αριθμό: χρόνος < 3s (κατώφλι CI).
    //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "Μικρο-στρες provider: επαναλαμβανόμενα performPhoneLookup παραμένουν γρήγορα"
    test(
      'Μικρο-στρες provider: επαναλαμβανόμενα performPhoneLookup παραμένουν γρήγορα',
      () async {
        final container = await _containerWithCatalog(
          users: [
            _u(id: 1, first: 'Γ', last: 'Δ', phone: '2345', departmentId: 1),
          ],
          equipment: [_e(id: 1, code: 'X')],
          departments: [DepartmentModel(id: 1, name: 'Τ')],
          userToEquipmentIds: {1: [1]},
        );
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);
        final sw = Stopwatch()..start();
        for (var i = 0; i < 100; i++) {
          n.updatePhone('2345');
          n.performPhoneLookup('2345');
        }
        sw.stop();
        expect(
          sw.elapsedMilliseconds,
          lessThan(3000),
          reason: greekExpectMsg(
            'Εξάντληση λογικής εκτός UI πρέπει να ολοκληρώνεται σε ελάχιστο χρόνο (κατώφλι ασφαλείας CI)',
          ),
        );
      },
    );
  });

  group(
    'Sequential Field Mutations & Cross-Field Reactions — Πλήρης ανάλυση αλληλεπιδράσεων',
    () {
      setUpAll(_crossFieldScenarioRecords.clear);

      tearDownAll(_printCrossFieldGroupSummary);

      // Cross-field 1: updatePhone + performPhoneLookup → caller, τμήμα, μοναδικός εξοπλισμός.
      //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "Σενάριο 1: τηλέφωνο → lookup → αυτόματη συμπλήρωση καλούντα + τμήματος + εξοπλισμού"
      test(
        'Σενάριο 1: τηλέφωνο → lookup → αυτόματη συμπλήρωση καλούντα + τμήματος + εξοπλισμού',
        () async {
          try {
            final u1 = _u(
              id: 501,
              first: 'Άλφα',
              last: 'Καλών',
              phone: '50111',
              departmentId: 81,
            );
            final u2 = _u(
              id: 502,
              first: 'Βήτα',
              last: 'Καλών',
              phone: '50222',
              departmentId: 82,
            );
            final container = await _containerWithCatalog(
              users: [u1, u2],
              equipment: [
                _e(id: 901, code: 'XF-EQ-501'),
                _e(id: 902, code: 'XF-EQ-502'),
              ],
              departments: [
                DepartmentModel(id: 81, name: 'Τμήμα Ανάπτυξης'),
                DepartmentModel(id: 82, name: 'Τμήμα Πωλήσεων'),
              ],
              userToEquipmentIds: {501: [901], 502: [902]},
            );
            addTearDown(container.dispose);
            final n = container.read(callSmartEntityProvider.notifier);

            n.updatePhone('50111');
            var s = container.read(callSmartEntityProvider);
            printStateSnapshot('Μετά updatePhone(50111)', s);
            expect(
              s.selectedPhone,
              '50111',
              reason: greekExpectMsg('Το πεδίο τηλεφώνου πρέπει να ενημερωθεί'),
            );

            n.performPhoneLookup('50111');
            s = container.read(callSmartEntityProvider);
            printStateSnapshot('Μετά performPhoneLookup(50111)', s);
            expect(
              s.selectedCaller?.id,
              501,
              reason: greekExpectMsg('Μοναδικός χρήστης για το τηλέφωνο — επιλογή καλούντα'),
            );
            expect(
              s.departmentText,
              'Τμήμα Ανάπτυξης',
              reason: greekExpectMsg('Αυτόματο τμήμα από departmentId του καλούντα'),
            );
            expect(
              s.selectedEquipment?.code,
              'XF-EQ-501',
              reason: greekExpectMsg('Ένας εξοπλισμός για τον χρήστη — αυτόματη επιλογή'),
            );
            expect(
              s.callerNoMatch,
              isFalse,
              reason: greekExpectMsg('Επιτυχής αντιστοίχιση καλούντα'),
            );
            expect(
              s.equipmentNoMatch,
              isFalse,
              reason: greekExpectMsg('Βρέθηκε εξοπλισμός'),
            );

            _recordCrossFieldScenario(
              1,
              'Βασική ροή τηλεφώνου με autofill καλούντα/τμήματος/εξοπλισμού',
              passed: true,
            );
          } catch (e, st) {
            _recordCrossFieldScenario(
              1,
              'Βασική ροή τηλεφώνου με autofill καλούντα/τμήματος/εξοπλισμού',
              passed: false,
              failures: ['$e', '$st'],
            );
            rethrow;
          }
        },
      );

      // Cross-field 2: επιτυχής lookup κωδικού εξοπλισμού, μετά άγνωστος κωδικός → καθαρισμός + equipmentNoMatch.
      //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "Σενάριο 2: πλήρης φόρμα → performEquipmentLookupByCode (επιτυχία και μετά εκκαθάριση)"
      test(
        'Σενάριο 2: πλήρης φόρμα → performEquipmentLookupByCode (επιτυχία και μετά εκκαθάριση)',
        () async {
          try {
            final u1 = _u(
              id: 511,
              first: 'Γιώργος',
              last: 'Πρώτος',
              phone: '51111',
              departmentId: 91,
            );
            final u2 = _u(
              id: 512,
              first: 'Δήμητρα',
              last: 'Δεύτερη',
              phone: '51222',
              departmentId: 92,
            );
            final container = await _containerWithCatalog(
              users: [u1, u2],
              equipment: [
                _e(id: 911, code: 'XF-PC-ALFA'),
                _e(id: 912, code: 'XF-PC-BETA'),
              ],
              departments: [
                DepartmentModel(id: 91, name: 'Λογιστήριο'),
                DepartmentModel(id: 92, name: 'Υποστήριξη'),
              ],
              userToEquipmentIds: {511: [911], 512: [912]},
            );
            addTearDown(container.dispose);
            final n = container.read(callSmartEntityProvider.notifier);

            n.updatePhone('51111');
            n.performPhoneLookup('51111');
            var s = container.read(callSmartEntityProvider);
            printStateSnapshot('Μετά performPhoneLookup — πλήρης αυτόματη κατάσταση', s);
            expect(s.selectedCaller?.id, 511, reason: greekExpectMsg('Καλώντας από τηλέφωνο'));

            n.performEquipmentLookupByCode('XF-PC-ALFA');
            s = container.read(callSmartEntityProvider);
            printStateSnapshot('Μετά performEquipmentLookupByCode (έγκυρος κωδικός)', s);
            expect(
              s.selectedEquipment?.code,
              'XF-PC-ALFA',
              reason: greekExpectMsg('Επιβεβαίωση/επιλογή εξοπλισμού από κωδικό'),
            );
            expect(
              s.selectedCaller?.id,
              511,
              reason: greekExpectMsg('Ο καλώντας παραμένει συμβατός με τον κάτοχο του εξοπλισμού'),
            );

            n.performEquipmentLookupByCode('ΚΩΔ-ΠΟΥ-ΔΕΝ-ΥΠΑΡΧΕΙ');
            s = container.read(callSmartEntityProvider);
            printStateSnapshot('Μετά performEquipmentLookupByCode (άγνωστος κωδικός)', s);
            expect(
              s.selectedEquipment,
              isNull,
              reason: greekExpectMsg('Άγνωστος κωδικός — καθαρισμός επιλεγμένου εξοπλισμού'),
            );
            expect(
              s.equipmentNoMatch,
              isTrue,
              reason: greekExpectMsg('Ένδειξη «κανένα ταίριασμα» για εξοπλισμό'),
            );

            _recordCrossFieldScenario(
              2,
              'Lookup εξοπλισμού μετά από πλήρη φόρμα — autofill/clear',
              passed: true,
            );
          } catch (e, st) {
            _recordCrossFieldScenario(
              2,
              'Lookup εξοπλισμού μετά από πλήρη φόρμα — autofill/clear',
              passed: false,
              failures: ['$e', '$st'],
            );
            rethrow;
          }
        },
      );

      // Cross-field 3: αλλαγή εξοπλισμού σε άλλο user → ενημέρωση caller και departmentText.
      //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "Σενάριο 3: όλα γεμάτα → αλλαγή εξοπλισμού σε άλλον κάτοχο (caller + τμήμα)"
      test(
        'Σενάριο 3: όλα γεμάτα → αλλαγή εξοπλισμού σε άλλον κάτοχο (caller + τμήμα)',
        () async {
          try {
            final u1 = _u(
              id: 521,
              first: 'Ελένη',
              last: 'Α',
              phone: '52111',
              departmentId: 101,
            );
            final u2 = _u(
              id: 522,
              first: 'Ζήσης',
              last: 'Β',
              phone: '52222',
              departmentId: 102,
            );
            final container = await _containerWithCatalog(
              users: [u1, u2],
              equipment: [
                _e(id: 921, code: 'XF-DEV-01'),
                _e(id: 922, code: 'XF-SALES-01'),
              ],
              departments: [
                DepartmentModel(id: 101, name: 'R&D'),
                DepartmentModel(id: 102, name: 'Sales'),
              ],
              userToEquipmentIds: {521: [921], 522: [922]},
            );
            addTearDown(container.dispose);
            final n = container.read(callSmartEntityProvider.notifier);

            n.updatePhone('52111');
            n.performPhoneLookup('52111');
            var s = container.read(callSmartEntityProvider);
            printStateSnapshot('Αρχική πλήρης κατάσταση (χρήστης 521)', s);
            expect(s.selectedEquipment?.code, 'XF-DEV-01');

            n.performEquipmentLookupByCode('XF-SALES-01');
            s = container.read(callSmartEntityProvider);
            printStateSnapshot('Μετά αλλαγή εξοπλισμού σε κάτοχο 522', s);
            expect(
              s.selectedCaller?.id,
              522,
              reason: greekExpectMsg('Ο νέος εξοπλισμός ανήκει σε άλλον χρήστη — ενημέρωση καλούντα'),
            );
            expect(
              s.departmentText,
              'Sales',
              reason: greekExpectMsg('Το τμήμα συγχρονίζεται με τον νέο κάτοχο όταν επιτρέπεται autofill'),
            );
            expect(
              s.selectedEquipment?.code,
              'XF-SALES-01',
              reason: greekExpectMsg('Επιλεγμένος νέος εξοπλισμός'),
            );

            _recordCrossFieldScenario(
              3,
              'Αλλαγή εξοπλισμού με ενημέρωση καλούντα/τμήματος',
              passed: true,
            );
          } catch (e, st) {
            _recordCrossFieldScenario(
              3,
              'Αλλαγή εξοπλισμού με ενημέρωση καλούντα/τμήματος',
              passed: false,
              failures: ['$e', '$st'],
            );
            rethrow;
          }
        },
      );

      // Cross-field 4: callerIsManual + εξοπλισμός άλλου κάτοχου — ο χειροκίνητος caller δεν αντικαθίσταται.
      //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "Σενάριο 4: όλα γεμάτα → χειροκίνητος καλών + αλλαγή εξοπλισμού"
      test(
        'Σενάριο 4: όλα γεμάτα → χειροκίνητος καλών + αλλαγή εξοπλισμού',
        () async {
          try {
            final u1 = _u(
              id: 531,
              first: 'Θωμάς',
              last: 'Ένα',
              phone: '53111',
              departmentId: 111,
            );
            final u2 = _u(
              id: 532,
              first: 'Ιωάννα',
              last: 'Δύο',
              phone: '53222',
              departmentId: 112,
            );
            final container = await _containerWithCatalog(
              users: [u1, u2],
              equipment: [
                _e(id: 931, code: 'XF-MAN-A'),
                _e(id: 932, code: 'XF-MAN-B'),
              ],
              departments: [
                DepartmentModel(id: 111, name: 'Ops'),
                DepartmentModel(id: 112, name: 'HR'),
              ],
              userToEquipmentIds: {531: [931], 532: [932]},
            );
            addTearDown(container.dispose);
            final n = container.read(callSmartEntityProvider.notifier);

            n.updatePhone('53111');
            n.performPhoneLookup('53111');
            var s = container.read(callSmartEntityProvider);
            printStateSnapshot('Πριν χειροκίνητη αλλαγή καλούντα', s);

            // Η [updateSelectedCaller] → [setCaller] μηδενίζει το callerIsManual·
            // η σειρά «επιλογή καλούντα → markCallerAsManual» αντιστοιχεί σε ρεαλιστικό UI flow.
            n.updateSelectedCaller(u2);
            n.updateCallerDisplayText(u2.name ?? 'Ιωάννα Δύο');
            n.markCallerAsManual();
            s = container.read(callSmartEntityProvider);
            printStateSnapshot('Μετά updateSelectedCaller(532) + markCallerAsManual', s);
            expect(s.callerIsManual, isTrue, reason: greekExpectMsg('Σήμα χειροκίνητου καλούντα'));
            expect(s.selectedCaller?.id, 532);

            n.performEquipmentLookupByCode('XF-MAN-A');
            s = container.read(callSmartEntityProvider);
            printStateSnapshot('Μετά επιλογή εξοπλισμού κάτοχου 531 ενώ caller=532 manual', s);
            expect(
              s.selectedEquipment?.code,
              'XF-MAN-A',
              reason: greekExpectMsg('Ο εξοπλισμός επιλέγεται πάντα σε μοναδικό ταίριασμα κωδικού'),
            );
            expect(
              s.selectedCaller?.id,
              532,
              reason: greekExpectMsg('Χειροκίνητος καλών — δεν αντικαθίσταται από κάτοχο εξοπλισμού'),
            );

            _recordCrossFieldScenario(
              4,
              'Manual caller + lookup εξοπλισμού άλλου κάτοχου',
              passed: true,
            );
          } catch (e, st) {
            _recordCrossFieldScenario(
              4,
              'Manual caller + lookup εξοπλισμού άλλου κάτοχου',
              passed: false,
              failures: ['$e', '$st'],
            );
            rethrow;
          }
        },
      );

      // Cross-field 5: χειροκίνητο τμήμα + εξοπλισμός άλλου τμήματος → ενημέρωση caller όπου επιτρέπεται.
      //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "Σενάριο 5: όλα γεμάτα → χειροκίνητο τμήμα + αλλαγή εξοπλισμού"
      test(
        'Σενάριο 5: όλα γεμάτα → χειροκίνητο τμήμα + αλλαγή εξοπλισμού',
        () async {
          try {
            final u1 = _u(
              id: 541,
              first: 'Κώστας',
              last: 'North',
              phone: '54111',
              departmentId: 121,
            );
            final u2 = _u(
              id: 542,
              first: 'Λίνα',
              last: 'South',
              phone: '54222',
              departmentId: 122,
            );
            final container = await _containerWithCatalog(
              users: [u1, u2],
              equipment: [
                _e(id: 941, code: 'XF-D1'),
                _e(id: 942, code: 'XF-D2'),
              ],
              departments: [
                DepartmentModel(id: 121, name: 'Βόρειο'),
                DepartmentModel(id: 122, name: 'Νότιο'),
              ],
              userToEquipmentIds: {541: [941], 542: [942]},
            );
            addTearDown(container.dispose);
            final n = container.read(callSmartEntityProvider.notifier);

            n.updatePhone('54111');
            n.performPhoneLookup('54111');
            n.selectDepartment(DepartmentModel(id: 122, name: 'Νότιο'));
            var s = container.read(callSmartEntityProvider);
            printStateSnapshot('Μετά επιλογή τμήματος ενώ caller παραμένει 541', s);
            expect(s.departmentIsManual, isTrue, reason: greekExpectMsg('Ρητή επιλογή τμήματος'));
            expect(s.selectedDepartmentId, 122);
            expect(s.selectedCaller?.id, 541);

            n.performEquipmentLookupByCode('XF-D2');
            s = container.read(callSmartEntityProvider);
            printStateSnapshot('Μετά εξοπλισμό κάτοχου τμήματος Νότιο', s);
            expect(s.selectedEquipment?.code, 'XF-D2');
            expect(
              s.selectedCaller?.id,
              542,
              reason: greekExpectMsg('Επιτρέπεται autofill καλούντα όταν το τμήμα δεν μπλοκάρει τον κάτοχο'),
            );

            _recordCrossFieldScenario(
              5,
              'Επιλογή τμήματος + εξοπλισμός νέου κάτοχη',
              passed: true,
            );
          } catch (e, st) {
            _recordCrossFieldScenario(
              5,
              'Επιλογή τμήματος + εξοπλισμός νέου κάτοχη',
              passed: false,
              failures: ['$e', '$st'],
            );
            rethrow;
          }
        },
      );

      // Cross-field 6: νέο τηλέφωνο (χωρίς ακόμη lookup) → καθαρισμός selectedCaller και selectedEquipment.
      //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "Σενάριο 6: όλα γεμάτα → αλλαγή τηλεφώνου καθαρίζει καλούντα και εξοπλισμό"
      test(
        'Σενάριο 6: όλα γεμάτα → αλλαγή τηλεφώνου καθαρίζει καλούντα και εξοπλισμό',
        () async {
          try {
            final u1 = _u(
              id: 551,
              first: 'Μάκης',
              last: 'Τηλεφώνου',
              phone: '55111',
              departmentId: 131,
            );
            final u2 = _u(
              id: 552,
              first: 'Νίκος',
              last: 'Άλλος',
              phone: '55222',
              departmentId: 132,
            );
            final container = await _containerWithCatalog(
              users: [u1, u2],
              equipment: [
                _e(id: 951, code: 'XF-PH-1'),
              ],
              departments: [
                DepartmentModel(id: 131, name: 'Τμ131'),
                DepartmentModel(id: 132, name: 'Τμ132'),
              ],
              userToEquipmentIds: {551: [951]},
            );
            addTearDown(container.dispose);
            final n = container.read(callSmartEntityProvider.notifier);

            n.updatePhone('55111');
            n.performPhoneLookup('55111');
            var s = container.read(callSmartEntityProvider);
            printStateSnapshot('Πλήρης κατάσταση πριν αλλαγή τηλεφώνου', s);
            expect(s.selectedCaller, isNotNull);
            expect(s.selectedEquipment, isNotNull);

            n.updatePhone('55222');
            s = container.read(callSmartEntityProvider);
            printStateSnapshot('Μετά updatePhone σε νέο αριθμό (χωρίς ακόμη lookup)', s);
            expect(
              s.selectedCaller,
              isNull,
              reason: greekExpectMsg('Νέο τηλέφωνο — εκκαθάριση επιλεγμένου καλούντα'),
            );
            expect(
              s.selectedEquipment,
              isNull,
              reason: greekExpectMsg('Νέο τηλέφωνο — εκκαθάριση επιλεγμένου εξοπλισμού'),
            );
            expect(s.selectedPhone, '55222');

            _recordCrossFieldScenario(
              6,
              'Αλλαγή τηλεφώνου — καθαρισμός caller/equipment',
              passed: true,
            );
          } catch (e, st) {
            _recordCrossFieldScenario(
              6,
              'Αλλαγή τηλεφώνου — καθαρισμός caller/equipment',
              passed: false,
              failures: ['$e', '$st'],
            );
            rethrow;
          }
        },
      );

      // Cross-field 7: από κενή κατάσταση, lookup κωδικού εξοπλισμού → caller, τμήμα, τηλέφωνο από προφίλ.
      //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "Σενάριο 7: εκκίνηση από εξοπλισμό — autofill καλούντα και τμήμα (όχι manual)"
      test(
        'Σενάριο 7: εκκίνηση από εξοπλισμό — autofill καλούντα και τμήμα (όχι manual)',
        () async {
          try {
            final u1 = _u(
              id: 561,
              first: 'Ξένια',
              last: 'Equip',
              phone: '56111',
              departmentId: 141,
            );
            final u2 = _u(
              id: 562,
              first: 'Ορέστης',
              last: 'Δεύτερος',
              phone: '56222',
              departmentId: 142,
            );
            final container = await _containerWithCatalog(
              users: [u1, u2],
              equipment: [
                _e(id: 961, code: 'XF-BOOT-EQ'),
              ],
              departments: [
                DepartmentModel(id: 141, name: 'Παραγωγή'),
                DepartmentModel(id: 142, name: 'Διοίκηση'),
              ],
              userToEquipmentIds: {561: [961]},
            );
            addTearDown(container.dispose);
            final n = container.read(callSmartEntityProvider.notifier);

            n.clearAll();
            var s = container.read(callSmartEntityProvider);
            printStateSnapshot('Μετά clearAll (κενή αφετηρία)', s);

            n.performEquipmentLookupByCode('XF-BOOT-EQ');
            s = container.read(callSmartEntityProvider);
            printStateSnapshot('Μετά performEquipmentLookupByCode από κενή κατάσταση', s);
            expect(
              s.selectedCaller?.id,
              561,
              reason: greekExpectMsg('Συμπλήρωση καλούντα από κάτοχο εξοπλισμού'),
            );
            expect(
              s.departmentText,
              'Παραγωγή',
              reason: greekExpectMsg('Συμπλήρωση τμήματος από προφίλ καλούντα'),
            );
            expect(
              s.selectedEquipment?.code,
              'XF-BOOT-EQ',
              reason: greekExpectMsg('Επιλεγμένος εξοπλισμός'),
            );
            expect(
              s.selectedPhone,
              '56111',
              reason: greekExpectMsg('Κενό τηλέφωνο — autofill από προφίλ κάτοχη'),
            );

            _recordCrossFieldScenario(
              7,
              'Εκκίνηση από κωδικό εξοπλισμού',
              passed: true,
            );
          } catch (e, st) {
            _recordCrossFieldScenario(
              7,
              'Εκκίνηση από κωδικό εξοπλισμού',
              passed: false,
              failures: ['$e', '$st'],
            );
            rethrow;
          }
        },
      );

      // Cross-field 8: 30 εναλλαγές phone/lookup/equipment/manual — όρια candidates + χρόνος < 5s.
      //   flutter test test/features/calls/smart_entity_selector_notifier_test.dart --plain-name "Σενάριο 8: stress — 30 εναλλαγές πεδίων χωρίς ασυνεπείς σημαίες"
      test(
        'Σενάριο 8: stress — 30 εναλλαγές πεδίων χωρίς ασυνεπείς σημαίες',
        () async {
          try {
            final u1 = _u(
              id: 571,
              first: 'Πέτρος',
              last: 'Stress',
              phone: '57111',
              departmentId: 151,
            );
            final u2 = _u(
              id: 572,
              first: 'Ραλλού',
              last: 'Stress',
              phone: '57222',
              departmentId: 152,
            );
            final container = await _containerWithCatalog(
              users: [u1, u2],
              equipment: [
                _e(id: 971, code: 'XF-ST-A'),
                _e(id: 972, code: 'XF-ST-B'),
              ],
              departments: [
                DepartmentModel(id: 151, name: 'ST-1'),
                DepartmentModel(id: 152, name: 'ST-2'),
              ],
              userToEquipmentIds: {571: [971], 572: [972]},
            );
            addTearDown(container.dispose);
            final n = container.read(callSmartEntityProvider.notifier);
            final sw = Stopwatch()..start();

            for (var i = 0; i < 30; i++) {
              final phase = i % 4;
              if (phase == 0) {
                n.updatePhone(i.isEven ? '57111' : '57222');
                printStateSnapshot('Stress #$i: updatePhone', container.read(callSmartEntityProvider));
              } else if (phase == 1) {
                n.performPhoneLookup(i.isEven ? '57111' : '57222');
                printStateSnapshot('Stress #$i: performPhoneLookup', container.read(callSmartEntityProvider));
              } else if (phase == 2) {
                n.performEquipmentLookupByCode(i.isEven ? 'XF-ST-A' : 'XF-ST-B');
                printStateSnapshot('Stress #$i: performEquipmentLookupByCode', container.read(callSmartEntityProvider));
              } else {
                n.markCallerAsManual();
                n.markEquipmentAsManual();
                printStateSnapshot('Stress #$i: mark manual flags', container.read(callSmartEntityProvider));
              }
              final st = container.read(callSmartEntityProvider);
              expect(
                st.phoneCandidates.length,
                lessThanOrEqualTo(50),
                reason: greekExpectMsg('Λογικό όριο υποψηφίων τηλεφώνου — όχι διόγκωση λίστας'),
              );
              expect(
                st.equipmentCandidates.length,
                lessThanOrEqualTo(50),
                reason: greekExpectMsg('Λογικό όριο υποψηφίων εξοπλισμού'),
              );
            }
            sw.stop();
            expect(
              sw.elapsedMilliseconds,
              lessThan(5000),
              reason: greekExpectMsg('30 βήματα χωρίς εμφανή καθυστέρηση (όχι de-facto άπειρος βρόχος)'),
            );

            _recordCrossFieldScenario(
              8,
              'Stress 30 εναλλαγές',
              passed: true,
            );
          } catch (e, st) {
            _recordCrossFieldScenario(
              8,
              'Stress 30 εναλλαγές',
              passed: false,
              failures: ['$e', '$st'],
            );
            rethrow;
          }
        },
      );
    },
  );
}
