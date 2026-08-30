// Τα κουμπιά επεξεργασίας της κάρτας δεν υπόσχονται ό,τι δεν μπορούν να δώσουν.
//
// Η κάρτα ξέρει ήδη ποια συνδεδεμένη οντότητα διαγράφηκε — το πάνω μισό της το
// γράφει «(διαγραμμένο)». Τα κουμπιά όμως έμπαιναν με μοναδικό κριτήριο
// «υπάρχει κωδικός», οπότε ο χρήστης το μάθαινε ΜΕΤΑ το πάτημα.
//
//   flutter test test/features/tasks/task_card_deleted_entity_actions_test.dart

import 'package:call_logger/features/operators/providers/operator_directory_providers.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/screens/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Task task({
    bool callerDeleted = false,
    bool departmentDeleted = false,
    bool equipmentDeleted = false,
  }) => Task(
    id: 1,
    title: 'Καταχωρήθηκε εξοπλισμός ως κοινόχρηστο',
    description: Task.quickAddTag,
    dueDate: '2026-09-01T10:00:00.000',
    status: 'open',
    callerId: 7,
    departmentId: 8,
    equipmentId: 9,
    userText: 'Βαρβάρα',
    departmentText: 'Αιματολογικό',
    equipmentText: '5010',
    callerLinkedDeleted: callerDeleted,
    departmentLinkedDeleted: departmentDeleted,
    equipmentLinkedDeleted: equipmentDeleted,
  );

  Future<void> pumpCard(WidgetTester tester, Task subject) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operatorNamesProvider.overrideWith((ref) async => <int, String>{}),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TaskCard(
                task: subject,
                onEditCaller: () async => false,
                onEditDepartment: () async => false,
                onEditEquipment: () async => false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Η υπόδειξη που κουβαλά το κουμπί με το δοσμένο κείμενο, αν υπάρχει.
  Finder hintFor(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(Tooltip));

  group('Κουμπιά επεξεργασίας σε διαγραμμένη οντότητα', () {
    testWidgets('όσο η οντότητα ζει, το κουμπί δεν φέρει καμία υπόδειξη', (
      tester,
    ) async {
      await pumpCard(tester, task());

      expect(find.text('Επεξεργασία Εξοπλισμού'), findsOneWidget);
      expect(
        hintFor('Επεξεργασία Εξοπλισμού'),
        findsNothing,
        reason:
            'Υπόδειξη σε κάθε κουμπί θα ήταν θόρυβος — μιλά μόνο όταν έχει '
            'κάτι να πει.',
      );
    });

    testWidgets('ο διαγραμμένος εξοπλισμός το λέει ΠΡΙΝ το πάτημα', (
      tester,
    ) async {
      await pumpCard(tester, task(equipmentDeleted: true));

      expect(
        find.text('Επεξεργασία Εξοπλισμού'),
        findsOneWidget,
        reason:
            'Το κουμπί μένει στη θέση του: η πληροφορία «υπήρχε σύνδεση» '
            'είναι χρήσιμη, δεν κρύβεται.',
      );
      final hint = tester.widget<Tooltip>(
        hintFor('Επεξεργασία Εξοπλισμού').first,
      );
      expect(hint.message, kTaskActionEquipmentMissingHint);
    });

    testWidgets('ο διαγραμμένος υπάλληλος το λέει ΠΡΙΝ το πάτημα', (
      tester,
    ) async {
      await pumpCard(tester, task(callerDeleted: true));

      final hint = tester.widget<Tooltip>(hintFor('Επεξεργασία Χρήστη').first);
      expect(hint.message, kTaskActionCallerMissingHint);
    });

    testWidgets('το διαγραμμένο τμήμα το λέει ΠΡΙΝ το πάτημα', (tester) async {
      await pumpCard(tester, task(departmentDeleted: true));

      final hint = tester.widget<Tooltip>(
        hintFor('Επεξεργασία Τμήματος').first,
      );
      expect(hint.message, kTaskActionDepartmentMissingHint);
    });

    testWidgets('η σήμανση αφορά μόνο τη διαγραμμένη οντότητα', (tester) async {
      await pumpCard(tester, task(equipmentDeleted: true));

      expect(
        hintFor('Επεξεργασία Χρήστη'),
        findsNothing,
        reason:
            'Ο υπάλληλος ζει· μια σήμανση εκεί θα έλεγε ψέματα για τρίτη '
            'οντότητα.',
      );
      expect(hintFor('Επεξεργασία Τμήματος'), findsNothing);
    });
  });
}
