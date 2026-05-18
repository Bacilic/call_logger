import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/dashboard_summary_model.dart';

class BarSparklineChart extends StatelessWidget {
  const BarSparklineChart({
    super.key,
    required this.values, required this.color,
  });

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final safeValues = values.isEmpty ? const [0.0] : values;
    final maxY = safeValues.reduce(math.max);
    final chartMaxY = maxY <= 0 ? 1.0 : maxY;
    final barWidth = switch (safeValues.length) {
      <= 5 => 5.0,
      <= 8 => 4.0,
      <= 12 => 3.0,
      _ => 2.0,
    };

    return BarChart(
      BarChartData(
        maxY: chartMaxY,
        minY: 0,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: const BarTouchData(enabled: false),
        alignment: BarChartAlignment.spaceBetween,
        groupsSpace: 1,
        barGroups: safeValues.indexed
            .map(
              (entry) => BarChartGroupData(
                x: entry.$1,
                barRods: [
                  BarChartRodData(
                    toY: entry.$2,
                    fromY: 0,
                    width: barWidth,
                    color: color,
                    borderRadius: BorderRadius.zero,
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

class SparklineChart extends StatelessWidget {
  const SparklineChart({
    super.key,
    required this.points, required this.color,
  });

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

class HourlyBarChart extends StatelessWidget {
  const HourlyBarChart({
    super.key,
    required this.buckets, required this.color,
  });

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

class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    super.key,
    required this.trend,
    required this.color,
    required this.gridLineColor,
  });

  final List<DailyTrendPoint> trend;
  final Color color;
  final Color gridLineColor;

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
                FlLine(color: gridLineColor, strokeWidth: 1),
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

class IssuePieChart extends StatelessWidget {
  const IssuePieChart({
    super.key,
    required this.issues,
    required this.formatDuration,
    required this.pieColors,
    required this.legendMutedColor,
  });

  final List<IssueStat> issues;
  final String Function(num) formatDuration;
  final List<Color> pieColors;
  final Color legendMutedColor;

  @override
  Widget build(BuildContext context) {
    final top = issues.take(5).toList();
    if (top.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text('Δεν υπάρχουν δεδομένα.')),
      );
    }
    final colors = pieColors;
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
                      style: TextStyle(color: legendMutedColor),
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

class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    required this.fill,
    required this.border,
  });

  final String title;
  final Widget child;
  final Color fill;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fill.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
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
