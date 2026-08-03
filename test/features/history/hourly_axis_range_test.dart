// Unit tests: ορατό εύρος ωρών στην «Κατανομή ανά ώρα».
//
//   flutter test test/features/history/hourly_axis_range_test.dart

import 'package:call_logger/features/history/models/dashboard_summary_model.dart';
import 'package:call_logger/features/history/utils/hourly_axis_range.dart';
import 'package:flutter_test/flutter_test.dart';

/// Οι 24 κάδοι όπως τους παράγει το repository, με κλήσεις στις [callsByHour].
List<HourlyBucket> _buckets(Map<int, int> callsByHour) =>
    List<HourlyBucket>.generate(
      24,
      (hour) => HourlyBucket(hour: hour, callCount: callsByHour[hour] ?? 0),
    );

void main() {
  group('visibleHourRange', () {
    test('συνηθισμένη μέρα: μία ώρα ανάσα πριν και μετά', () {
      final range = visibleHourRange(
        _buckets({7: 12, 10: 25, 14: 6, 18: 1, 20: 1}),
      );
      expect(range.firstHour, 6);
      expect(range.lastHour, 21);
    });

    test('χωρίς καμία κλήση δείχνει ολόκληρη τη μέρα', () {
      final range = visibleHourRange(_buckets({}));
      expect(range.firstHour, 0);
      expect(range.lastHour, 23);
    });

    test('μία μόνο κλήση απλώνεται στο ελάχιστο εύρος', () {
      final range = visibleHourRange(_buckets({9: 1}));
      expect(range.span, 8);
      expect(range.contains(9), isTrue);
    });

    test('κλήση στην πρώτη ώρα της μέρας δεν βγαίνει εκτός ορίων', () {
      final range = visibleHourRange(_buckets({0: 3}));
      expect(range.firstHour, 0);
      expect(range.span, 8);
    });

    test('κλήση στην τελευταία ώρα της μέρας δεν βγαίνει εκτός ορίων', () {
      final range = visibleHourRange(_buckets({23: 3}));
      expect(range.lastHour, 23);
      expect(range.span, 8);
    });

    test('απογευματινή βάρδια απλώνει τον άξονα χωρίς ρύθμιση', () {
      final range = visibleHourRange(
        _buckets({8: 4, 12: 9, 17: 5, 22: 2}),
      );
      expect(range.firstHour, 7);
      expect(range.lastHour, 23);
    });

    test('μια απομονωμένη νυχτερινή κλήση τεντώνει τον άξονα, δεν κρύβεται', () {
      final range = visibleHourRange(_buckets({3: 1, 9: 10, 14: 4}));
      expect(range.firstHour, 2);
      expect(range.lastHour, 15);
      expect(range.contains(3), isTrue);
    });

    test('ήδη μεγάλο εύρος δεν μεγαλώνει άλλο από το ελάχιστο', () {
      final range = visibleHourRange(_buckets({7: 1, 15: 1}));
      expect(range.firstHour, 6);
      expect(range.lastHour, 16);
      expect(range.span, 11);
    });

    test('το ελάχιστο εύρος είναι παράμετρος, όχι σταθερά', () {
      final range = visibleHourRange(_buckets({9: 1}), minSpan: 12);
      expect(range.span, 12);
      expect(range.contains(9), isTrue);
    });

    test('η ώρα εκτός εύρους δεν περιλαμβάνεται', () {
      final range = visibleHourRange(_buckets({7: 1, 14: 1}));
      expect(range.contains(0), isFalse);
      expect(range.contains(23), isFalse);
      expect(range.contains(7), isTrue);
    });
  });
}
