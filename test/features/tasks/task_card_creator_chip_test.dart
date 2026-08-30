// Ο δημιουργός της εκκρεμότητας στην κάρτα: φαίνεται όταν λέει κάτι, σιωπά
// όταν δεν λέει.
//
// Η βάση κρατούσε πάντα ποιος άνοιξε την εκκρεμότητα, αλλά η στήλη δεν
// διαβαζόταν ποτέ. Η μετακίνηση της ευθύνης δεν πρέπει να σβήνει το «από πού
// ήρθε» — ούτε όμως να γεμίζει κάθε κάρτα με το ίδιο όνομα δύο φορές.
//
//   flutter test test/features/tasks/task_card_creator_chip_test.dart

import 'package:call_logger/features/operators/providers/operator_directory_providers.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/screens/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Task task({int? createdBy, int? assignedTo}) => Task(
    id: 1,
    title: 'Προς δοκιμή',
    dueDate: '2026-09-01T10:00:00.000',
    status: 'open',
    createdByOperatorId: createdBy,
    assignedOperatorId: assignedTo,
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

  group('Σήμα δημιουργού στην κάρτα', () {
    testWidgets('δημιουργός και υπεύθυνος διαφορετικοί: φαίνονται και οι δύο', (
      tester,
    ) async {
      await pumpCard(tester, subject: task(createdBy: 11, assignedTo: 22));

      expect(find.text('Άνοιξε: Βασίλης'), findsOneWidget);
      expect(find.text('Βλάσης'), findsOneWidget);
    });

    testWidgets('ίδιο πρόσωπο και στα δύο: ο δημιουργός δεν επαναλαμβάνεται', (
      tester,
    ) async {
      await pumpCard(tester, subject: task(createdBy: 22, assignedTo: 22));

      expect(
        find.text('Άνοιξε: Βλάσης'),
        findsNothing,
        reason:
            'Το ίδιο όνομα δύο φορές στην ίδια κάρτα δεν προσθέτει '
            'πληροφορία — προσθέτει θόρυβο.',
      );
      expect(find.text('Βλάσης'), findsOneWidget);
    });

    testWidgets('χωρίς ανάθεση, ο δημιουργός φαίνεται', (tester) async {
      await pumpCard(tester, subject: task(createdBy: 11));

      expect(
        find.text('Άνοιξε: Βασίλης'),
        findsOneWidget,
        reason:
            'Το φίλτρο χρήστη φέρνει τις ανανάθετες στον δημιουργό τους — η '
            'κάρτα πρέπει να εξηγεί γιατί εμφανίστηκε εκεί.',
      );
    });

    testWidgets('χωρίς καταγεγραμμένο δημιουργό δεν εμφανίζεται τίποτα', (
      tester,
    ) async {
      await pumpCard(tester, subject: task(assignedTo: 22));

      expect(find.textContaining('Άνοιξε:'), findsNothing);
    });

    testWidgets('άγνωστο προφίλ δεν κρύβεται πίσω από κενό', (tester) async {
      await pumpCard(tester, subject: task(createdBy: 99));

      expect(find.text('Άνοιξε: Χρήστης #99'), findsOneWidget);
    });

    testWidgets('το σήμα του δημιουργού δεν πατιέται', (tester) async {
      await pumpCard(tester, subject: task(createdBy: 11, assignedTo: 22));

      expect(
        find.ancestor(
          of: find.text('Άνοιξε: Βασίλης'),
          matching: find.byType(ActionChip),
        ),
        findsNothing,
        reason:
            'Η δημιουργία είναι γεγονός του παρελθόντος: σήμα που μοιάζει με '
            'κουμπί θα υποσχόταν αλλαγή που δεν γίνεται.',
      );
    });
  });
}
