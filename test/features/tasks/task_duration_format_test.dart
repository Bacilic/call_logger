// Unit tests: ανθρώπινη μορφοποίηση διάρκειας εκκρεμότητας.
//
//   flutter test test/features/tasks/task_duration_format_test.dart

import 'package:call_logger/features/tasks/utils/task_duration_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('durationSince', () {
    test('λεπτά μόνο', () {
      final from = DateTime(2026, 7, 12, 10, 0);
      final to = from.add(const Duration(minutes: 45));
      expect(durationSince(from, to), '45 λεπτά');
    });

    test('ώρες και λεπτά', () {
      final from = DateTime(2026, 7, 12, 8, 0);
      final to = from.add(const Duration(hours: 3, minutes: 20));
      expect(durationSince(from, to), '3 ώρες και 20 λεπτά');
    });

    test('ημέρες, ώρες και λεπτά', () {
      final from = DateTime(2026, 7, 10, 9, 0);
      final to = from.add(const Duration(days: 2, hours: 5, minutes: 10));
      expect(durationSince(from, to), '2 μ. 5 ώρες και 10 λεπτά');
    });

    test('ελάχιστο 1 λεπτό όταν η διαφορά είναι μηδενική ή αρνητική', () {
      final at = DateTime(2026, 7, 12, 12, 0);
      expect(durationSince(at, at), '1 λεπτά');
      expect(
        durationSince(at, at.subtract(const Duration(minutes: 5))),
        '1 λεπτά',
      );
    });
  });
}
