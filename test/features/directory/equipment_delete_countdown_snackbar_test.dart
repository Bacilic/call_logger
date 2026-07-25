// Snackbar διαγραφής εξοπλισμού: κουμπιά στην ίδια γραμμή + αντίστροφη μέτρηση.
//
//   flutter test test/features/directory/equipment_delete_countdown_snackbar_test.dart

import 'package:call_logger/features/directory/screens/widgets/equipment_delete_countdown_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'αντίστροφη μέτρηση στο Επιβεβαίωση και κλήσεις onConfirm/onUndo',
    (tester) async {
      var confirmed = false;
      var undone = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EquipmentDeleteCountdownSnackBarContent(
              message: 'Διαγράφηκε εξοπλισμός 3601',
              seconds: 5,
              onConfirm: () => confirmed = true,
              onUndo: () => undone = true,
            ),
          ),
        ),
      );
      await tester.pump();

      // (α) Αρχική ετικέτα και ίδια γραμμή με το μήνυμα.
      expect(find.text('Επιβεβαίωση (5)'), findsOneWidget);
      expect(find.text('Αναίρεση'), findsOneWidget);
      expect(find.text('Διαγράφηκε εξοπλισμός 3601'), findsOneWidget);
      expect(find.byType(Row), findsWidgets);

      // (β) Αντίστροφη μέτρηση ανά δευτερόλεπτο.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Επιβεβαίωση (4)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Επιβεβαίωση (3)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Επιβεβαίωση (2)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Επιβεβαίωση (1)'), findsOneWidget);

      // (γ) Κλήσεις callbacks.
      await tester.tap(find.text('Επιβεβαίωση (1)'));
      await tester.pump();
      expect(confirmed, isTrue);

      await tester.tap(find.text('Αναίρεση'));
      await tester.pump();
      expect(undone, isTrue);
    },
  );
}
