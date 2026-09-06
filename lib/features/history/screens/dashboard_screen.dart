import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/user_facing_error_messages.dart';
import '../../../core/widgets/calendar_range_picker.dart';
import '../../../core/widgets/quick_call_fab.dart';
import '../models/dashboard_summary_model.dart';
import '../models/lansweeper_report_scope.dart';
import '../providers/dashboard_provider.dart';
import '../providers/history_provider.dart';
import '../services/dashboard_export_launcher.dart';
import '../utils/history_navigation_feedback.dart';
import '../widgets/lansweeper/lansweeper_report_launcher.dart';
import 'dashboard_cards.dart';
import 'dashboard_filter_bar.dart';
import 'dashboard_kpi_cards.dart';
import 'dashboard_palette_colors.dart';
import 'dashboard_top_bar.dart';
import 'dashboard_top_entity_selector.dart';

/// Οθόνη στατιστικών κλήσεων (πίνακας ελέγχου / dashboard).
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  /// Τα χειριστήρια των φίλτρων ξεκινούν ανοιχτά: η οθόνη ανοίγει με φίλτρο
  /// ημερομηνιών ήδη σε ισχύ, οπότε ο χρήστης πρέπει να μπορεί να το δει και να
  /// το αλλάξει χωρίς να ψάξει κουμπί.
  bool _filtersExpanded = true;

  /// Οι κατανομές ξεκινούν ανοιχτές — απόφαση χρήστη.
  bool _showDistributions = true;

  TopEntityMode _topEntityMode = TopEntityMode.department;

  Future<void> _openLansweeperReportDialog() async {
    await openLansweeperReport(
      context,
      ref,
      // Η είσοδος από τα Στατιστικά είναι η μόνη που δανείζεται τα φίλτρα της
      // οθόνης — και το δηλώνει, αντί να το υποθέτει η αναφορά.
      scope: LansweeperReportScope.dashboard(ref.read(dashboardFilterProvider)),
    );
  }

  Future<void> _pickDateRange() async {
    final filter = ref.read(dashboardFilterProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final result = await showCalendarRangePickerDialog(
      context,
      initialValue: DateTimeRange(
        start: filter.dateFrom ?? today,
        end: filter.dateTo ?? today,
      ),
    );
    if (!mounted || result == null) return;
    if (result.wasCleared) {
      await ref.read(dashboardFilterProvider.notifier).clearDateRange();
      return;
    }
    final range = result.range;
    if (range == null) return;
    await ref
        .read(dashboardFilterProvider.notifier)
        .setCustomDateRange(range.start, range.end);
  }

  /// Η εξαγωγή δουλεύει μόνο πάνω σε νούμερα που υπάρχουν ήδη στην οθόνη:
  /// αλλιώς το αρχείο θα έδειχνε άλλο σύνολο από αυτό που είδε ο χρήστης.
  Future<void> _export(DashboardExportFormat format) async {
    final messenger = ScaffoldMessenger.of(context);
    final data = ref.read(dashboardStatsProvider).asData?.value;
    if (data == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Τα στατιστικά φορτώνουν ακόμη — δοκιμάστε ξανά.'),
        ),
      );
      return;
    }
    await exportDashboardStatistics(
      messenger: messenger,
      format: format,
      data: data,
      filter: ref.read(dashboardFilterProvider),
    );
  }

  /// Επιστροφή στο Ιστορικό με το πλαίσιο της κάρτας: ίδια φίλτρα, ίδιο
  /// διάστημα, καθαρή αναζήτηση ώστε να φανούν όντως όλες οι κλήσεις, και η
  /// ταξινόμηση που αναπαράγει τη σειρά της κάρτας.
  void _openHistoryForCard(HistorySortModel sort) {
    final dash = ref.read(dashboardFilterProvider);
    final messenger = ScaffoldMessenger.of(context);
    ref.read(historySortProvider.notifier).apply(sort);
    final cleared = ref
        .read(historyFilterProvider.notifier)
        .focusFromDashboard(dash);
    Navigator.of(context).pop();
    showHistoryFiltersClearedSnackBar(messenger, cleared);
  }

  void _openHistoryForTopCallers() =>
      _openHistoryForCard(historySortForTopCallers);

  void _openHistoryForLongestCalls() => _openHistoryForCard(
    historySortForLongestCalls(ref.read(dashboardLongestCallsModeProvider)),
  );

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(dashboardFilterProvider);
    final activeDatePreset = ref
        .read(dashboardFilterProvider.notifier)
        .activeDatePreset;
    final statsAsync = ref.watch(dashboardStatsProvider);
    final palette = ref.watch(dashboardPaletteProvider);
    final colors = DashboardPaletteColors.from(palette);

    return Scaffold(
      backgroundColor: colors.pageBg,
      floatingActionButton: const QuickCallFloatingButton(
        scope: QuickCallFabScope.overlayRoute,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.pageGradientStart, colors.pageGradientEnd],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                DashboardTopBar(
                  colors: colors,
                  palette: palette,
                  filtersExpanded: _filtersExpanded,
                  onBack: () => Navigator.of(context).maybePop(),
                  onToggleFilters: () =>
                      setState(() => _filtersExpanded = !_filtersExpanded),
                  onExport: _export,
                  onPaletteChanged: (value) => ref
                      .read(dashboardPaletteProvider.notifier)
                      .select(value),
                ),
                const SizedBox(height: 12),
                DashboardFilterBar(
                  colors: colors,
                  filter: filter,
                  activeDatePreset: activeDatePreset,
                  controlsExpanded: _filtersExpanded,
                  onPickDateRange: _pickDateRange,
                  onSetDatePreset: (preset) => ref
                      .read(dashboardFilterProvider.notifier)
                      .setDatePreset(preset),
                ),
                const SizedBox(height: 16),
                statsAsync.when(
                  data: (data) => _content(data, colors),
                  loading: () => LoadingDashboard(colors: colors),
                  error: (e, _) => ErrorCard(
                    message: 'Σφάλμα φόρτωσης: ${humanizeUserFacingError(e)}',
                    colors: colors,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(DashboardSummaryModel data, DashboardPaletteColors colors) {
    final filter = ref.watch(dashboardFilterProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final kpiCrossCount = width >= 1200
            ? 4
            : width >= 800
            ? 2
            : 1;
        final splitMainRow = width >= 1050;

        return Column(
          children: [
            if (data.totalCalls == 0) ...[
              EmptyStateCard(
                message: 'Δεν βρέθηκαν κλήσεις για τα επιλεγμένα φίλτρα.',
                colors: colors,
              ),
              const SizedBox(height: 12),
            ],
            KpiGrid(
              crossAxisCount: kpiCrossCount,
              paletteColors: colors,
              cards: buildDashboardKpiCards(
                data: data,
                filter: filter,
                colors: colors,
                topEntityMode: _topEntityMode,
                onTopEntityModeChanged: (selected) =>
                    setState(() => _topEntityMode = selected),
                onLansweeperReportTap: _openLansweeperReportDialog,
              ),
            ),
            const SizedBox(height: 18),
            if (splitMainRow)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: _topCallersCard(data, colors)),
                  const SizedBox(width: 16),
                  Expanded(flex: 9, child: _longestCallsCard(data, colors)),
                ],
              )
            else ...[
              _topCallersCard(data, colors),
              const SizedBox(height: 16),
              _longestCallsCard(data, colors),
            ],
            const SizedBox(height: 18),
            MoreSection(
              expanded: _showDistributions,
              onToggle: () =>
                  setState(() => _showDistributions = !_showDistributions),
              data: data,
              colors: colors,
              formatDuration: formatDashboardCallDuration,
            ),
          ],
        );
      },
    );
  }

  Widget _topCallersCard(
    DashboardSummaryModel data,
    DashboardPaletteColors colors,
  ) {
    return TopCallersCard(
      data: data,
      colors: colors,
      onViewAll: _openHistoryForTopCallers,
    );
  }

  Widget _longestCallsCard(
    DashboardSummaryModel data,
    DashboardPaletteColors colors,
  ) {
    return LongestCallsCard(
      data: data,
      topN: ref.watch(dashboardFilterProvider).topN,
      colors: colors,
      formatDuration: formatDashboardCallDuration,
      formatAggregateDuration: formatDashboardAggregateDuration,
      onTopNChanged: (value) => ref
          .read(dashboardFilterProvider.notifier)
          .update((s) => s.copyWith(topN: value)),
      onViewAll: _openHistoryForLongestCalls,
    );
  }
}
