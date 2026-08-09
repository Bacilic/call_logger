// Unit tests: το χρονικό πλαίσιο της Αναφοράς Lansweeper.
//
//   flutter test test/features/history/lansweeper_report_scope_test.dart

import 'package:call_logger/features/history/models/dashboard_filter_model.dart';
import 'package:call_logger/features/history/models/lansweeper_report_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Τετάρτη 05/08/2026, μεσημέρι — η ώρα που περνούν οι κλήσεις στο Lansweeper.
  final now = DateTime(2026, 8, 5, 13, 20);

  group('resolveFilter', () {
    test('«Σήμερα» δίνει τη σημερινή ημέρα και στα δύο άκρα', () {
      final filter = LansweeperReportScope.today.resolveFilter(now);

      expect(filter.dateFrom, DateTime(2026, 8, 5));
      expect(filter.dateTo, DateTime(2026, 8, 5));
    });

    test('η ώρα της ημέρας δεν επηρεάζει το διάστημα', () {
      final earlyMorning = LansweeperReportScope.today.resolveFilter(
        DateTime(2026, 8, 5, 7, 5),
      );
      final lateNight = LansweeperReportScope.today.resolveFilter(
        DateTime(2026, 8, 5, 23, 59),
      );

      expect(earlyMorning.dateFrom, lateNight.dateFrom);
      expect(earlyMorning.dateTo, lateNight.dateTo);
    });

    test('«Χθες» δίνει την προηγούμενη ημέρα', () {
      final filter = const LansweeperReportScope.range(
        LansweeperReportRange.yesterday,
      ).resolveFilter(now);

      expect(filter.dateFrom, DateTime(2026, 8, 4));
      expect(filter.dateTo, DateTime(2026, 8, 4));
    });

    test('«Χθες» περνά σωστά την αλλαγή μήνα', () {
      final filter = const LansweeperReportScope.range(
        LansweeperReportRange.yesterday,
      ).resolveFilter(DateTime(2026, 8, 1, 13));

      expect(filter.dateFrom, DateTime(2026, 7, 31));
      expect(filter.dateTo, DateTime(2026, 7, 31));
    });

    test('«7 ημέρες» μετράει τη σημερινή μέσα στις επτά', () {
      final filter = const LansweeperReportScope.range(
        LansweeperReportRange.last7Days,
      ).resolveFilter(now);

      expect(filter.dateFrom, DateTime(2026, 7, 30));
      expect(filter.dateTo, DateTime(2026, 8, 5));
    });

    test('«Όλες οι ακαταχώρητες» δεν βάζει όριο ημερομηνίας', () {
      final filter = const LansweeperReportScope.range(
        LansweeperReportRange.allUnregistered,
      ).resolveFilter(now);

      expect(filter.dateFrom, isNull);
      expect(filter.dateTo, isNull);
    });

    test('τα φίλτρα των Στατιστικών περνούν αυτούσια', () {
      final dashboard = DashboardFilterModel(
        dateFrom: DateTime(2026, 6, 5),
        dateTo: DateTime(2026, 7, 28),
        department: 'Γραμματεία ΤΕΠ',
      );

      final filter = LansweeperReportScope.dashboard(
        dashboard,
      ).resolveFilter(now);

      expect(filter.dateFrom, DateTime(2026, 6, 5));
      expect(filter.dateTo, DateTime(2026, 7, 28));
      expect(filter.department, 'Γραμματεία ΤΕΠ');
    });
  });

  group('label', () {
    test('κάθε προκαθορισμένο διάστημα έχει το δικό του όνομα', () {
      expect(LansweeperReportScope.today.label, 'Σήμερα');
      expect(
        const LansweeperReportScope.range(
          LansweeperReportRange.yesterday,
        ).label,
        'Χθες',
      );
      expect(
        const LansweeperReportScope.range(
          LansweeperReportRange.last7Days,
        ).label,
        '7 ημέρες',
      );
      expect(
        const LansweeperReportScope.range(
          LansweeperReportRange.allUnregistered,
        ).label,
        'Όλες οι ακαταχώρητες',
      );
    });

    test('τα φίλτρα των Στατιστικών δεν έχουν δικό τους όνομα', () {
      final scope = LansweeperReportScope.dashboard(
        const DashboardFilterModel(),
      );

      expect(scope.label, isNull);
    });
  });
}
