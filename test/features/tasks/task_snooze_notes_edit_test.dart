// Unit tests: επεξεργασία σημειώσεων αναβολών στο μοντέλο Task.
//
//   flutter test test/features/tasks/task_snooze_notes_edit_test.dart

import 'dart:convert';

import 'package:call_logger/features/tasks/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

const _snooze1At = '2026-06-01T09:15:00.000';
const _snooze1Due = '2026-06-02T12:00:00.000';
const _snooze2At = '2026-06-03T14:30:00.000';
const _snooze2Due = '2026-06-04T08:00:00.000';

String _twoEntryHistoryJson({String? note1, String? note2}) {
  return jsonEncode([
    {
      'snoozedAt': _snooze1At,
      'dueAt': _snooze1Due,
      'note': ?note1,
    },
    {
      'snoozedAt': _snooze2At,
      'dueAt': _snooze2Due,
      'note': ?note2,
    },
  ]);
}

Task _taskWithTwoSnoozes({String? note1, String? note2}) {
  return Task(
    title: 'Εκκρεμότητα με αναβολές',
    dueDate: '2026-06-05T17:00:00.000',
    status: 'snoozed',
    snoozeHistoryJson: _twoEntryHistoryJson(note1: note1, note2: note2),
  );
}

void main() {
  group('Task.withUpdatedSnoozeNotes', () {
    test('διατηρούνται snoozedAt/dueAt και αλλάζει μόνο το note', () {
      final task = _taskWithTwoSnoozes(note1: 'παλιό 1', note2: 'παλιό 2');
      final before = task.snoozeEntries;

      final updated = task.withUpdatedSnoozeNotes([
        'νέο 1',
        'νέο 2',
      ]);

      expect(updated.snoozeEntries, hasLength(2));
      expect(updated.snoozeEntries[0].snoozedAt, before[0].snoozedAt);
      expect(updated.snoozeEntries[0].dueAt, before[0].dueAt);
      expect(updated.snoozeEntries[1].snoozedAt, before[1].snoozedAt);
      expect(updated.snoozeEntries[1].dueAt, before[1].dueAt);
      expect(updated.snoozeEntries[0].note, 'νέο 1');
      expect(updated.snoozeEntries[1].note, 'νέο 2');

      final decoded = jsonDecode(updated.snoozeHistoryJson!) as List;
      expect(decoded[0]['snoozedAt'], _snooze1At);
      expect(decoded[0]['dueAt'], _snooze1Due);
      expect(decoded[1]['snoozedAt'], _snooze2At);
      expect(decoded[1]['dueAt'], _snooze2Due);
    });

    test('κενή σημείωση αποθηκεύεται ως null (χωρίς κλειδί note στο JSON)', () {
      final task = _taskWithTwoSnoozes(note1: 'υπήρχε', note2: 'και αυτό');

      final updated = task.withUpdatedSnoozeNotes(['', '   ']);

      expect(updated.snoozeEntries[0].note, isNull);
      expect(updated.snoozeEntries[1].note, isNull);

      final decoded = jsonDecode(updated.snoozeHistoryJson!) as List;
      for (final item in decoded) {
        final map = item as Map<String, dynamic>;
        expect(map.containsKey('note'), isFalse);
      }
    });

    test('task χωρίς αναβολές ή με λάθος μήκος λίστας μένει αμετάβλητο', () {
      final noSnoozes = Task(
        title: 'Χωρίς αναβολές',
        dueDate: '2026-06-05T17:00:00.000',
        status: 'open',
      );
      expect(
        identical(noSnoozes, noSnoozes.withUpdatedSnoozeNotes(['x'])),
        isTrue,
      );

      final withSnoozes = _taskWithTwoSnoozes();
      expect(
        identical(withSnoozes, withSnoozes.withUpdatedSnoozeNotes(['μόνο ένα'])),
        isTrue,
      );
      expect(
        identical(
          withSnoozes,
          withSnoozes.withUpdatedSnoozeNotes(['ένα', 'δύο', 'τρία']),
        ),
        isTrue,
      );
    });

    test('round-trip μέσω snoozeEntries επιστρέφει τις νέες σημειώσεις', () {
      final task = _taskWithTwoSnoozes();
      final updated = task.withUpdatedSnoozeNotes([
        'πρώτη επεξεργασμένη',
        'δεύτερη επεξεργασμένη',
      ]);

      final roundTrip = Task(
        title: task.title,
        dueDate: task.dueDate,
        status: task.status,
        snoozeHistoryJson: updated.snoozeHistoryJson,
      );

      expect(roundTrip.snoozeEntries[0].note, 'πρώτη επεξεργασμένη');
      expect(roundTrip.snoozeEntries[1].note, 'δεύτερη επεξεργασμένη');
    });
  });
}
