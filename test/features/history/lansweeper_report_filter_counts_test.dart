// Unit test: μετρητές κατηγορίας και αντιστοίχιση φίλτρου αναφοράς Lansweeper.
//
//   flutter test test/features/history/lansweeper_report_filter_counts_test.dart

import 'package:call_logger/features/history/models/lansweeper_sync_state.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_report_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lansweeperReportCategoryCounts', () {
    test('υπολογίζει σωστά πλήθη ανά κατηγορία', () {
      final counts = lansweeperReportCategoryCounts(<String?>[
        LansweeperSyncState.unsent,
        LansweeperSyncState.sent,
        LansweeperSyncState.excluded,
        LansweeperSyncState.failed,
        LansweeperSyncState.unsent,
      ]);

      expect(counts.unsent, 2);
      expect(counts.sent, 1);
      expect(counts.excluded, 1);
      expect(counts.failed, 1);
      expect(counts.total, 5);
    });

    test('κενή ή whitespace κατάσταση μετρά ως ακαταχώρητη', () {
      final counts = lansweeperReportCategoryCounts(<String?>[
        null,
        '',
        '   ',
        '\t',
      ]);

      expect(counts.unsent, 4);
      expect(counts.sent, 0);
      expect(counts.excluded, 0);
      expect(counts.failed, 0);
      expect(counts.total, 4);
    });

    test('άγνωστη κατάσταση μετρά μόνο στο total', () {
      final counts = lansweeperReportCategoryCounts(<String?>[
        'unknown_state',
        'pending',
        LansweeperSyncState.unsent,
      ]);

      expect(counts.unsent, 1);
      expect(counts.sent, 0);
      expect(counts.excluded, 0);
      expect(counts.failed, 0);
      expect(counts.total, 3);
    });

    test('forFilter επιστρέφει σωστές τιμές', () {
      const counts = LansweeperReportCategoryCounts(
        unsent: 3,
        sent: 2,
        excluded: 1,
        failed: 4,
        total: 10,
      );

      expect(counts.forFilter(LansweeperReportFilter.unsentOnly), 3);
      expect(counts.forFilter(LansweeperReportFilter.sentOnly), 2);
      expect(counts.forFilter(LansweeperReportFilter.excludedOnly), 1);
      expect(counts.forFilter(LansweeperReportFilter.failedOnly), 4);
      expect(counts.forFilter(LansweeperReportFilter.all), 10);
    });
  });

  group('lansweeperReportStateMatches', () {
    test('συμφωνεί με τα πλήθη της lansweeperReportCategoryCounts', () {
      final states = <String?>[
        LansweeperSyncState.unsent,
        null,
        LansweeperSyncState.sent,
        '  ',
        LansweeperSyncState.excluded,
        LansweeperSyncState.failed,
        'orphan',
      ];
      final counts = lansweeperReportCategoryCounts(states);

      var matchedUnsent = 0;
      var matchedSent = 0;
      var matchedExcluded = 0;
      var matchedFailed = 0;
      var matchedAll = 0;

      for (final state in states) {
        if (lansweeperReportStateMatches(
          LansweeperReportFilter.unsentOnly,
          state,
        )) {
          matchedUnsent++;
        }
        if (lansweeperReportStateMatches(
          LansweeperReportFilter.sentOnly,
          state,
        )) {
          matchedSent++;
        }
        if (lansweeperReportStateMatches(
          LansweeperReportFilter.excludedOnly,
          state,
        )) {
          matchedExcluded++;
        }
        if (lansweeperReportStateMatches(
          LansweeperReportFilter.failedOnly,
          state,
        )) {
          matchedFailed++;
        }
        if (lansweeperReportStateMatches(LansweeperReportFilter.all, state)) {
          matchedAll++;
        }
      }

      expect(matchedUnsent, counts.unsent);
      expect(matchedSent, counts.sent);
      expect(matchedExcluded, counts.excluded);
      expect(matchedFailed, counts.failed);
      expect(matchedAll, counts.total);
    });
  });
}
