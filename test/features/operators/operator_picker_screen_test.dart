// Η οθόνη «Ποιος είστε;»: τι προσφέρει, τι εμποδίζει και τι παραδίδει.
//
//   flutter test test/features/operators/operator_picker_screen_test.dart

import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/features/operators/screens/operator_picker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Operator _profile(String name) =>
    Operator(displayName: name, createdAt: DateTime(2026, 8, 20));

void main() {
  group('Οθόνη επιλογής χρήστη', () {
    late List<String> picked;
    late List<(String, bool)> created;

    setUp(() {
      picked = [];
      created = [];
    });

    Future<void> pump(
      WidgetTester tester, {
      required List<Operator> profiles,
      String suggestedName = 'v.drosos',
      bool hasWindowsAccount = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OperatorPickerScreen(
            profiles: profiles,
            suggestedName: suggestedName,
            hasWindowsAccount: hasWindowsAccount,
            onPick: (operator) => picked.add(operator.displayName),
            onCreate: (name, bind) async => created.add((name, bind)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('με προφίλ: επιλογή ονόματος παραδίδει τον χρήστη', (
      tester,
    ) async {
      await pump(tester, profiles: [_profile('Βασίλης'), _profile('Σωτήρης')]);

      expect(find.text('Σωτήρης'), findsOneWidget);
      await tester.tap(find.text('Σωτήρης'));

      expect(picked, ['Σωτήρης']);
      expect(created, isEmpty);
    });

    testWidgets('πρώτη εκκίνηση: χωρίς προφίλ ανοίγει κατευθείαν η φόρμα', (
      tester,
    ) async {
      await pump(tester, profiles: const []);

      expect(find.widgetWithText(FilledButton, 'Συνέχεια'), findsOneWidget);
      expect(
        find.text('Δεν είμαι στη λίστα'),
        findsNothing,
        reason: 'δεν υπάρχει λίστα για να επιστρέψει κανείς',
      );
    });

    testWidgets('το προτεινόμενο όνομα είναι ο λογαριασμός Windows', (
      tester,
    ) async {
      await pump(tester, profiles: const []);

      expect(find.text('v.drosos'), findsOneWidget);
    });

    testWidgets('κενό όνομα: μήνυμα και καμία δημιουργία', (tester) async {
      await pump(tester, profiles: const [], suggestedName: '');

      await tester.tap(find.widgetWithText(FilledButton, 'Συνέχεια'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Δώστε όνομα'), findsOneWidget);
      expect(created, isEmpty);
    });

    testWidgets('κοινόχρηστος υπολογιστής: το δέσιμο φεύγει από την επιλογή', (
      tester,
    ) async {
      await pump(tester, profiles: const []);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Συνέχεια'));
      await tester.pumpAndSettle();

      expect(created, [('v.drosos', false)]);
    });

    testWidgets('δικός μου υπολογιστής: το δέσιμο είναι η προεπιλογή', (
      tester,
    ) async {
      await pump(tester, profiles: const []);

      await tester.enterText(find.byType(TextField), 'Βασίλης Δρόσος');
      await tester.tap(find.widgetWithText(FilledButton, 'Συνέχεια'));
      await tester.pumpAndSettle();

      expect(created, [('Βασίλης Δρόσος', true)]);
    });

    testWidgets('χωρίς λογαριασμό Windows δεν προσφέρεται δέσιμο', (
      tester,
    ) async {
      await pump(
        tester,
        profiles: const [],
        suggestedName: '',
        hasWindowsAccount: false,
      );

      expect(find.byType(CheckboxListTile), findsNothing);
    });

    testWidgets('«Δεν είμαι στη λίστα» ανοίγει τη φόρμα και επιστρέφει', (
      tester,
    ) async {
      await pump(tester, profiles: [_profile('Βασίλης')]);

      await tester.tap(find.text('Δεν είμαι στη λίστα'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Συνέχεια'), findsOneWidget);

      await tester.tap(find.text('Επιστροφή στη λίστα'));
      await tester.pumpAndSettle();
      expect(find.text('Βασίλης'), findsOneWidget);
    });
  });
}
