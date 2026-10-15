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
  // Έμεινε ΑΝΟΙΧΤΗ μετά από κάποια προθεσμία της; (ο κανόνας του ποσοστού
  // καθυστέρησης του διαστήματος)
  group('wasEverOverdue', () {
    final now = DateTime(2026, 10, 15);

    bool late({
      DateTime? endedAt,
      DateTime? currentDue,
      List<TaskSnoozeEntry> snoozes = const [],
    }) => TaskOverdueTimeline.wasEverOverdue(
      now: now,
      endedAt: endedAt,
      currentDue: currentDue,
      snoozes: snoozes,
    );

    test('έκλεισε ΠΡΙΝ την προθεσμία → δεν άργησε, ακόμη κι αν η προθεσμία '
        'έχει περάσει σήμερα', () {
      expect(
        late(currentDue: DateTime(2026, 3, 10), endedAt: DateTime(2026, 3, 5)),
        isFalse,
      );
    });

    test('έκλεισε ΜΕΤΑ την προθεσμία → άργησε', () {
      expect(
        late(currentDue: DateTime(2026, 3, 2), endedAt: DateTime(2026, 3, 3)),
        isTrue,
      );
    });

    test('ανοιχτή με περασμένη προθεσμία → άργησε· με μελλοντική → όχι', () {
      expect(late(currentDue: DateTime(2026, 3, 2)), isTrue);
      expect(late(currentDue: DateTime(2026, 12, 1)), isFalse);
    });

    test('χωρίς προθεσμία δεν μπορεί να άργησε', () {
      expect(late(currentDue: null), isFalse);
      expect(late(currentDue: null, endedAt: DateTime(2026, 3, 3)), isFalse);
    });

    test(
      'άργησε και ΜΕΤΑ αναβλήθηκε σε νέα προθεσμία → μετρά ως καθυστέρηση',
      () {
        expect(
          late(
            currentDue: DateTime(2026, 12, 1),
            snoozes: [
              TaskSnoozeEntry(
                snoozedAt: DateTime(2026, 3, 3),
                dueAt: DateTime(2026, 12, 1),
                replacedDueAt: DateTime(2026, 3, 2),
              ),
            ],
          ),
          isTrue,
        );
      },
    );

    test('αναβλήθηκε ΠΡΙΝ περάσει η προθεσμία → δεν άργησε', () {
      expect(
        late(
          currentDue: DateTime(2026, 12, 1),
          snoozes: [
            TaskSnoozeEntry(
              snoozedAt: DateTime(2026, 3, 2),
              dueAt: DateTime(2026, 12, 1),
              replacedDueAt: DateTime(2026, 3, 10),
            ),
          ],
        ),
        isFalse,
      );
    });

    test('αναβλήθηκε πριν την προθεσμία και η νέα τηρήθηκε → δεν άργησε', () {
      expect(
        late(
          currentDue: DateTime(2026, 3, 10),
          endedAt: DateTime(2026, 3, 5),
          snoozes: [
            TaskSnoozeEntry(
              snoozedAt: DateTime(2026, 3, 1),
              dueAt: DateTime(2026, 3, 10),
              replacedDueAt: DateTime(2026, 3, 2),
            ),
          ],
        ),
        isFalse,
      );
    });
  });
  // Ήταν ΑΝΟΙΧΤΗ στο τέλος μιας μέρας; (η καμπύλη «Ενεργές»)
  group('wasOpenAt', () {
    final dayEnd = DateTime(2026, 3, 4);

    test('δημιουργήθηκε πριν και δεν έχει τελειώσει → ανοιχτή', () {
      expect(
        TaskOverdueTimeline.wasOpenAt(
          dayEnd,
          createdAt: DateTime(2026, 3, 1),
          endedAt: null,
        ),
        isTrue,
      );
    });

    test('έκλεισε ή ακυρώθηκε πριν το τέλος της μέρας → όχι', () {
      expect(
        TaskOverdueTimeline.wasOpenAt(
          dayEnd,
          createdAt: DateTime(2026, 3, 1),
          endedAt: DateTime(2026, 3, 3, 12),
        ),
        isFalse,
      );
    });

    test('έκλεισε ΜΕΤΑ τη μέρα → ήταν ακόμη ανοιχτή', () {
      expect(
        TaskOverdueTimeline.wasOpenAt(
          dayEnd,
          createdAt: DateTime(2026, 3, 1),
          endedAt: DateTime(2026, 3, 5),
        ),
        isTrue,
      );
    });

    test('δημιουργήθηκε ΜΕΤΑ το τέλος της μέρας → δεν υπήρχε ακόμη', () {
      expect(
        TaskOverdueTimeline.wasOpenAt(
          dayEnd,
          createdAt: DateTime(2026, 3, 4, 9),
          endedAt: null,
        ),
        isFalse,
      );
    });
  });
}
