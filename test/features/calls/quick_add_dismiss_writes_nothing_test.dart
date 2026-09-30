// Ακύρωση διαλόγου του «+» (κουμπί ή κλικ έξω) = τίποτα δεν γράφεται.
//
// Χρειάζεται πραγματική οθόνη (οι διάλογοι ανοίγουν) ΚΑΙ πραγματική βάση — γι'
// αυτό ζει σε δικό του αρχείο, με τη βάση πάντα μέσα σε `runAsync`.
//
//   flutter test test/features/calls/quick_add_dismiss_writes_nothing_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/association_two_step_runner.dart';
import '../../test_setup.dart';

typedef _Seeded = ({ProviderContainer container, int koika});

/// Κόικα στις Άδειες με προσωπικό 2519· το 2858 είναι κοινό του Χρηματικού.
Future<_Seeded> _seed() async {
  await AssociationTwoStepRunner.resetCatalog();
  final db = await DatabaseHelper.instance.database;
  Future<int> department(String name) => db.insert('departments', {
    'name': name,
    'name_key': SearchTextNormalizer.normalizeForSearch(name),
    'is_deleted': 0,
  });
  final leaves = await department('Άδειες');
  await department('Βιοχημικό');
  final treasury = await department('Χρηματικό');
  await db.insert('phones', {'number': '2858', 'department_id': treasury});
  final koika = await db.insert('users', {
    'first_name': 'Βασιλική',
    'last_name': 'Κόικα',
    'department_id': leaves,
    'is_deleted': 0,
  });
  final personal = await db.insert('phones', {'number': '2519'});
  await db.insert('user_phones', {'user_id': koika, 'phone_id': personal});
  // 3248: προσωπικός εξοπλισμός της Πλακογιάννη, σε άλλο τμήμα.
  final biomedical = await department('Βιοϊατρική');
  final plakogianni = await db.insert('users', {
    'first_name': 'Ελένη',
    'last_name': 'Πλακογιάννη',
    'department_id': biomedical,
    'is_deleted': 0,
  });
  final equipment = await db.insert('equipment', {
    'code_equipment': '3248',
    'is_deleted': 0,
  });
  await db.insert('user_equipment', {
    'user_id': plakogianni,
    'equipment_id': equipment,
  });
  LookupService.instance.resetForReload();
  await LookupService.instance.loadFromDatabase();
  final container = ProviderContainer(
    overrides: callLoggerTestProviderOverrides(),
  );
  await container.read(lookupServiceProvider.future);
  return (container: container, koika: koika);
}

/// «Ακύρωση» — για όσους δεν κλείνουν με κλικ έξω.
Future<void> _tapCancel(WidgetTester tester) =>
    tester.tap(find.widgetWithText(TextButton, 'Ακύρωση'));

/// Τρέχει το «+», περιμένει τον διάλογο, του απαντά με [answer], και
/// επιστρέφει το μήνυμα της καταχώρησης.
Future<String?> _associateAndAnswer(
  WidgetTester tester,
  _Seeded seeded, {
  required Future<void> Function(WidgetTester) answer,
  bool updatePrimaryDepartment = false,
}) async {
  late BuildContext screen;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: seeded.container,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            screen = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    ),
  );

  late Future<String?> pending;
  await tester.runAsync(() async {
    pending = seeded.container
        .read(callSmartEntityProvider.notifier)
        .associateCurrentIfNeeded(
          updatePrimaryDepartment: updatePrimaryDepartment,
          context: screen,
        );
    for (var i = 0; i < 100; i++) {
      await tester.pump();
      if (find.byType(Dialog).evaluate().isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  expect(find.byType(Dialog), findsOneWidget, reason: 'ο διάλογος άνοιξε');

  await answer(tester);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  String? message;
  await tester.runAsync(() async {
    message = await pending;
  });
  return message;
}

Future<List<Object?>> _equipmentOf(int userId) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.rawQuery(
    'SELECT e.code_equipment FROM user_equipment ue '
    'JOIN equipment e ON e.id = ue.equipment_id WHERE ue.user_id = ?',
    [userId],
  );
  return rows.map((r) => r['code_equipment']).toList();
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  testWidgets('«Ακύρωση» στη σύγκρουση τηλεφώνου: ούτε ο εξοπλισμός γράφεται', (
    tester,
  ) async {
    final seeded = (await tester.runAsync(_seed))!;
    final notifier = seeded.container.read(callSmartEntityProvider.notifier);
    final lookup = LookupService.instance;
    notifier.updatePhone('2858');
    notifier.checkContent(phoneText: '2858');
    notifier.setCaller(lookup.findUserById(seeded.koika));
    notifier.checkContent(equipmentText: '3000');

    final message = await _associateAndAnswer(
      tester,
      seeded,
      answer: _tapCancel,
    );

    expect(message, isNull);
    await tester.runAsync(() async {
      expect(await _equipmentOf(seeded.koika), isEmpty);
      final db = await DatabaseHelper.instance.database;
      expect(await db.query('tasks'), isEmpty);
      expect(
        await db.query('equipment', where: "code_equipment = '3000'"),
        isEmpty,
        reason: 'Ο νέος εξοπλισμός δεν δημιουργείται καν',
      );
    });
    seeded.container.dispose();
  });

  testWidgets(
    '«Ακύρωση» στο «τι απογίνονται όσα κουβαλά»: τίποτα δεν γράφεται',
    (tester) async {
      final seeded = (await tester.runAsync(_seed))!;
      final notifier = seeded.container.read(callSmartEntityProvider.notifier);
      final lookup = LookupService.instance;
      notifier.setCaller(lookup.findUserById(seeded.koika));
      notifier.selectDepartment(lookup.findDepartmentByName('Βιοχημικό')!);
      notifier.checkContent(equipmentText: '3000');

      final message = await _associateAndAnswer(
        tester,
        seeded,
        answer: _tapCancel,
        updatePrimaryDepartment: true,
      );

      expect(message, isNull);
      await tester.runAsync(() async {
        expect(await _equipmentOf(seeded.koika), isEmpty);
        final db = await DatabaseHelper.instance.database;
        final department = (await db.rawQuery(
          'SELECT d.name FROM users u JOIN departments d '
          'ON d.id = u.department_id WHERE u.id = ?',
          [seeded.koika],
        )).single['name'];
        expect(department, 'Άδειες');
        expect(await db.query('tasks'), isEmpty);
      });
      seeded.container.dispose();
    },
  );

  group('νέος καλών σε νέο τμήμα, με κοινό τηλέφωνο άλλου τμήματος', () {
    void fillNewCaller(_Seeded seeded) {
      final notifier = seeded.container.read(callSmartEntityProvider.notifier);
      notifier.updatePhone('2858');
      notifier.checkContent(phoneText: '2858');
      notifier.updateDepartmentText('Νέο Τμήμα');
      notifier.checkContent(departmentText: 'Νέο Τμήμα');
      notifier.updateCallerDisplayText('Νέα Υπάλληλος');
      notifier.checkContent(callerText: 'Νέα Υπάλληλος');
    }

    testWidgets('«Ακύρωση»: ούτε υπάλληλος ούτε τμήμα δημιουργούνται', (
      tester,
    ) async {
      final seeded = (await tester.runAsync(_seed))!;
      fillNewCaller(seeded);
      expect(
        seeded.container.read(callSmartEntityProvider).needsNewCallerCreation,
        isTrue,
      );

      final message = await _associateAndAnswer(
        tester,
        seeded,
        answer: _tapCancel,
      );

      expect(message, isNull);
      await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        expect(await db.query('users', where: "first_name = 'Νέα'"), isEmpty);
        expect(
          await db.query('departments', where: "name = 'Νέο Τμήμα'"),
          isEmpty,
          reason: 'Το τμήμα δημιουργείται μόνο αφού απαντηθεί η ερώτηση',
        );
        expect(await db.query('tasks'), isEmpty);
      });
      seeded.container.dispose();
    });

    testWidgets('«μεταφορά στο τμήμα του» φέρνει το τηλέφωνο στο νέο τμήμα', (
      tester,
    ) async {
      final seeded = (await tester.runAsync(_seed))!;
      fillNewCaller(seeded);

      final message = await _associateAndAnswer(
        tester,
        seeded,
        answer: (tester) async {
          final options = find.descendant(
            of: find.byType(Dialog),
            matching: find.byWidgetPredicate((w) => w is RadioListTile),
          );
          expect(
            options,
            findsNWidgets(2),
            reason: 'Παραμονή ΚΑΙ μεταφορά, παρότι το τμήμα δεν υπάρχει ακόμη',
          );
          await tester.tap(options.last);
          await tester.pump();
          await tester.tap(find.text('Επιβεβαίωση'));
        },
      );

      expect(message, isNotNull);
      await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        final department = (await db.query(
          'departments',
          where: "name = 'Νέο Τμήμα'",
        )).single;
        final phone = (await db.query(
          'phones',
          where: "number = '2858'",
        )).single;
        expect(phone['department_id'], department['id']);
        final user = (await db.query(
          'users',
          where: "first_name = 'Νέα' OR last_name = 'Νέα'",
        )).single;
        final linked = await db.query(
          'user_phones',
          where: 'user_id = ? AND phone_id = ?',
          whereArgs: [user['id'], phone['id']],
        );
        expect(linked, hasLength(1));
      });
      seeded.container.dispose();
    });
  });

  testWidgets(
    '«Ναι, μεταφορά»: ο εξοπλισμός φεύγει από το άλλο τμήμα και πάει στον νέο καλούντα',
    (tester) async {
      final seeded = (await tester.runAsync(_seed))!;
      final notifier = seeded.container.read(callSmartEntityProvider.notifier);
      final lookup = LookupService.instance;
      notifier.updateCallerDisplayText('Νέα Υπάλληλος');
      notifier.checkContent(callerText: 'Νέα Υπάλληλος');
      notifier.selectDepartment(lookup.findDepartmentByName('Άδειες')!);
      notifier.checkContent(equipmentText: '3248');

      final message = await _associateAndAnswer(
        tester,
        seeded,
        answer: (tester) async {
          expect(find.textContaining('Πλακογιάννη'), findsOneWidget);
          await tester.tap(find.text('Ναι, μεταφορά'));
        },
      );

      expect(message, contains('3248'));
      await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        final newUser = (await db.query(
          'users',
          where: "first_name = 'Νέα' OR last_name = 'Νέα'",
        )).single;
        final owners = await db.rawQuery(
          'SELECT ue.user_id FROM user_equipment ue '
          'JOIN equipment e ON e.id = ue.equipment_id '
          "WHERE e.code_equipment = '3248'",
        );
        expect(owners.map((r) => r['user_id']), [
          newUser['id'],
        ], reason: 'Μεταφορά, όχι μοιρασιά ανάμεσα σε δύο τμήματα');
      });
      seeded.container.dispose();
    },
  );
}
