// Μετάβαση από τις κάρτες του Πίνακα Ελέγχου προς το Ιστορικό, και ο διακόπτης
// «Άγνωστου» των Κορυφαίων Καλούντων.
//
//   flutter test test/features/history/dashboard_view_all_navigation_test.dart

import 'package:call_logger/features/history/models/dashboard_summary_model.dart';
import 'package:call_logger/features/history/providers/history_provider.dart';
import 'package:call_logger/features/history/screens/dashboard_cards.dart';
import 'package:call_logger/features/history/screens/dashboard_palette_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Στατιστικά με μόνο τους καλούντες συμπληρωμένους — ό,τι χρειάζεται η κάρτα.
DashboardSummaryModel summaryWithTopCallers(List<CallerStat> topCallers) =>
    DashboardSummaryModel(
      totalCalls: 84,
      totalDurationSeconds: 0,
      avgDurationSeconds: 0,
      previousPeriodTotalCalls: 0,
      previousPeriodTotalDurationSeconds: 0,
      previousPeriodAvgDurationSeconds: 0,
      dailyTrend: const [],
      sparklineLast7Days: const [],
      topCallers: topCallers,
      longestCalls: const [],
      hourlyDistribution: const [],
      byDepartment: const [],
      byIssue: const [],
    );

void main() {
  group('visibleCallerStats', () {
    const stats = [
      CallerStat(name: kDashboardUnknownCallerLabel, count: 75),
      CallerStat(name: 'Φιλιώ Γκίλλα', count: 9),
    ];

    test('χωρίς απόκρυψη επιστρέφει τα πάντα', () {
      final visible = visibleCallerStats(stats, hideUnknownCaller: false);

      expect(visible.map((s) => s.name), [
        kDashboardUnknownCallerLabel,
        'Φιλιώ Γκίλλα',
      ]);
    });

    test('με απόκρυψη φεύγει μόνο ο «Άγνωστος»', () {
      final visible = visibleCallerStats(stats, hideUnknownCaller: true);

      expect(visible.map((s) => s.name), ['Φιλιώ Γκίλλα']);
    });
  });

  group('ταξινόμηση που ζητούν οι κάρτες', () {
    test('«ανά κλήση» ζητά τις μεγαλύτερες διάρκειες πρώτες', () {
      final sort = historySortForLongestCalls(LongestCallsMode.perCall);

      expect(sort.column, HistorySortColumn.duration);
      expect(sort.ascending, isFalse);
    });

    test('«ανά άτομο» ζητά ομαδοποίηση ανά καλούντα', () {
      final sort = historySortForLongestCalls(LongestCallsMode.perPerson);

      expect(sort.column, HistorySortColumn.caller);
      expect(sort.ascending, isTrue);
    });

    test('οι Κορυφαίοι Καλούντες ζητούν ομαδοποίηση ανά καλούντα', () {
      expect(historySortForTopCallers.column, HistorySortColumn.caller);
      expect(historySortForTopCallers.ascending, isTrue);
    });
  });

  group('HistorySortNotifier', () {
    test('η ίδια στήλη αντιστρέφει τη φορά, η νέα ξεκινά αύξουσα', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(historySortProvider.notifier);

      notifier.toggle(HistorySortColumn.duration);
      expect(container.read(historySortProvider).ascending, isTrue);

      notifier.toggle(HistorySortColumn.duration);
      expect(container.read(historySortProvider).ascending, isFalse);

      notifier.toggle(HistorySortColumn.caller);
      expect(
        container.read(historySortProvider).column,
        HistorySortColumn.caller,
      );
      expect(container.read(historySortProvider).ascending, isTrue);
    });

    test('η μετάβαση από κάρτα επιβάλλει τη ζητούμενη ταξινόμηση', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(historySortProvider.notifier)
          .apply(historySortForLongestCalls(LongestCallsMode.perCall));

      final sort = container.read(historySortProvider);
      expect(sort.column, HistorySortColumn.duration);
      expect(sort.ascending, isFalse);
    });
  });

  group('TopCallersCard', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    testWidgets('ο διακόπτης βγάζει τον «Άγνωστο» από τη λίστα', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 420,
                child: TopCallersCard(
                  data: summaryWithTopCallers(const [
                    CallerStat(name: kDashboardUnknownCallerLabel, count: 75),
                    CallerStat(name: 'Φιλιώ Γκίλλα', count: 9),
                  ]),
                  colors: DashboardPaletteColors.from(DashboardPalette.classic),
                  onViewAll: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 900));

      expect(find.text(kDashboardUnknownCallerLabel), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pump(const Duration(milliseconds: 900));

      expect(find.text(kDashboardUnknownCallerLabel), findsNothing);
      expect(find.text('Φιλιώ Γκίλλα'), findsOneWidget);
      expect(
        find.text('+ 75 κλήσεις χωρίς καταγεγραμμένο καλούντα'),
        findsOneWidget,
      );
    });
  });
}
