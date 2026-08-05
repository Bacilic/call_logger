import 'package:call_logger/core/widgets/dialog_snackbar_scope.dart';
import 'package:call_logger/features/database/widgets/database_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'snackbar από το εσωτερικό του διαλόγου ρυθμίσεων βάσης '
    'εμφανίζεται στο επίπεδο του διαλόγου, όχι στο ριζικό Scaffold',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => DatabaseSettingsDialog(
                      onDatabaseLifecycleChanged: () async {},
                      // Το υποκατάστατο εκπέμπει με την ίδια κλήση που
                      // χρησιμοποιούν οι ροές του πάνελ (χειροκίνητο
                      // αντίγραφο, συνέχεια «χαμένου φακέλου»).
                      panelBuilder: (_) => Builder(
                        builder: (panelContext) => FilledButton(
                          onPressed: () {
                            ScaffoldMessenger.of(panelContext).showSnackBar(
                              const SnackBar(content: Text('Μήνυμα πάνελ')),
                            );
                          },
                          child: const Text('Εκπομπή'),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Άνοιγμα'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Άνοιγμα'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Εκπομπή'));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(DialogSnackbarScope),
          matching: find.text('Μήνυμα πάνελ'),
        ),
        findsOneWidget,
        reason:
            'Το snackbar πρέπει να εμφανίζεται μέσα στο DialogSnackbarScope '
            'του διαλόγου — αλλιώς καταλήγει στο ριζικό Scaffold, πίσω από '
            'το φράγμα.',
      );

      // Καθάρισμα: το snackbar ολοκληρώνει τον κύκλο του και ο διάλογος
      // κλείνει, ώστε να μη μένουν εκκρεμείς χρονομετρητές/αντικείμενα.
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(find.byType(DatabaseSettingsDialog)),
      ).pop();
      await tester.pumpAndSettle();
    },
  );
}
