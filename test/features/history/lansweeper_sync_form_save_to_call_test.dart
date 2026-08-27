// Το κουμπί «Αποθήκευση στην κλήση» στη φόρμα της Αναφοράς Lansweeper.
//
// Φυλάει τη ΣΥΝΔΕΣΗ, όχι την εμφάνιση: ότι το κουμπί υπάρχει δίπλα στο
// «Αποθήκευση ως γνώση», ότι το πάτημά του φτάνει στη ροή, και ότι όταν δεν
// επιτρέπεται μένει ορατό αλλά ανενεργό — αν έσβηνε, θα έμοιαζε με βλάβη αντί
// για «λείπει κάτι».
//
//   flutter test test/features/history/lansweeper_sync_form_save_to_call_test.dart

import 'package:call_logger/core/widgets/spell_check_controller.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_sync_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Κουμπί «Αποθήκευση στην κλήση»', () {
    late SpellCheckController titleController;
    late SpellCheckController notesController;
    late SpellCheckController solutionController;

    setUp(() {
      titleController = SpellCheckController();
      notesController = SpellCheckController();
      solutionController = SpellCheckController();
    });

    tearDown(() {
      titleController.dispose();
      notesController.dispose();
      solutionController.dispose();
    });

    Widget buildForm({
      VoidCallback? onSaveToCall,
      String? Function()? saveToCallDisabledReason,
    }) {
      return ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LansweeperSyncForm(
                titleController: titleController,
                notesController: notesController,
                solutionController: solutionController,
                onSaveToCall: onSaveToCall,
                saveToCallDisabledReason: saveToCallDisabledReason,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('το πάτημα φτάνει στη ροή αποθήκευσης', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(buildForm(onSaveToCall: () => pressed++));

      await tester.tap(find.text('Αποθήκευση στην κλήση'));
      await tester.pump();

      expect(pressed, 1);
    });

    testWidgets('όταν δεν επιτρέπεται, μένει ορατό αλλά ανενεργό', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildForm(
          saveToCallDisabledReason: () => 'Επιλέξτε πρώτα την κλήση.',
          onSaveToCall: () {},
        ),
      );

      expect(find.text('Αποθήκευση στην κλήση'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Αποθήκευση στην κλήση'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('ξυπνά μόλις αλλάξει το κείμενο, χωρίς άλλη παρέμβαση', (
      tester,
    ) async {
      // Μιμείται τον πραγματικό λόγο απενεργοποίησης: «τίποτα δεν άλλαξε».
      const stored = 'Ήδη αποθηκευμένο';
      await tester.pumpWidget(
        buildForm(
          saveToCallDisabledReason: () =>
              notesController.text.trim() == stored ? 'Καμία αλλαγή.' : null,
          onSaveToCall: () {},
        ),
      );

      notesController.text = stored;
      // Ο ορθογραφικός έλεγχος προγραμματίζει δικό του χρονιστή σε κάθε αλλαγή
      // κειμένου· χωρίς να τον αφήσουμε να τρέξει, ο έλεγχος τερματίζει με
      // εκκρεμή χρονιστή.
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Αποθήκευση στην κλήση'),
            )
            .onPressed,
        isNull,
      );

      // Ο χρήστης πληκτρολογεί: κανείς άλλος δεν ζητά ανανέωση της οθόνης.
      notesController.text = '$stored — και κάτι νέο';
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Αποθήκευση στην κλήση'),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('η αλλαγή ΜΟΝΟ του τίτλου ξυπνά κι αυτή το κουμπί', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildForm(
          saveToCallDisabledReason: () =>
              titleController.text.trim().isEmpty ? 'Καμία αλλαγή.' : null,
          onSaveToCall: () {},
        ),
      );

      titleController.text = 'Ο εκτυπωτής δεν τραβά χαρτί';
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Αποθήκευση στην κλήση'),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('χωρίς τη δυνατότητα, το κουμπί δεν εμφανίζεται καθόλου', (
      tester,
    ) async {
      await tester.pumpWidget(buildForm());

      expect(find.text('Αποθήκευση στην κλήση'), findsNothing);
    });
  });
}
