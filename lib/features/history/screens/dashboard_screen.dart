import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/calendar_range_picker.dart';
import '../models/dashboard_date_preset.dart';
import '../models/dashboard_filter_model.dart';
import '../models/dashboard_summary_model.dart';
import '../providers/dashboard_provider.dart';
import '../providers/history_provider.dart';
import '../widgets/lansweeper_report_dialog.dart';
import 'dashboard_cards.dart';
import 'dashboard_filter_pane.dart';
import 'dashboard_palette_colors.dart';

enum TopEntityMode { department, caller, issue }

/// Οθόνη στατιστικών κλήσεων (πίνακας ελέγχου / dashboard).
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  static const Duration _debounceDuration = Duration(milliseconds: 350);

  final TextEditingController _keywordController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _equipmentController = TextEditingController();

  Timer? _debounceTimer;
  bool _isFilterOpen = false;
  bool _showMoreSection = false;
  TopEntityMode _topEntityMode = TopEntityMode.department;
  DashboardPalette _palette = DashboardPalette.classic;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final f = ref.read(dashboardFilterProvider);
      _keywordController.text = f.keyword;
      _userController.text = f.userName ?? '';
      _equipmentController.text = f.equipmentCode ?? '';
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _keywordController.dispose();
    _userController.dispose();
    _equipmentController.dispose();
    super.dispose();
  }

  void _scheduleDebouncedTextFilters() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (!mounted) return;
      _pushTextFiltersToProvider();
    });
  }

  void _pushTextFiltersToProvider() {
    final u = _userController.text.trim();
    final e = _equipmentController.text.trim();
    ref
        .read(dashboardFilterProvider.notifier)
        .update(
          (s) => s.copyWith(
            keyword: _keywordController.text,
            userName: u.isEmpty ? null : u,
            equipmentCode: e.isEmpty ? null : e,
            clearUserName: u.isEmpty,
            clearEquipmentCode: e.isEmpty,
          ),
        );
  }

  void _applyAllFilters() {
    _debounceTimer?.cancel();
    _pushTextFiltersToProvider();
  }

  Future<void> _openLansweeperReportDialog() async {
    _applyAllFilters();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => const LansweeperReportDialog(),
    );
  }

  Future<void> _pickDateRange() async {
    final filter = ref.read(dashboardFilterProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialStart = filter.dateFrom ?? today;
    final initialEnd = filter.dateTo ?? today;
    final result = await showCalendarRangePickerDialog(
      context,
      initialValue: DateTimeRange(start: initialStart, end: initialEnd),
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

  Future<void> _setDatePreset(DashboardDatePreset preset) async {
    await ref.read(dashboardFilterProvider.notifier).setDatePreset(preset);
  }

  /// Διάρκεια ανά κλήση — λεπτά:δευτερόλεπτα (π.χ. `03:15`).
  String _formatCallDurationSeconds(num seconds) {
    final safeSeconds = seconds.isNaN ? 0 : seconds.round();
    final absSeconds = math.max(0, safeSeconds);
    final m = absSeconds ~/ 60;
    final s = absSeconds % 60;
    if (m > 0) {
      return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '00:${s.toString().padLeft(2, '0')}';
  }

  /// Συνολικές / ημερήσιες διάρκειες — `ώρ:λεπ` ή `λεπ:δευτ` (π.χ. `10ω:23λ`).
  String _formatAggregateDurationSeconds(num seconds) {
    final safeSeconds = seconds.isNaN ? 0 : seconds.round();
    final absSeconds = math.max(0, safeSeconds);
    final h = absSeconds ~/ 3600;
    final m = (absSeconds % 3600) ~/ 60;
    final s = absSeconds % 60;
    if (h > 0) {
      return '$hω:${m.toString().padLeft(2, '0')}λ';
    }
    if (m > 0) {
      return '$mλ:${s.toString().padLeft(2, '0')}δ';
    }
    return '$sδ';
  }

  String _formatDeltaPercent(num current, num previous) {
    if (previous == 0) {
      if (current == 0) return '0.0%';
      return '100.0%';
    }
    final delta = ((current - previous) / previous) * 100;
    final prefix = delta >= 0 ? '+' : '';
    return '$prefix${delta.toStringAsFixed(1)}%';
  }

  String _formatAvgCallsPerDay(DashboardSummaryModel data) {
    final avg = data.avgCallsPerActiveDay;
    if (avg == null) return 'Μ.Ο.: —';
    return 'Μ.Ο.: ${avg.round()} κλήσεις / ημέρα';
  }

  String _formatAvgDurationPerDay(DashboardSummaryModel data) {
    final avg = data.avgDurationSecondsPerActiveDay;
    if (avg == null) return 'Μ.Ο.: —';
    return 'Μ.Ο.: ${_formatAggregateDurationSeconds(avg)} / ημέρα';
  }

  List<String> _callsSparklineTooltips(List<DailyTrendPoint> days) {
    return days
        .map((dayPoint) {
          if (dayPoint.callCount <= 0) return '';
          final day = DateFormat('dd/MM').format(dayPoint.date);
          return '$day: ${formatKpiCallCountLabel(dayPoint.callCount)}';
        })
        .toList(growable: false);
  }

  List<String> _durationSparklineTooltips(List<DailyTrendPoint> days) {
    return days
        .map((dayPoint) {
          if (dayPoint.totalDurationSeconds <= 0) return '';
          final day = DateFormat('dd/MM').format(dayPoint.date);
          return '$day: ${formatKpiAggregateDurationSeconds(dayPoint.totalDurationSeconds)}';
        })
        .toList(growable: false);
  }

  List<String> _avgCallSparklineTooltips(List<DailyTrendPoint> days) {
    return days
        .map((dayPoint) {
          if (dayPoint.callCount <= 0) return '';
          final day = DateFormat('dd/MM').format(dayPoint.date);
          final avgSeconds =
              dayPoint.totalDurationSeconds / dayPoint.callCount;
          return '$day: ${formatKpiCallDurationSeconds(avgSeconds)}';
        })
        .toList(growable: false);
  }

  String _formatTopEntityShareSubtitle(int count, int totalCalls) {
    if (totalCalls <= 0) return '$count κλήσεις';
    final pct = (count / totalCalls) * 100;
    return '$count κλήσεις (${pct.toStringAsFixed(1)}% του συνόλου)';
  }

  List<KpiBarSparklinePoint> _runnerUpBarPoints(
    KpiAllDatesBarSparklines? bars,
    TopEntityMode mode,
  ) {
    if (bars == null) return const <KpiBarSparklinePoint>[];
    switch (mode) {
      case TopEntityMode.department:
        return bars.departmentCountsRank2To6;
      case TopEntityMode.caller:
        return bars.callerCountsRank2To6;
      case TopEntityMode.issue:
        return bars.issueCountsRank2To6;
    }
  }

  void _popWithHistoryPrefill({
    required String keyword,
    required bool clearKeyword,
  }) {
    final dash = ref.read(dashboardFilterProvider);
    final kw = clearKeyword ? '' : keyword;
    ref
        .read(historyFilterProvider.notifier)
        .update(
          (s) => s.copyWith(
            keyword: kw,
            dateFrom: dash.dateFrom,
            dateTo: dash.dateTo,
            clearDateRange: dash.dateFrom == null && dash.dateTo == null,
          ),
        );
    Navigator.of(context).pop();
  }

  KpiTopEntity _resolveTopEntity(DashboardSummaryModel data) {
    switch (_topEntityMode) {
      case TopEntityMode.department:
        final d = data.byDepartment.isNotEmpty ? data.byDepartment.first : null;
        return KpiTopEntity(
          title: 'Κορυφαίο Τμήμα',
          label: d?.name ?? '-',
          count: d?.count ?? 0,
          icon: Icons.workspace_premium_rounded,
        );
      case TopEntityMode.caller:
        final c = data.topCallers.isNotEmpty ? data.topCallers.first : null;
        return KpiTopEntity(
          title: 'Κορυφαίος Καλών',
          label: c?.name ?? '-',
          count: c?.count ?? 0,
          icon: Icons.person_pin_circle_outlined,
        );
      case TopEntityMode.issue:
        final i = data.byIssue.isNotEmpty ? data.byIssue.first : null;
        return KpiTopEntity(
          title: 'Κορυφαία Βλάβη',
          label: i?.name ?? '-',
          count: i?.count ?? 0,
          icon: Icons.build_circle_outlined,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = ref.watch(dashboardFilterProvider);
    final activeDatePreset =
        ref.read(dashboardFilterProvider.notifier).activeDatePreset;
    final statsAsync = ref.watch(dashboardStatsProvider);
    final departmentsAsync = ref.watch(dashboardDepartmentsProvider);
    final colors = DashboardPaletteColors.from(_palette);

    final dateRangeLabel = _formatDateRange(filter);

    return Scaffold(
      backgroundColor: colors.pageBg,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.pageGradientStart, colors.pageGradientEnd],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  children: [
                    _buildTopBar(theme, colors),
                    const SizedBox(height: 16),
                    statsAsync.when(
                      data: (data) {
                        final topEntity = _resolveTopEntity(data);
                        final allDatesMode = data.isAllDatesMode;
                        final allDatesBars = data.allDatesBarSparklines;
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            final kpiCrossCount = width >= 1200
                                ? 4
                                : width >= 800
                                ? 2
                                : 1;
                            final mainSplit = width >= 1050;
                            return Column(
                              children: [
                                if (data.totalCalls == 0) ...[
                                  EmptyStateCard(
                                    message:
                                        'Δεν βρέθηκαν κλήσεις για τα επιλεγμένα φίλτρα.',
                                    colors: colors,
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                KpiGrid(
                                  crossAxisCount: kpiCrossCount,
                                  paletteColors: colors,
                                  cards: [
                                    KpiCardData(
                                      title:
                                          data.totalCallsKpiTitleAllDates() ??
                                          'Συνολικές κλήσεις · ${filter.kpiTotalCallsRangeTitle()}',
                                      value: '${data.totalCalls}',
                                      subtitle: allDatesMode
                                          ? _formatAvgCallsPerDay(data)
                                          : '${_formatDeltaPercent(data.totalCalls, data.previousPeriodTotalCalls)} vs ${filter.kpiComparisonRangeHint()}: ${data.previousPeriodTotalCalls}',
                                      isUp:
                                          data.totalCalls >=
                                          data.previousPeriodTotalCalls,
                                      showTrendIndicator: !allDatesMode,
                                      useBarSparkline: allDatesMode,
                                      icon: Icons.call_rounded,
                                      points: data.sparklineLast7Days
                                          .map((e) => e.callCount.toDouble())
                                          .toList(),
                                      sparklineTooltips: _callsSparklineTooltips(
                                        data.sparklineLast7Days,
                                      ),
                                      barPoints:
                                          allDatesBars?.callsByMonth ??
                                          const <KpiBarSparklinePoint>[],
                                      colors: colors.kpiBlue,
                                    ),
                                    KpiCardData(
                                      title:
                                          'Συνολική Διάρκεια Κλήσεων (ώρ:λεπ)',
                                      value: _formatAggregateDurationSeconds(
                                        data.totalDurationSeconds,
                                      ),
                                      subtitle: allDatesMode
                                          ? _formatAvgDurationPerDay(data)
                                          : '${_formatDeltaPercent(data.totalDurationSeconds, data.previousPeriodTotalDurationSeconds)} vs ${filter.kpiComparisonRangeHint()}: ${_formatAggregateDurationSeconds(data.previousPeriodTotalDurationSeconds)}',
                                      isUp:
                                          data.totalDurationSeconds >=
                                          data.previousPeriodTotalDurationSeconds,
                                      showTrendIndicator: !allDatesMode,
                                      useBarSparkline: allDatesMode,
                                      icon: Icons.timer_outlined,
                                      points: data.sparklineLast7Days
                                          .map(
                                            (e) => e.totalDurationSeconds
                                                .toDouble(),
                                          )
                                          .toList(),
                                      sparklineTooltips: _durationSparklineTooltips(
                                        data.sparklineLast7Days,
                                      ),
                                      barPoints:
                                          allDatesBars
                                              ?.durationByWeekdayMonToFri ??
                                          const <KpiBarSparklinePoint>[],
                                      colors: colors.kpiGreen,
                                    ),
                                    KpiCardData(
                                      title:
                                          'Μέσος Όρος ανά Κλήση (λεπ:δευτ)',
                                      value: _formatCallDurationSeconds(
                                        data.avgDurationSeconds,
                                      ),
                                      subtitle: allDatesMode
                                          ? 'Διάμεσος χρόνος: ${_formatCallDurationSeconds(data.medianDurationSeconds)}'
                                          : '${_formatDeltaPercent(data.avgDurationSeconds, data.previousPeriodAvgDurationSeconds)} vs ${filter.kpiComparisonRangeHint()}: ${_formatCallDurationSeconds(data.previousPeriodAvgDurationSeconds)}',
                                      isUp:
                                          data.avgDurationSeconds >=
                                          data.previousPeriodAvgDurationSeconds,
                                      showTrendIndicator: !allDatesMode,
                                      useBarSparkline: allDatesMode,
                                      icon: Icons.av_timer_outlined,
                                      points: data.sparklineLast7Days
                                          .map(
                                            (e) => e.callCount == 0
                                                ? 0.0
                                                : e.totalDurationSeconds /
                                                      e.callCount,
                                          )
                                          .toList(),
                                      sparklineTooltips: _avgCallSparklineTooltips(
                                        data.sparklineLast7Days,
                                      ),
                                      barPoints:
                                          allDatesBars?.durationExtremesSix ??
                                          const <KpiBarSparklinePoint>[],
                                      colors: colors.kpiOrange,
                                    ),
                                    KpiCardData(
                                      title: topEntity.title,
                                      value: topEntity.label,
                                      subtitle: allDatesMode
                                          ? _formatTopEntityShareSubtitle(
                                              topEntity.count,
                                              data.totalCalls,
                                            )
                                          : '${topEntity.count} κλήσεις',
                                      isUp: true,
                                      showTrendIndicator: !allDatesMode,
                                      useBarSparkline: allDatesMode,
                                      icon: topEntity.icon,
                                      points: data.sparklineLast7Days
                                          .map((e) => e.callCount.toDouble())
                                          .toList(),
                                      sparklineTooltips: _callsSparklineTooltips(
                                        data.sparklineLast7Days,
                                      ),
                                      barPoints: _runnerUpBarPoints(
                                        allDatesBars,
                                        _topEntityMode,
                                      ),
                                      colors: colors.kpiPurple,
                                    ),
                                  ],
                                  onCardTap: (index) async {
                                    if (index == 0) {
                                      await _openLansweeperReportDialog();
                                      return;
                                    }
                                    if (index != 3) return;
                                    final selected =
                                        await showModalBottomSheet<
                                          TopEntityMode
                                        >(
                                          context: context,
                                          showDragHandle: true,
                                          builder: (context) {
                                            return SafeArea(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  ListTile(
                                                    leading: const Icon(
                                                      Icons.apartment_outlined,
                                                    ),
                                                    title: const Text(
                                                      'Κορυφαίο Τμήμα',
                                                    ),
                                                    onTap: () => Navigator.pop(
                                                      context,
                                                      TopEntityMode.department,
                                                    ),
                                                  ),
                                                  ListTile(
                                                    leading: const Icon(
                                                      Icons
                                                          .person_outline_rounded,
                                                    ),
                                                    title: const Text(
                                                      'Κορυφαίος Καλών',
                                                    ),
                                                    onTap: () => Navigator.pop(
                                                      context,
                                                      TopEntityMode.caller,
                                                    ),
                                                  ),
                                                  ListTile(
                                                    leading: const Icon(
                                                      Icons.build_outlined,
                                                    ),
                                                    title: const Text(
                                                      'Κορυφαία Βλάβη',
                                                    ),
                                                    onTap: () => Navigator.pop(
                                                      context,
                                                      TopEntityMode.issue,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        );
                                    if (selected != null) {
                                      setState(() => _topEntityMode = selected);
                                    }
                                  },
                                ),
                                const SizedBox(height: 18),
                                if (mainSplit)
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 4,
                                        child: TopCallersCard(
                                          data: data,
                                          colors: colors,
                                          onViewAll: () {
                                            final q = data.topCallers.isNotEmpty
                                                ? data.topCallers.first.name
                                                : null;
                                            _popWithHistoryPrefill(
                                              keyword: q ?? '',
                                              clearKeyword:
                                                  q == null || q == '-',
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        flex: 9,
                                        child: LongestCallsCard(
                                          data: data,
                                          topN: filter.topN,
                                          colors: colors,
                                          formatDuration:
                                              _formatCallDurationSeconds,
                                          onTopNChanged: (v) {
                                            ref
                                                .read(
                                                  dashboardFilterProvider
                                                      .notifier,
                                                )
                                                .update(
                                                  (s) => s.copyWith(topN: v),
                                                );
                                          },
                                          onOpenReport: () {
                                            _popWithHistoryPrefill(
                                              keyword: '',
                                              clearKeyword: true,
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  )
                                else ...[
                                  TopCallersCard(
                                    data: data,
                                    colors: colors,
                                    onViewAll: () {
                                      final q = data.topCallers.isNotEmpty
                                          ? data.topCallers.first.name
                                          : null;
                                      _popWithHistoryPrefill(
                                        keyword: q ?? '',
                                        clearKeyword: q == null || q == '-',
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  LongestCallsCard(
                                    data: data,
                                    topN: filter.topN,
                                    colors: colors,
                                    formatDuration: _formatCallDurationSeconds,
                                    onTopNChanged: (v) {
                                      ref
                                          .read(
                                            dashboardFilterProvider.notifier,
                                          )
                                          .update((s) => s.copyWith(topN: v));
                                    },
                                    onOpenReport: () {
                                      _popWithHistoryPrefill(
                                        keyword: '',
                                        clearKeyword: true,
                                      );
                                    },
                                  ),
                                ],
                                const SizedBox(height: 18),
                                MoreSection(
                                  expanded: _showMoreSection,
                                  onToggle: () => setState(
                                    () => _showMoreSection = !_showMoreSection,
                                  ),
                                  data: data,
                                  colors: colors,
                                  formatDuration: _formatCallDurationSeconds,
                                ),
                              ],
                            );
                          },
                        );
                      },
                      loading: () => LoadingDashboard(colors: colors),
                      error: (e, _) => ErrorCard(
                        message: 'Σφάλμα φόρτωσης: $e',
                        colors: colors,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                right: _isFilterOpen ? 20 : -360,
                top: 90,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 210),
                  curve: Curves.easeOut,
                  opacity: _isFilterOpen ? 1 : 0,
                  child: FilterPane(
                    paneWidth: math.max(
                      220,
                      math.min(330, MediaQuery.sizeOf(context).width - 24),
                    ),
                    dateRangeLabel: dateRangeLabel,
                    keywordController: _keywordController,
                    userController: _userController,
                    equipmentController: _equipmentController,
                    departmentsAsync: departmentsAsync,
                    selectedDepartment: filter.department,
                    activeDatePreset: activeDatePreset,
                    onClose: () => setState(() => _isFilterOpen = false),
                    onPickDateRange: _pickDateRange,
                    onSetToday: () => _setDatePreset(DashboardDatePreset.today),
                    onSetWeek: () => _setDatePreset(DashboardDatePreset.last7),
                    onSetMonth: () =>
                        _setDatePreset(DashboardDatePreset.last30),
                    onSetAll: () => _setDatePreset(DashboardDatePreset.all),
                    onApply: _applyAllFilters,
                    onClearAll: () {
                      _keywordController.clear();
                      _userController.clear();
                      _equipmentController.clear();
                      ref
                          .read(dashboardFilterProvider.notifier)
                          .clearAllFilters();
                    },
                    onDepartmentChanged: (v) {
                      ref
                          .read(dashboardFilterProvider.notifier)
                          .update(
                            (s) => s.copyWith(
                              department: v,
                              clearDepartment: v == null,
                            ),
                          );
                    },
                    onChangedText: _scheduleDebouncedTextFilters,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(ThemeData theme, DashboardPaletteColors colors) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            color: colors.topBarFill.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.topBarBorder.withValues(alpha: 0.95),
            ),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [
                          colors.topBarLogoBgStart,
                          colors.topBarLogoBgEnd,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Icon(
                      Icons.call_outlined,
                      color: colors.topBarLogoIcon,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Στατιστικά Κλήσεων',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Έξοδος'),
                  ),
                  PopupMenuButton<DashboardPalette>(
                    tooltip: 'Παλέτα Χρωμάτων',
                    initialValue: _palette,
                    onSelected: (v) => setState(() => _palette = v),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: DashboardPalette.classic,
                        child: Text('Κλασικό'),
                      ),
                      PopupMenuItem(
                        value: DashboardPalette.ocean,
                        child: Text('Ωκεανός'),
                      ),
                      PopupMenuItem(
                        value: DashboardPalette.sunrise,
                        child: Text('Ανατολή'),
                      ),
                      PopupMenuItem(
                        value: DashboardPalette.forest,
                        child: Text('Δάσος'),
                      ),
                      PopupMenuItem(
                        value: DashboardPalette.indigoNight,
                        child: Text('Νυχτερινό ίντιγκο'),
                      ),
                    ],
                    child: OutlinedButton.icon(
                      onPressed: null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurface,
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                        disabledForegroundColor: theme.colorScheme.onSurface,
                      ),
                      icon: GradientPaletteIcon(colors: colors),
                      label: const Text('Χρώματα'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Η εξαγωγή από την πάνω μπάρα έρχεται.',
                          ),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Γρήγορη Εξαγωγή'),
                  ),
                  FilledButton.icon(
                    onPressed: () =>
                        setState(() => _isFilterOpen = !_isFilterOpen),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.actionBlue,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Ρυθμίσεις / Φίλτρα'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateRange(DashboardFilterModel filter) {
    if (filter.dateFrom != null && filter.dateTo != null) {
      return '${DateFormat('dd/MM/yyyy').format(filter.dateFrom!)} – ${DateFormat('dd/MM/yyyy').format(filter.dateTo!)}';
    }
    if (filter.dateFrom != null) {
      return 'από ${DateFormat('dd/MM/yyyy').format(filter.dateFrom!)}';
    }
    if (filter.dateTo != null) {
      return 'έως ${DateFormat('dd/MM/yyyy').format(filter.dateTo!)}';
    }
    return 'Εύρος ημερομηνιών';
  }
}
