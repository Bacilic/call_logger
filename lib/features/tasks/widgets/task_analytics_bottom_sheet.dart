import 'dart:math' as math;
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/calendar_range_picker.dart';
import '../models/task_analytics_summary.dart';
import '../providers/task_analytics_provider.dart';
import '../providers/tasks_provider.dart';

class TaskAnalyticsBottomSheet extends ConsumerWidget {
  const TaskAnalyticsBottomSheet({super.key});

  static const _palette = _TaskAnalyticsPalette();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsFilter = ref.watch(taskAnalyticsFilterProvider);
    final asyncSummary = ref.watch(taskAnalyticsProvider);
    final theme = Theme.of(context);
    final dateRangeText =
        '${DateFormat('dd/MM/yyyy').format(analyticsFilter.startDate)} - '
        '${DateFormat('dd/MM/yyyy').format(analyticsFilter.endDate)}';

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: const Color(0xFFF8FAFC),
          padding: EdgeInsets.fromLTRB(
            16,
            14,
            16,
            16 + MediaQuery.of(context).viewPadding.bottom,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0E7FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.analytics_outlined,
                        color: Color(0xFF4F46E5),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Αναφορές Εκκρεμοτήτων',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Στατιστική απεικόνιση εκκρεμοτήτων',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickDateRange(context, ref),
                      icon: const Icon(
                        Icons.event_available_outlined,
                        size: 18,
                      ),
                      label: Text(dateRangeText),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _setDatePreset(ref, 1),
                      child: const Text('Σήμερα'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _setDatePreset(ref, 7),
                      child: const Text('7 ημέρες'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _setDatePreset(ref, 30),
                      child: const Text('30 ημέρες'),
                    ),
                    TextButton(
                      onPressed: () => _clearDateRange(ref),
                      child: const Text('Καθαρισμός'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: asyncSummary.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text(
                        'Σφάλμα φόρτωσης αναφορών: $e',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                    data: (summary) => _TaskAnalyticsBody(summary: summary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDateRange(BuildContext context, WidgetRef ref) async {
    final filter = ref.read(taskFilterProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialStart = filter.startDate ?? today;
    final initialEnd = filter.endDate ?? today;
    final result = await showCalendarRangePickerDialog(
      context,
      initialValue: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (!context.mounted || result == null) return;
    if (result.wasCleared) {
      _clearDateRange(ref);
      return;
    }
    final range = result.range;
    if (range == null) return;
    ref
        .read(taskFilterProvider.notifier)
        .update((s) => s.copyWith(startDate: range.start, endDate: range.end));
  }

  void _setDatePreset(WidgetRef ref, int inclusiveDays) {
    final filter = ref.read(taskFilterProvider);
    final anchor = filter.endDate ?? filter.startDate ?? DateTime.now();
    final end = DateTime(anchor.year, anchor.month, anchor.day);
    final start = end.subtract(Duration(days: inclusiveDays - 1));
    ref
        .read(taskFilterProvider.notifier)
        .update((s) => s.copyWith(startDate: start, endDate: end));
  }

  void _clearDateRange(WidgetRef ref) {
    ref
        .read(taskFilterProvider.notifier)
        .update((s) => s.copyWith(clearDateRange: true));
  }
}

class _TaskAnalyticsBody extends StatelessWidget {
  const _TaskAnalyticsBody({required this.summary});

  final TaskAnalyticsSummary summary;

  static const _palette = TaskAnalyticsBottomSheet._palette;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _TaskAnalyticsLayout.fromWidth(constraints.maxWidth);
        final dominantOrigin = summary.originDistribution.isEmpty
            ? null
            : summary.originDistribution.first;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final card in <Widget>[
                    _KpiCard(
                      title: 'Ανοικτές τώρα',
                      value: '${summary.activeNowCount}',
                      subtitle:
                          'Ανοικτές στο εύρος: ${summary.activeCreatedInRangeCount}',
                      color: _palette.indigo,
                      icon: Icons.inventory_2_outlined,
                      sparkline: summary.sparklineActive,
                    ),
                    _KpiCard(
                      title: 'Ολοκληρωμένες',
                      value: '${summary.closedInRangeCount}',
                      subtitle:
                          'Ποσοστό ολοκλήρωσης: ${summary.completionRateInRange.toStringAsFixed(1)}%',
                      color: _palette.emerald,
                      icon: Icons.task_alt_outlined,
                      sparkline: summary.sparklineClosed,
                    ),
                    _KpiCard(
                      title: 'Ακυρωμένες',
                      value: '${summary.cancelledInRangeCount}',
                      subtitle:
                          'Ποσοστό ακύρωσης: ${summary.cancellationRateInRange.toStringAsFixed(1)}%',
                      color: _palette.criticalRed,
                      icon: Icons.cancel_outlined,
                      sparkline: summary.sparklineCancelled,
                    ),
                    _KpiCard(
                      title: 'Ποσοστό καθυστερήσεων',
                      value: '${summary.overdueRateActive.toStringAsFixed(1)}%',
                      subtitle:
                          'Ενεργές: ${summary.overdueRateActive.toStringAsFixed(1)}% | Εύρος: ${summary.overdueRateRange.toStringAsFixed(1)}%',
                      color: _palette.criticalRed,
                      icon: Icons.warning_amber_rounded,
                      sparkline: summary.sparklineOverdue,
                    ),
                    _KpiCard(
                      title: 'Δείκτης αναβολών',
                      value: summary.avgSnoozesPerTask.toStringAsFixed(2),
                      subtitle:
                          'Μ. χρόνος ολοκλήρωσης: ${_formatDuration(summary.avgCompletionSeconds)}',
                      color: _palette.softAmber,
                      icon: Icons.snooze_outlined,
                      sparkline: summary.sparklineCompletionRate,
                    ),
                  ])
                    SizedBox(
                      width: layout.kpiCardWidth(constraints.maxWidth),
                      child: card,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (layout.isMainRowHorizontal)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: layout.backlogFlex,
                      child: _SectionCard(
                        title: 'Μεταβολή υπολοίπου εκκρεμοτήτων',
                        child: _BacklogAreaChart(points: summary.backlogGrowth),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: layout.originFlex,
                      child: _SectionCard(
                        title: 'Κατανομή προέλευσης',
                        child: _OriginDonutChart(
                          data: summary.originDistribution,
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
                _SectionCard(
                  title: 'Μεταβολή υπολοίπου εκκρεμοτήτων',
                  child: _BacklogAreaChart(points: summary.backlogGrowth),
                ),
                const SizedBox(height: 10),
                _SectionCard(
                  title: 'Κατανομή προέλευσης',
                  child: _OriginDonutChart(data: summary.originDistribution),
                ),
              ],
              const SizedBox(height: 10),
              _InsightsCard(text: _buildInsightText(summary, dominantOrigin)),
            ],
          ),
        );
      },
    );
  }

  static String _formatDuration(double seconds) {
    final sec = seconds.isNaN ? 0 : seconds.round().clamp(0, 31536000);
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    if (h > 0) return '$h ώρ. $m λ.';
    return '${m.clamp(0, 59)} λ.';
  }

  static String _buildInsightText(
    TaskAnalyticsSummary summary,
    TaskAnalyticsOriginSlice? dominantOrigin,
  ) {
    final backlogLast = summary.backlogGrowth.isEmpty
        ? 0
        : summary.backlogGrowth.last.delta;
    final trendWord = backlogLast >= 0 ? 'αυξήθηκε' : 'μειώθηκε';
    final trendAbs = backlogLast.abs();
    final originText = dominantOrigin == null
        ? 'δεν υπάρχει κυρίαρχο κανάλι προέλευσης'
        : 'κυρίαρχη προέλευση: ${_localizedOriginLabel(dominantOrigin.origin)} (${dominantOrigin.percent.toStringAsFixed(1)}%)';
    return 'Το υπόλοιπο εκκρεμοτήτων $trendWord κατά $trendAbs στην τελευταία ημέρα του εύρους. '
        'Ο δείκτης καθυστερήσεων στις ενεργές εκκρεμότητες είναι '
        '${summary.overdueRateActive.toStringAsFixed(1)}%, ενώ $originText.';
  }

  static String _localizedOriginLabel(String origin) {
    return switch (origin) {
      'call_linked' => 'Από κλήση',
      'manual_fab' => 'Χειροκίνητη',
      'quick_add' => 'Γρήγορη προσθήκη',
      'legacy' => 'Παλαιές εγγραφές',
      _ => 'Άγνωστη προέλευση',
    };
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.sparkline,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;
  final List<double> sparkline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 3,
            overflow: TextOverflow.fade,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: _SparklineMini(points: sparkline, color: color),
          ),
        ],
      ),
    );
  }
}

class _SparklineMini extends StatelessWidget {
  const _SparklineMini({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final safePoints = points.isEmpty ? const [0.0] : points;
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
              color: color.withValues(alpha: 0.14),
            ),
          ),
        ],
      ),
    );
  }
}

class _BacklogAreaChart extends StatelessWidget {
  const _BacklogAreaChart({required this.points});

  final List<TaskAnalyticsBacklogPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(child: Text('Δεν υπάρχουν δεδομένα στο εύρος.')),
      );
    }
    final maxAbs = points
        .map((e) => e.runningDelta.abs())
        .fold<int>(1, (a, b) => math.max(a, b))
        .toDouble();
    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minY: -maxAbs * 1.1,
          maxY: maxAbs * 1.1,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: math.max(1, maxAbs / 4),
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0xFFE2E8F0), strokeWidth: 1),
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
                interval: math.max(1, (points.length / 6).floor()).toDouble(),
                getTitlesWidget: (value, _) {
                  final index = value.toInt();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateFormat('dd/MM').format(points[index].date),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: points.indexed
                  .map(
                    (entry) => FlSpot(
                      entry.$1.toDouble(),
                      entry.$2.runningDelta.toDouble(),
                    ),
                  )
                  .toList(),
              color: const Color(0xFF4F46E5),
              barWidth: 2.8,
              isCurved: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF4F46E5).withValues(alpha: 0.30),
                    const Color(0xFF4F46E5).withValues(alpha: 0.04),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OriginDonutChart extends StatelessWidget {
  const _OriginDonutChart({required this.data});

  final List<TaskAnalyticsOriginSlice> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(child: Text('Δεν υπάρχουν δεδομένα προέλευσης.')),
      );
    }
    final colors = <String, Color>{
      'call_linked': const Color(0xFF4F46E5),
      'manual_fab': const Color(0xFF10B981),
      'quick_add': const Color(0xFFF59E0B),
      'legacy': const Color(0xFF94A3B8),
    };
    final dominant = data.first;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow =
            constraints.maxWidth < _TaskAnalyticsBreakpoints.tablet;
        final chart = SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  centerSpaceRadius: 52,
                  sectionsSpace: 2,
                  sections: data
                      .map(
                        (slice) => PieChartSectionData(
                          color:
                              colors[slice.origin] ?? const Color(0xFF94A3B8),
                          value: slice.count.toDouble(),
                          title: '${slice.percent.toStringAsFixed(0)}%',
                          radius: 54,
                          titleStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _TaskAnalyticsBody._localizedOriginLabel(dominant.origin),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${dominant.percent.toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
        final legend = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: data
              .map(
                (slice) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color:
                              colors[slice.origin] ?? const Color(0xFF94A3B8),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _TaskAnalyticsBody._localizedOriginLabel(
                            slice.origin,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${slice.count}'),
                    ],
                  ),
                ),
              )
              .toList(),
        );
        if (isNarrow) {
          return Column(children: [chart, const SizedBox(height: 8), legend]);
        }
        return Row(
          children: [
            chart,
            const SizedBox(width: 8),
            Expanded(child: legend),
          ],
        );
      },
    );
  }
}

class _TaskAnalyticsBreakpoints {
  const _TaskAnalyticsBreakpoints._();

  // Πλήρες desktop (desktop): 4 KPI σε μία σειρά + οριζόντια κύρια ζώνη.
  static const double desktop = 960;

  // Tablet landscape (tablet): 2x2 KPI και οριζόντια κύρια ζώνη charts.
  static const double tablet = 760;

  // Compact tablet / μεγάλα κινητά (compact): 2x2 KPI και κάθετη κύρια ζώνη.
  static const double compact = 560;
}

class _TaskAnalyticsLayout {
  const _TaskAnalyticsLayout({
    required this.kpiColumns,
    required this.isMainRowHorizontal,
    required this.backlogFlex,
    required this.originFlex,
  });

  final int kpiColumns;
  final bool isMainRowHorizontal;
  final int backlogFlex;
  final int originFlex;

  static _TaskAnalyticsLayout fromWidth(double width) {
    if (width >= _TaskAnalyticsBreakpoints.desktop) {
      return const _TaskAnalyticsLayout(
        kpiColumns: 4,
        isMainRowHorizontal: true,
        backlogFlex: 7,
        originFlex: 5,
      );
    }
    if (width >= _TaskAnalyticsBreakpoints.tablet) {
      return const _TaskAnalyticsLayout(
        kpiColumns: 2,
        isMainRowHorizontal: true,
        backlogFlex: 6,
        originFlex: 4,
      );
    }
    if (width >= _TaskAnalyticsBreakpoints.compact) {
      return const _TaskAnalyticsLayout(
        kpiColumns: 2,
        isMainRowHorizontal: false,
        backlogFlex: 1,
        originFlex: 1,
      );
    }
    return const _TaskAnalyticsLayout(
      kpiColumns: 1,
      isMainRowHorizontal: false,
      backlogFlex: 1,
      originFlex: 1,
    );
  }

  double kpiCardWidth(double availableWidth) {
    const spacing = 10.0;
    final totalSpacing = spacing * (kpiColumns - 1);
    return (availableWidth - totalSpacing) / kpiColumns;
  }
}

class _InsightsCard extends StatelessWidget {
  const _InsightsCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFE0E7FF),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.insights_outlined,
              color: Color(0xFF4F46E5),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF1E293B),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskAnalyticsPalette {
  const _TaskAnalyticsPalette();

  final Color indigo = const Color(0xFF4F46E5);
  final Color softAmber = const Color(0xFFF59E0B);
  final Color criticalRed = const Color(0xFFEF4444);
  final Color emerald = const Color(0xFF10B981);
}
