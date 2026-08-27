// Οι αριθμητικές ρυθμίσεις αντιγράφων: αποθηκεύονται όταν φύγει η εστίαση,
// και η επικύρωση φαίνεται ΚΑΘΩΣ πληκτρολογείς.
//
// Το συμβόλαιο: «Κάθε αριθμητική ρύθμιση αποθηκεύεται όταν ο χρήστης φύγει
// από το πεδίο — όχι μόνο αν πατήσει Enter.» Πριν, το πεδίο άκουγε μόνο
// onEditingComplete/onSubmitted: ο χρήστης έγραφε «3», έκανε κλικ αλλού ή
// έκλεινε τον διάλογο, και η τιμή χανόταν σιωπηλά.
//
//   flutter test test/features/database/backup_int_setting_field_test.dart

import 'package:call_logger/features/database/widgets/backup_int_setting_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Μήνυμα ορίων', () {
    String? err(String raw) =>
        backupIntFieldError(raw: raw, min: 15, max: 1440);

    test('τιμή κάτω από το ελάχιστο το λέει', () {
      expect(err('2'), 'Ελάχιστο: 15');
    });

    test('τιμή πάνω από το μέγιστο το λέει', () {
      expect(err('5000'), 'Μέγιστο: 1440');
    });

    test('τιμή μέσα στα όρια δεν παραπονιέται', () {
      expect(err('15'), isNull);
      expect(err('240'), isNull);
      expect(err('1440'), isNull);
    });

    test('κενό πεδίο ΔΕΝ είναι σφάλμα — σβήνει για να ξαναγράψει', () {
      expect(err(''), isNull);
      expect(err('   '), isNull);
    });
  });

  group('Πότε αποθηκεύεται', () {
    late TextEditingController controller;
    late FocusNode fieldFocus;
    late FocusNode elsewhere;
    late List<String> saved;

    setUp(() {
      controller = TextEditingController(text: '100');
      fieldFocus = FocusNode();
      elsewhere = FocusNode();
      saved = [];
    });

    tearDown(() {
      controller.dispose();
      fieldFocus.dispose();
      elsewhere.dispose();
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                BackupIntSettingField(
                  leadingText: 'Κάθε ',
                  trailingText: ' αλλαγές',
                  controller: controller,
                  focusNode: fieldFocus,
                  min: 1,
                  max: 9999,
                  onPersist: () async => saved.add(controller.text),
                ),
                // Κάτι άλλο να πάρει την εστίαση — όπως ένα κλικ αλλού.
                TextField(focusNode: elsewhere),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('η απώλεια εστίασης αποθηκεύει — ΧΩΡΙΣ Enter', (tester) async {
      await pump(tester);

      fieldFocus.requestFocus();
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '3');
      await tester.pump();
      expect(saved, isEmpty, reason: 'Δεν έχει φύγει ακόμη η εστίαση.');

      elsewhere.requestFocus();
      await tester.pump();

      expect(saved, ['3'], reason: 'Η τιμή χανόταν σιωπηλά όταν έφευγες.');
    });

    testWidgets('το Enter εξακολουθεί να αποθηκεύει', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField).first, '7');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(saved, contains('7'));
    });
  });

  group('Η επικύρωση φαίνεται καθώς πληκτρολογείς', () {
    testWidgets('τιμή εκτός ορίων δείχνει το όριο πριν φύγει η εστίαση', (
      tester,
    ) async {
      final controller = TextEditingController(text: '15');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BackupIntSettingField(
              leadingText: 'Το συντομότερο μετά από ',
              trailingText: ' λεπτά',
              controller: controller,
              focusNode: focus,
              min: 15,
              max: 1440,
              limitHint: 'ελάχιστο 15 λεπτά',
              onPersist: () async {},
            ),
          ),
        ),
      );

      expect(find.text('ελάχιστο 15 λεπτά'), findsOneWidget);
      expect(find.text('Ελάχιστο: 15'), findsNothing);

      await tester.enterText(find.byType(TextField), '2');
      await tester.pump();

      // Χωρίς να φύγει η εστίαση και χωρίς Enter.
      expect(find.text('Ελάχιστο: 15'), findsOneWidget);
      expect(
        find.text('ελάχιστο 15 λεπτά'),
        findsNothing,
        reason: 'Το σφάλμα παίρνει τη θέση της υπενθύμισης, δεν στοιβάζεται.',
      );

      await tester.enterText(find.byType(TextField), '30');
      await tester.pump();

      expect(find.text('Ελάχιστο: 15'), findsNothing);
      expect(find.text('ελάχιστο 15 λεπτά'), findsOneWidget);
    });
  });
}
