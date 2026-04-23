import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/calendar_range_picker.dart';
import '../models/dashboard_filter_model.dart';
import '../models/dashboard_summary_model.dart';
import '../providers/dashboard_provider.dart';
import '../providers/history_provider.dart';

enum _TopEntityMode { department, caller, issue }

enum _DashboardPalette { classic, ocean, sunrise }

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
  _TopEntityMode _topEntityMode = _TopEntityMode.department;
  _DashboardPalette _palette = _DashboardPalette.classic;

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
      ref
          .read(dashboardFilterProvider.notifier)
          .update((s) => s.copyWith(clearDateRange: true));
      return;
    }
    final range = result.range;
    if (range == null) return;
    ref
        .read(dashboardFilterProvider.notifier)
        .update((s) => s.copyWith(dateFrom: range.start, dateTo: range.end));
  }

  void _setDatePreset(int inclusiveDays) {
    final filter = ref.read(dashboardFilterProvider);
    final anchor = filter.dateTo ?? filter.dateFrom ?? DateTime.now();
    final end = DateTime(anchor.year, anchor.month, anchor.day);
    final start = end.subtract(Duration(days: inclusiveDays - 1));
    ref
        .read(dashboardFilterProvider.notifier)
        .update((s) => s.copyWith(dateFrom: start, dateTo: end));
  }

  void _clearDateRange() {
    ref
        .read(dashboardFilterProvider.notifier)
        .update((s) => s.copyWith(clearDateRange: true));
  }

  String _formatDurationSeconds(num seconds) {
    final safeSeconds = seconds.isNaN ? 0 : seconds.round();
    final absSeconds = math.max(0, safeSeconds);
    final h = absSeconds ~/ 3600;
    final m = (absSeconds % 3600) ~/ 60;
    final s = absSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    if (m > 0) {
      return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '00:${s.toString().padLeft(2, '0')}';
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

  _KpiTopEntity _resolveTopEntity(DashboardSummaryModel data) {
    switch (_topEntityMode) {
      case _TopEntityMode.department:
        final d = data.byDepartment.isNotEmpty ? data.byDepartment.first : null;
        return _KpiTopEntity(
          title: 'Κορυφαίο Τμήμα',
          label: d?.name ?? '-',
          count: d?.count ?? 0,
          icon: Icons.workspace_premium_rounded,
        );
      case _TopEntityMode.caller:
        final c = data.topCallers.isNotEmpty ? data.topCallers.first : null;
        return _KpiTopEntity(
          title: 'Κορυφαίος Καλών',
          label: c?.name ?? '-',
          count: c?.count ?? 0,
          icon: Icons.person_pin_circle_outlined,
        );
      case _TopEntityMode.issue:
        final i = data.byIssue.isNotEmpty ? data.byIssue.first : null;
        return _KpiTopEntity(
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
    final statsAsync = ref.watch(dashboardStatsProvider);
    final departmentsAsync = ref.watch(dashboardDepartmentsProvider);
    final colors = _DashboardPaletteColors.from(_palette);

    final dateRangeLabel = _formatDateRange(filter);

    return Scaffold(
      backgroundColor: const Color(0xFFEFF3FC),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEAF2FF), Color(0xFFF7FAFF)],
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
                                  _EmptyStateCard(
                                    message:
                                        'Δεν βρέθηκαν κλήσεις για τα επιλεγμένα φίλτρα.',
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                _KpiGrid(
                                  crossAxisCount: kpiCrossCount,
                                  cards: [
                                    _KpiCardData(
                                      title:
                                          'Συνολικές κλήσεις · ${filter.kpiTotalCallsRangeTitle()}',
                                      value: '${data.totalCalls}',
                                      subtitle:
                                          '${_formatDeltaPercent(data.totalCalls, data.previousPeriodTotalCalls)} vs ${filter.kpiComparisonRangeHint()}: ${data.previousPeriodTotalCalls}',
                                      isUp:
                                          data.totalCalls >=
                                          data.previousPeriodTotalCalls,
                                      icon: Icons.call_rounded,
                                      points: data.sparklineLast7Days
                                          .map((e) => e.callCount.toDouble())
                                          .toList(),
                                      colors: colors.kpiBlue,
                                    ),
                                    _KpiCardData(
                                      title: 'Συνολική Διάρκεια Κλήσεων',
                                      value: _formatDurationSeconds(
                                        data.totalDurationSeconds,
                                      ),
                                      subtitle:
                                          '${_formatDeltaPercent(data.totalDurationSeconds, data.previousPeriodTotalDurationSeconds)} vs ${filter.kpiComparisonRangeHint()}: ${_formatDurationSeconds(data.previousPeriodTotalDurationSeconds)}',
                                      isUp:
                                          data.totalDurationSeconds >=
                                          data.previousPeriodTotalDurationSeconds,
                                      icon: Icons.timer_outlined,
                                      points: data.sparklineLast7Days
                                          .map(
                                            (e) => e.totalDurationSeconds
                                                .toDouble(),
                                          )
                                          .toList(),
                                      colors: colors.kpiGreen,
                                    ),
                                    _KpiCardData(
                                      title: 'Μέσος Όρος ανά Κλήση',
                                      value: _formatDurationSeconds(
                                        data.avgDurationSeconds,
                                      ),
                                      subtitle:
                                          '${_formatDeltaPercent(data.avgDurationSeconds, data.previousPeriodAvgDurationSeconds)} vs ${filter.kpiComparisonRangeHint()}: ${_formatDurationSeconds(data.previousPeriodAvgDurationSeconds)}',
                                      isUp:
                                          data.avgDurationSeconds >=
                                          data.previousPeriodAvgDurationSeconds,
                                      icon: Icons.av_timer_outlined,
                                      points: data.sparklineLast7Days
                                          .map(
                                            (e) => e.callCount == 0
                                                ? 0.0
                                                : e.totalDurationSeconds /
                                                      e.callCount,
                                          )
                                          .toList(),
                                      colors: colors.kpiOrange,
                                    ),
                                    _KpiCardData(
                                      title: topEntity.title,
                                      value: topEntity.label,
                                      subtitle: '${topEntity.count} κλήσεις',
                                      isUp: true,
                                      icon: topEntity.icon,
                                      points: data.sparklineLast7Days
                                          .map((e) => e.callCount.toDouble())
                                          .toList(),
                                      colors: colors.kpiPurple,
                                    ),
                                  ],
                                  onCardTap: (index) async {
                                    if (index != 3) return;
                                    final selected =
                                        await showModalBottomSheet<
                                          _TopEntityMode
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
                                                      _TopEntityMode.department,
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
                                                      _TopEntityMode.caller,
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
                                                      _TopEntityMode.issue,
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
                                        child: _TopCallersCard(
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
                                        child: _LongestCallsCard(
                                          data: data,
                                          topN: filter.topN,
                                          colors: colors,
                                          formatDuration:
                                              _formatDurationSeconds,
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
                                  _TopCallersCard(
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
                                  _LongestCallsCard(
                                    data: data,
                                    topN: filter.topN,
                                    colors: colors,
                                    formatDuration: _formatDurationSeconds,
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
                                _MoreSection(
                                  expanded: _showMoreSection,
                                  onToggle: () => setState(
                                    () => _showMoreSection = !_showMoreSection,
                                  ),
                                  data: data,
                                  colors: colors,
                                  formatDuration: _formatDurationSeconds,
                                ),
                              ],
                            );
                          },
                        );
                      },
                      loading: () => const _LoadingDashboard(),
                      error: (e, _) =>
                          _ErrorCard(message: 'Σφάλμα φόρτωσης: $e'),
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
                  child: _FilterPane(
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
                    onClose: () => setState(() => _isFilterOpen = false),
                    onPickDateRange: _pickDateRange,
                    onSetToday: () => _setDatePreset(1),
                    onSetWeek: () => _setDatePreset(7),
                    onSetMonth: () => _setDatePreset(30),
                    onApply: _applyAllFilters,
                    onClearDate: _clearDateRange,
                    onClearAll: () {
                      _keywordController.clear();
                      _userController.clear();
                      _equipmentController.clear();
                      ref
                          .read(dashboardFilterProvider.notifier)
                          .update((s) => const DashboardFilterModel());
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

  Widget _buildTopBar(ThemeData theme, _DashboardPaletteColors colors) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
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
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF0F6FF), Color(0xFFE2EDFF)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: const Icon(
                      Icons.call_outlined,
                      color: Color(0xFF2563EB),
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
                  PopupMenuButton<_DashboardPalette>(
                    tooltip: 'Παλέτα Χρωμάτων',
                    initialValue: _palette,
                    onSelected: (v) => setState(() => _palette = v),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _DashboardPalette.classic,
                        child: Text('Classic'),
                      ),
                      PopupMenuItem(
                        value: _DashboardPalette.ocean,
                        child: Text('Ocean'),
                      ),
                      PopupMenuItem(
                        value: _DashboardPalette.sunrise,
                        child: Text('Sunrise'),
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
                      icon: const Icon(Icons.palette_outlined, size: 18),
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

class _KpiTopEntity {
  const _KpiTopEntity({
    required this.title,
    required this.label,
    required this.count,
    required this.icon,
  });

  final String title;
  final String label;
  final int count;
  final IconData icon;
}

class _KpiCardData {
  const _KpiCardData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.isUp,
    required this.icon,
    required this.points,
    required this.colors,
  });

  final String title;
  final String value;
  final String subtitle;
  final bool isUp;
  final IconData icon;
  final List<double> points;
  final _KpiTone colors;
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({
    required this.crossAxisCount,
    required this.cards,
    required this.onCardTap,
  });

  final int crossAxisCount;
  final List<_KpiCardData> cards;
  final ValueChanged<int> onCardTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: cards.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.62,
      ),
      itemBuilder: (context, index) {
        final card = cards[index];
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 320 + (index * 90)),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) {
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 14),
                child: child,
              ),
            );
          },
          child: _HoverLiftCard(
            onTap: () => onCardTap(index),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: card.colors.surface,
                border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x140F172A),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: card.colors.iconSurface,
                    ),
                    child: Icon(
                      card.icon,
                      color: card.colors.iconColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    card.title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Text(
                      card.value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            color: card.colors.valueColor,
                          ),
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        card.isUp ? '▲ ' : '▼ ',
                        style: TextStyle(
                          color: card.isUp
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          card.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                      ),
                      SizedBox(
                        width: 86,
                        height: 34,
                        child: _SparklineChart(
                          points: card.points,
                          color: card.colors.sparkColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HoverLiftCard extends StatefulWidget {
  const _HoverLiftCard({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_HoverLiftCard> createState() => _HoverLiftCardState();
}

class _HoverLiftCardState extends State<_HoverLiftCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressed
        ? 0.992
        : _hovered
        ? 1.01
        : 1.0;
    final y = _hovered ? -3.0 : 0.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedSlide(
            offset: Offset(0, y / 100),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _TopCallersCard extends StatelessWidget {
  const _TopCallersCard({
    required this.data,
    required this.colors,
    required this.onViewAll,
  });

  final DashboardSummaryModel data;
  final _DashboardPaletteColors colors;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final callers = data.topCallers.take(7).toList();
    final maxCount = callers.isEmpty
        ? 1
        : callers.map((e) => e.count).reduce(math.max).toDouble();
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.emoji_events_outlined,
            title: 'Κορυφαίοι Καλούντες',
            iconColor: const Color(0xFFD97706),
            iconBg: const Color(0xFFFFF4D6),
          ),
          const SizedBox(height: 10),
          if (callers.isEmpty)
            const Text('Δεν υπάρχουν δεδομένα.')
          else
            ...callers.indexed.map((entry) {
              final i = entry.$1;
              final c = entry.$2;
              final progress = maxCount == 0 ? 0.0 : c.count / maxCount;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: colors.rankColor(i),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0, end: progress),
                              duration: Duration(milliseconds: 320 + (i * 80)),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, _) {
                                return LinearProgressIndicator(
                                  value: value,
                                  minHeight: 6,
                                  backgroundColor: const Color(0xFFE6EBF7),
                                  color: colors.actionBlue,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${c.count}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              );
            }),
          TextButton(onPressed: onViewAll, child: const Text('Προβολή όλων >')),
        ],
      ),
    );
  }
}

class _LongestCallsCard extends StatelessWidget {
  const _LongestCallsCard({
    required this.data,
    required this.topN,
    required this.colors,
    required this.formatDuration,
    required this.onTopNChanged,
    required this.onOpenReport,
  });

  final DashboardSummaryModel data;
  final int topN;
  final _DashboardPaletteColors colors;
  final String Function(num) formatDuration;
  final ValueChanged<int> onTopNChanged;
  final VoidCallback onOpenReport;

  @override
  Widget build(BuildContext context) {
    final rows = data.longestCalls.take(topN).toList();
    final maxDur = rows.isEmpty
        ? 1
        : rows.map((e) => e.durationSeconds).reduce(math.max).toDouble();

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _SectionHeader(
                  icon: Icons.schedule_outlined,
                  title: 'Πιο Χρονοβόρες Κλήσεις',
                  iconColor: Color(0xFF1D4ED8),
                  iconBg: Color(0xFFDBEAFE),
                ),
              ),
              DropdownButton<int>(
                value: topN,
                items: const [
                  DropdownMenuItem(value: 5, child: Text('Top 5')),
                  DropdownMenuItem(value: 10, child: Text('Top 10')),
                  DropdownMenuItem(value: 20, child: Text('Top 20')),
                ],
                onChanged: (v) {
                  if (v != null) onTopNChanged(v);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(
                const Color(0xFFF8FAFD).withValues(alpha: 0.95),
              ),
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('Καλών')),
                DataColumn(label: Text('Τμήμα')),
                DataColumn(label: Text('Διάρκεια')),
              ],
              rows: rows.indexed.map((entry) {
                final idx = entry.$1;
                final r = entry.$2;
                final pct = maxDur == 0 ? 0.0 : r.durationSeconds / maxDur;
                return DataRow(
                  color: WidgetStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(WidgetState.hovered)) {
                      return const Color(0xFFF1F6FF);
                    }
                    return null;
                  }),
                  cells: [
                    DataCell(Text('${idx + 1}')),
                    DataCell(
                      SizedBox(
                        width: 210,
                        child: Text(
                          r.callerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(_DepartmentPill(name: r.department)),
                    DataCell(
                      SizedBox(
                        width: 220,
                        child: Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween<double>(begin: 0, end: pct),
                                  duration: Duration(
                                    milliseconds: 300 + (idx * 70),
                                  ),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, value, _) {
                                    return LinearProgressIndicator(
                                      value: value,
                                      minHeight: 6,
                                      backgroundColor: const Color(0xFFE5EDFF),
                                      color: colors.actionBlue,
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(formatDuration(r.durationSeconds)),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          TextButton(
            onPressed: onOpenReport,
            child: const Text('Προβολή αναφοράς >'),
          ),
        ],
      ),
    );
  }
}

class _MoreSection extends StatelessWidget {
  const _MoreSection({
    required this.expanded,
    required this.onToggle,
    required this.data,
    required this.colors,
    required this.formatDuration,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final DashboardSummaryModel data;
  final _DashboardPaletteColors colors;
  final String Function(num) formatDuration;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Περισσότερα...',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                onPressed: onToggle,
                icon: Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                ),
              ),
            ],
          ),
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 210),
                curve: Curves.easeOut,
                opacity: expanded ? 1 : 0,
                child: expanded
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          final split = constraints.maxWidth >= 980;
                          if (split) {
                            return Column(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _ChartCard(
                                        title: 'Κατανομή ανά ώρα',
                                        child: _HourlyBarChart(
                                          buckets: data.hourlyDistribution,
                                          color: colors.actionBlue,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: _ChartCard(
                                        title: 'Τάση Κλήσεων (7 ημέρες)',
                                        child: _TrendLineChart(
                                          trend: data.dailyTrend,
                                          color: colors.kpiGreen.sparkColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                _ChartCard(
                                  title: 'Κατανομή Βλαβών',
                                  child: _IssuePieChart(
                                    issues: data.byIssue,
                                    formatDuration: formatDuration,
                                  ),
                                ),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              _ChartCard(
                                title: 'Κατανομή ανά ώρα',
                                child: _HourlyBarChart(
                                  buckets: data.hourlyDistribution,
                                  color: colors.actionBlue,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _ChartCard(
                                title: 'Τάση Κλήσεων (7 ημέρες)',
                                child: _TrendLineChart(
                                  trend: data.dailyTrend,
                                  color: colors.kpiGreen.sparkColor,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _ChartCard(
                                title: 'Κατανομή Βλαβών',
                                child: _IssuePieChart(
                                  issues: data.byIssue,
                                  formatDuration: formatDuration,
                                ),
                              ),
                            ],
                          );
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterPane extends StatelessWidget {
  const _FilterPane({
    required this.paneWidth,
    required this.dateRangeLabel,
    required this.keywordController,
    required this.userController,
    required this.equipmentController,
    required this.departmentsAsync,
    required this.selectedDepartment,
    required this.onClose,
    required this.onPickDateRange,
    required this.onSetToday,
    required this.onSetWeek,
    required this.onSetMonth,
    required this.onApply,
    required this.onClearDate,
    required this.onClearAll,
    required this.onDepartmentChanged,
    required this.onChangedText,
  });

  final double paneWidth;
  final String dateRangeLabel;
  final TextEditingController keywordController;
  final TextEditingController userController;
  final TextEditingController equipmentController;
  final AsyncValue<List<String>> departmentsAsync;
  final String? selectedDepartment;
  final VoidCallback onClose;
  final VoidCallback onPickDateRange;
  final VoidCallback onSetToday;
  final VoidCallback onSetWeek;
  final VoidCallback onSetMonth;
  final VoidCallback onApply;
  final VoidCallback onClearDate;
  final VoidCallback onClearAll;
  final ValueChanged<String?> onDepartmentChanged;
  final VoidCallback onChangedText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: paneWidth,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330F172A),
                blurRadius: 28,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Φίλτρα',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: keywordController,
                onChanged: (_) => onChangedText(),
                decoration: const InputDecoration(
                  labelText: 'Αναζήτηση Οντότητας',
                  hintText: 'Αναζήτηση ονόματος ή τμήματος...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onPickDateRange,
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(dateRangeLabel),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  FilledButton.tonal(
                    onPressed: onSetToday,
                    child: const Text('Σήμερα'),
                  ),
                  FilledButton.tonal(
                    onPressed: onSetWeek,
                    child: const Text('7 ημέρες'),
                  ),
                  FilledButton.tonal(
                    onPressed: onSetMonth,
                    child: const Text('30 ημέρες'),
                  ),
                  TextButton(
                    onPressed: onClearDate,
                    child: const Text('Καθαρισμός'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              departmentsAsync.when(
                data: (deps) {
                  final options = <String?>[null, ...deps];
                  return DropdownButtonFormField<String?>(
                    initialValue: options.contains(selectedDepartment)
                        ? selectedDepartment
                        : null,
                    isExpanded: true,
                    items: options
                        .map(
                          (e) => DropdownMenuItem<String?>(
                            value: e,
                            child: Text(e ?? 'Όλα τα Τμήματα'),
                          ),
                        )
                        .toList(),
                    onChanged: onDepartmentChanged,
                    decoration: const InputDecoration(
                      labelText: 'Τμήμα',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(10),
                  child: LinearProgressIndicator(),
                ),
                error: (e, _) => Text(
                  'Σφάλμα φόρτωσης τμημάτων: $e',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: userController,
                onChanged: (_) => onChangedText(),
                decoration: const InputDecoration(
                  labelText: 'Όνομα Χρήστη',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: equipmentController,
                onChanged: (_) => onChangedText(),
                decoration: const InputDecoration(
                  labelText: 'Εξοπλισμός',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onClearAll,
                      child: const Text('Καθαρισμός'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: onApply,
                      child: const Text('Εφαρμογή'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SparklineChart extends StatelessWidget {
  const _SparklineChart({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final safePoints = points.isEmpty ? [0.0] : points;
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: safePoints.indexed
                .map((e) => FlSpot(e.$1.toDouble(), e.$2))
                .toList(),
            isCurved: true,
            barWidth: 2.2,
            color: color,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}

class _HourlyBarChart extends StatelessWidget {
  const _HourlyBarChart({required this.buckets, required this.color});

  final List<HourlyBucket> buckets;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final maxY = buckets.isEmpty
        ? 1.0
        : (buckets.map((e) => e.callCount).reduce(math.max)).toDouble();
    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: math.max(maxY, 1),
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: math.max(1, maxY / 4),
            getDrawingHorizontalLine: (value) =>
                const FlLine(color: Color(0xFFE5EAF6), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 3,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
          ),
          barGroups: buckets
              .map(
                (e) => BarChartGroupData(
                  x: e.hour,
                  barRods: [
                    BarChartRodData(
                      toY: e.callCount.toDouble(),
                      width: 8,
                      borderRadius: BorderRadius.circular(4),
                      color: color,
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _TrendLineChart extends StatelessWidget {
  const _TrendLineChart({required this.trend, required this.color});

  final List<DailyTrendPoint> trend;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final maxY = trend.isEmpty
        ? 1.0
        : trend.map((e) => e.callCount).reduce(math.max).toDouble();
    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: math.max(maxY, 1),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: math.max(1, maxY / 4),
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0xFFE5EAF6), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= trend.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateFormat('dd/MM').format(trend[index].date),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: trend.indexed
                  .map(
                    (e) => FlSpot(e.$1.toDouble(), e.$2.callCount.toDouble()),
                  )
                  .toList(),
              isCurved: true,
              barWidth: 2.6,
              color: color,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IssuePieChart extends StatelessWidget {
  const _IssuePieChart({required this.issues, required this.formatDuration});

  final List<IssueStat> issues;
  final String Function(num) formatDuration;

  @override
  Widget build(BuildContext context) {
    final top = issues.take(5).toList();
    if (top.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text('Δεν υπάρχουν δεδομένα.')),
      );
    }
    final colors = <Color>[
      const Color(0xFF3B82F6),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFA855F7),
      const Color(0xFFEF4444),
    ];
    return Row(
      children: [
        SizedBox(
          width: 210,
          height: 210,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 46,
              sectionsSpace: 2,
              sections: top.indexed.map((entry) {
                final i = entry.$1;
                final issue = entry.$2;
                return PieChartSectionData(
                  color: colors[i % colors.length],
                  value: issue.count.toDouble(),
                  title: '${issue.count}',
                  radius: 52,
                  titleStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: top.indexed.map((entry) {
              final i = entry.$1;
              final issue = entry.$2;
              return Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors[i % colors.length],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        issue.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${issue.count}'),
                    const SizedBox(width: 8),
                    Text(
                      formatDuration(issue.sumDurationSeconds),
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _DepartmentPill extends StatelessWidget {
  const _DepartmentPill({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final lower = name.toLowerCase();
    Color bg;
    Color fg;
    if (lower.contains('λογ') || lower.contains('account')) {
      bg = const Color(0xFFEDE9FE);
      fg = const Color(0xFF5B21B6);
    } else if (lower.contains('πωλ') || lower.contains('sales')) {
      bg = const Color(0xFFFFF1DF);
      fg = const Color(0xFFB45309);
    } else {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF166534);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        name,
        style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.iconColor,
    required this.iconBg,
  });

  final IconData icon;
  final String title;
  final Color iconColor;
  final Color iconBg;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: iconBg,
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.82)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _LoadingDashboard extends StatelessWidget {
  const _LoadingDashboard();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _LoadingSkeleton(height: 172),
        const SizedBox(height: 12),
        const _LoadingSkeleton(height: 172),
        const SizedBox(height: 12),
        const _LoadingSkeleton(height: 240),
      ],
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFE9EDF7), Color(0xFFF4F6FB), Color(0xFFE9EDF7)],
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Center(child: Text(message, textAlign: TextAlign.center)),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _GlassCard(
      child: Text(message, style: TextStyle(color: theme.colorScheme.error)),
    );
  }
}

class _KpiTone {
  const _KpiTone({
    required this.surface,
    required this.iconSurface,
    required this.iconColor,
    required this.valueColor,
    required this.sparkColor,
  });

  final Color surface;
  final Color iconSurface;
  final Color iconColor;
  final Color valueColor;
  final Color sparkColor;
}

class _DashboardPaletteColors {
  const _DashboardPaletteColors({
    required this.kpiBlue,
    required this.kpiGreen,
    required this.kpiOrange,
    required this.kpiPurple,
    required this.actionBlue,
  });

  final _KpiTone kpiBlue;
  final _KpiTone kpiGreen;
  final _KpiTone kpiOrange;
  final _KpiTone kpiPurple;
  final Color actionBlue;

  Color rankColor(int index) {
    const colors = [
      Color(0xFFE0F2FE),
      Color(0xFFDCFCE7),
      Color(0xFFFFEDD5),
      Color(0xFFEDE9FE),
      Color(0xFFFCE7F3),
      Color(0xFFE0F2FE),
      Color(0xFFDCFCE7),
    ];
    return colors[index % colors.length];
  }

  factory _DashboardPaletteColors.from(_DashboardPalette palette) {
    switch (palette) {
      case _DashboardPalette.classic:
        return const _DashboardPaletteColors(
          kpiBlue: _KpiTone(
            surface: Color(0xFFEEF6FF),
            iconSurface: Color(0xFFDBEAFE),
            iconColor: Color(0xFF2563EB),
            valueColor: Color(0xFF0B63CE),
            sparkColor: Color(0xFF3B82F6),
          ),
          kpiGreen: _KpiTone(
            surface: Color(0xFFE9F9F1),
            iconSurface: Color(0xFFD1FAE5),
            iconColor: Color(0xFF059669),
            valueColor: Color(0xFF047857),
            sparkColor: Color(0xFF10B981),
          ),
          kpiOrange: _KpiTone(
            surface: Color(0xFFFFF4E8),
            iconSurface: Color(0xFFFFEDD5),
            iconColor: Color(0xFFEA580C),
            valueColor: Color(0xFFC2410C),
            sparkColor: Color(0xFFF97316),
          ),
          kpiPurple: _KpiTone(
            surface: Color(0xFFF5F0FF),
            iconSurface: Color(0xFFEDE9FE),
            iconColor: Color(0xFF7C3AED),
            valueColor: Color(0xFF6D28D9),
            sparkColor: Color(0xFF8B5CF6),
          ),
          actionBlue: Color(0xFF2563EB),
        );
      case _DashboardPalette.ocean:
        return const _DashboardPaletteColors(
          kpiBlue: _KpiTone(
            surface: Color(0xFFEFF8FF),
            iconSurface: Color(0xFFD8EEFF),
            iconColor: Color(0xFF0284C7),
            valueColor: Color(0xFF0369A1),
            sparkColor: Color(0xFF0EA5E9),
          ),
          kpiGreen: _KpiTone(
            surface: Color(0xFFEDFBF7),
            iconSurface: Color(0xFFD2F6EC),
            iconColor: Color(0xFF0D9488),
            valueColor: Color(0xFF0F766E),
            sparkColor: Color(0xFF14B8A6),
          ),
          kpiOrange: _KpiTone(
            surface: Color(0xFFFFF7ED),
            iconSurface: Color(0xFFFFEDD5),
            iconColor: Color(0xFFEA580C),
            valueColor: Color(0xFFC2410C),
            sparkColor: Color(0xFFF97316),
          ),
          kpiPurple: _KpiTone(
            surface: Color(0xFFF4F4FF),
            iconSurface: Color(0xFFE9E8FF),
            iconColor: Color(0xFF6366F1),
            valueColor: Color(0xFF4F46E5),
            sparkColor: Color(0xFF6366F1),
          ),
          actionBlue: Color(0xFF0284C7),
        );
      case _DashboardPalette.sunrise:
        return const _DashboardPaletteColors(
          kpiBlue: _KpiTone(
            surface: Color(0xFFF1F7FF),
            iconSurface: Color(0xFFDDEBFF),
            iconColor: Color(0xFF2563EB),
            valueColor: Color(0xFF1E40AF),
            sparkColor: Color(0xFF3B82F6),
          ),
          kpiGreen: _KpiTone(
            surface: Color(0xFFF4FDF4),
            iconSurface: Color(0xFFDCFCE7),
            iconColor: Color(0xFF16A34A),
            valueColor: Color(0xFF166534),
            sparkColor: Color(0xFF22C55E),
          ),
          kpiOrange: _KpiTone(
            surface: Color(0xFFFFF6EC),
            iconSurface: Color(0xFFFFEDD5),
            iconColor: Color(0xFFF97316),
            valueColor: Color(0xFFEA580C),
            sparkColor: Color(0xFFF59E0B),
          ),
          kpiPurple: _KpiTone(
            surface: Color(0xFFFFF0FA),
            iconSurface: Color(0xFFFCE7F3),
            iconColor: Color(0xFFDB2777),
            valueColor: Color(0xFFBE185D),
            sparkColor: Color(0xFFEC4899),
          ),
          actionBlue: Color(0xFF1D4ED8),
        );
    }
  }
}
