// Ποιος ολοκλήρωσε την εκκρεμότητα, πάνω στην κάρτα.
//
// Η ομάδα δουλεύει με βάρδιες: η εκκρεμότητα του ενός κλείνει συχνά από τον
// άλλον. Ως τώρα η κάρτα συνέχιζε να δείχνει μόνο τον υπεύθυνο, και η δουλειά
// του άλλου φαινόταν μόνο σε όποιον άνοιγε το Ιστορικό.
//
// Το σήμα λέει κάτι ΜΟΝΟ όταν ο κλείσας διαφέρει από αυτόν που τη χρωστούσε —
// και μόνο όσο η εκκρεμότητα είναι ολοκληρωμένη.
//
//   flutter test test/features/tasks/task_card_closer_chip_test.dart

import 'package:call_logger/features/operators/providers/operator_directory_providers.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/screens/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Task task({
    int? createdBy,
    int? assignedTo,
    int? closedBy,
    String status = 'closed',
  }) => Task(
    id: 1,
    title: 'Προς δοκιμή',
    dueDate: '2026-09-01T10:00:00.000',
    status: status,
    completedAt: status == 'closed' ? '2026-09-02T12:00:00.000' : null,
    createdByOperatorId: createdBy,
    assignedOperatorId: assignedTo,
    closedByOperatorId: closedBy,
  );

  Future<void> pumpCard(WidgetTester tester, {required Task subject}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operatorNamesProvider.overrideWith(
            (ref) async => {11: 'Βασίλης', 22: 'Βλάσης'},
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: TaskCard(task: subject)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Σήμα κλείσαντα στην κάρτα', () {
    testWidgets('ξένη ανάθεση: φαίνεται ποιος την έκλεισε', (tester) async {
      await pumpCard(
        tester,
        subject: task(createdBy: 22, assignedTo: 22, closedBy: 11),
      );

      expect(find.text('Έκλεισε: Βασίλης'), findsOneWidget);
    });

    testWidgets('ο υπεύθυνος την έκλεισε: το σήμα σιωπά', (tester) async {
      await pumpCard(
        tester,
        subject: task(createdBy: 11, assignedTo: 22, closedBy: 22),
      );

      expect(
        find.textContaining('Έκλεισε:'),
        findsNothing,
        reason:
            'Το ίδιο όνομα δύο φορές στην ίδια κάρτα δεν προσθέτει '
            'πληροφορία — προσθέτει θόρυβο.',
      );
    });

    testWidgets('χωρίς ανάθεση, η ευθύνη είναι ο δημιουργός', (tester) async {
      await pumpCard(tester, subject: task(createdBy: 11, closedBy: 11));

      expect(
        find.textContaining('Έκλεισε:'),
        findsNothing,
        reason:
            'Ο δημιουργός ανανάθετης εκκρεμότητας ΕΙΝΑΙ η ευθύνη — ίδια '
            'φόρμουλα με το φίλτρο χρήστη.',
      );
    });

    testWidgets('χωρίς ανάθεση, ξένος κλείσας: φαίνεται', (tester) async {
      await pumpCard(tester, subject: task(createdBy: 22, closedBy: 11));

      expect(find.text('Έκλεισε: Βασίλης'), findsOneWidget);
    });

    testWidgets('ξανα-ανοιγμένη εκκρεμότητα: το σήμα αποσύρεται', (
      tester,
    ) async {
      await pumpCard(
        tester,
        subject: task(
          createdBy: 22,
          assignedTo: 22,
          closedBy: 11,
          status: 'open',
        ),
      );

      expect(
        find.textContaining('Έκλεισε:'),
        findsNothing,
        reason:
            'Η σφραγίδα επιβιώνει της αναίρεσης, αλλά «Έκλεισε: …» πάνω σε '
            'ανοιχτή εκκρεμότητα διαβάζεται σαν ψέμα.',
      );
    });

    testWidgets('παλιά κλεισμένη χωρίς καταγραφή: τίποτα', (tester) async {
      await pumpCard(tester, subject: task(createdBy: 11, assignedTo: 22));

      expect(find.textContaining('Έκλεισε:'), findsNothing);
    });

    testWidgets('άγνωστο προφίλ δεν κρύβεται πίσω από κενό', (tester) async {
      await pumpCard(
        tester,
        subject: task(createdBy: 22, assignedTo: 22, closedBy: 99),
      );

      expect(find.text('Έκλεισε: Χρήστης #99'), findsOneWidget);
    });

    testWidgets('το σήμα του κλείσαντα δεν πατιέται', (tester) async {
      await pumpCard(
        tester,
        subject: task(createdBy: 22, assignedTo: 22, closedBy: 11),
      );

      expect(
        find.ancestor(
          of: find.text('Έκλεισε: Βασίλης'),
          matching: find.byType(ActionChip),
        ),
        findsNothing,
        reason: 'Είναι γεγονός του παρελθόντος, όχι ενέργεια.',
      );
    });

    testWidgets('δημιουργός και κλείσας μαζί: φαίνονται και οι δύο', (
      tester,
    ) async {
      await pumpCard(
        tester,
        subject: task(createdBy: 11, assignedTo: 22, closedBy: 11),
      );

      expect(find.text('Άνοιξε: Βασίλης'), findsOneWidget);
      expect(find.text('Έκλεισε: Βασίλης'), findsOneWidget);
    });
  });
}
