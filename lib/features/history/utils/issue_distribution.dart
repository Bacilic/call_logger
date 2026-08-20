import '../models/dashboard_summary_model.dart';

/// Τι μετράει η «Κατανομή Βλαβών».
///
/// Οι δύο όψεις απαντούν σε διαφορετικό ερώτημα: το [count] δείχνει τι καλεί
/// συχνά, η [duration] τι τρώει χρόνο. Μια κατηγορία με λίγα αλλά χρονοβόρα
/// περιστατικά είναι αόρατη στην πρώτη και κυρίαρχη στη δεύτερη.
enum IssueDistributionMetric { count, duration }

/// Μία γραμμή της κατανομής, με τα δύο μεγέθη και τη θέση της στην κλίμακα.
class IssueDistributionRow {
  const IssueDistributionRow({
    required this.name,
    required this.count,
    required this.durationSeconds,
    required this.share,
    required this.barFraction,
  });

  final String name;
  final int count;
  final int durationSeconds;

  /// Μερίδιο επί του συνόλου **όλων** των κατηγοριών, 0..1 — αυτό γίνεται «67%».
  final double share;

  /// Μήκος μπάρας ως προς τη μεγαλύτερη γραμμή, 0..1. Ξεχωριστό από το
  /// [share], ώστε η πρώτη μπάρα να γεμίζει πάντα το διαθέσιμο πλάτος.
  final double barFraction;
}

/// Η κατανομή έτοιμη για εμφάνιση, ταξινομημένη κατά την επιλεγμένη όψη.
class IssueDistributionView {
  const IssueDistributionView({
    required this.rows,
    required this.totalCount,
    required this.totalDurationSeconds,
    required this.hiddenCount,
    required this.hiddenShare,
  });

  final List<IssueDistributionRow> rows;
  final int totalCount;
  final int totalDurationSeconds;

  /// Πόσες κατηγορίες δεν χώρεσαν στο όριο εμφάνισης.
  final int hiddenCount;

  /// Το συνολικό τους μερίδιο, ώστε η περικοπή να μη γίνεται σιωπηλά.
  final double hiddenShare;

  bool get isEmpty => rows.isEmpty;
}

/// Ταξινομεί τις κατηγορίες κατά την επιλεγμένη [metric] και υπολογίζει
/// μερίδια. Ό,τι δεν χωράει στο [limit] δεν εξαφανίζεται: επιστρέφεται ως
/// [IssueDistributionView.hiddenCount] για να το δείξει η διεπαφή.
IssueDistributionView buildIssueDistribution(
  List<IssueStat> issues,
  IssueDistributionMetric metric, {
  int limit = 6,
}) {
  var totalCount = 0;
  var totalDuration = 0;
  for (final issue in issues) {
    totalCount += issue.count;
    totalDuration += issue.sumDurationSeconds;
  }

  int valueOf(IssueStat issue) => switch (metric) {
    IssueDistributionMetric.count => issue.count,
    IssueDistributionMetric.duration => issue.sumDurationSeconds,
  };

  final total = switch (metric) {
    IssueDistributionMetric.count => totalCount,
    IssueDistributionMetric.duration => totalDuration,
  };

  final sorted = [...issues]..sort((a, b) => valueOf(b).compareTo(valueOf(a)));
  final visible = sorted.take(limit).toList();
  final maxValue = visible.isEmpty ? 0 : valueOf(visible.first);

  double shareOf(IssueStat issue) => total <= 0 ? 0 : valueOf(issue) / total;

  final rows = [
    for (final issue in visible)
      IssueDistributionRow(
        name: issue.name,
        count: issue.count,
        durationSeconds: issue.sumDurationSeconds,
        share: shareOf(issue),
        barFraction: maxValue <= 0 ? 0 : valueOf(issue) / maxValue,
      ),
  ];

  final hidden = sorted.skip(limit).toList();
  var hiddenShare = 0.0;
  for (final issue in hidden) {
    hiddenShare += shareOf(issue);
  }

  return IssueDistributionView(
    rows: rows,
    totalCount: totalCount,
    totalDurationSeconds: totalDuration,
    hiddenCount: hidden.length,
    hiddenShare: hiddenShare,
  );
}
