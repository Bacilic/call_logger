// Η νέα διάταξη των Στατιστικών χωρά χωρίς υπερχειλίσεις, και τα κείμενα
// αναδιπλώνονται αντί να κόβονται.
//
// Τα σφάλματα διάταξης του Flutter καταπίνονται στην κανονική εκτέλεση: η
// οθόνη δείχνει μια κίτρινη λωρίδα και προχωρά. Εδώ τα κάνουμε αποτυχία, ώστε
// να μη φτάσουν στον χρήστη.
//
//   flutter test test/features/history/dashboard_layout_test.dart

import 'package:call_logger/features/history/models/dashboard_date_preset.dart';
import 'package:call_logger/features/history/models/dashboard_filter_model.dart';
import 'package:call_logger/features/history/models/dashboard_summary_model.dart';
import 'package:call_logger/features/history/screens/dashboard_cards.dart';
import 'package:call_logger/features/history/screens/dashboard_filter_bar.dart';
import 'package:call_logger/features/history/screens/dashboard_palette_colors.dart';
import 'package:call_logger/features/history/providers/dashboard_provider.dart';
import 'package:call_logger/features/history/providers/history_provider.dart';
import 'package:call_logger/features/history/screens/dashboard_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Το πραγματικό παράθυρο της εφαρμογής στα Windows, όχι το προεπιλεγμένο
/// 800x600 του δοκιμαστή — που είναι κάτω από το ελάχιστο της εφαρμογής.
const Size _kWindowSize = Size(1600, 1200);

DashboardSummaryModel _summaryWithLongNames() {
  return const DashboardSummaryModel(
    totalCalls: 228,
    totalDurationSeconds: 80340,
    avgDurationSeconds: 352,
    previousPeriodTotalCalls: 110,
    previousPeriodTotalDurationSeconds: 53820,
    previousPeriodAvgDurationSeconds: 489,
    dailyTrend: [],
    sparklineLast7Days: [],
    topCallers: [
      // Μακρύ ονοματεπώνυμο: ακριβώς η περίπτωση που κοβόταν πριν.
      CallerStat(name: 'Κωνσταντίνα Παπαδοπούλου-Αναγνωστοπούλου', count: 8),
      CallerStat(name: kDashboardUnknownCallerLabel, count: 56),
    ],
    longestCalls: [],
    hourlyDistribution: [],
    byDepartment: [],
    byIssue: [],
  );
}

/// Οι λίστες των φίλτρων έρχονται από τη βάση· εδώ δίνονται έτοιμες.
///
/// Χωρίς αυτό, οι providers σκάνε και το Riverpod ξαναδοκιμάζει σε δύο
/// δευτερόλεπτα — ένα χρονόμετρο που κρέμεται μετά το τέλος του ελέγχου. Το
/// ζητούμενο εδώ είναι η διάταξη, όχι η ανάγνωση της βάσης.
Widget _wrap(Widget child, {double width = 1560}) {
  return ProviderScope(
    overrides: [
      callFilterDepartmentsProvider.overrideWith(
        (ref) async => const ['Γραμματεία ΤΕΠ', 'Καρδιολογική'],
      ),
      callFilterCallersProvider.overrideWith(
        (ref) async => const [(name: 'Αφροδίτη Καρρά', phones: '2534')],
      ),
      callFilterEquipmentProvider.overrideWith(
        (ref) async => const ['5010', '3495'],
      ),
      historyCategoriesProvider.overrideWith(
        (ref) async => const ['Medico', 'Εκτυπωτής'],
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: SizedBox(width: width, child: child)),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  final colors = DashboardPaletteColors.from(DashboardPalette.classic);

  group('Η λωρίδα φίλτρων', () {
    testWidgets('χωρά στο παράθυρο χωρίς υπερχείλιση', (tester) async {
      tester.view.physicalSize = _kWindowSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          DashboardFilterBar(
            colors: colors,
            filter: const DashboardFilterModel(),
            activeDatePreset: DashboardDatePreset.last30,
            controlsExpanded: true,
            onPickDateRange: () {},
            onSetDatePreset: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('λέει με λόγια ότι δεν ισχύει κανένα φίλτρο', (tester) async {
      tester.view.physicalSize = _kWindowSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          DashboardFilterBar(
            colors: colors,
            filter: const DashboardFilterModel(),
            activeDatePreset: DashboardDatePreset.all,
            controlsExpanded: false,
            onPickDateRange: () {},
            onSetDatePreset: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.textContaining('Ενεργά φίλτρα: κανένα'),
        findsOneWidget,
        reason:
            'Η άδεια γραμμή είναι διφορούμενη: «δεν φιλτράρω» ή «δεν το δείχνει '
            'η οθόνη;». Μια πρόταση απαντά.',
      );
    });

    testWidgets('κάθε ενεργό φίλτρο εμφανίζεται ως μάρκα', (tester) async {
      tester.view.physicalSize = _kWindowSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          DashboardFilterBar(
            colors: colors,
            filter: const DashboardFilterModel(
              department: 'Γραμματεία ΤΕΠ',
              category: 'Medico',
            ),
            activeDatePreset: DashboardDatePreset.all,
            controlsExpanded: false,
            onPickDateRange: () {},
            onSetDatePreset: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Τμήμα: Γραμματεία ΤΕΠ'), findsOneWidget);
      expect(find.text('Κατηγορία: Medico'), findsOneWidget);
      expect(find.text('Καθαρισμός όλων'), findsOneWidget);
    });

    testWidgets('τα χειριστήρια κρύβονται, οι μάρκες μένουν', (tester) async {
      tester.view.physicalSize = _kWindowSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          DashboardFilterBar(
            colors: colors,
            filter: const DashboardFilterModel(department: 'Καρδιολογική'),
            activeDatePreset: DashboardDatePreset.all,
            controlsExpanded: false,
            onPickDateRange: () {},
            onSetDatePreset: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('30 ημέρες'), findsNothing);
      expect(find.text('Τμήμα: Καρδιολογική'), findsOneWidget);
    });
  });

  group('Η πάνω μπάρα', () {
    testWidgets('η επιστροφή είναι βέλος, όχι κουμπί «Έξοδος»', (
      tester,
    ) async {
      tester.view.physicalSize = _kWindowSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var backTaps = 0;
      await tester.pumpWidget(
        _wrap(
          DashboardTopBar(
            colors: colors,
            palette: DashboardPalette.classic,
            filtersExpanded: true,
            onBack: () => backTaps++,
            onToggleFilters: () {},
            onExport: (_) {},
            onPaletteChanged: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Έξοδος'), findsNothing);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pump();
      expect(backTaps, 1);
    });

    testWidgets('το εικονίδιο της οθόνης δεν είναι τηλέφωνο', (tester) async {
      tester.view.physicalSize = _kWindowSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          DashboardTopBar(
            colors: colors,
            palette: DashboardPalette.classic,
            filtersExpanded: true,
            onBack: () {},
            onToggleFilters: () {},
            onExport: (_) {},
            onPaletteChanged: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byIcon(Icons.call_outlined),
        findsNothing,
        reason:
            'Το τηλέφωνο σημαίνει «εδώ καταγράφεις κλήσεις»· τα Στατιστικά '
            'είναι άλλη δουλειά και θέλουν δικό τους σήμα.',
      );
      expect(find.byIcon(Icons.insights_rounded), findsOneWidget);
    });

    testWidgets('η εξαγωγή προσφέρει Excel και PDF', (tester) async {
      tester.view.physicalSize = _kWindowSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      DashboardExportFormat? chosen;
      await tester.pumpWidget(
        _wrap(
          DashboardTopBar(
            colors: colors,
            palette: DashboardPalette.classic,
            filtersExpanded: true,
            onBack: () {},
            onToggleFilters: () {},
            onExport: (format) => chosen = format,
            onPaletteChanged: (_) {},
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Εξαγωγή'));
      await tester.pumpAndSettle();

      expect(find.text('Excel (.xlsx)'), findsOneWidget);
      expect(find.text('PDF (.pdf)'), findsOneWidget);

      await tester.tap(find.text('Excel (.xlsx)'));
      await tester.pumpAndSettle();
      expect(chosen, DashboardExportFormat.excel);
    });

    testWidgets('η παλέτα ζει στο μενού, όχι στη γραμμή τίτλου', (
      tester,
    ) async {
      tester.view.physicalSize = _kWindowSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      DashboardPalette? chosen;
      await tester.pumpWidget(
        _wrap(
          DashboardTopBar(
            colors: colors,
            palette: DashboardPalette.classic,
            filtersExpanded: true,
            onBack: () {},
            onToggleFilters: () {},
            onExport: (_) {},
            onPaletteChanged: (palette) => chosen = palette,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Χρώματα'), findsNothing);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Παλέτα χρωμάτων'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ωκεανός'));
      await tester.pumpAndSettle();

      expect(chosen, DashboardPalette.ocean);
    });
  });

  group('Οι Κορυφαίοι Καλούντες', () {
    testWidgets('τα μακριά ονόματα αναδιπλώνονται αντί να κόβονται', (
      tester,
    ) async {
      tester.view.physicalSize = _kWindowSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          TopCallersCard(
            data: _summaryWithLongNames(),
            colors: colors,
            onViewAll: () {},
          ),
          // Το στενό μισό της οθόνης, όπου η κάρτα ζει στην πράξη.
          width: 420,
        ),
      );
      // Η κάρτα κινεί τις μπάρες προόδου της· περιμένουμε να ηρεμήσουν, ώστε να
      // μη μείνει χρονόμετρο ζωντανό μετά το τέλος του ελέγχου.
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final name = tester.widget<Text>(
        find.text('Κωνσταντίνα Παπαδοπούλου-Αναγνωστοπούλου'),
      );
      expect(
        name.maxLines,
        greaterThan(1),
        reason:
            'Το κόψιμο σε μία γραμμή έσβηνε το επώνυμο — το μέρος που ξεχωρίζει '
            'τον έναν άνθρωπο από τον άλλον.',
      );
    });
  });
}
