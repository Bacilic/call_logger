// Η οθόνη «Διαχείριση λεξικού» με πραγματική βάση: τι φορτώνει, τι γράφει
// μια επεξεργασία ή μια διαγραφή, και πότε μια λέξη φεύγει από τη λίστα.
//
//   flutter test test/features/dictionary/dictionary_manager_screen_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/features/dictionary/providers/lexicon_ai_review_provider.dart';
import 'package:call_logger/features/dictionary/screens/dictionary_manager_screen.dart';
import 'package:call_logger/features/dictionary/services/lexicon_ai_prompts.dart';
import 'package:call_logger/features/dictionary/services/lexicon_ai_review_service.dart';
import 'package:call_logger/features/dictionary/widgets/dictionary_grid_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

Future<void> _seed() async {
  final db = await DatabaseHelper.instance.database;
  await db.delete('full_dictionary');
  await db.delete('user_dictionary');
  Future<void> full(String word, String norm, String category) =>
      db.insert('full_dictionary', {
        'word': word,
        'normalized_word': norm,
        'source': 'imported',
        'language': 'el',
        'category': category,
        'letters_count': norm.length,
      });
  await full('Αλφα', 'αλφα', 'Γενική');
  await full('Βήτα', 'βητα', 'Γενική');
  await full('Γάμμα', 'γαμμα', 'Ιατρική');
  // Πρόχειρο: λέξη του Λεξικού Χρήστη χωρίς εγγραφή στο Πλήρες Λεξικό.
  await db.insert('user_dictionary', {
    'word': 'δελτα',
    'display_word': 'Δέλτα',
    'language': 'el',
    'letters_count': 5,
  });
}

/// Αφήνει τις πραγματικές εργασίες της βάσης να ολοκληρωθούν.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  });
  await tester.pump();
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  LexiconAiReviewRunner? aiReview,
}) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.runAsync(_seed);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...callLoggerTestProviderOverrides(),
        if (aiReview != null)
          lexiconAiReviewRunnerProvider.overrideWithValue(aiReview),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: DictionaryManagerScreen(
            databaseResult: DatabaseInitResult.success(),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  await _settle(tester);
}

List<Map<String, dynamic>> _rows(WidgetTester tester) => tester
    .widgetList<DictionaryGridRow>(find.byType(DictionaryGridRow))
    .map((r) => r.row)
    .toList();

List<String> _words(WidgetTester tester) =>
    _rows(tester).map((r) => r['display_word'] as String).toList();

Finder _rowOf(String word) => find.byWidgetPredicate(
  (w) => w is DictionaryGridRow && w.row['display_word'] == word,
);

Finder _wordFieldOf(String word) =>
    find.descendant(of: _rowOf(word), matching: find.byType(TextField));

Future<void> _editWord(WidgetTester tester, String from, String to) async {
  await tester.tap(_wordFieldOf(from));
  await tester.pump();
  await tester.enterText(_wordFieldOf(from), to);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await _settle(tester);
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Αναζήτηση (normalized)'),
    text,
  );
  await tester.pump(const Duration(milliseconds: 350));
  await _settle(tester);
}

Future<Map<String, Object?>?> _fullEntry(String normalized) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query(
    'full_dictionary',
    where: 'normalized_word = ?',
    whereArgs: [normalized],
  );
  return rows.isEmpty ? null : rows.single;
}

Finder _selectBoxOf(String word) =>
    find.descendant(of: _rowOf(word), matching: find.byType(Checkbox));

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 11));
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  testWidgets('φορτώνει Πλήρες Λεξικό και πρόχειρο μαζί, με το σύνολό τους', (
    tester,
  ) async {
    await _pumpScreen(tester);

    expect(_words(tester), ['Αλφα', 'Βήτα', 'Γάμμα', 'Δέλτα']);
    final draft = _rows(tester).last;
    expect(draft['entry_id'], isNull);
    expect(draft['src'], 'draft');
    expect(find.text('Σύνολο: 4'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('η αναζήτηση στενεύει τη λίστα και το σύνολο', (tester) async {
    await _pumpScreen(tester);

    await _search(tester, 'βητα');

    expect(_words(tester), ['Βήτα']);
    expect(find.text('Σύνολο: 1'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets(
    'αλλαγή κατηγορίας γράφεται στη βάση και η λέξη μένει στη λίστα',
    (tester) async {
      await _pumpScreen(tester);

      await tester.tap(
        find.descendant(
          of: _rowOf('Αλφα'),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Όνομα').last);
      await tester.pump(const Duration(milliseconds: 300));
      await _settle(tester);

      final entry = await tester.runAsync(() => _fullEntry('αλφα'));
      expect(entry?['category'], 'Όνομα');
      expect(_words(tester), ['Αλφα', 'Βήτα', 'Γάμμα', 'Δέλτα']);
      expect(_rows(tester).first['cat'], 'Όνομα');
      await _finish(tester);
    },
  );

  testWidgets('λέξη που μετονομάζεται εκτός αναζήτησης φεύγει από τη λίστα', (
    tester,
  ) async {
    await _pumpScreen(tester);
    await _search(tester, 'αλφ');
    expect(_words(tester), ['Αλφα']);

    await _editWord(tester, 'Αλφα', 'Ωμέγα');

    final renamed = await tester.runAsync(() async {
      final db = await DatabaseHelper.instance.database;
      return db.query('full_dictionary', where: "word = 'Ωμέγα'");
    });
    expect(renamed, hasLength(1));
    expect(
      renamed!.single['source'],
      'user',
      reason: 'η διόρθωση με το χέρι είναι έλεγχος από άνθρωπο',
    );
    expect(await tester.runAsync(() => _fullEntry('αλφα')), isNull);
    expect(_words(tester), isEmpty);
    expect(find.text('Σύνολο: 0'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('αλλαγή κατηγορίας προχείρου το προάγει στο Πλήρες Λεξικό', (
    tester,
  ) async {
    await _pumpScreen(tester);

    await tester.tap(
      find.descendant(
        of: _rowOf('Δέλτα'),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Όνομα').last);
    await tester.pump(const Duration(milliseconds: 300));
    await _settle(tester);

    final promoted = await tester.runAsync(() => _fullEntry('δελτα'));
    expect(promoted?['word'], 'Δέλτα');
    expect(promoted?['source'], 'user');
    expect(promoted?['category'], 'Όνομα');
    final row = _rows(tester).last;
    expect(row['entry_id'], promoted?['id']);
    expect(row['src'], 'user');
    await _finish(tester);
  });

  // Φωτογραφία της σημερινής συμπεριφοράς, όχι της σωστής: η μετονομασία
  // προχείρου γράφει τη νέα λέξη με την ΠΑΛΙΑ κανονικοποιημένη μορφή, και η
  // οθόνη — που ψάχνει με τη νέα — τη δείχνει ακόμη ως πρόχειρο. Καταγράφηκε
  // στο Πρόχειρο του roadmap για ξεχωριστή διόρθωση.
  testWidgets(
    'μετονομασία προχείρου: μπαίνει στο Πλήρες Λεξικό με τη νέα ορθογραφία',
    (tester) async {
      await _pumpScreen(tester);

      await _editWord(tester, 'Δέλτα', 'Δέλτας');

      final written = await tester.runAsync(() => _fullEntry('δελτας'));
      expect(written?['word'], 'Δέλτας');
      expect(written?['source'], 'user');
      expect(await tester.runAsync(() => _fullEntry('δελτα')), isNull);
      final row = _rows(tester).last;
      expect(row['display_word'], 'Δέλτας');
      expect(row['norm_key'], 'δελτας');
      expect(row['entry_id'], isNotNull);
      expect(row['src'], isNot('draft'));
      await _finish(tester);
    },
  );

  testWidgets(
    'μετονομασία προχείρου σε λέξη που υπάρχει ήδη: μήνυμα, η υπάρχουσα μένει ανέγγιχτη',
    (tester) async {
      await _pumpScreen(tester);

      await _editWord(tester, 'Δέλτα', 'Γάμμα');

      expect(find.textContaining('υπάρχει ήδη στο λεξικό'), findsOneWidget);
      final existing = await tester.runAsync(() => _fullEntry('γαμμα'));
      expect(existing?['category'], 'Ιατρική');
      await _finish(tester);
    },
  );

  testWidgets('διαγραφή με επιβεβαίωση σβήνει από τη βάση και τη λίστα', (
    tester,
  ) async {
    await _pumpScreen(tester);

    await tester.tap(
      find.descendant(of: _rowOf('Βήτα'), matching: find.byTooltip('Διαγραφή')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Διαγραφή «Βήτα»;'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Διαγραφή'));
    await tester.pump(const Duration(milliseconds: 300));
    await _settle(tester);

    final entry = await tester.runAsync(() => _fullEntry('βητα'));
    expect(entry, isNull);
    expect(_words(tester), ['Αλφα', 'Γάμμα', 'Δέλτα']);
    expect(find.text('Σύνολο: 3'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('ο διάλογος νέων λέξεων τις γράφει και η λίστα ξαναφορτώνεται', (
    tester,
  ) async {
    await _pumpScreen(tester);

    await tester.tap(
      find.byTooltip('Προσθήκη λέξεων στο λεξικό (πολλές, με κενά ή κόμμα)'),
    );
    await _settle(tester);
    expect(find.text('Νέες λέξεις στο λεξικό'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Λέξεις'),
      'Έψιλον, Ζήτα',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Προσθήκη'));
    await _settle(tester);
    await _settle(tester);

    expect(find.text('Νέες λέξεις στο λεξικό'), findsNothing);
    expect(find.text('Οι λέξεις προστέθηκαν στο λεξικό'), findsOneWidget);
    final added = await tester.runAsync(() => _fullEntry('εψιλον'));
    expect(added?['word'], 'Έψιλον');
    expect(_words(tester), containsAll(<String>['Έψιλον', 'Ζήτα']));
    expect(find.text('Σύνολο: 6'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('κουτάκι για μία λέξη, Shift + κλικ για περιοχή', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(_selectBoxOf('Αλφα'));
    await tester.pump();
    expect(find.text('Επιλεγμένες: 1'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(_selectBoxOf('Γάμμα'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.text('Επιλεγμένες: 3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.textContaining('Καμία επιλεγμένη λέξη'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets(
    'Έλεγχος με ΤΝ: γράφονται μόνο τα τσεκαρισμένα, οι σωστές γίνονται «Χρήστης»',
    (tester) async {
      List<String>? sent;
      await _pumpScreen(
        tester,
        aiReview: (words) async {
          sent = words;
          return const LexiconAiReviewed({
            1: LexiconAiVerdict(
              kind: LexiconAiVerdictKind.fix,
              suggestion: 'Άλφα',
              sure: true,
            ),
            2: LexiconAiVerdict(kind: LexiconAiVerdictKind.delete, sure: true),
            3: LexiconAiVerdict(kind: LexiconAiVerdictKind.correct, sure: true),
            // Αβέβαιη: μένει ατσεκάριστη, άρα ανέγγιχτη.
            4: LexiconAiVerdict(kind: LexiconAiVerdictKind.delete, sure: false),
          });
        },
      );

      await tester.tap(find.byTooltip('Επιλογή όλης της σελίδας'));
      await tester.pump();
      await tester.tap(find.text('Έλεγχος με ΤΝ'));
      await _settle(tester);

      expect(sent, ['Αλφα', 'Βήτα', 'Γάμμα', 'Δέλτα']);
      expect(find.text('Εφαρμογή 3 επιλεγμένων'), findsOneWidget);
      await tester.tap(find.text('Εφαρμογή 3 επιλεγμένων'));
      await _settle(tester);
      await _settle(tester);

      final fixed = await tester.runAsync(() => _fullEntry('αλφα'));
      expect(fixed?['word'], 'Άλφα');
      expect(fixed?['source'], 'user');
      expect(await tester.runAsync(() => _fullEntry('βητα')), isNull);
      expect(
        (await tester.runAsync(() => _fullEntry('γαμμα')))?['source'],
        'user',
      );
      expect(_words(tester), contains('Δέλτα'));
      expect(find.textContaining('Καμία επιλεγμένη λέξη'), findsOneWidget);
      expect(
        find.textContaining('Διορθώθηκαν 1 · διαγράφηκαν 1'),
        findsOneWidget,
      );
      await _finish(tester);
    },
  );

  testWidgets('Άκυρο στο παράθυρο ελέγχου: τίποτα δεν γράφεται', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      aiReview: (words) async => const LexiconAiReviewed({
        1: LexiconAiVerdict(kind: LexiconAiVerdictKind.delete, sure: true),
      }),
    );

    await tester.tap(_selectBoxOf('Αλφα'));
    await tester.pump();
    await tester.tap(find.text('Έλεγχος με ΤΝ'));
    await _settle(tester);
    await tester.tap(find.text('Άκυρο'));
    await _settle(tester);

    expect(await tester.runAsync(() => _fullEntry('αλφα')), isNotNull);
    expect(find.text('Επιλεγμένες: 1'), findsOneWidget);
    await _finish(tester);
  });
}
