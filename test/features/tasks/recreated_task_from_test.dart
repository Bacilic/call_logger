// Unit test: το «Εκ νέου» γεννά πραγματικά καθαρή εκκρεμότητα.
//
// Το παλιό copyWith(solutionNotes: null, ...) ΚΡΑΤΟΥΣΕ τις παλιές τιμές
// (σημασιολογία copyWith), οπότε η «νέα» εκκρεμότητα κουβαλούσε τη λύση,
// το ιστορικό αναβολών και τη σφραγίδα ολοκλήρωσης της παλιάς.
//
//   flutter test test/features/tasks/recreated_task_from_test.dart

import 'dart:convert';

import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/screens/tasks_screen_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('recreatedTaskFrom', () {
    final edited = Task(
      id: 42,
      title: 'Έλεγχος εκτυπωτή',
      description: 'Βγάζει κενές σελίδες.',
      dueDate: '2026-08-10T08:00:00.000',
      status: 'closed',
      priority: 2,
      solutionNotes: 'Αντικαταστάθηκε το τόνερ.',
      snoozeHistoryJson: jsonEncode([
        {'snoozedAt': '2026-08-01T09:00:00.000', 'dueAt': '2026-08-02'},
      ]),
      createdAt: '2026-07-30T08:00:00.000',
      updatedAt: '2026-08-01T10:00:00.000',
      completedAt: '2026-08-01T10:00:00.000',
      callerId: 3,
      departmentId: 5,
      userText: 'Ψαρρά Σοφία',
      phoneText: '2565',
    );

    test('κρατά τα στοιχεία της υπόθεσης', () {
      final fresh = recreatedTaskFrom(edited);

      expect(fresh.title, 'Έλεγχος εκτυπωτή');
      expect(fresh.description, 'Βγάζει κενές σελίδες.');
      expect(fresh.dueDate, '2026-08-10T08:00:00.000');
      expect(fresh.priority, 2);
      expect(fresh.callerId, 3);
      expect(fresh.departmentId, 5);
      expect(fresh.userText, 'Ψαρρά Σοφία');
      expect(fresh.phoneText, '2565');
    });

    test('δεν κουβαλά τίποτα από τον κύκλο ζωής της παλιάς', () {
      final fresh = recreatedTaskFrom(edited);

      expect(fresh.id, isNull);
      expect(fresh.status, 'open');
      expect(fresh.solutionNotes, isNull);
      expect(fresh.snoozeHistoryJson, isNull);
      expect(fresh.createdAt, isNull);
      expect(fresh.updatedAt, isNull);
      expect(fresh.completedAt, isNull);
    });
  });
}
