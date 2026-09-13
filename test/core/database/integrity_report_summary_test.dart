// Τι φτάνει στην οθόνη όταν ο έλεγχος ακεραιότητας βρει εκατοντάδες βλάβες.
//
//   flutter test test/core/database/integrity_report_summary_test.dart

import 'package:call_logger/core/database/integrity_report_summary.dart';
import 'package:flutter_test/flutter_test.dart';

String _corruptReport(int pages) => List.generate(
  pages,
  (i) => 'Tree 18 page ${2100 + i} cell 3: Rowid 5041 out of order',
).join('\n');

void main() {
  group('λίγα ευρήματα', () {
    test('περνούν αυτούσια — δεν υπάρχει τι να κοπεί', () {
      final summary = summarizeIntegrityReport(
        'Page 42: btreeInitPage() returns error code 11',
      );

      expect(summary.findingCount, 1);
      expect(summary.wasTrimmed, isFalse);
      expect(summary.forDisplay, contains('Page 42'));
    });

    test('το πλήθος μετριέται σε γραμμές, αγνοώντας τις κενές', () {
      final summary = summarizeIntegrityReport('πρώτο\n\n  \nδεύτερο\n');
      expect(summary.findingCount, 2);
    });
  });

  group('εκατοντάδες ευρήματα', () {
    test('η οθόνη παίρνει σύνοψη, όχι τη λίστα', () {
      final summary = summarizeIntegrityReport(_corruptReport(214));

      expect(summary.findingCount, 214);
      expect(summary.wasTrimmed, isTrue);
      expect(summary.forDisplay, contains('214'));
      // Το δείγμα υπάρχει: ο τεχνικός θέλει να δει τι είδους βλάβη είναι.
      expect(summary.forDisplay, contains('Tree 18 page 2100'));
    });

    test('το κείμενο της οθόνης μένει μικρό, όσο κι αν μεγαλώσει η βλάβη', () {
      final small = summarizeIntegrityReport(_corruptReport(20));
      final huge = summarizeIntegrityReport(_corruptReport(2000));

      expect(huge.forDisplay.length, lessThan(500));
      // Δεκαπλάσια βλάβη δεν σημαίνει δεκαπλάσιο κείμενο στην οθόνη.
      expect(huge.forDisplay.length, lessThan(small.forDisplay.length + 20));
    });

    test('το πλήρες τεκμήριο δεν χάνεται', () {
      final summary = summarizeIntegrityReport(_corruptReport(214));

      expect(summary.full, contains('Tree 18 page 2313'));
      expect('\n'.allMatches(summary.full).length, 213);
    });
  });

  group('μία γραμμή-τέρας', () {
    test('κόβεται κι αυτή — ξεχειλίζει το ίδιο με τετρακόσιες κοντές', () {
      final summary = summarizeIntegrityReport('x' * 4000);

      expect(summary.findingCount, 1);
      expect(summary.wasTrimmed, isTrue);
      expect(summary.forDisplay.length, lessThan(200));
      expect(summary.full.length, 4000);
    });
  });

  test('κενό κείμενο δεν γεννά εύρημα', () {
    final summary = summarizeIntegrityReport('   \n  \n');
    expect(summary.findingCount, 0);
    expect(summary.forDisplay, isEmpty);
  });
}
