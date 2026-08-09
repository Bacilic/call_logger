// Widget tests: σύνδεση των χειριστηρίων στις KPI κάρτες του Πίνακα Ελέγχου.
//
//   flutter test test/features/history/dashboard_kpi_card_controls_test.dart

import 'package:call_logger/features/history/screens/dashboard_cards.dart';
import 'package:call_logger/features/history/screens/dashboard_palette_colors.dart';
import 'package:call_logger/features/history/screens/dashboard_top_entity_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

/// Το `fl_chart` (sparkline της κάρτας) φτιάχνει τρεις αναγνωριστές χειρονομιών
/// μέσα στο RenderBox του και δεν τους αποδεσμεύει ποτέ — δεν υπάρχει `dispose`
/// στο `render_base_chart.dart` του πακέτου. Αγνοούμε ΜΟΝΟ αυτούς τους τρεις
/// τύπους, ώστε μια δική μας διαρροή (π.χ. controller) να εξακολουθεί να
/// κοκκινίζει.
final _ignoreChartRecognizers = LeakTesting.settings.withIgnored(
  notDisposed: {
    'PanGestureRecognizer': null,
    'TapGestureRecognizer': null,
    'LongPressGestureRecognizer': null,
  },
);

void main() {
  final colors = DashboardPaletteColors.from(DashboardPalette.classic);

  KpiCardData buildCard(String title, {VoidCallback? onTap}) => KpiCardData(
    title: title,
    value: '1',
    subtitle: 'υπότιτλος',
    isUp: true,
    icon: Icons.call_rounded,
    points: const [1, 2],
    onTap: onTap,
    colors: colors.kpiBlue,
  );

  Future<void> pumpGrid(WidgetTester tester, List<KpiCardData> cards) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: KpiGrid(
              crossAxisCount: 2,
              cards: cards,
              paletteColors: colors,
            ),
          ),
        ),
      ),
    );
    // Οι κάρτες εμφανίζονται με κλιμακωτή κίνηση εισόδου.
    await tester.pump(const Duration(milliseconds: 700));
  }

  testWidgets(
    'το κλικ φτάνει στην ενέργεια της ίδιας της κάρτας',
    experimentalLeakTesting: _ignoreChartRecognizers,
    (tester) async {
      var first = 0;
      var second = 0;
      await pumpGrid(tester, [
        buildCard('Πρώτη', onTap: () => first++),
        buildCard('Δεύτερη', onTap: () => second++),
      ]);

      await tester.tap(find.text('Δεύτερη'));
      await tester.pump();

      expect(second, 1);
      expect(first, 0);
    },
  );

  testWidgets(
    'κάρτα χωρίς ενέργεια δεν αντιδρά στο κλικ',
    experimentalLeakTesting: _ignoreChartRecognizers,
    (tester) async {
      var withAction = 0;
      await pumpGrid(tester, [
        buildCard('Χωρίς ενέργεια'),
        buildCard('Με ενέργεια', onTap: () => withAction++),
      ]);

      await tester.tap(find.text('Χωρίς ενέργεια'));
      await tester.pump();

      expect(withAction, 0);
    },
  );

  testWidgets('ο επιλογέας όψης αλλάζει όψη με ένα κλικ', (tester) async {
    TopEntityMode? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TopEntityModeSelector(
            mode: TopEntityMode.department,
            onChanged: (mode) => picked = mode,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pump();
    expect(picked, TopEntityMode.caller);

    await tester.tap(find.byIcon(Icons.build_outlined));
    await tester.pump();
    expect(picked, TopEntityMode.issue);
  });
}
