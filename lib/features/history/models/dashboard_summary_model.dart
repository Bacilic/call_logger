import 'package:intl/intl.dart';

import '../../../core/utils/call_duration_format.dart';
import 'dashboard_filter_model.dart';

/// Ετικέτα για κλήσεις χωρίς κατηγορία προβλήματος — συμφωνεί με το SQL του dashboard.
const String kDashboardNoCategoryLabel =
    '\u03a7\u03c9\u03c1\u03af\u03c2 \u039a\u03b1\u03c4\u03b7\u03b3\u03bf\u03c1\u03af\u03b1';

/// Ετικέτα για κλήσεις χωρίς τμήμα στα στατιστικά dashboard.
const String kDashboardUnknownDepartmentLabel = 'Άγνωστο';

/// Ετικέτα για κλήσεις χωρίς καλούντα στα στατιστικά dashboard.
const String kDashboardUnknownCallerLabel = 'Άγνωστος';

DateTime? parseDashboardSqlDate(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final parsed = DateTime.tryParse(trimmed);
  if (parsed == null) return null;
  return DashboardFilterModel.dayOnly(parsed);
}

/// Στατιστικά ανά τμήμα (resolved όνομα).
class DepartmentStat {
  const DepartmentStat({
    required this.name,
    required this.count,
    required this.sumDurationSeconds,
  });

  final String name;
  final int count;
  final int sumDurationSeconds;
}

/// Στατιστικά ανά κατηγορία προβλήματος (`categories` / `calls.category_text`).
class IssueStat {
  const IssueStat({
    required this.name,
    required this.count,
    required this.sumDurationSeconds,
  });

  final String name;
  final int count;
  final int sumDurationSeconds;
}

/// Ημερήσιο σημείο τάσης (για sparkline/γραμμή).
class DailyTrendPoint {
  const DailyTrendPoint({
    required this.date,
    required this.callCount,
    required this.totalDurationSeconds,
  });

  final DateTime date;
  final int callCount;
  final int totalDurationSeconds;
}

/// Στατιστικά ανά καλούντα.
class CallerStat {
  const CallerStat({required this.name, required this.count});

  final String name;
  final int count;
}

/// Συγκεντρωτικός χρόνος ενός καλούντα στο επιλεγμένο διάστημα.
///
/// Απαντά σε άλλο ερώτημα από το [CallerStat] (πλήθος κλήσεων): «πόση ώρα μου
/// τρώει συνολικά αυτό το άτομο» — λίγες μεγάλες κλήσεις ζυγίζουν διαφορετικά
/// από πολλές σύντομες.
class CallerTimeStat {
  const CallerTimeStat({
    required this.name,
    required this.callCount,
    required this.totalDurationSeconds,
  });

  final String name;
  final int callCount;
  final int totalDurationSeconds;

  /// Μέση διάρκεια ανά κλήση· 0 όταν δεν υπάρχουν κλήσεις.
  int get avgDurationSeconds =>
      callCount <= 0 ? 0 : (totalDurationSeconds / callCount).round();
}

/// Οι δύο όψεις της κάρτας χρόνου: μεμονωμένες κλήσεις ή σύνολο ανά άτομο.
enum LongestCallsMode { perCall, perPerson }

/// Κριτήριο ταξινόμησης της όψης «ανά άτομο».
enum CallerTimeSort { total, count, average }

/// Ταξινόμηση φθίνουσα κατά το επιλεγμένο κριτήριο, με σταθερό δεύτερο κριτήριο
/// (όνομα) ώστε η σειρά να μην αλλάζει τυχαία σε ισοπαλίες.
List<CallerTimeStat> sortedCallerTimeStats(
  List<CallerTimeStat> stats,
  CallerTimeSort sort,
) {
  int key(CallerTimeStat s) => switch (sort) {
    CallerTimeSort.total => s.totalDurationSeconds,
    CallerTimeSort.count => s.callCount,
    CallerTimeSort.average => s.avgDurationSeconds,
  };
  final sorted = List<CallerTimeStat>.from(stats)
    ..sort((a, b) {
      final byKey = key(b).compareTo(key(a));
      if (byKey != 0) return byKey;
      return a.name.compareTo(b.name);
    });
  return sorted;
}

/// Οι καλούντες που εμφανίζονται, με ή χωρίς τον συγκεντρωτικό «Άγνωστο».
///
/// Ο «Άγνωστος» δεν είναι πρόσωπο αλλά «δεν καταγράφηκε ποιος»· όσο η βάση
/// συμπληρώνεται θα σβήσει μόνος του, ώς τότε ο διακόπτης τον κρύβει για να
/// φαίνονται οι πραγματικοί άνθρωποι.
List<CallerTimeStat> visibleCallerTimeStats(
  List<CallerTimeStat> stats, {
  required bool hideUnknownCaller,
}) {
  if (!hideUnknownCaller) return stats;
  return stats
      .where((s) => s.name != kDashboardUnknownCallerLabel)
      .toList(growable: false);
}

/// Εγγραφή χρονοβόρας κλήσης.
class LongestCallEntry {
  const LongestCallEntry({
    required this.callerName,
    required this.department,
    required this.durationSeconds,
  });

  final String callerName;
  final String department;
  final int durationSeconds;
}

/// Κατανομή κλήσεων ανά ώρα.
class HourlyBucket {
  const HourlyBucket({required this.hour, required this.callCount});

  final int hour;
  final int callCount;
}

/// Σημείο mini bar sparkline με κείμενο tooltip.
class KpiBarSparklinePoint {
  const KpiBarSparklinePoint({required this.value, required this.tooltip});

  final double value;
  final String tooltip;
}

const _kWeekdayLabelsMonToFri = [
  'Δευτέρα',
  'Τρίτη',
  'Τετάρτη',
  'Πέμπτη',
  'Παρασκευή',
];

const _kDurationExtremeLabels = [
  'Μεγαλύτερη #1',
  'Μεγαλύτερη #2',
  'Μεγαλύτερη #3',
  'Μικρότερη #1',
  'Μικρότερη #2',
  'Μικρότερη #3',
];

/// Mini-γράφημα ράβδων για KPI κάρτες σε λειτουργία «Όλες οι ημερομηνίες».
class KpiAllDatesBarSparklines {
  const KpiAllDatesBarSparklines({
    required this.callsByMonth,
    required this.durationByWeekdayMonToFri,
    required this.durationExtremesSix,
    required this.departmentCountsRank2To6,
    required this.callerCountsRank2To6,
    required this.issueCountsRank2To6,
  });

  /// Σύνολο κλήσεων ανά μήνα (χρονολογική σειρά).
  final List<KpiBarSparklinePoint> callsByMonth;

  /// Συνολική διάρκεια ανά ημέρα εβδομάδας (Δευ–Παρ, 5 ράβδοι).
  final List<KpiBarSparklinePoint> durationByWeekdayMonToFri;

  /// 3 μεγαλύτερες + 3 μικρότερες διάρκειες κλήσεων (6 ράβδοι).
  final List<KpiBarSparklinePoint> durationExtremesSix;

  /// Κλήσεις τμημάτων θέσεων 2–6 (το #1 είναι η κύρια τιμή KPI).
  final List<KpiBarSparklinePoint> departmentCountsRank2To6;

  /// Κλήσεις καλούντων θέσεων 2–6.
  final List<KpiBarSparklinePoint> callerCountsRank2To6;

  /// Κλήσεις βλαβών θέσεων 2–6.
  final List<KpiBarSparklinePoint> issueCountsRank2To6;
}

String formatKpiCallCountLabel(num count) {
  final rounded = count.round();
  final unit = rounded == 1 ? 'κλήση' : 'κλήσεις';
  return '$rounded $unit';
}

String formatKpiCallDurationSeconds(num seconds) =>
    formatCallDurationSeconds(seconds, ifMissing: '00:00');

/// Σύνολο διάρκειας στις υποδείξεις των γραφημάτων — με μονάδες, όπως οι κάρτες.
String formatKpiAggregateDurationSeconds(num seconds) =>
    formatAggregateDurationSeconds(seconds, ifMissing: '0δ');

/// Συνολική διάρκεια στη λεζάντα «Κατανομή Βλαβών» — ίδια μορφή με τα σύνολα.
String formatIssueChartDurationSeconds(num seconds) =>
    formatAggregateDurationSeconds(seconds, ifMissing: '0δ');

String formatKpiMonthCallsTooltip(String monthKey, num count) {
  final parsed = DateTime.tryParse('$monthKey-01');
  final label = parsed != null
      ? DateFormat('MMMM yyyy', 'el').format(parsed)
      : monthKey;
  return '$label: ${formatKpiCallCountLabel(count)}';
}

KpiBarSparklinePoint kpiWeekdayDurationPoint(int weekdayIndex, num seconds) {
  final label = _kWeekdayLabelsMonToFri[weekdayIndex];
  return KpiBarSparklinePoint(
    value: seconds.toDouble(),
    tooltip: '$label: ${formatKpiAggregateDurationSeconds(seconds)}',
  );
}

KpiBarSparklinePoint kpiDurationExtremePoint(int index, num seconds) {
  final label = _kDurationExtremeLabels[index];
  return KpiBarSparklinePoint(
    value: seconds.toDouble(),
    tooltip: '$label: ${formatKpiCallDurationSeconds(seconds)}',
  );
}

KpiBarSparklinePoint kpiRunnerUpCallsPoint(String name, int count, int rank) {
  return KpiBarSparklinePoint(
    value: count.toDouble(),
    tooltip: '$rankο · $name: ${formatKpiCallCountLabel(count)}',
  );
}

/// Συμπλήρωση λίστας σημείων σε σταθερό μήκος (μηδενικά στο τέλος).
List<KpiBarSparklinePoint> padBarSparklinePoints(
  List<KpiBarSparklinePoint> points,
  int length,
) {
  if (length <= 0) return List<KpiBarSparklinePoint>.from(points);
  if (points.length >= length) {
    return points.sublist(0, length);
  }
  return [
    ...points,
    ...List<KpiBarSparklinePoint>.filled(
      length - points.length,
      const KpiBarSparklinePoint(value: 0, tooltip: ''),
    ),
  ];
}

List<KpiBarSparklinePoint> runnerUpPointsFromDepartmentStats(
  List<DepartmentStat> stats,
  int take,
) {
  return padBarSparklinePoints(
    stats
        .skip(1)
        .take(take)
        .toList()
        .asMap()
        .entries
        .map(
          (e) => kpiRunnerUpCallsPoint(e.value.name, e.value.count, e.key + 2),
        )
        .toList(growable: false),
    take,
  );
}

List<KpiBarSparklinePoint> runnerUpPointsFromCallerStats(
  List<CallerStat> stats,
  int take,
) {
  return padBarSparklinePoints(
    stats
        .skip(1)
        .take(take)
        .toList()
        .asMap()
        .entries
        .map(
          (e) => kpiRunnerUpCallsPoint(e.value.name, e.value.count, e.key + 2),
        )
        .toList(growable: false),
    take,
  );
}

List<KpiBarSparklinePoint> runnerUpPointsFromIssueStats(
  List<IssueStat> stats,
  int take,
) {
  return padBarSparklinePoints(
    stats
        .skip(1)
        .take(take)
        .toList()
        .asMap()
        .entries
        .map(
          (e) => kpiRunnerUpCallsPoint(e.value.name, e.value.count, e.key + 2),
        )
        .toList(growable: false),
    take,
  );
}

/// Τοπικό φίλτρο κατηγοριών για το γράφημα «Κατανομή Βλαβών» (χωρίς επανάληψη SQL).
List<IssueStat> visibleDashboardIssueStats(
  List<IssueStat> issues, {
  required bool excludeCallsWithoutCategory,
}) {
  if (!excludeCallsWithoutCategory) {
    return issues;
  }
  return issues
      .where((issue) => issue.name != kDashboardNoCategoryLabel)
      .toList(growable: false);
}

/// Υπολογισμός διάμεσου (median) από ταξινομημένη λίστα δευτερολέπτων.
int medianDurationSecondsFromList(List<int> durations) {
  if (durations.isEmpty) return 0;
  final sorted = List<int>.from(durations)..sort();
  final n = sorted.length;
  if (n.isOdd) return sorted[n ~/ 2];
  return ((sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2).round();
}

/// Αποτέλεσμα ερωτημάτων dashboard (KPIs + ομαδοποιήσεις).
class DashboardSummaryModel {
  const DashboardSummaryModel({
    required this.totalCalls,
    required this.totalDurationSeconds,
    required this.avgDurationSeconds,
    required this.previousPeriodTotalCalls,
    required this.previousPeriodTotalDurationSeconds,
    required this.previousPeriodAvgDurationSeconds,
    this.isAllDatesMode = false,
    this.totalActiveDays = 0,
    this.medianDurationSeconds = 0,
    this.historyDateFrom,
    this.historyDateTo,
    this.allDatesBarSparklines,
    required this.dailyTrend,
    required this.sparklineLast7Days,
    required this.topCallers,
    required this.longestCalls,
    this.callerTimeTotals = const <CallerTimeStat>[],
    required this.hourlyDistribution,
    required this.byDepartment,
    required this.byIssue,
  });

  final int totalCalls;
  final int totalDurationSeconds;

  /// Μέση διάρκεια κλήσης σε δευτερόλεπτα (0 αν δεν υπάρχουν κλήσεις).
  final double avgDurationSeconds;

  /// KPIs προηγούμενης περιόδου (ίδιο μήκος με το επιλεγμένο εύρος, όπου ορίζεται).
  final int previousPeriodTotalCalls;
  final int previousPeriodTotalDurationSeconds;
  final double previousPeriodAvgDurationSeconds;

  /// Χωρίς φίλτρο ημερομηνιών («Όλες οι ημερομηνίες») — macro KPIs αντί σύγκρισης.
  final bool isAllDatesMode;

  /// Ημέρες με τουλάχιστον μία κλήση (μόνο σε [isAllDatesMode]).
  final int totalActiveDays;

  /// Διάμεσος χρόνος κλήσης σε δευτερόλεπτα (μόνο σε [isAllDatesMode]).
  final int medianDurationSeconds;

  /// Πρώτη / τελευταία ημερομηνία κλήσης στο φιλτραρισμένο σύνολο (μόνο σε [isAllDatesMode]).
  final DateTime? historyDateFrom;
  final DateTime? historyDateTo;

  /// Mini bar sparklines για KPI κάρτες (μόνο σε [isAllDatesMode]).
  final KpiAllDatesBarSparklines? allDatesBarSparklines;

  /// Τίτλος KPI «Συνολικές κλήσεις» όταν δεν υπάρχει φίλτρο ημερομηνιών.
  String? totalCallsKpiTitleAllDates({DateTime? now}) {
    if (!isAllDatesMode) return null;
    if (totalActiveDays <= 0 || historyDateFrom == null) {
      return 'Συνολικές κλήσεις · Όλες οι ημερομηνίες';
    }
    final today = DashboardFilterModel.dayOnly(now ?? DateTime.now());
    final fromStr = DashboardFilterModel.formatDisplayDate(historyDateFrom!);
    final endDay = historyDateTo != null
        ? DashboardFilterModel.dayOnly(historyDateTo!)
        : today;
    final toStr = endDay == today
        ? 'Σήμερα'
        : DashboardFilterModel.formatDisplayDate(endDay);
    return 'Συνολικές κλήσεις - $totalActiveDays ενεργές ημέρες (Από $fromStr έως $toStr)';
  }

  /// Μέσος αριθμός κλήσεων ανά ενεργή ημέρα.
  double? get avgCallsPerActiveDay {
    if (!isAllDatesMode || totalActiveDays <= 0) return null;
    return totalCalls / totalActiveDays;
  }

  /// Μέσος συνολικός χρόνος κλήσεων ανά ενεργή ημέρα (δευτερόλεπτα).
  double? get avgDurationSecondsPerActiveDay {
    if (!isAllDatesMode || totalActiveDays <= 0) return null;
    return totalDurationSeconds / totalActiveDays;
  }

  /// Τάση τελευταίων ημερών (σχετίζεται με το επιλεγμένο φίλτρο — για γράφημα «Περισσότερα»).
  final List<DailyTrendPoint> dailyTrend;

  /// Τελευταίες 7 ημερολογιακές ημέρες (σήμερα + 6 προηγούμενες) — για sparklines στις KPI κάρτες.
  final List<DailyTrendPoint> sparklineLast7Days;

  /// Κορυφαίοι καλούντες.
  final List<CallerStat> topCallers;

  /// Πιο χρονοβόρες κλήσεις.
  final List<LongestCallEntry> longestCalls;

  /// Συγκεντρωτικός χρόνος ανά καλούντα — η δεύτερη όψη της ίδιας κάρτας.
  final List<CallerTimeStat> callerTimeTotals;

  /// Κατανομή κλήσεων ανά ώρα (0-23).
  final List<HourlyBucket> hourlyDistribution;

  final List<DepartmentStat> byDepartment;
  final List<IssueStat> byIssue;
}
