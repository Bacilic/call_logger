// Χάρτης σχέσεων πεδίων — δείκτες, σοβαρότητες, άγκυρα.
//
//   flutter test test/features/calls/smart_entity_conflict_symmetry_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/phone_list_parser.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ───────────────────────────── Τμήματα ─────────────────────────────
const _kKinisi = 20;
const _kKinisiName = 'Γραφείο Κίνησης';
const _kAimodosia = 30;
const _kAimodosiaName = 'Αιμοδοσία';
const _kGrammateia = 40;
const _kGrammateiaName = 'Γραμματεία';
const _kAktinologiko = 50;
const _kAktinologikoName = 'Ακτινολογικό';
const _kMageireio = 60;
const _kMageireioName = 'Μαγειρείο';

List<DepartmentModel> _allDepartments() => [
  DepartmentModel(id: _kKinisi, name: _kKinisiName),
  DepartmentModel(id: _kAimodosia, name: _kAimodosiaName),
  DepartmentModel(id: _kGrammateia, name: _kGrammateiaName),
  DepartmentModel(id: _kAktinologiko, name: _kAktinologikoName),
  DepartmentModel(id: _kMageireio, name: _kMageireioName),
];

// ───────────────────────────── Οντότητες ─────────────────────────────

/// Αλεξάνδρα: τηλέφωνο 2542, Γραφείο Κίνησης, εξοπλισμός 3694.
UserModel _alexandra() => UserModel(
  id: 2,
  firstName: 'Αλεξάνδρα',
  lastName: 'Νικολάου',
  phones: PhoneListParser.splitPhones('2542'),
  departmentId: _kKinisi,
);

EquipmentModel _pc3694() =>
    EquipmentModel(id: 102, code: '3694', departmentId: _kKinisi);

Future<ProviderContainer> _openContainer({
  required List<UserModel> users,
  required List<EquipmentModel> equipment,
  Map<int, List<int>>? links,
  Map<int, List<String>>? departmentPhones,
}) async {
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: users,
    equipment: equipment,
    departmentRows: _allDepartments(),
    userToEquipmentIds: links,
    departmentDirectPhones: departmentPhones,
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

/// Ο κόσμος του σεναρίου πεδίου: μόνο η Αλεξάνδρα και ο εξοπλισμός της.
Future<ProviderContainer> _alexandraWorld() => _openContainer(
  users: [_alexandra()],
  equipment: [_pc3694()],
  links: {
    2: <int>[102],
  },
);

SmartEntitySelectorState _read(ProviderContainer c) =>
    c.read(callSmartEntityProvider);

SmartEntitySelectorNotifier _n(ProviderContainer c) =>
    c.read(callSmartEntityProvider.notifier);

Map<SelectorField, ConflictSeverity?> _snapshot(ProviderContainer c) {
  final s = _read(c);
  return {for (final f in SelectorField.values) f: s.conflictSeverityFor(f)};
}

/// Ό,τι κάνει το `_onFocusOut` του widget σε κάθε κλικ εκτός πεδίου.
void _focusOut(
  ProviderContainer c, {
  required String phone,
  required String caller,
  required String department,
  required String equipment,
}) {
  _n(c).checkContent(
    phoneText: phone,
    callerText: caller,
    departmentText: department,
    equipmentText: equipment,
  );
}

/// Επικύρωση καλούντα (Enter / focus-out / επιλογή από λίστα).
void _commitCaller(ProviderContainer c, String name) {
  _n(c)
    ..updateCallerDisplayText(name)
    ..performCallerLookup(name);
}

void _commitPhone(ProviderContainer c, String digits) {
  _n(c)
    ..updatePhone(digits)
    ..performPhoneLookup(digits);
}

void _commitEquipment(ProviderContainer c, String code) {
  _n(c)
    ..checkContent(equipmentText: code)
    ..performEquipmentLookupByCode(code);
}

void _commitDepartment(ProviderContainer c, int id, String name) {
  _n(c).selectDepartment(DepartmentModel(id: id, name: name));
}

void main() {
  // ═══════════════════ Το σενάριο πεδίου του χρήστη ═══════════════════
  group('Σενάριο πεδίου — 2543 · Αλεξάνδρα · Αιμοδοσία · 3695', () {
    test('βήμα 1 — τηλέφωνο άγνωστο + καλούντας γνωστός → κίτρινα', () async {
      final c = await _alexandraWorld();
      addTearDown(c.dispose);

      _commitPhone(c, '2543');
      expect(
        _read(c).hasAnyConflict,
        isFalse,
        reason: '§Δ.12: ένα μόνο πεδίο δεν παράγει ποτέ δείκτη',
      );

      _commitCaller(c, 'Αλεξάνδρα Νικολάου');
      final s = _read(c);

      expect(s.anchorField, SelectorField.phone, reason: 'Πρώτο επικυρωμένο');
      expect(
        s.isAnchorHighlighted(SelectorField.phone),
        isTrue,
        reason: 'Πράσινο πλαίσιο — η άγκυρα δεν χρειάζεται να υπάρχει στη βάση',
      );
      expect(
        s.conflictSeverityFor(SelectorField.phone),
        ConflictSeverity.unknown,
        reason: 'Νέο τηλέφωνο σε υπάλληλο = προσθήκη (§Α.4)',
      );
      expect(
        s.conflictSeverityFor(SelectorField.caller),
        ConflictSeverity.unknown,
        reason: 'Συμμετρία: ίδια σοβαρότητα και στα δύο μέλη (§Α.3)',
      );

      // Η επικύρωση του καλούντα γέμισε αυτόματα τμήμα και εξοπλισμό, άρα το
      // νέο τηλέφωνο δεν σχετίζεται με κανένα από τα τρία.
      expect(s.conflictTooltipFor(SelectorField.phone)!.split('\n'), [
        'Τηλέφωνο 2543 — δεν σχετίζεται με Αλεξάνδρα Νικολάου',
        'Τηλέφωνο 2543 — δεν σχετίζεται με το τμήμα Γραφείο Κίνησης',
        'Τηλέφωνο 2543 — δεν σχετίζεται με τον εξοπλισμό 3694',
        'Δεν είναι καταχωρημένο στη βάση',
      ]);
      expect(
        s.conflictTooltipFor(SelectorField.caller)!.split('\n'),
        ['Αλεξάνδρα Νικολάου — δεν σχετίζεται με το τηλέφωνο 2543'],
        reason: 'Ο καλούντας δένει με το τμήμα και τον εξοπλισμό του',
      );
      expect(
        s.conflictSeverityFor(SelectorField.department),
        ConflictSeverity.unknown,
        reason: 'Μόνο η σχέση με το νέο τηλέφωνο λείπει',
      );
    });

    test(
      'βήμα 2 — υπαρκτό τμήμα άλλου → κόκκινο μόνο σε αυτό το ζεύγος',
      () async {
        final c = await _alexandraWorld();
        addTearDown(c.dispose);

        _commitPhone(c, '2543');
        _commitCaller(c, 'Αλεξάνδρα Νικολάου');
        _commitDepartment(c, _kAimodosia, _kAimodosiaName);

        final s = _read(c);
        expect(
          s.conflictSeverityFor(SelectorField.caller),
          ConflictSeverity.mismatch,
          reason: 'Δύο γνωστά που δεν σχετίζονται = μετακίνηση υπαλλήλου',
        );
        expect(
          s.conflictSeverityFor(SelectorField.department),
          ConflictSeverity.mismatch,
        );
        expect(
          s.conflictSeverityFor(SelectorField.phone),
          ConflictSeverity.unknown,
          reason: 'Το τηλέφωνο έχει μόνο κίτρινες σχέσεις — μένει κίτρινο',
        );

        expect(s.conflictTooltipFor(SelectorField.phone)!.split('\n'), [
          'Τηλέφωνο 2543 — δεν σχετίζεται με Αλεξάνδρα Νικολάου',
          'Τηλέφωνο 2543 — δεν σχετίζεται με το τμήμα Αιμοδοσία',
          'Τηλέφωνο 2543 — δεν σχετίζεται με τον εξοπλισμό 3694',
          'Δεν είναι καταχωρημένο στη βάση',
        ]);
        expect(s.conflictTooltipFor(SelectorField.caller)!.split('\n'), [
          'Αλεξάνδρα Νικολάου — δεν σχετίζεται με το τηλέφωνο 2543',
          'Αλεξάνδρα Νικολάου — δεν ανήκει στο τμήμα Αιμοδοσία',
        ]);
        expect(s.conflictTooltipFor(SelectorField.department)!.split('\n'), [
          'Τμήμα Αιμοδοσία — δεν σχετίζεται με το τηλέφωνο 2543',
          'Τμήμα Αιμοδοσία — δεν περιλαμβάνει: Αλεξάνδρα Νικολάου',
          'Τμήμα Αιμοδοσία — δεν σχετίζεται με τον εξοπλισμό 3694',
        ]);
      },
    );

    test('βήμα 3 — άγνωστος εξοπλισμός → και τα τέσσερα ανάβουν', () async {
      final c = await _alexandraWorld();
      addTearDown(c.dispose);

      _commitPhone(c, '2543');
      _commitCaller(c, 'Αλεξάνδρα Νικολάου');
      _commitDepartment(c, _kAimodosia, _kAimodosiaName);
      _commitEquipment(c, '3695');

      final s = _read(c);
      expect(_snapshot(c), {
        SelectorField.phone: ConflictSeverity.unknown,
        SelectorField.caller: ConflictSeverity.mismatch,
        SelectorField.department: ConflictSeverity.mismatch,
        SelectorField.equipment: ConflictSeverity.unknown,
      });

      expect(
        s.conflictTooltipFor(SelectorField.equipment)!.split('\n'),
        [
          'Εξοπλισμός 3695 — δεν σχετίζεται με το τηλέφωνο 2543',
          'Εξοπλισμός 3695 — δεν σχετίζεται με Αλεξάνδρα Νικολάου',
          'Εξοπλισμός 3695 — δεν σχετίζεται με το τμήμα Αιμοδοσία',
          'Δεν είναι καταχωρημένο στη βάση',
        ],
        reason: '§Α.7: πρώτη η άγκυρα (τηλέφωνο), τελευταία η μονομερής',
      );
      expect(
        s.conflictTooltipFor(SelectorField.caller)!.split('\n').length,
        3,
        reason: 'Ο καλούντας υπάρχει — καμία γραμμή «δεν είναι καταχωρημένο»',
      );
    });

    test('βήμα 4 — κλικ οπουδήποτε παγώνει την εικόνα', () async {
      final c = await _alexandraWorld();
      addTearDown(c.dispose);

      _commitPhone(c, '2543');
      _commitCaller(c, 'Αλεξάνδρα Νικολάου');
      _commitDepartment(c, _kAimodosia, _kAimodosiaName);
      _commitEquipment(c, '3695');

      final before = _snapshot(c);
      final tooltipsBefore = {
        for (final f in SelectorField.values) f: _read(c).conflictTooltipFor(f),
      };

      for (var i = 0; i < 3; i++) {
        _focusOut(
          c,
          phone: '2543',
          caller: 'Αλεξάνδρα Νικολάου',
          department: _kAimodosiaName,
          equipment: '3695',
        );
        expect(_snapshot(c), before, reason: 'κλικ #${i + 1}');
        expect(_read(c).anchorField, SelectorField.phone);
      }
      expect({
        for (final f in SelectorField.values) f: _read(c).conflictTooltipFor(f),
      }, tooltipsBefore);
    });
  });

  // ═══════════════════ §Δ.10 — πληκτρολόγηση ═══════════════════
  group('§Δ.10 — η πληκτρολόγηση δεν αγγίζει δείκτες', () {
    test('πληκτρολόγηση τμήματος δεν εμφανίζει ✱ πριν την επικύρωση', () async {
      final c = await _alexandraWorld();
      addTearDown(c.dispose);
      _commitCaller(c, 'Αλεξάνδρα Νικολάου');
      expect(_read(c).hasAnyConflict, isFalse, reason: 'Όλα δένουν');

      for (final partial in ['Α', 'Αιμ', 'Αιμοδοσία']) {
        _n(c).updateDepartmentText(partial);
        _focusOut(
          c,
          phone: '2542',
          caller: 'Αλεξάνδρα Νικολάου',
          department: partial,
          equipment: '3694',
        );
        expect(
          _read(c).hasAnyConflict,
          isFalse,
          reason: 'Κανένα ✱ κατά την πληκτρολόγηση — «$partial»',
        );
      }

      _commitDepartment(c, _kAimodosia, _kAimodosiaName);
      expect(
        _read(c).conflictSeverityFor(SelectorField.department),
        ConflictSeverity.mismatch,
        reason: 'Μόνο η επικύρωση χτίζει τους δείκτες',
      );
    });

    test('καθαρισμός πεδίου ξαναχτίζει τις σχέσεις', () async {
      final c = await _alexandraWorld();
      addTearDown(c.dispose);
      _commitCaller(c, 'Αλεξάνδρα Νικολάου');
      _commitDepartment(c, _kAimodosia, _kAimodosiaName);
      expect(_read(c).hasAnyConflict, isTrue);

      expect(
        _read(c).conflictTooltipFor(SelectorField.department),
        contains('Αλεξάνδρα'),
      );

      _n(c).clearCaller();
      expect(
        _read(c).conflictTooltipFor(SelectorField.department),
        isNot(contains('Αλεξάνδρα')),
        reason: 'Χωρίς καλούντα το ζεύγος έπαψε να υπάρχει (§Α.10)',
      );
      expect(
        _read(c).conflictSeverityFor(SelectorField.caller),
        isNull,
        reason: 'Κενό πεδίο δεν παίρνει ποτέ δείκτη',
      );
    });
  });

  // ═══════════════════ §Α.4.α — αρπαγή δεσμευμένης σχέσης ═══════════════════
  group('§Α.4.α — αρπαγή vs προσθήκη', () {
    test('νέος καλούντας πάνω σε τηλέφωνο ΑΛΛΟΥ → κόκκινο', () async {
      final c = await _alexandraWorld();
      addTearDown(c.dispose);

      _commitPhone(c, '2542'); // της Αλεξάνδρας
      _commitCaller(c, 'Νέος Υπάλληλος'); // δεν υπάρχει

      final s = _read(c);
      expect(
        s.conflictSeverityFor(SelectorField.caller),
        ConflictSeverity.mismatch,
        reason: 'Το 2542 θα περάσει από την Αλεξάνδρα σε άλλον — αρπαγή',
      );
      expect(
        s.conflictSeverityFor(SelectorField.phone),
        ConflictSeverity.mismatch,
      );
    });

    test('νέος καλούντας πάνω σε κοινόχρηστο τηλέφωνο → κίτρινο', () async {
      final c = await _openContainer(
        users: [_alexandra()],
        equipment: const [],
        departmentPhones: {
          _kGrammateia: ['2100'],
        },
      );
      addTearDown(c.dispose);

      _commitPhone(c, '2100');
      _commitCaller(c, 'Νέος Υπάλληλος');

      expect(
        _read(c).conflictSeverityFor(SelectorField.caller),
        ConflictSeverity.unknown,
        reason: 'Κοινόχρηστο τηλέφωνο τμήματος — καθαρή προσθήκη',
      );
    });

    test('νέο τμήμα σε υπάρχοντα υπάλληλο → κόκκινο (μετακίνηση)', () async {
      final c = await _alexandraWorld();
      addTearDown(c.dispose);

      _commitCaller(c, 'Αλεξάνδρα Νικολάου');
      _n(c).updateDepartmentText('Νέο Τμήμα Χ');
      _focusOut(
        c,
        phone: '2542',
        caller: 'Αλεξάνδρα Νικολάου',
        department: 'Νέο Τμήμα Χ',
        equipment: '3694',
      );
      // Επικύρωση ελεύθερου κειμένου τμήματος μέσω καθαρισμού+επαναφοράς άλλου
      // πεδίου: το τμήμα δεν έχει δικό του lookup για ελεύθερο κείμενο (§Ζ.4).
      _commitPhone(c, '2542');

      expect(
        _read(c).conflictSeverityFor(SelectorField.department),
        ConflictSeverity.mismatch,
        reason: 'Η Αλεξάνδρα έχει ήδη τμήμα — θα μετακινηθεί',
      );
    });
  });

  // ═══════════════════ §Α.5.α — ουδέτερα ζεύγη ═══════════════════
  group('§Α.5.α — ορφανές οντότητες δεν κοκκινίζουν', () {
    test('υπάλληλος χωρίς τμήμα + τμήμα → ουδέτερο', () async {
      final orphan = UserModel(
        id: 7,
        firstName: 'Ορφανός',
        lastName: 'Χρήστης',
        phones: PhoneListParser.splitPhones('2777'),
      );
      final c = await _openContainer(users: [orphan], equipment: const []);
      addTearDown(c.dispose);

      _commitCaller(c, 'Ορφανός Χρήστης');
      _commitDepartment(c, _kAimodosia, _kAimodosiaName);

      expect(
        _read(c).conflictSeverityFor(SelectorField.caller),
        isNull,
        reason: 'Δεν ξέρουμε ότι διαφωνούν — δεν υπάρχει τμήμα να συγκρίνουμε',
      );
      expect(_read(c).conflictSeverityFor(SelectorField.department), isNull);
    });

    test(
      'εξοπλισμός χωρίς τμήμα και χωρίς κάτοχο → ουδέτερος παντού',
      () async {
        final orphanPc = EquipmentModel(id: 108, code: '9999');
        final c = await _openContainer(
          users: [_alexandra()],
          equipment: [orphanPc],
        );
        addTearDown(c.dispose);

        _commitCaller(c, 'Αλεξάνδρα Νικολάου');
        _commitEquipment(c, '9999');

        expect(_read(c).conflictSeverityFor(SelectorField.equipment), isNull);
        expect(_read(c).conflictSeverityFor(SelectorField.caller), isNull);
      },
    );
  });

  // ═══════════════════ §Α.4.β / §Α.5.β — οριακά ═══════════════════
  group('§Α.4.β & §Α.5.β — δύο άγνωστα και μικρά τηλέφωνα', () {
    test(
      'δύο άγνωστα χωρίς καμία γνωστή οντότητα → μόνο η μονομερής',
      () async {
        final c = await _openContainer(
          users: [_alexandra()],
          equipment: const [],
        );
        addTearDown(c.dispose);

        _commitPhone(c, '2543');
        _commitEquipment(c, '3695');

        final s = _read(c);
        expect(
          s.conflictTooltipFor(SelectorField.phone),
          'Δεν είναι καταχωρημένο στη βάση',
        );
        expect(
          s.conflictTooltipFor(SelectorField.equipment),
          'Δεν είναι καταχωρημένο στη βάση',
        );
      },
    );

    test('τηλέφωνο < 3 ψηφία αγνοείται εντελώς', () async {
      final c = await _alexandraWorld();
      addTearDown(c.dispose);

      _commitCaller(c, 'Αλεξάνδρα Νικολάου');
      _commitPhone(c, '25');

      expect(
        _read(c).conflictSeverityFor(SelectorField.phone),
        isNull,
        reason: 'Ημιτελής πληκτρολόγηση, όχι τιμή (§Α.5.β)',
      );
      expect(_read(c).conflictSeverityFor(SelectorField.caller), isNull);
    });
  });

  // ═══════════════════ §Α.6 — φόρτωση έτοιμης φόρμας ═══════════════════
  group('§Α.6 — φορτωμένη φόρμα: δείκτες ναι, άγκυρα όχι', () {
    test('loadFromTask δεν ορίζει άγκυρα αλλά υπολογίζει σχέσεις', () async {
      final c = await _alexandraWorld();
      addTearDown(c.dispose);

      await _n(c).loadFromTask(
        Task(
          title: 'Δοκιμή φόρτωσης',
          dueDate: '2026-07-27',
          status: 'open',
          callerId: 2,
          userText: 'Αλεξάνδρα Νικολάου',
          phoneText: '2542',
          departmentText: _kAimodosiaName,
        ),
      );

      final s = _read(c);
      expect(
        s.conflictSeverityFor(SelectorField.department),
        ConflictSeverity.mismatch,
        reason: 'Η πληροφορία «άλλαξε τμήμα» είναι αληθινή',
      );
      expect(s.anchorField, isNull, reason: 'Κανείς δεν επικύρωσε τίποτα');
      for (final f in SelectorField.values) {
        expect(s.isAnchorHighlighted(f), isFalse);
      }
    });
  });

  // ═══════════════════ Το δύσκολο σενάριο ═══════════════════
  group('Δύσκολο σενάριο — Ν υποψήφιοι, κοινόχρηστα, μετακίνηση άγκυρας', () {
    /// 2100 κοινόχρηστο Γραμματείας · 4040 με δύο κατόχους σε δύο τμήματα ·
    /// δύο ομώνυμοι «Γιώργος Παππάς» σε Γραμματεία και Μαγειρείο.
    Future<ProviderContainer> world() => _openContainer(
      users: [
        UserModel(
          id: 3,
          firstName: 'Νίκος',
          lastName: 'Ζώης',
          departmentId: _kGrammateia,
        ),
        UserModel(
          id: 4,
          firstName: 'Μαρία',
          lastName: 'Κοντού',
          departmentId: _kAktinologiko,
        ),
        UserModel(
          id: 5,
          firstName: 'Γιώργος',
          lastName: 'Παππάς',
          departmentId: _kGrammateia,
        ),
        UserModel(
          id: 6,
          firstName: 'Γιώργος',
          lastName: 'Παππάς',
          departmentId: _kMageireio,
        ),
      ],
      equipment: [EquipmentModel(id: 104, code: '4040')],
      links: {
        3: <int>[104],
        4: <int>[104],
      },
      departmentPhones: {
        _kGrammateia: ['2100'],
      },
    );

    test('ένας από τους Ν υποψηφίους αρκεί για σιωπή', () async {
      final c = await world();
      addTearDown(c.dispose);

      _commitEquipment(c, '4040');
      expect(
        _read(c).selectedCaller,
        isNull,
        reason: '§Δ.3: δύο κάτοχοι → λίστα, ποτέ αυτόματη επιλογή',
      );
      _commitPhone(c, '2100');
      _commitCaller(c, 'Γιώργος Παππάς');

      final s = _read(c);
      expect(
        s.conflictSeverityFor(SelectorField.phone),
        isNull,
        reason:
            'Το 2100 είναι της Γραμματείας· δένει και με τον Γιώργο#Γραμματείας '
            'και με τον 4040 μέσω Νίκου Ζώη (§Α.9: αρκεί ένας υποψήφιος)',
      );
      // Κανένας από τους δύο Γιώργους δεν κατέχει τον 4040 (κάτοχοι: Ζώης,
      // Κοντού) — το ζεύγος σπάει, συμμετρικά και στα δύο μέλη.
      expect(
        s.conflictSeverityFor(SelectorField.caller),
        ConflictSeverity.mismatch,
      );
      expect(
        s.conflictSeverityFor(SelectorField.equipment),
        ConflictSeverity.mismatch,
      );
      expect(
        s.conflictTooltipFor(SelectorField.caller)!.split('\n'),
        ['Γιώργος Παππάς — δεν σχετίζεται με τον εξοπλισμό 4040'],
        reason: 'Μόνο αυτή η σχέση λείπει — οι άλλες δύο δένουν',
      );
      expect(s.anchorField, SelectorField.equipment);
    });

    test('καθαρισμός της άγκυρας τη μεταφέρει στο επόμενο', () async {
      final c = await world();
      addTearDown(c.dispose);

      _commitEquipment(c, '4040');
      _commitPhone(c, '2100');
      _commitCaller(c, 'Γιώργος Παππάς');
      expect(_read(c).anchorField, SelectorField.equipment);

      _n(c).clearEquipment();

      expect(
        _read(c).anchorField,
        SelectorField.phone,
        reason: 'Η άγκυρα περνά στο επόμενο κατά σειρά επικύρωσης (§Α.6)',
      );
    });
  });
}
