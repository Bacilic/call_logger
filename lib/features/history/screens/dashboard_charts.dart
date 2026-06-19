import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/dashboard_summary_model.dart';

class BarSparklineChart extends StatefulWidget {
  const BarSparklineChart({
    super.key,
    required this.points,
    required this.color,
  });

  final List<KpiBarSparklinePoint> points;
  final Color color;

  @override
  State<BarSparklineChart> createState() => _BarSparklineChartState();
}

class _BarSparklineChartState extends State<BarSparklineChart> {
  final GlobalKey _chartKey = GlobalKey();
  final OverlayPortalController _tooltipPortal = OverlayPortalController();
  String? _tooltipText;
  double? _tooltipAnchorX;

  @override
  void dispose() {
    _hideTooltip();
    super.dispose();
  }

  void _hideTooltip() {
    final wasVisible = _tooltipText != null;
    _tooltipText = null;
    _tooltipAnchorX = null;
    if (_tooltipPortal.isShowing) {
      _tooltipPortal.hide();
    } else if (wasVisible && mounted) {
      setState(() {});
    }
  }

  void _showTooltip(String text, double anchorX) {
    final wasShowing = _tooltipPortal.isShowing;
    _tooltipText = text;
    _tooltipAnchorX = anchorX;
    if (wasShowing) {
      setState(() {});
      return;
    }
    _tooltipPortal.show();
  }

  Widget? _buildOverlayTooltip(BuildContext overlayContext) {
    final text = _tooltipText;
    final anchorX = _tooltipAnchorX;
    if (text == null || anchorX == null) {
      return null;
    }

    final renderBox = _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return null;
    }

    final chartTopLeft = renderBox.localToGlobal(Offset.zero);
    final chartSize = renderBox.size;
    const tooltipWidth = 160.0;
    final clampedAnchorX = anchorX.clamp(0.0, chartSize.width);
    final anchorGlobalX = chartTopLeft.dx + clampedAnchorX;
    final screenWidth = MediaQuery.sizeOf(overlayContext).width;
    final left = (anchorGlobalX - tooltipWidth / 2)
        .clamp(
          8.0,
          math.max(8.0, screenWidth - tooltipWidth - 8),
        )
        .toDouble();
    final top = chartTopLeft.dy - 6;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: left,
          top: top,
          width: tooltipWidth,
          child: Transform.translate(
            offset: const Offset(0, -1),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: IgnorePointer(
                child: _BarSparklineTooltip(text: text),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onBarTouch(FlTouchEvent event, BarTouchResponse? response) {
    if (!event.isInterestedForInteractions) {
      _hideTooltip();
      return;
    }

    final spot = response?.spot;
    if (spot == null) {
      _hideTooltip();
      return;
    }

    final safePoints = widget.points.isEmpty
        ? const [KpiBarSparklinePoint(value: 0, tooltip: '')]
        : widget.points;
    final index = spot.touchedBarGroupIndex;
    if (index < 0 || index >= safePoints.length) return;

    final point = safePoints[index];
    if (point.tooltip.isEmpty) {
      _hideTooltip();
      return;
    }

    _showTooltip(point.tooltip, spot.offset.dx);
  }

  @override
  Widget build(BuildContext context) {
    final safePoints = widget.points.isEmpty
        ? const [KpiBarSparklinePoint(value: 0, tooltip: '')]
        : widget.points;
    final values = safePoints.map((point) => point.value).toList();
    final maxY = values.reduce(math.max);
    final chartMaxY = maxY <= 0 ? 1.0 : maxY;
    final barWidth = switch (safePoints.length) {
      <= 5 => 5.0,
      <= 8 => 4.0,
      <= 12 => 3.0,
      _ => 2.0,
    };

    return OverlayPortal(
      controller: _tooltipPortal,
      overlayChildBuilder: (overlayContext) {
        return _buildOverlayTooltip(overlayContext) ?? const SizedBox.shrink();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            key: _chartKey,
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: BarChart(
              BarChartData(
                maxY: chartMaxY,
                minY: 0,
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  enabled: true,
                  handleBuiltInTouches: false,
                  touchCallback: _onBarTouch,
                  mouseCursorResolver: (event, response) {
                    final index = response?.spot?.touchedBarGroupIndex;
                    if (index == null ||
                        index < 0 ||
                        index >= safePoints.length ||
                        safePoints[index].tooltip.isEmpty) {
                      return SystemMouseCursors.basic;
                    }
                    return SystemMouseCursors.click;
                  },
                ),
                alignment: BarChartAlignment.spaceBetween,
                groupsSpace: 1,
                barGroups: safePoints.indexed
                    .map(
                      (entry) => BarChartGroupData(
                        x: entry.$1,
                        barRods: [
                          BarChartRodData(
                            toY: entry.$2.value,
                            fromY: 0,
                            width: barWidth,
                            color: widget.color,
                            borderRadius: BorderRadius.zero,
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BarSparklineTooltip extends StatelessWidget {
  const _BarSparklineTooltip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(6),
      color: const Color(0xF01E293B),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

class SparklineChart extends StatefulWidget {
  const SparklineChart({
    super.key,
    required this.points,
    required this.color,
    this.tooltips = const [],
  });

  final List<double> points;
  final List<String> tooltips;
  final Color color;

  @override
  State<SparklineChart> createState() => _SparklineChartState();
}

class _SparklineChartState extends State<SparklineChart> {
  final GlobalKey _chartKey = GlobalKey();
  final OverlayPortalController _tooltipPortal = OverlayPortalController();
  String? _tooltipText;
  double? _tooltipAnchorX;

  bool get _hasTooltips =>
      widget.tooltips.length == widget.points.length &&
      widget.tooltips.any((t) => t.isNotEmpty);

  @override
  void dispose() {
    _hideTooltip();
    super.dispose();
  }

  void _hideTooltip() {
    final wasVisible = _tooltipText != null;
    _tooltipText = null;
    _tooltipAnchorX = null;
    if (_tooltipPortal.isShowing) {
      _tooltipPortal.hide();
    } else if (wasVisible && mounted) {
      setState(() {});
    }
  }

  void _showTooltip(String text, double anchorX) {
    final wasShowing = _tooltipPortal.isShowing;
    _tooltipText = text;
    _tooltipAnchorX = anchorX;
    if (wasShowing) {
      setState(() {});
      return;
    }
    _tooltipPortal.show();
  }

  Widget? _buildOverlayTooltip(BuildContext overlayContext) {
    final text = _tooltipText;
    final anchorX = _tooltipAnchorX;
    if (text == null || anchorX == null) {
      return null;
    }

    final renderBox = _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return null;
    }

    final chartTopLeft = renderBox.localToGlobal(Offset.zero);
    final chartSize = renderBox.size;
    const tooltipWidth = 160.0;
    final clampedAnchorX = anchorX.clamp(0.0, chartSize.width);
    final anchorGlobalX = chartTopLeft.dx + clampedAnchorX;
    final screenWidth = MediaQuery.sizeOf(overlayContext).width;
    final left = (anchorGlobalX - tooltipWidth / 2)
        .clamp(
          8.0,
          math.max(8.0, screenWidth - tooltipWidth - 8),
        )
        .toDouble();
    final top = chartTopLeft.dy - 6;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: left,
          top: top,
          width: tooltipWidth,
          child: Transform.translate(
            offset: const Offset(0, -1),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: IgnorePointer(
                child: _BarSparklineTooltip(text: text),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onLineTouch(FlTouchEvent event, LineTouchResponse? response) {
    if (!_hasTooltips) return;

    if (!event.isInterestedForInteractions) {
      _hideTooltip();
      return;
    }

    final spot = response?.lineBarSpots?.firstOrNull;
    if (spot == null) {
      _hideTooltip();
      return;
    }

    final index = spot.spotIndex;
    if (index < 0 || index >= widget.tooltips.length) return;

    final tooltip = widget.tooltips[index];
    if (tooltip.isEmpty) {
      _hideTooltip();
      return;
    }

    _showTooltip(tooltip, response!.touchLocation.dx);
  }

  @override
  Widget build(BuildContext context) {
    final safePoints = widget.points.isEmpty ? [0.0] : widget.points;
    final chart = LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          key: _chartKey,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                enabled: _hasTooltips,
                handleBuiltInTouches: false,
                touchCallback: _onLineTouch,
                mouseCursorResolver: (event, response) {
                  final index = response?.lineBarSpots?.firstOrNull?.spotIndex;
                  if (index == null ||
                      index < 0 ||
                      index >= widget.tooltips.length ||
                      widget.tooltips[index].isEmpty) {
                    return SystemMouseCursors.basic;
                  }
                  return SystemMouseCursors.click;
                },
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: safePoints.indexed
                      .map((e) => FlSpot(e.$1.toDouble(), e.$2))
                      .toList(),
                  isCurved: true,
                  barWidth: 2.2,
                  color: widget.color,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: widget.color.withValues(alpha: 0.15),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!_hasTooltips) {
      return chart;
    }

    return OverlayPortal(
      controller: _tooltipPortal,
      overlayChildBuilder: (overlayContext) {
        return _buildOverlayTooltip(overlayContext) ?? const SizedBox.shrink();
      },
      child: chart,
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
    required this.pieColors,
    required this.legendMutedColor,
  });

  final List<IssueStat> issues;
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
                      formatIssueChartDurationSeconds(issue.sumDurationSeconds),
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
    this.titleTrailing,
  });

  final String title;
  final Widget child;
  final Color fill;
  final Color border;
  final Widget? titleTrailing;

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
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ?titleTrailing,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
