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

  group('twoUnitDuration', () {
    test('ημέρες και ώρες', () {
      expect(
        twoUnitDuration(const Duration(days: 2, hours: 12)),
        '2 μέρες και 12 ώρες',
      );
    });

    test('τα λεπτά στρογγυλοποιούνται στην πλησιέστερη ώρα', () {
      expect(
        twoUnitDuration(const Duration(days: 2, hours: 11, minutes: 45)),
        '2 μέρες και 12 ώρες',
      );
      expect(
        twoUnitDuration(const Duration(days: 2, hours: 12, minutes: 20)),
        '2 μέρες και 12 ώρες',
      );
    });

    test('το κρατούμενο ανεβαίνει σε ημέρα αντί για «24 ώρες»', () {
      expect(
        twoUnitDuration(const Duration(days: 2, hours: 23, minutes: 45)),
        '3 μέρες',
      );
      expect(
        twoUnitDuration(
          const Duration(hours: 23, minutes: 59, seconds: 40),
        ),
        '1 μέρα',
      );
    });

    test('ώρες και λεπτά', () {
      expect(
        twoUnitDuration(const Duration(hours: 3, minutes: 15)),
        '3 ώρες και 15 λεπτά',
      );
    });

    test('τα δευτερόλεπτα στρογγυλοποιούνται στο πλησιέστερο λεπτό', () {
      expect(
        twoUnitDuration(const Duration(hours: 3, minutes: 14, seconds: 40)),
        '3 ώρες και 15 λεπτά',
      );
    });

    test('το κρατούμενο ανεβαίνει σε ώρα αντί για «60 λεπτά»', () {
      expect(
        twoUnitDuration(const Duration(hours: 2, minutes: 59, seconds: 50)),
        '3 ώρες',
      );
    });

    test('λεπτά και δευτερόλεπτα', () {
      expect(
        twoUnitDuration(const Duration(minutes: 5, seconds: 30)),
        '5 λεπτά και 30 δευτερόλεπτα',
      );
    });

    test('κάτω από ένα λεπτό: μόνο δευτερόλεπτα', () {
      expect(twoUnitDuration(const Duration(seconds: 42)), '42 δευτερόλεπτα');
    });

    test('ενικός όπου χρειάζεται', () {
      expect(
        twoUnitDuration(const Duration(days: 1, hours: 1)),
        '1 μέρα και 1 ώρα',
      );
      expect(
        twoUnitDuration(const Duration(minutes: 1, seconds: 1)),
        '1 λεπτό και 1 δευτερόλεπτο',
      );
    });

    test('η μηδενική δεύτερη μονάδα παραλείπεται', () {
      expect(twoUnitDuration(const Duration(days: 3)), '3 μέρες');
      expect(twoUnitDuration(const Duration(hours: 4)), '4 ώρες');
    });

    test('η αρνητική διάρκεια μετρά το ίδιο απόλυτο διάστημα', () {
      expect(
        twoUnitDuration(const Duration(days: -2, hours: -12)),
        '2 μέρες και 12 ώρες',
      );
    });
  });

  group('dueRelativeLabel', () {
    final now = DateTime(2026, 7, 31, 18, 0);

    test('λήξη στο μέλλον', () {
      expect(
        dueRelativeLabel(now, now.add(const Duration(hours: 3, minutes: 15))),
        'Λήγει σε 3 ώρες και 15 λεπτά',
      );
    });

    test('λήξη στο παρελθόν', () {
      expect(
        dueRelativeLabel(
          now,
          now.subtract(const Duration(days: 2, hours: 12)),
        ),
        'Εκκρεμεί 2 μέρες και 12 ώρες',
      );
    });

    test('διαφορά κάτω από ένα λεπτό, πριν ή μετά', () {
      expect(dueRelativeLabel(now, now), 'Λήγει τώρα');
      expect(
        dueRelativeLabel(now, now.add(const Duration(seconds: 30))),
        'Λήγει τώρα',
      );
      expect(
        dueRelativeLabel(now, now.subtract(const Duration(seconds: 30))),
        'Λήγει τώρα',
      );
    });
  });
}
