// Τι λέει ο διάλογος διένεξης — καθαρή λογική, χωρίς οθόνη.
//
//   flutter test test/features/tasks/task_conflict_summary_test.dart

import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/services/task_conflict_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Task task({
    required String status,
    String? solution,
    int? assignee,
  }) => Task(
    id: 7,
    title: 'Για δω τι θα δω;',
    dueDate: DateTime(2026, 8, 22, 16, 31).toIso8601String(),
    status: status,
    solutionNotes: solution,
    assignedOperatorId: assignee,
  );

  final now = DateTime(2026, 8, 22, 18, 5);
  final changedAt = DateTime(2026, 8, 22, 18, 0);

  test('ο άλλος ολοκλήρωσε: το λέει με το όνομά του και την ώρα', () {
    final summary = TaskConflictSummary.of(
      attempted: task(status: 'snoozed'),
      fresh: task(status: 'closed', solution: 'Αντικαταστάθηκε το καλώδιο.'),
      changedBy: 'Βλάσης',
      changedAt: changedAt,
      now: now,
    );

    expect(summary.headline, contains('Βλάσης'));
    expect(summary.headline, contains('ολοκλήρωσε'));
    expect(summary.headline, contains('18:00'));
    expect(summary.currentStateLine, contains('ολοκληρωμένη'));
    expect(summary.freshSolution, 'Αντικαταστάθηκε το καλώδιο.');
  });

  test('και οι δύο πήγαν να κλείσουν: «πρόλαβε»', () {
    final summary = TaskConflictSummary.of(
      attempted: task(status: 'closed', solution: 'Η δική μου λύση'),
      fresh: task(status: 'closed', solution: 'Η δική του λύση'),
      changedBy: 'Βλάσης',
      changedAt: changedAt,
      now: now,
    );

    expect(summary.headline, contains('πρόλαβε'));
    expect(
      summary.overwriteWarning,
      contains('λύση'),
      reason: 'Ο χρήστης πρέπει να ξέρει ότι σβήνει τη λύση του άλλου',
    );
  });

  test('άγνωστος δράστης: δεν εφευρίσκεται όνομα', () {
    final summary = TaskConflictSummary.of(
      attempted: task(status: 'open'),
      fresh: task(status: 'snoozed'),
      changedBy: null,
      changedAt: null,
      now: now,
    );

    expect(summary.headline, startsWith('Κάποιος άλλος'));
    expect(summary.headline, isNot(contains('στις')));
    expect(summary.headline, contains('άλλαξε'));
  });

  test('η ανάθεση μετράει στα όσα χάνονται', () {
    final summary = TaskConflictSummary.of(
      attempted: task(status: 'open', assignee: 3),
      fresh: task(status: 'open', assignee: 5),
      changedBy: 'Βλάσης',
      changedAt: changedAt,
      now: now,
    );

    expect(summary.overwriteWarning, contains('ανάθεση'));
  });

  test('η ώρα παίρνει ημερομηνία όταν δεν είναι σήμερα', () {
    expect(
      TaskConflictSummary.describeMoment(
        DateTime(2026, 8, 20, 9, 15),
        now: now,
      ),
      '20/08 09:15',
    );
    expect(
      TaskConflictSummary.describeMoment(
        DateTime(2026, 8, 22, 9, 15),
        now: now,
      ),
      '09:15',
    );
  });
}
