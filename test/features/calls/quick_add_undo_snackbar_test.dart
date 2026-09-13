// Snackbar γρήγορης καταχώρησης: δύο λέξεις-ενέργειες, καθεμιά στη δουλειά της.
//
// Το «Κλείσιμο» δεν αναιρεί τίποτα — η προσθήκη έχει ήδη γίνει και μένει.
//
//   flutter test test/features/calls/quick_add_undo_snackbar_test.dart

import 'package:call_logger/features/calls/screens/widgets/quick_add_undo_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpContent(
    WidgetTester tester, {
    required VoidCallback onUndo,
    required VoidCallback onDismiss,
    String message = 'Δημιουργήθηκε νέος χρήστης Μαρία Δαμανάκη',
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickAddUndoSnackBarContent(
            message: message,
            onUndo: onUndo,
            onDismiss: onDismiss,
          ),
        ),
      ),
    );
  }

  testWidgets('δείχνει το μήνυμα και τις δύο ενέργειες', (tester) async {
    await pumpContent(tester, onUndo: () {}, onDismiss: () {});

    expect(
      find.text('Δημιουργήθηκε νέος χρήστης Μαρία Δαμανάκη'),
      findsOneWidget,
    );
    expect(find.text('Αναίρεση'), findsOneWidget);
    expect(find.text('Κλείσιμο (10)'), findsOneWidget);
  });

  // Ο χρόνος τρέχει έτσι κι αλλιώς· αν δεν φαίνεται, ο χρήστης δεν ξέρει πόσο
  // έχει για να αποφασίσει.
  testWidgets('η μέτρηση φαίνεται και τρέχει αντίστροφα', (tester) async {
    await pumpContent(tester, onUndo: () {}, onDismiss: () {});

    expect(find.text('Κλείσιμο (10)'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Κλείσιμο (9)'), findsOneWidget);

    await tester.pump(const Duration(seconds: 8));
    expect(find.text('Κλείσιμο (1)'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('Κλείσιμο (0)'),
      findsOneWidget,
      reason: 'στο μηδέν το μήνυμα φεύγει μόνο του — η καταχώρηση μένει',
    );
  });

  testWidgets('η ζωή της μέτρησης είναι η ζωή του μηνύματος', (tester) async {
    expect(
      kQuickAddUndoSnackBarDuration.inSeconds,
      kQuickAddUndoSnackBarSeconds,
      reason: 'δύο τιμές θα απέκλιναν και ο αριθμός θα έλεγε ψέματα',
    );
  });

  testWidgets('το «Κλείσιμο» δεν αναιρεί', (tester) async {
    var undone = false;
    var dismissed = false;

    await pumpContent(
      tester,
      onUndo: () => undone = true,
      onDismiss: () => dismissed = true,
    );
    await tester.tap(find.textContaining('Κλείσιμο'));
    await tester.pump();

    expect(dismissed, isTrue);
    expect(
      undone,
      isFalse,
      reason: 'η προσθήκη έχει ήδη γίνει — το κλείσιμο απλώς φεύγει',
    );
  });

  testWidgets('η «Αναίρεση» δεν κλείνει απλώς το μήνυμα', (tester) async {
    var undone = false;
    var dismissed = false;

    await pumpContent(
      tester,
      onUndo: () => undone = true,
      onDismiss: () => dismissed = true,
    );
    await tester.tap(find.text('Αναίρεση'));
    await tester.pump();

    expect(undone, isTrue);
    expect(dismissed, isFalse);
  });

  testWidgets('δίγραμμο μήνυμα δεν κόβει τις ενέργειες', (tester) async {
    await pumpContent(
      tester,
      onUndo: () {},
      onDismiss: () {},
      message:
          'Δημιουργήθηκε νέος χρήστης Μαρία Δαμανάκη στο τμήμα: Άδειες\n'
          'Προσθήκη νέου καλούντα: Μαρία Δαμανάκη στο τμήμα: Άδειες',
    );

    expect(find.text('Αναίρεση'), findsOneWidget);
    expect(find.textContaining('Κλείσιμο'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
