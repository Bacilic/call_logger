// Διέξοδος όταν ο χρήστης ακυρώνει στη μέση της σειριακής διαγραφής.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/screens/widgets/department_deletion_partial_dialog_test.dart

import 'package:call_logger/features/directory/screens/widgets/bulk_deletion_partial_dialog.dart';
import 'package:call_logger/features/directory/screens/widgets/department_deletion_partial_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Μήνυμα διακοπής', () {
    test('ένα ολοκληρωμένο τμήμα: ενικός και στα δύο σκέλη', () {
      expect(
        departmentDeletionPartialQuestion(completed: 1, total: 30),
        'Ολοκληρώσατε 1 τμήμα από τα 30. Να διαγραφεί αυτό που ολοκληρώθηκε;',
      );
    });

    test('πολλά ολοκληρωμένα: πληθυντικός', () {
      expect(
        departmentDeletionPartialQuestion(completed: 20, total: 30),
        'Ολοκληρώσατε 20 τμήματα από τα 30. '
        'Να διαγραφούν αυτά που ολοκληρώθηκαν;',
      );
    });
  });

  group('Διάλογος διακοπής', () {
    BulkDeletionPartialChoice? captured;

    Future<void> open(WidgetTester tester) async {
      captured = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  captured = await showDepartmentDeletionPartialDialog(
                    context: ctx,
                    completed: 20,
                    total: 30,
                  );
                },
                child: const Text('άνοιγμα'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('άνοιγμα'));
      await tester.pumpAndSettle();
    }

    testWidgets('δείχνει πόσα ολοκληρώθηκαν από πόσα', (tester) async {
      await open(tester);

      expect(find.textContaining('20 τμήματα από τα 30'), findsOneWidget);
    });

    testWidgets('«Διαγραφή όσων ολοκληρώθηκαν» κρατά τη δουλειά', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('Διαγραφή όσων ολοκληρώθηκαν'));
      await tester.pumpAndSettle();

      expect(captured, BulkDeletionPartialChoice.applyCompleted);
    });

    testWidgets('«Ακύρωση όλων» πετά τα πάντα', (tester) async {
      await open(tester);

      await tester.tap(find.text('Ακύρωση όλων'));
      await tester.pumpAndSettle();

      expect(captured, BulkDeletionPartialChoice.discardAll);
    });
  });
}
