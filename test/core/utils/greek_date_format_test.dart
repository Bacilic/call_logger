// Unit tests: ελληνικές σύντομες μορφές ημερομηνίας.
//
//   flutter test test/core/utils/greek_date_format_test.dart

import 'package:call_logger/core/utils/greek_date_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('τρίγραμμο ανά ημέρα εβδομάδας', () {
    expect(weekdayShortEl(DateTime(2026, 7, 27)), 'ΔΕΥ');
    expect(weekdayShortEl(DateTime(2026, 7, 28)), 'ΤΡΙ');
    expect(weekdayShortEl(DateTime(2026, 7, 29)), 'ΤΕΤ');
    expect(weekdayShortEl(DateTime(2026, 7, 30)), 'ΠΕΜ');
    expect(weekdayShortEl(DateTime(2026, 7, 31)), 'ΠΑΡ');
    expect(weekdayShortEl(DateTime(2026, 8)), 'ΣΑΒ');
    expect(weekdayShortEl(DateTime(2026, 8, 2)), 'ΚΥΡ');
  });

  test('η κανονική γραφή της ημέρας ακολουθεί την ίδια σειρά', () {
    expect(weekdayShortElTitle(DateTime(2026, 7, 27)), 'Δευ');
    expect(weekdayShortElTitle(DateTime(2026, 8, 2)), 'Κυρ');
  });

  test('σύντομο όνομα μήνα', () {
    expect(monthShortEl(DateTime(2026)), 'Ιαν');
    expect(monthShortEl(DateTime(2026, 6)), 'Ιουν');
    expect(monthShortEl(DateTime(2026, 7)), 'Ιουλ');
    expect(monthShortEl(DateTime(2026, 8)), 'Αυγ');
    expect(monthShortEl(DateTime(2026, 12)), 'Δεκ');
  });

  group('formatGreekShortDate', () {
    test('ημέρα, ημερομηνία με δύο ψηφία, μήνας και έτος', () {
      expect(formatGreekShortDate(DateTime(2026, 8, 5)), 'Τετ 05 - Αυγ - 2026');
    });

    test('διψήφια ημέρα δεν παίρνει μηδενικό', () {
      expect(
        formatGreekShortDate(DateTime(2026, 12, 31)),
        'Πεμ 31 - Δεκ - 2026',
      );
    });
  });

  group('formatGreekShortDateFromIso', () {
    test('μετατρέπει ημερομηνία αρχείου έκδοσης', () {
      expect(formatGreekShortDateFromIso('2026-08-04'), 'Τρι 04 - Αυγ - 2026');
    });

    test('αγνοεί κενά γύρω από την ημερομηνία', () {
      expect(
        formatGreekShortDateFromIso('  2026-08-05  '),
        'Τετ 05 - Αυγ - 2026',
      );
    });

    test('ό,τι δεν αναγνωρίζεται επιστρέφεται αυτούσιο', () {
      expect(formatGreekShortDateFromIso('χθες'), 'χθες');
      expect(formatGreekShortDateFromIso('04/08/2026'), '04/08/2026');
      expect(formatGreekShortDateFromIso(''), '');
    });

    test('ανύπαρκτη ημερομηνία δεν μεταμφιέζεται σε άλλη', () {
      expect(formatGreekShortDateFromIso('2026-13-45'), '2026-13-45');
      expect(formatGreekShortDateFromIso('2026-02-30'), '2026-02-30');
      expect(formatGreekShortDateFromIso('2026-00-10'), '2026-00-10');
    });
  });

  group('formatGreekTodayAwareTimestamp', () {
    final now = DateTime(2026, 9, 18, 17, 52);

    test('ό,τι έγινε σήμερα δείχνει μόνο την ώρα', () {
      expect(
        formatGreekTodayAwareTimestamp(DateTime(2026, 9, 18, 8, 5), now: now),
        'σήμερα 08:05',
      );
    });

    test('η ίδια στιγμή με το τώρα μετράει ως σήμερα', () {
      expect(formatGreekTodayAwareTimestamp(now, now: now), 'σήμερα 17:52');
    });

    test('χθεσινό δείχνει ολόκληρη την ημερομηνία', () {
      expect(
        formatGreekTodayAwareTimestamp(DateTime(2026, 9, 17, 8, 40), now: now),
        '17/09/2026 08:40',
      );
    });

    // Ίδια ημέρα και μήνας, άλλη χρονιά: η σύγκριση δεν επιτρέπεται να
    // κοιτάζει μόνο ημέρα/μήνα.
    test('ίδια ημερομηνία περυσινής χρονιάς δεν είναι «σήμερα»', () {
      expect(
        formatGreekTodayAwareTimestamp(DateTime(2025, 9, 18, 17, 52), now: now),
        '18/09/2025 17:52',
      );
    });

    test('μονοψήφια ώρα και ημέρα παίρνουν μηδενικό μπροστά', () {
      expect(
        formatGreekTodayAwareTimestamp(DateTime(2026, 1, 3, 9, 7), now: now),
        '03/01/2026 09:07',
      );
    });
  });
}
