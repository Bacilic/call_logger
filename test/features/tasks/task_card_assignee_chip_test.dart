// Το σήμα του υπευθύνου στην κάρτα δεν είναι μόνο ένδειξη — ανοίγει τον ίδιο
// επιλογέα ανάθεσης με το μενού.
//
// Ό,τι δείχνει μια κατάσταση, την αλλάζει κιόλας: ίδιο μοτίβο με την
// ημερομηνία δίπλα του, που ανοίγει την αναβολή.
//
//   flutter test test/features/tasks/task_card_assignee_chip_test.dart

import 'package:call_logger/features/operators/providers/operator_directory_providers.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/screens/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Task task({int? assignedTo}) => Task(
    id: 1,
    title: 'Προς δοκιμή',
    dueDate: '2026-09-01T10:00:00.000',
    status: 'open',
    assignedOperatorId: assignedTo,
  );

  Future<int> pumpCard(
    WidgetTester tester, {
    required Task subject,
    VoidCallback? onAssign,
  }) async {
    var taps = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operatorNamesProvider.overrideWith((ref) async => {22: 'Βλάσης'}),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TaskCard(
              task: subject,
              onAssign: onAssign == null
                  ? null
                  : () {
                      taps++;
                      onAssign();
                    },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return taps;
  }

  Finder assigneeChip() =>
      find.ancestor(of: find.text('Βλάσης'), matching: find.byType(ActionChip));

  group('Σήμα υπευθύνου στην κάρτα', () {
    testWidgets('χωρίς ανάθεση δεν εμφανίζεται καθόλου', (tester) async {
      await pumpCard(tester, subject: task());

      expect(
        find.byType(ActionChip),
        findsNothing,
        reason:
            'Η συντριπτική πλειοψηφία των εκκρεμοτήτων δεν έχει υπεύθυνο — '
            'ένα κενό σήμα σε κάθε κάρτα θα ήταν σκέτος θόρυβος.',
      );
    });

    testWidgets('με ανάθεση δείχνει το όνομα του υπευθύνου', (tester) async {
      await pumpCard(tester, subject: task(assignedTo: 22));

      expect(find.text('Βλάσης'), findsOneWidget);
    });

    testWidgets('το κλικ ανοίγει τον επιλογέα ανάθεσης', (tester) async {
      var opened = 0;
      await pumpCard(
        tester,
        subject: task(assignedTo: 22),
        onAssign: () => opened++,
      );

      await tester.tap(assigneeChip());
      await tester.pumpAndSettle();

      expect(
        opened,
        1,
        reason:
            'Το σήμα είναι κουμπί: ένα κλικ, όχι διπλό — η ημερομηνία δίπλα '
            'θέλει διπλό επειδή είναι ετικέτα κειμένου.',
      );
    });

    testWidgets('χωρίς διαθέσιμη ανάθεση, το σήμα δεν πατιέται', (
      tester,
    ) async {
      await pumpCard(tester, subject: task(assignedTo: 22));

      final chip = tester.widget<ActionChip>(assigneeChip());
      expect(
        chip.onPressed,
        isNull,
        reason:
            'Κουμπί που δεν οδηγεί πουθενά είναι χειρότερο από ένδειξη — σε '
            'οθόνες που δεν προσφέρουν ανάθεση, το σήμα μένει ένδειξη.',
      );
    });

    testWidgets('άγνωστο προφίλ δεν κρύβεται πίσω από κενό', (tester) async {
      await pumpCard(tester, subject: task(assignedTo: 99));

      expect(
        find.text('Χρήστης #99'),
        findsOneWidget,
        reason:
            'Υπεύθυνος που δεν βρίσκεται πια στα προφίλ εξακολουθεί να έχει '
            'τη δουλειά χρεωμένη — το κενό θα έμοιαζε με «καμία ανάθεση».',
      );
    });
  });
}
