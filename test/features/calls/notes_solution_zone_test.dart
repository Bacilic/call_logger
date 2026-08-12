// Η ζώνη «Λύση» του χαρτιού σημειώσεων: το chip κατεβάζει τη γραμμή του
// κέρσορα, η υποβολή γράφει τη λύση στην κλήση με ίχνος «χειρόγραφο», και η
// Εκκαθάριση της φόρμας την αδειάζει μαζί με όλα τα υπόλοιπα.
//
//   flutter test test/features/calls/notes_solution_zone_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/call_refined_source.dart';
import 'package:call_logger/features/calls/provider/call_entry_provider.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/widgets/notes_sticky_field.dart';
import 'package:call_logger/features/calls/utils/notes_solution_split.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

const _kProblemLine = 'Ο εκτυπωτης εχει κοκκινο λαμπακι';
const _kSolutionLine = 'Εγινε αλλαγη τονερ';

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Ζώνη «Λύση» στο χαρτί σημειώσεων', () {
    setUpAll(() async {
      GoogleFonts.config.allowRuntimeFetching = false;
      await seedTestCallRowForHistorySearch();
    });

    Future<ProviderContainer> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      late ProviderContainer container;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: callLoggerTestProviderOverrides(),
            child: const MyApp(showStartupSplash: false),
          ),
        );
        await tester.pump();
        await pumpUntilSettledLong(tester);
        await GoogleFonts.pendingFonts();
        container = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
        );
        await container.read(lookupServiceProvider.future);
      });
      return container;
    }

    // Η οθόνη ξεκινά συμπτυγμένη — το χαρτί σημειώσεων εμφανίζεται μόνο αφού
    // ολοκληρωθεί η καταχώρηση τηλεφώνου (ίδια χορογραφία debounce/blur με το
    // happy path του call_form_test).
    Future<void> expandFormWithPhone(WidgetTester tester) async {
      final phoneField = callLoggerPhoneTextField();
      await tester.tap(phoneField);
      await pumpUntilSettled(tester);
      await tester.enterText(phoneField, kTestPhoneDigits);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await pumpUntilSettled(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 450));
      await pumpUntilSettled(
        tester,
        steps: 40,
        step: const Duration(milliseconds: 60),
      );
      await pumpUntilSettledLong(tester);
    }

    Finder notesField() => find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          (w.decoration?.hintText?.contains('Περιγραφή κλήσης') ?? false),
    );

    Finder solutionField() => find.byWidgetPredicate(
      (w) =>
          w is TextField && (w.decoration?.hintText?.contains('Λύση') ?? false),
    );

    Finder solutionChip() => find.descendant(
      of: find.byType(NotesStickyField),
      matching: find.text('Λύση'),
    );

    testWidgets('το chip κατεβάζει τη γραμμή του κέρσορα στη ζώνη Λύσης', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await expandFormWithPhone(tester);

      await tester.tap(notesField());
      await pumpUntilSettled(tester);
      await tester.enterText(notesField(), '$_kProblemLine\n$_kSolutionLine');
      await pumpUntilSettled(tester);

      expect(
        solutionField(),
        findsNothing,
        reason: greekExpectMsg('Η ζώνη Λύσης ξεκινά κλειστή'),
      );

      await tester.tap(solutionChip());
      await pumpUntilSettled(tester);

      final entry = container.read(callEntryProvider);
      expect(
        entry.notes.trim(),
        _kProblemLine,
        reason: greekExpectMsg('Στις σημειώσεις μένει μόνο το πρόβλημα'),
      );
      expect(
        entry.solution,
        _kSolutionLine,
        reason: greekExpectMsg('Η γραμμή του κέρσορα έγινε λύση'),
      );
      expect(
        solutionField(),
        findsOneWidget,
        reason: greekExpectMsg('Η ζώνη Λύσης άνοιξε και είναι ορατή'),
      );
    }, semanticsEnabled: false, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('μοναδική γραμμή δεν μεταφέρεται — το χαρτί δεν αδειάζει', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await expandFormWithPhone(tester);

      await tester.tap(notesField());
      await pumpUntilSettled(tester);
      await tester.enterText(notesField(), _kProblemLine);
      await pumpUntilSettled(tester);

      await tester.tap(solutionChip());
      await pumpUntilSettled(tester);

      final entry = container.read(callEntryProvider);
      expect(entry.notes.trim(), _kProblemLine);
      expect(entry.solution, isEmpty);
      expect(
        solutionField(),
        findsOneWidget,
        reason: greekExpectMsg(
          'Η ζώνη ανοίγει κενή — έτοιμη να γραφτεί η λύση',
        ),
      );
    }, semanticsEnabled: false, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('η υποβολή γράφει τη λύση στην κλήση με ίχνος «χειρόγραφο»', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await expandFormWithPhone(tester);

      await tester.tap(notesField());
      await pumpUntilSettled(tester);
      await tester.enterText(notesField(), '$_kProblemLine\n$_kSolutionLine');
      await pumpUntilSettled(tester);
      await tester.tap(solutionChip());
      await pumpUntilSettled(tester);

      final submitOk = await tester.runAsync(
        () => container.read(callEntryProvider.notifier).submitCall(),
      );
      expect(
        submitOk,
        isTrue,
        reason: greekExpectMsg('Η υποβολή πρέπει να ολοκληρωθεί'),
      );
      await tester.pump();

      final saved = await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        return db.query(
          'calls',
          where: 'issue LIKE ?',
          whereArgs: ['%$_kProblemLine%'],
        );
      });
      expect(saved, hasLength(1));
      final row = saved!.single;
      expect(row['issue'], _kProblemLine);
      expect(row['solution'], _kSolutionLine);
      expect(row['refined_source'], CallRefinedSource.manual);
      expect((row['refined_at'] as String?)?.isNotEmpty, isTrue);

      // Μετά την υποβολή η φόρμα καθάρισε — και η ζώνη Λύσης μαζί της.
      final entry = container.read(callEntryProvider);
      expect(entry.notes, isEmpty);
      expect(entry.solution, isEmpty);
    }, semanticsEnabled: false, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('υποβολή χωρίς λύση δεν αφήνει ίχνος εξευγενισμού', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await expandFormWithPhone(tester);

      await tester.tap(notesField());
      await pumpUntilSettled(tester);
      const plainNote = 'σκετη σημειωση χωρις λυση';
      await tester.enterText(notesField(), plainNote);
      await pumpUntilSettled(tester);

      final submitOk = await tester.runAsync(
        () => container.read(callEntryProvider.notifier).submitCall(),
      );
      expect(submitOk, isTrue);
      await tester.pump();

      final saved = await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        return db.query(
          'calls',
          where: 'issue LIKE ?',
          whereArgs: ['%$plainNote%'],
        );
      });
      expect(saved, hasLength(1));
      expect(saved!.single['solution'], isNull);
      expect(saved.single['refined_source'], isNull);
    }, semanticsEnabled: false, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('ΕΝΑΣ μετρητής για όλο το χαρτί — περιγραφή συν λύση', (
      tester,
    ) async {
      await pumpApp(tester);
      await expandFormWithPhone(tester);

      await tester.tap(notesField());
      await pumpUntilSettled(tester);
      await tester.enterText(notesField(), '123456\nλ');
      await pumpUntilSettled(tester);

      expect(
        find.text('8 / $kNotesTotalMaxLength'),
        findsOneWidget,
        reason: greekExpectMsg('Μόνο περιγραφή: 8 χαρακτήρες'),
      );

      await tester.tap(solutionChip());
      await pumpUntilSettled(tester);
      await tester.enterText(solutionField(), 'τονερ');
      await pumpUntilSettled(tester);

      // 6 («123456») + 5 («τονερ») — η γραμμή «λ» κατέβηκε και ξαναγράφτηκε.
      expect(
        find.text('11 / $kNotesTotalMaxLength'),
        findsOneWidget,
        reason: greekExpectMsg('Ο μετρητής αθροίζει τα δύο πεδία'),
      );
      expect(
        find.textContaining('/ $kNotesTotalMaxLength'),
        findsOneWidget,
        reason: greekExpectMsg('Υπάρχει ΜΟΝΟ ένας μετρητής στο χαρτί'),
      );
    }, semanticsEnabled: false, timeout: const Timeout(Duration(minutes: 2)));
  });
}
