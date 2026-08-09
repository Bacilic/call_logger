// Π4: η επεξεργασία κλήσης δείχνει τις συνδεδεμένες εκκρεμότητες και τις
// ανοίγει — αντίστοιχο του μηνύματος Lansweeper για την άλλη «ουρά».
//
//   flutter test test/features/history/linked_tasks_card_test.dart

import 'package:call_logger/features/history/widgets/linked_tasks_card.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Task _task({
  int id = 1,
  String title = 'Παραγγελία μελανιού',
  String status = 'open',
}) {
  return Task(
    id: id,
    title: title,
    description: '',
    dueDate: '2026-07-20T10:00:00.000',
    status: status,
    callId: 5,
  );
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required List<Task> tasks,
  ValueChanged<Task>? onOpen,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LinkedTasksCard(tasks: tasks, onOpen: onOpen ?? (_) {}),
      ),
    ),
  );
}

void main() {
  testWidgets('μία εκκρεμότητα: ενικός τίτλος και ο τίτλος της', (
    tester,
  ) async {
    await _pumpCard(tester, tasks: [_task()]);

    expect(find.text('Η κλήση έχει συνδεδεμένη εκκρεμότητα'), findsOneWidget);
    expect(find.text('Παραγγελία μελανιού'), findsOneWidget);
  });

  testWidgets('πολλές εκκρεμότητες: πληθυντικός με το πλήθος', (tester) async {
    await _pumpCard(
      tester,
      tasks: [_task(), _task(id: 2, title: 'Έλεγχος καλωδίωσης')],
    );

    expect(
      find.text('Η κλήση έχει 2 συνδεδεμένες εκκρεμότητες'),
      findsOneWidget,
    );
    expect(find.text('Έλεγχος καλωδίωσης'), findsOneWidget);
  });

  testWidgets('η κατάσταση κάθε εκκρεμότητας φαίνεται στην κάρτα', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      tasks: [
        _task(),
        _task(id: 2, title: 'Κλειστή', status: 'closed'),
        _task(id: 3, title: 'Σε αναβολή', status: 'snoozed'),
      ],
    );

    expect(find.text('Ανοιχτή'), findsOneWidget);
    expect(find.text('Κλειστή'), findsWidgets);
    expect(find.text('Σε αναβολή'), findsWidgets);
  });

  testWidgets('το «Άνοιγμα» επιστρέφει τη συγκεκριμένη εκκρεμότητα', (
    tester,
  ) async {
    Task? opened;
    await _pumpCard(
      tester,
      tasks: [_task(), _task(id: 2, title: 'Δεύτερη')],
      onOpen: (task) => opened = task,
    );

    // Το κουμπί της δεύτερης γραμμής — όχι της πρώτης.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Άνοιγμα').last);
    await tester.pumpAndSettle();

    expect(opened?.id, 2);
  });
}
