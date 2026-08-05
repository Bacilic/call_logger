// Widget tests: πώς κλείνει ο διάλογος «Ρυθμίσεις βάσης δεδομένων».
//
// Το προηγούμενο τεστ του διαλόγου τον έκλεινε προγραμματιστικά με
// `Navigator.pop`, οπότε δεν φύλαγε τίποτα από όσα έχει στη διάθεσή του ο
// χρήστης. Εδώ δένονται και τα δύο σκέλη: υπάρχει κουμπί, και το φράγμα
// ΔΕΝ κλείνει τον διάλογο (μακρές ροές — κατά λάθος κλικ θα έχανε δουλειά).
//
//   flutter test test/features/database/database_settings_dialog_close_test.dart

import 'package:call_logger/features/database/widgets/database_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpOpenDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              // Ίδια είσοδος με την εφαρμογή: η πολιτική του φράγματος ζει
              // εκεί, όχι στο τεστ.
              onPressed: () => showDatabaseSettingsDialog(
                context,
                onDatabaseLifecycleChanged: () async {},
                panelBuilder: (_) => const Text('Περιεχόμενο πάνελ'),
              ),
              child: const Text('Άνοιγμα'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Άνοιγμα'));
    await tester.pumpAndSettle();
    expect(find.byType(DatabaseSettingsDialog), findsOneWidget);
  }

  testWidgets('έχει κουμπί «Κλείσιμο» που κλείνει τον διάλογο', (tester) async {
    await pumpOpenDialog(tester);

    final closeButton = find.widgetWithText(TextButton, 'Κλείσιμο');
    expect(
      closeButton,
      findsOneWidget,
      reason: 'Ο διάλογος οφείλει να έχει ορατό μέσο κλεισίματος.',
    );

    await tester.tap(closeButton);
    await tester.pumpAndSettle();

    expect(find.byType(DatabaseSettingsDialog), findsNothing);
  });

  testWidgets('το κουμπί «Κλείσιμο» μένει ορατό χωρίς κύλιση', (tester) async {
    await pumpOpenDialog(tester);

    // Ζει στο κέλυφος, όχι μέσα στο κυλιόμενο περιεχόμενο του πάνελ.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(TextButton, 'Κλείσιμο'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.widgetWithText(TextButton, 'Κλείσιμο'),
      ),
      findsNothing,
    );
  });

  testWidgets('κλικ έξω από το πλαίσιο ΔΕΝ κλείνει τον διάλογο', (
    tester,
  ) async {
    await pumpOpenDialog(tester);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(
      find.byType(DatabaseSettingsDialog),
      findsOneWidget,
      reason:
          'Ο διάλογος φιλοξενεί μακρές ροές (αντίγραφα, έλεγχος ακεραιότητας)· '
          'κατά λάθος κλικ στο φράγμα δεν πρέπει να χάνει δουλειά.',
    );

    // Καθάρισμα: κλείσιμο με το προβλεπόμενο μέσο.
    await tester.tap(find.widgetWithText(TextButton, 'Κλείσιμο'));
    await tester.pumpAndSettle();
  });
}
