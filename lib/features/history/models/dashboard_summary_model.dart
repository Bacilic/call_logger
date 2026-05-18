import 'dashboard_filter_model.dart';

/// Ετικέτα για κενή/NULL περιγραφή βλάβης (`issue`) — συμφωνεί με το SQL του dashboard.
const String kDashboardNoIssueLabel =
    '\u03a7\u03c9\u03c1\u03af\u03c2 \u03c0\u03b5\u03c1\u03b9\u03b3\u03c1\u03b1\u03c6\u03ae';

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

/// Στατιστικά ανά περιγραφή βλάβης (`calls.issue`).
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
  final List<double> callsByMonth;

  /// Συνολική διάρκεια ανά ημέρα εβδομάδας (Δευ–Παρ, 5 ράβδοι).
  final List<double> durationByWeekdayMonToFri;

  /// 3 μεγαλύτερες + 3 μικρότερες διάρκειες κλήσεων (6 ράβδοι).
  final List<double> durationExtremesSix;

  /// Κλήσεις τμημάτων θέσεων 2–6 (το #1 είναι η κύρια τιμή KPI).
  final List<double> departmentCountsRank2To6;

  /// Κλήσεις καλούντων θέσεων 2–6.
  final List<double> callerCountsRank2To6;

  /// Κλήσεις βλαβών θέσεων 2–6.
  final List<double> issueCountsRank2To6;
}

/// Συμπλήρωση λίστας τιμών σε σταθερό μήκος (μηδενικά στο τέλος).
List<double> padBarSparklineValues(List<double> values, int length) {
  if (length <= 0) return List<double>.from(values);
  if (values.length >= length) {
    return values.sublist(0, length);
  }
  return [...values, ...List<double>.filled(length - values.length, 0)];
}

/// Απόσπαση count θέσεων 2..(1+take) από ταξινομημένη λίστα στατιστικών.
List<double> runnerUpCountsFromStats(List<int> counts, int take) {
  return padBarSparklineValues(
    counts.skip(1).take(take).map((c) => c.toDouble()).toList(),
    take,
  );
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

  /// Κατανομή κλήσεων ανά ώρα (0-23).
  final List<HourlyBucket> hourlyDistribution;

  final List<DepartmentStat> byDepartment;
  final List<IssueStat> byIssue;
}
