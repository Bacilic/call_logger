/// Οι τέσσερις κάρτες σύνοψης των Στατιστικών Κλήσεων.
///
/// Γράφονται εδώ και όχι μέσα στην οθόνη επειδή είναι **μορφοποίηση**, όχι
/// διάταξη: παίρνουν τα νούμερα της βάσης και τα κάνουν προτάσεις. Όσο ζούσαν
/// μέσα στη `build`, μία μέθοδος κρατούσε τετρακόσιες γραμμές και η δομή της
/// οθόνης δεν φαινόταν με μια ματιά.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/dashboard_filter_model.dart';
import '../models/dashboard_summary_model.dart';
import 'dashboard_cards.dart';
import 'dashboard_palette_colors.dart';
import 'dashboard_top_entity_selector.dart';

/// Διάρκεια ανά κλήση — ίδια μορφή με ιστορικό και χρονόμετρο.
String formatDashboardCallDuration(num seconds) =>
    formatKpiCallDurationSeconds(seconds);

/// Συνολικές / ημερήσιες διάρκειες — ίδια μορφή με τις υποδείξεις.
String formatDashboardAggregateDuration(num seconds) =>
    formatKpiAggregateDurationSeconds(seconds);

/// Ποσοστιαία μεταβολή με πρόσημο, π.χ. «+107,3%».
///
/// Το κόμμα είναι το ελληνικό υποδιαστολικό σημείο· ο υπότιτλος διαβάζεται από
/// άνθρωπο, όχι από μηχάνημα.
String formatDashboardDeltaPercent(num current, num previous) {
  if (previous == 0) {
    if (current == 0) return '0,0%';
    return '100,0%';
  }
  final delta = ((current - previous) / previous) * 100;
  final prefix = delta >= 0 ? '+' : '';
  return '$prefix${delta.toStringAsFixed(1).replaceAll('.', ',')}%';
}

String _formatAvgCallsPerDay(DashboardSummaryModel data) {
  final avg = data.avgCallsPerActiveDay;
  if (avg == null) return 'Μ.Ο.: —';
  return 'Μ.Ο.: ${avg.round()} κλήσεις / ημέρα';
}

String _formatAvgDurationPerDay(DashboardSummaryModel data) {
  final avg = data.avgDurationSecondsPerActiveDay;
  if (avg == null) return 'Μ.Ο.: —';
  return 'Μ.Ο.: ${formatDashboardAggregateDuration(avg)} / ημέρα';
}

/// Ο υπότιτλος σύγκρισης μιας κάρτας: πόσο άλλαξε, και από ποια τιμή.
///
/// **Χωρίς την περίοδο μέσα στο κείμενο.** Ο τίτλος της κάρτας τη λέει ήδη
/// («Συνολικές κλήσεις · Τελευταίες 30 ημέρες»), οπότε η επανάληψή της εδώ
/// έσπρωχνε έξω από τη γραμμή τον αριθμό σύγκρισης — το μόνο που δεν λέγεται
/// πουθενά αλλού.
///
/// Γράφεται μία φορά για τις τρεις κάρτες που συγκρίνουν, ώστε να μην μπορεί η
/// μία να πει «έναντι» και η άλλη «vs».
String _comparisonSubtitle({
  required num current,
  required num previous,
  required String previousLabel,
}) {
  final delta = formatDashboardDeltaPercent(current, previous);
  return '$delta από $previousLabel';
}

String _formatTopEntityShareSubtitle(int count, int totalCalls) {
  if (totalCalls <= 0) return '$count κλήσεις';
  final pct = (count / totalCalls) * 100;
  return '$count κλήσεις (${pct.toStringAsFixed(1).replaceAll('.', ',')}% '
      'του συνόλου)';
}

List<String> _callsSparklineTooltips(List<DailyTrendPoint> days) {
  return days.map((dayPoint) {
    if (dayPoint.callCount <= 0) return '';
    final day = DateFormat('dd/MM').format(dayPoint.date);
    return '$day: ${formatKpiCallCountLabel(dayPoint.callCount)}';
  }).toList(growable: false);
}

List<String> _durationSparklineTooltips(List<DailyTrendPoint> days) {
  return days.map((dayPoint) {
    if (dayPoint.totalDurationSeconds <= 0) return '';
    final day = DateFormat('dd/MM').format(dayPoint.date);
    return '$day: '
        '${formatKpiAggregateDurationSeconds(dayPoint.totalDurationSeconds)}';
  }).toList(growable: false);
}

List<String> _avgCallSparklineTooltips(List<DailyTrendPoint> days) {
  return days.map((dayPoint) {
    if (dayPoint.callCount <= 0) return '';
    final day = DateFormat('dd/MM').format(dayPoint.date);
    final avgSeconds = dayPoint.totalDurationSeconds / dayPoint.callCount;
    return '$day: ${formatKpiCallDurationSeconds(avgSeconds)}';
  }).toList(growable: false);
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

/// Η τέταρτη κάρτα αλλάζει θέμα με τον επιλογέα της: τμήμα, καλών ή κατηγορία.
KpiTopEntity resolveDashboardTopEntity(
  DashboardSummaryModel data,
  TopEntityMode mode,
) {
  switch (mode) {
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
        title: 'Κορυφαία Κατηγορία',
        label: i?.name ?? '-',
        count: i?.count ?? 0,
        icon: Icons.build_circle_outlined,
      );
  }
}

/// Οι τέσσερις κάρτες, με τη σειρά που στέκονται στην οθόνη.
List<KpiCardData> buildDashboardKpiCards({
  required DashboardSummaryModel data,
  required DashboardFilterModel filter,
  required DashboardPaletteColors colors,
  required TopEntityMode topEntityMode,
  required ValueChanged<TopEntityMode> onTopEntityModeChanged,
  required VoidCallback onLansweeperReportTap,
}) {
  final allDatesMode = data.isAllDatesMode;
  final allDatesBars = data.allDatesBarSparklines;
  final topEntity = resolveDashboardTopEntity(data, topEntityMode);
  final trend = data.sparklineLast7Days;

  return [
    KpiCardData(
      title:
          data.totalCallsKpiTitleAllDates() ??
          'Συνολικές κλήσεις · ${filter.kpiTotalCallsRangeTitle()}',
      value: '${data.totalCalls}',
      subtitle: allDatesMode
          ? _formatAvgCallsPerDay(data)
          : _comparisonSubtitle(
              current: data.totalCalls,
              previous: data.previousPeriodTotalCalls,
              previousLabel: '${data.previousPeriodTotalCalls}',
            ),
      isUp: data.totalCalls >= data.previousPeriodTotalCalls,
      showTrendIndicator: !allDatesMode,
      useBarSparkline: allDatesMode,
      icon: Icons.call_rounded,
      points: trend.map((e) => e.callCount.toDouble()).toList(),
      sparklineTooltips: _callsSparklineTooltips(trend),
      barPoints: allDatesBars?.callsByMonth ?? const <KpiBarSparklinePoint>[],
      showLansweeperReportBadge: true,
      onTap: onLansweeperReportTap,
      colors: colors.kpiBlue,
    ),
    KpiCardData(
      title: 'Συνολική Διάρκεια Κλήσεων',
      value: formatDashboardAggregateDuration(data.totalDurationSeconds),
      subtitle: allDatesMode
          ? _formatAvgDurationPerDay(data)
          : _comparisonSubtitle(
              current: data.totalDurationSeconds,
              previous: data.previousPeriodTotalDurationSeconds,
              previousLabel: formatDashboardAggregateDuration(
                data.previousPeriodTotalDurationSeconds,
              ),
            ),
      isUp:
          data.totalDurationSeconds >= data.previousPeriodTotalDurationSeconds,
      showTrendIndicator: !allDatesMode,
      useBarSparkline: allDatesMode,
      icon: Icons.timer_outlined,
      points: trend.map((e) => e.totalDurationSeconds.toDouble()).toList(),
      sparklineTooltips: _durationSparklineTooltips(trend),
      barPoints:
          allDatesBars?.durationByWeekdayMonToFri ??
          const <KpiBarSparklinePoint>[],
      colors: colors.kpiGreen,
    ),
    KpiCardData(
      title: 'Μέσος Όρος ανά Κλήση',
      value: formatDashboardCallDuration(data.avgDurationSeconds),
      subtitle: allDatesMode
          ? 'Διάμεσος χρόνος: '
                '${formatDashboardCallDuration(data.medianDurationSeconds)}'
          : _comparisonSubtitle(
              current: data.avgDurationSeconds,
              previous: data.previousPeriodAvgDurationSeconds,
              previousLabel: formatDashboardCallDuration(
                data.previousPeriodAvgDurationSeconds,
              ),
            ),
      isUp: data.avgDurationSeconds >= data.previousPeriodAvgDurationSeconds,
      showTrendIndicator: !allDatesMode,
      useBarSparkline: allDatesMode,
      icon: Icons.av_timer_outlined,
      points: trend
          .map(
            (e) =>
                e.callCount == 0 ? 0.0 : e.totalDurationSeconds / e.callCount,
          )
          .toList(),
      sparklineTooltips: _avgCallSparklineTooltips(trend),
      barPoints:
          allDatesBars?.durationExtremesSix ?? const <KpiBarSparklinePoint>[],
      colors: colors.kpiOrange,
    ),
    KpiCardData(
      title: topEntity.title,
      value: topEntity.label,
      // Το μερίδιο λέγεται πάντα, με ή χωρίς φίλτρο ημερομηνιών: «25 κλήσεις»
      // σκέτο δεν απαντά στο «είναι πολλές;».
      subtitle: _formatTopEntityShareSubtitle(topEntity.count, data.totalCalls),
      // Χωρίς δείκτη τάσης: δεν υπάρχει προηγούμενη τιμή να συγκριθεί, και το
      // πράσινο βελάκι που έδειχνε πάντα «άνοδο» δεν σήμαινε τίποτα.
      isUp: true,
      showTrendIndicator: false,
      useBarSparkline: allDatesMode,
      icon: topEntity.icon,
      points: trend.map((e) => e.callCount.toDouble()).toList(),
      sparklineTooltips: _callsSparklineTooltips(trend),
      barPoints: _runnerUpBarPoints(allDatesBars, topEntityMode),
      headerTrailing: TopEntityModeSelector(
        mode: topEntityMode,
        onChanged: onTopEntityModeChanged,
      ),
      colors: colors.kpiPurple,
    ),
  ];
}
