/// Ετικέτα για κενή/NULL περιγραφή βλάβης (`issue`) — συμφωνεί με το SQL του dashboard.
const String kDashboardNoIssueLabel =
    '\u03a7\u03c9\u03c1\u03af\u03c2 \u03c0\u03b5\u03c1\u03b9\u03b3\u03c1\u03b1\u03c6\u03ae';

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

/// Αποτέλεσμα ερωτημάτων dashboard (KPIs + ομαδοποιήσεις).
class DashboardSummaryModel {
  const DashboardSummaryModel({
    required this.totalCalls,
    required this.totalDurationSeconds,
    required this.avgDurationSeconds,
    required this.previousPeriodTotalCalls,
    required this.previousPeriodTotalDurationSeconds,
    required this.previousPeriodAvgDurationSeconds,
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
