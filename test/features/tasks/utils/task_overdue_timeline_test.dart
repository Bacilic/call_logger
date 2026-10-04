// Αν μια εκκρεμότητα ήταν καθυστερημένη στο τέλος μιας περασμένης μέρας.
//
//   flutter test test/features/tasks/utils/task_overdue_timeline_test.dart

import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/utils/task_overdue_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// Τέλος της Τρίτης 3/3 — η στιγμή που κρίνεται.
final _tuesdayEnd = DateTime(2026, 3, 4);

bool _wasOverdue({
  DateTime? createdAt,
  DateTime? endedAt,
  DateTime? currentDue,
  List<TaskSnoozeEntry> snoozes = const [],
}) => TaskOverdueTimeline.wasOverdueAt(
  _tuesdayEnd,
  createdAt: createdAt ?? DateTime(2026, 2, 27),
  endedAt: endedAt,
  currentDue: currentDue,
  snoozes: snoozes,
);

void main() {
  test('ανοιχτή με περασμένη προθεσμία → καθυστερημένη', () {
    expect(_wasOverdue(currentDue: DateTime(2026, 3, 2)), isTrue);
  });

  test('έκλεισε ΜΕΤΑ την Τρίτη → μετρά στην Τρίτη', () {
    expect(
      _wasOverdue(
        currentDue: DateTime(2026, 3, 2),
        endedAt: DateTime(2026, 3, 5, 11),
      ),
      isTrue,
    );
  });

  test('έκλεισε ΠΡΙΝ το τέλος της Τρίτης → δεν μετρά', () {
    expect(
      _wasOverdue(
        currentDue: DateTime(2026, 3, 2),
        endedAt: DateTime(2026, 3, 3, 15),
      ),
      isFalse,
    );
  });

  test('δημιουργήθηκε μετά την Τρίτη → δεν μετρά', () {
    expect(
      _wasOverdue(
        createdAt: DateTime(2026, 3, 4, 9),
        currentDue: DateTime(2026, 3, 2),
      ),
      isFalse,
    );
  });

  test(
    'αναβολή ΜΕΤΑ την Τρίτη: κρίνεται με την προθεσμία που αντικατέστησε',
    () {
      expect(
        _wasOverdue(
          currentDue: DateTime(2026, 3, 10),
          snoozes: [
            TaskSnoozeEntry(
              snoozedAt: DateTime(2026, 3, 5, 10),
              dueAt: DateTime(2026, 3, 10),
              replacedDueAt: DateTime(2026, 3, 2),
            ),
          ],
        ),
        isTrue,
      );
    },
  );

  test('αναβολή ΠΡΙΝ την Τρίτη: ισχύει η νέα προθεσμία', () {
    expect(
      _wasOverdue(
        currentDue: DateTime(2026, 3, 10),
        snoozes: [
          TaskSnoozeEntry(
            snoozedAt: DateTime(2026, 3, 1, 10),
            dueAt: DateTime(2026, 3, 10),
            replacedDueAt: DateTime(2026, 2, 28),
          ),
        ],
      ),
      isFalse,
    );
  });

  test('παλιά αναβολή χωρίς καταγεγραμμένη προθεσμία → η τρέχουσα', () {
    expect(
      _wasOverdue(
        currentDue: DateTime(2026, 3, 10),
        snoozes: [
          TaskSnoozeEntry(
            snoozedAt: DateTime(2026, 3, 5, 10),
            dueAt: DateTime(2026, 3, 10),
          ),
        ],
      ),
      isFalse,
    );
  });

  test(
    'δύο αναβολές: ισχύει όποια προθεσμία έδωσε η τελευταία πριν την Τρίτη',
    () {
      expect(
        _wasOverdue(
          currentDue: DateTime(2026, 3, 20),
          snoozes: [
            TaskSnoozeEntry(
              snoozedAt: DateTime(2026, 3, 1, 10),
              dueAt: DateTime(2026, 3, 3, 9),
              replacedDueAt: DateTime(2026, 2, 28),
            ),
            TaskSnoozeEntry(
              snoozedAt: DateTime(2026, 3, 6, 10),
              dueAt: DateTime(2026, 3, 20),
              replacedDueAt: DateTime(2026, 3, 3, 9),
            ),
          ],
        ),
        isTrue,
      );
    },
  );
}
