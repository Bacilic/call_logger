// Ο κοινός ελεγκτής ημερομηνιών: μία ημερομηνία από πεδίο που δέχεται μόνο
// ημερομηνία.
//
//   flutter test test/core/utils/date_parser_util_test.dart

import 'package:call_logger/core/utils/date_parser_util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DateParserUtil.parseSingleDate', () {
    test('η μορφή αποθήκευσης διαβάζεται', () {
      expect(
        DateParserUtil.parseSingleDate('2026-03-05').$1,
        DateTime(2026, 3, 5),
      );
    });

    test('ελληνική γραφή με πλήρες ή σύντομο έτος', () {
      expect(
        DateParserUtil.parseSingleDate('5/3/2024').$1,
        DateTime(2024, 3, 5),
      );
      expect(DateParserUtil.parseSingleDate('5/3/24').$1, DateTime(2024, 3, 5));
    });

    test('χωρίς έτος: το τρέχον έτος', () {
      final year = DateTime.now().year;
      expect(DateParserUtil.parseSingleDate('5/3').$1, DateTime(year, 3, 5));
    });

    test('ημερομηνία που δεν υπάρχει: μήνυμα, ποτέ 3 Μαρτίου', () {
      expect(DateParserUtil.parseSingleDate('31/02/2026'), (
        null,
        'Δεν υπάρχει αυτή η μέρα',
      ));
      expect(DateParserUtil.parseSingleDate('2026-02-31'), (
        null,
        'Δεν υπάρχει αυτή η μέρα',
      ));
    });

    test('κείμενο ή σκέτος αριθμός δεν είναι ημερομηνία', () {
      for (final text in ['abc', 'αύριο', '5', '1/2/3/4']) {
        expect(DateParserUtil.parseSingleDate(text), (
          null,
          DateParserUtil.invalidDateMessage,
        ), reason: text);
      }
    });

    test('κενό: καμία ημερομηνία, κανένα μήνυμα', () {
      expect(DateParserUtil.parseSingleDate('  '), (null, null));
    });
  });
}
