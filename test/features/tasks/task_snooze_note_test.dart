// Unit tests: προαιρετικός λόγος αναβολής στο μοντέλο Task.
//
//   flutter test test/features/tasks/task_snooze_note_test.dart

import 'dart:convert';

import 'package:call_logger/features/tasks/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

Task _baseTask({String? snoozeHistoryJson}) {
  return Task(
    title: 'Δοκιμαστική εκκρεμότητα',
    dueDate: '2026-05-26T17:00:00.000',
    status: 'open',
    snoozeHistoryJson: snoozeHistoryJson,
  );
}

void main() {
  group('TaskSnoozeEntry note', () {
    test('addSnoozeEntry με note αποθηκεύει note στο entry και στο JSON', () {
      final due = DateTime(2026, 5, 27, 10, 0);
      final updated = _baseTask().addSnoozeEntry(due, note: 'κάτι');

      expect(updated.snoozeEntries.last.note, 'κάτι');

      final decoded = jsonDecode(updated.snoozeHistoryJson!) as List;
      final lastMap = decoded.last as Map<String, dynamic>;
      expect(lastMap['note'], 'κάτι');
    });

    test('addSnoozeEntry χωρίς note ή με κενό/whitespace δεν γράφει κλειδί note', () {
      final due = DateTime(2026, 5, 27, 10, 0);

      for (final note in [null, '', '   ', '\t\n']) {
        final updated = _baseTask().addSnoozeEntry(due, note: note);
        expect(updated.snoozeEntries.last.note, isNull);

        final decoded = jsonDecode(updated.snoozeHistoryJson!) as List;
        final lastMap = decoded.last as Map<String, dynamic>;
        expect(lastMap.containsKey('note'), isFalse);
      }
    });

    test('παλιό snoozeHistoryJson (ISO strings ή Maps χωρίς note) — backward compatibility', () {
      const isoList = '["2026-05-20T12:00:00.000","2026-05-21T15:30:00.000"]';
      final taskFromIso = _baseTask(snoozeHistoryJson: isoList);
      expect(taskFromIso.snoozeEntries, hasLength(2));
      expect(taskFromIso.snoozeEntries.every((e) => e.note == null), isTrue);

      const mapWithoutNote =
          '[{"snoozedAt":"2026-05-20T12:00:00.000","dueAt":"2026-05-21T18:00:00.000"}]';
      final taskFromMap = _baseTask(snoozeHistoryJson: mapWithoutNote);
      expect(taskFromMap.snoozeEntries, hasLength(1));
      expect(taskFromMap.snoozeEntries.first.note, isNull);
    });

    test('combinedSearchText περιλαμβάνει τους λόγους αναβολής', () {
      final due = DateTime(2026, 5, 27, 10, 0);
      final updated = _baseTask().addSnoozeEntry(
        due,
        note: 'περιμένω απάντηση πελάτη',
      );

      expect(
        updated.combinedSearchText,
        contains('περιμένω απάντηση πελάτη'),
      );
    });
  });
}
