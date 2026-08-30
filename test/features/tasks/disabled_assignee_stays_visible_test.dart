// Ο υπεύθυνος που απενεργοποιήθηκε δεν εξαφανίζεται από τις λίστες ανάθεσης.
//
// Το σφάλμα: και οι δύο λίστες ρωτούσαν ΜΟΝΟ τα ενεργά προφίλ. Όταν το προφίλ
// του υπευθύνου απενεργοποιούνταν, η φόρμα τον έδειχνε ως «Χρήστης #22» και ο
// διάλογος γρήγορης ανάθεσης δεν τον ανέφερε καθόλου — η εκκρεμότητα έμοιαζε
// αδέσποτη ενώ ανήκε σε συγκεκριμένο πρόσωπο.
//
//   flutter test test/features/tasks/disabled_assignee_stays_visible_test.dart

import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/features/operators/providers/operator_directory_providers.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/screens/tasks_screen_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ο Βασίλης δουλεύει ακόμη, ο Βλάσης έφυγε — και κρατά μια εκκρεμότητα.
final _createdAt = DateTime(2026, 1, 1);

final _operators = <Operator>[
  Operator(id: 11, displayName: 'Βασίλης', createdAt: _createdAt),
  Operator(
    id: 22,
    displayName: 'Βλάσης',
    isActive: false,
    createdAt: _createdAt,
  ),
];

Task _task({int? assignedTo}) => Task(
  id: 7,
  title: 'Παραγγελία μελανιού',
  dueDate: '2026-09-01T10:00:00.000',
  status: 'open',
  assignedOperatorId: assignedTo,
);

void main() {
  group('Γρήγορη ανάθεση με απενεργοποιημένο υπεύθυνο', () {
    Future<void> openAssignDialog(WidgetTester tester, Task task) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allOperatorsProvider.overrideWith((ref) async => _operators),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => ElevatedButton(
                  onPressed: () => assignTaskFlow(context, ref, task),
                  child: const Text('ΑΝΟΙΓΜΑ'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ΑΝΟΙΓΜΑ'));
      await tester.pumpAndSettle();
    }

    testWidgets('ο σημερινός υπεύθυνος φαίνεται, σημειωμένος ως ανενεργός', (
      tester,
    ) async {
      await openAssignDialog(tester, _task(assignedTo: 22));

      expect(
        find.text('Βλάσης (απενεργοποιημένος)'),
        findsOneWidget,
        reason:
            'Χωρίς αυτόν, ο διάλογος δείχνει μόνο ενεργούς και «Χωρίς '
            'ανάθεση» — η εκκρεμότητα μοιάζει αδέσποτη ενώ ανήκει κάπου.',
      );
      expect(find.text('Βασίλης'), findsOneWidget);
    });

    testWidgets('απενεργοποιημένος που ΔΕΝ είναι ο υπεύθυνος δεν προσφέρεται', (
      tester,
    ) async {
      await openAssignDialog(tester, _task(assignedTo: 11));

      expect(
        find.textContaining('Βλάσης'),
        findsNothing,
        reason:
            'Η απενεργοποίηση σταματά τη νέα δουλειά: ο Βλάσης εμφανίζεται '
            'μόνο όταν κρατά ήδη αυτή την εκκρεμότητα.',
      );
    });

    testWidgets('χωρίς ανάθεση, κανένας απενεργοποιημένος στη λίστα', (
      tester,
    ) async {
      await openAssignDialog(tester, _task());

      expect(find.textContaining('Βλάσης'), findsNothing);
      expect(find.text('Χωρίς ανάθεση'), findsOneWidget);
    });
  });
}
