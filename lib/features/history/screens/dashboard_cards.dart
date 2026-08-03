import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/ellipsis_tooltip_text.dart';
import '../../../core/widgets/app_asset_image.dart';
import '../models/dashboard_summary_model.dart';
import '../providers/dashboard_provider.dart';
import '../utils/issue_distribution.dart';
import 'dashboard_charts.dart';
import 'dashboard_palette_colors.dart';

const _kLansweeperReportBadgeAsset = 'assets/lansweeper tickets.png';
const _kLansweeperReportBadgeTooltip = 'Αναφορές Lansweeper';

/// Μέγιστο πλάτος της κάρτας χρόνου.
///
/// Οι στήλες της έχουν σταθερό πλάτος: αύξων + όνομα (210) + αριθμητικές +
/// μπάρα (220) + αποστάσεις + padding κάρτας ≈ 715. Χωρίς όριο, η κάρτα θα
/// τεντωνόταν με την οθόνη και τα κουμπιά της κεφαλίδας θα έφευγαν δεκάδες
/// εκατοστά δεξιά από την τελευταία στήλη — το ίδιο max-width container που
/// χρησιμοποιεί κάθε σοβαρή εφαρμογή για να μη διαλύεται σε φαρδιές οθόνες.
///
/// Κοινό και για τις δύο όψεις, ώστε η κάρτα να μην αλλάζει μέγεθος στην
/// εναλλαγή «ανά κλήση» / «ανά άτομο».
const double kLongestCallsCardMaxWidth = 760;

class KpiTopEntity {
  const KpiTopEntity({
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

class KpiCardData {
  const KpiCardData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.isUp,
    this.showTrendIndicator = true,
    this.useBarSparkline = false,
    required this.icon,
    required this.points,
    this.sparklineTooltips = const [],
    this.barPoints = const <KpiBarSparklinePoint>[],
    this.showLansweeperReportBadge = false,
    required this.colors,
  });

  final String title;
  final String value;
  final String subtitle;
  final bool isUp;
  final bool showTrendIndicator;
  final bool useBarSparkline;
  final IconData icon;
  final List<double> points;
  final List<String> sparklineTooltips;
  final List<KpiBarSparklinePoint> barPoints;
  final bool showLansweeperReportBadge;
  final KpiTone colors;
}

class KpiGrid extends StatelessWidget {
  const KpiGrid({
    super.key,
    required this.crossAxisCount,
    required this.cards,
    required this.onCardTap,
    required this.paletteColors,
  });

  final int crossAxisCount;
  final List<KpiCardData> cards;
  final ValueChanged<int> onCardTap;
  final DashboardPaletteColors paletteColors;

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
          child: HoverLiftCard(
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
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
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
                      EllipsisTooltipText(
                        text: card.title,
                        maxLines: 2,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: paletteColors.kpiTitle,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
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
                        ),
                      ),
                      Row(
                        children: [
                          if (card.showTrendIndicator)
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
                            child: EllipsisTooltipText(
                              text: card.subtitle,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: paletteColors.kpiSubtitle),
                            ),
                          ),
                          SizedBox(
                            width: 86,
                            height: card.useBarSparkline ? 52 : 34,
                            child: card.useBarSparkline
                                ? BarSparklineChart(
                                    points: card.barPoints,
                                    color: card.colors.sparkColor,
                                  )
                                : SparklineChart(
                                    points: card.points,
                                    tooltips: card.sparklineTooltips,
                                    color: card.colors.sparkColor,
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (card.showLansweeperReportBadge)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Tooltip(
                        message: _kLansweeperReportBadgeTooltip,
                        child: AppAssetImage(
                          assetPath: _kLansweeperReportBadgeAsset,
                          width: 32,
                          height: 32,
                          fit: BoxFit.contain,
                          fallbackIcon: Icons.assignment_outlined,
                        ),
                      ),
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

class HoverLiftCard extends StatefulWidget {
  const HoverLiftCard({super.key, required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<HoverLiftCard> createState() => HoverLiftCardState();
}

class HoverLiftCardState extends State<HoverLiftCard> {
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

class TopCallersCard extends StatelessWidget {
  const TopCallersCard({
    super.key,
    required this.data,
    required this.colors,
    required this.onViewAll,
  });

  final DashboardSummaryModel data;
  final DashboardPaletteColors colors;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final callers = data.topCallers.take(7).toList();
    final maxCount = callers.isEmpty
        ? 1
        : callers.map((e) => e.count).reduce(math.max).toDouble();
    return GlassCard(
      fill: colors.glassFill,
      border: colors.glassBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: Icons.emoji_events_outlined,
            title: 'Κορυφαίοι Καλούντες',
            iconColor: colors.sectionCallersIcon,
            iconBg: colors.sectionCallersBg,
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
                                  backgroundColor: colors.progressTrackBg,
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

class LongestCallsCard extends ConsumerWidget {
  const LongestCallsCard({
    super.key,
    required this.data,
    required this.topN,
    required this.colors,
    required this.formatDuration,
    required this.formatAggregateDuration,
    required this.onTopNChanged,
    required this.onOpenReport,
  });

  final DashboardSummaryModel data;
  final int topN;
  final DashboardPaletteColors colors;

  /// Διάρκεια μίας κλήσης — «02:00:00».
  final String Function(num) formatDuration;

  /// Σύνολο χρόνου — «3ω:58λ».
  final String Function(num) formatAggregateDuration;

  final ValueChanged<int> onTopNChanged;
  final VoidCallback onOpenReport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(dashboardLongestCallsModeProvider);
    final isPerPerson = mode == LongestCallsMode.perPerson;

    // Στοίχιση αριστερά: σε φαρδιά οθόνη η κάρτα σταματά στο δεξί άκρο των
    // στηλών της αντί να τεντώνεται και να ξεκρεμά τα κουμπιά της κεφαλίδας.
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kLongestCallsCardMaxWidth),
        child: _buildCard(context, ref, isPerPerson: isPerPerson, mode: mode),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    WidgetRef ref, {
    required bool isPerPerson,
    required LongestCallsMode mode,
  }) {
    return GlassCard(
      fill: colors.glassFill,
      border: colors.glassBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SectionHeader(
                  icon: isPerPerson
                      ? Icons.person_search_outlined
                      : Icons.schedule_outlined,
                  title: isPerPerson
                      ? 'Χρόνος ανά Άτομο'
                      : 'Πιο Χρονοβόρες Κλήσεις',
                  iconColor: colors.sectionDurationIcon,
                  iconBg: colors.sectionDurationBg,
                ),
              ),
              SegmentedButton<LongestCallsMode>(
                segments: const [
                  ButtonSegment(
                    value: LongestCallsMode.perCall,
                    label: Text('Ανά κλήση'),
                  ),
                  ButtonSegment(
                    value: LongestCallsMode.perPerson,
                    label: Text('Ανά άτομο'),
                  ),
                ],
                selected: {mode},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onSelectionChanged: (selection) => ref
                    .read(dashboardLongestCallsModeProvider.notifier)
                    .set(selection.first),
              ),
              const SizedBox(width: 8),
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
          if (isPerPerson)
            _buildPerPersonTable(context, ref)
          else
            _buildPerCallTable(context),
          TextButton(
            onPressed: onOpenReport,
            child: const Text('Προβολή αναφοράς >'),
          ),
        ],
      ),
    );
  }

  /// Όψη «ανά άτομο»: σύνολο, πλήθος και μέσος όρος, με ταξινόμηση από τις
  /// κεφαλίδες. Το βέλος του [DataTable] δείχνει ποιο κριτήριο ισχύει.
  Widget _buildPerPersonTable(BuildContext context, WidgetRef ref) {
    final hideUnknown = ref.watch(dashboardHideUnknownCallerProvider);
    final sort = ref.watch(dashboardCallerTimeSortProvider);

    final visible = visibleCallerTimeStats(
      data.callerTimeTotals,
      hideUnknownCaller: hideUnknown,
    );
    final rows = sortedCallerTimeStats(visible, sort).take(topN).toList();
    final hiddenUnknown = data.callerTimeTotals
        .where((s) => s.name == kDashboardUnknownCallerLabel)
        .firstOrNull;
    final maxValue = rows.isEmpty
        ? 1.0
        : rows
              .map((e) => _sortValue(e, sort))
              .reduce(math.max)
              .toDouble()
              .clamp(1.0, double.infinity);

    const sortColumnIndex = {
      CallerTimeSort.count: 2,
      CallerTimeSort.average: 3,
      CallerTimeSort.total: 4,
    };

    void setSort(CallerTimeSort value) =>
        ref.read(dashboardCallerTimeSortProvider.notifier).set(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStatePropertyAll(
              colors.tableHeaderBg.withValues(alpha: 0.95),
            ),
            columnSpacing: 16,
            sortColumnIndex: sortColumnIndex[sort],
            sortAscending: false,
            columns: [
              const DataColumn(label: Text('#')),
              const DataColumn(label: Text('Καλών')),
              DataColumn(
                label: const Text('Κλήσεις'),
                numeric: true,
                onSort: (_, _) => setSort(CallerTimeSort.count),
              ),
              DataColumn(
                label: const Text('Μ.Ο.'),
                numeric: true,
                onSort: (_, _) => setSort(CallerTimeSort.average),
              ),
              DataColumn(
                label: const Text('Σύνολο'),
                onSort: (_, _) => setSort(CallerTimeSort.total),
              ),
            ],
            rows: rows.indexed.map((entry) {
              final idx = entry.$1;
              final r = entry.$2;
              final pct = _sortValue(r, sort) / maxValue;
              return DataRow(
                color: WidgetStateProperty.resolveWith<Color?>((states) {
                  if (states.contains(WidgetState.hovered)) {
                    return colors.tableRowHover;
                  }
                  return null;
                }),
                cells: [
                  DataCell(Text('${idx + 1}')),
                  DataCell(
                    SizedBox(
                      width: 210,
                      child: Text(
                        r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(Text('${r.callCount}')),
                  DataCell(Text(formatDuration(r.avgDurationSeconds))),
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
                                    backgroundColor:
                                        colors.progressTrackDataRowBg,
                                    color: colors.actionBlue,
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(formatAggregateDuration(r.totalDurationSeconds)),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Tooltip(
                message: 'Απόκρυψη κλήσεων χωρίς καταγεγραμμένο καλούντα',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Απόκρυψη «Άγνωστου»',
                      style: TextStyle(fontSize: 11, color: colors.kpiSubtitle),
                    ),
                    const SizedBox(width: 4),
                    Transform.scale(
                      scale: 0.82,
                      child: Switch(
                        value: hideUnknown,
                        onChanged: (value) => ref
                            .read(dashboardHideUnknownCallerProvider.notifier)
                            .set(value),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
              if (hideUnknown && hiddenUnknown != null)
                Expanded(
                  child: Text(
                    '+ ${formatAggregateDuration(hiddenUnknown.totalDurationSeconds)} '
                    'σε ${hiddenUnknown.callCount} κλήσεις χωρίς καταγεγραμμένο καλούντα',
                    style: TextStyle(fontSize: 11, color: colors.kpiSubtitle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static int _sortValue(CallerTimeStat s, CallerTimeSort sort) =>
      switch (sort) {
        CallerTimeSort.total => s.totalDurationSeconds,
        CallerTimeSort.count => s.callCount,
        CallerTimeSort.average => s.avgDurationSeconds,
      };

  Widget _buildPerCallTable(BuildContext context) {
    final rows = data.longestCalls.take(topN).toList();
    final maxDur = rows.isEmpty
        ? 1
        : rows.map((e) => e.durationSeconds).reduce(math.max).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStatePropertyAll(
              colors.tableHeaderBg.withValues(alpha: 0.95),
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
                    return colors.tableRowHover;
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
                  DataCell(DepartmentPill(name: r.department)),
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
                                    backgroundColor:
                                        colors.progressTrackDataRowBg,
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
      ],
    );
  }
}

class CategoryDistributionChartCard extends ConsumerWidget {
  const CategoryDistributionChartCard({
    super.key,
    required this.issues,
    required this.colors,
  });

  final List<IssueStat> issues;
  final DashboardPaletteColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final excludeCallsWithoutCategory = ref.watch(
      dashboardExcludeCallsWithoutCategoryProvider,
    );
    final visibleIssues = visibleDashboardIssueStats(
      issues,
      excludeCallsWithoutCategory: excludeCallsWithoutCategory,
    );

    final metric = ref.watch(dashboardIssueMetricProvider);

    return ChartCard(
      title: 'Κατανομή Βλαβών',
      fill: colors.chartCardFill,
      border: colors.chartCardBorder,
      titleTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<IssueDistributionMetric>(
            segments: const [
              ButtonSegment(
                value: IssueDistributionMetric.count,
                label: Text('Πλήθος'),
              ),
              ButtonSegment(
                value: IssueDistributionMetric.duration,
                label: Text('Διάρκεια'),
              ),
            ],
            selected: {metric},
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onSelectionChanged: (selection) => ref
                .read(dashboardIssueMetricProvider.notifier)
                .set(selection.first),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: 'Αγνόηση κλήσεων χωρίς κατηγορία',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Χωρίς Κατηγορία',
                  style: TextStyle(fontSize: 11, color: colors.kpiSubtitle),
                ),
                const SizedBox(width: 4),
                Transform.scale(
                  scale: 0.82,
                  child: Switch(
                    value: excludeCallsWithoutCategory,
                    onChanged: (value) {
                      ref
                          .read(
                            dashboardExcludeCallsWithoutCategoryProvider
                                .notifier,
                          )
                          .set(value);
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) =>
            currentChild ?? const SizedBox.shrink(),
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: IssueDistributionList(
          key: ValueKey<String>('$excludeCallsWithoutCategory-${metric.name}'),
          issues: visibleIssues,
          metric: metric,
          barColors: colors.categoryColors,
          mutedColor: colors.kpiSubtitle,
        ),
      ),
    );
  }
}

class MoreSection extends StatelessWidget {
  const MoreSection({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.data,
    required this.colors,
    required this.formatDuration,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final DashboardSummaryModel data;
  final DashboardPaletteColors colors;
  final String Function(num) formatDuration;

  Widget _categoryDistributionCard() {
    return CategoryDistributionChartCard(issues: data.byIssue, colors: colors);
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      fill: colors.glassFill,
      border: colors.glassBorder,
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
                                      child: ChartCard(
                                        title: 'Κατανομή ανά ώρα',
                                        fill: colors.chartCardFill,
                                        border: colors.chartCardBorder,
                                        child: HourlyBarChart(
                                          buckets: data.hourlyDistribution,
                                          color: colors.actionBlue,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: ChartCard(
                                        title: 'Τάση Κλήσεων (7 ημέρες)',
                                        fill: colors.chartCardFill,
                                        border: colors.chartCardBorder,
                                        child: TrendLineChart(
                                          trend: data.dailyTrend,
                                          color: colors.kpiGreen.sparkColor,
                                          gridLineColor: colors.chartGridLine,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                _categoryDistributionCard(),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              ChartCard(
                                title: 'Κατανομή ανά ώρα',
                                fill: colors.chartCardFill,
                                border: colors.chartCardBorder,
                                child: HourlyBarChart(
                                  buckets: data.hourlyDistribution,
                                  color: colors.actionBlue,
                                ),
                              ),
                              const SizedBox(height: 14),
                              ChartCard(
                                title: 'Τάση Κλήσεων (7 ημέρες)',
                                fill: colors.chartCardFill,
                                border: colors.chartCardBorder,
                                child: TrendLineChart(
                                  trend: data.dailyTrend,
                                  color: colors.kpiGreen.sparkColor,
                                  gridLineColor: colors.chartGridLine,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _categoryDistributionCard(),
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

class DepartmentPill extends StatelessWidget {
  const DepartmentPill({super.key, required this.name});

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

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
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

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    required this.fill,
    required this.border,
  });

  final Widget child;
  final Color fill;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: fill.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border.withValues(alpha: 0.9)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class LoadingDashboard extends StatelessWidget {
  const LoadingDashboard({super.key, required this.colors});

  final DashboardPaletteColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LoadingSkeleton(height: 172, colors: colors),
        const SizedBox(height: 12),
        LoadingSkeleton(height: 172, colors: colors),
        const SizedBox(height: 12),
        LoadingSkeleton(height: 240, colors: colors),
      ],
    );
  }
}

class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({
    super.key,
    required this.height,
    required this.colors,
  });

  final double height;
  final DashboardPaletteColors colors;

  @override
  Widget build(BuildContext context) {
    final a = colors.chartGridLine.withValues(alpha: 0.65);
    final b = colors.chartCardFill.withValues(alpha: 0.95);
    final c = colors.chartGridLine.withValues(alpha: 0.65);
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [a, b, c],
        ),
      ),
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    super.key,
    required this.message,
    required this.colors,
  });

  final String message;
  final DashboardPaletteColors colors;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      fill: colors.glassFill,
      border: colors.glassBorder,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Center(child: Text(message, textAlign: TextAlign.center)),
      ),
    );
  }
}

class ErrorCard extends StatelessWidget {
  const ErrorCard({super.key, required this.message, required this.colors});

  final String message;
  final DashboardPaletteColors colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      fill: colors.glassFill,
      border: colors.glassBorder,
      child: Text(message, style: TextStyle(color: theme.colorScheme.error)),
    );
  }
}

class GradientPaletteIcon extends StatelessWidget {
  const GradientPaletteIcon({super.key, required this.colors});

  final DashboardPaletteColors colors;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colors.kpiBlue.sparkColor,
          colors.kpiGreen.sparkColor,
          colors.kpiOrange.sparkColor,
          colors.kpiPurple.sparkColor,
        ],
      ).createShader(bounds),
      child: const Icon(Icons.palette_outlined, size: 18, color: Colors.white),
    );
  }
}
