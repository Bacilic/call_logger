import '../models/dashboard_summary_model.dart';

/// Τι μετράει η «Κατανομή ανά κατηγορία».
///
/// Οι δύο όψεις απαντούν σε διαφορετικό ερώτημα: το [count] δείχνει τι καλεί
/// συχνά, η [duration] τι τρώει χρόνο. Μια κατηγορία με λίγα αλλά χρονοβόρα
/// περιστατικά είναι αόρατη στην πρώτη και κυρίαρχη στη δεύτερη.
enum CategoryDistributionMetric { count, duration }

/// Μία γραμμή της κατανομής, με τα δύο μεγέθη και τη θέση της στην κλίμακα.
class CategoryDistributionRow {
  const CategoryDistributionRow({
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
class CategoryDistributionView {
  const CategoryDistributionView({
    required this.rows,
    required this.totalCount,
    required this.totalDurationSeconds,
    required this.hiddenCount,
    required this.hiddenShare,
  });

  final List<CategoryDistributionRow> rows;
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
/// [CategoryDistributionView.hiddenCount] για να το δείξει η διεπαφή.
CategoryDistributionView buildCategoryDistribution(
  List<CategoryStat> categories,
  CategoryDistributionMetric metric, {
  int limit = 6,
}) {
  var totalCount = 0;
  var totalDuration = 0;
  for (final category in categories) {
    totalCount += category.count;
    totalDuration += category.sumDurationSeconds;
  }

  int valueOf(CategoryStat category) => switch (metric) {
    CategoryDistributionMetric.count => category.count,
    CategoryDistributionMetric.duration => category.sumDurationSeconds,
  };

  final total = switch (metric) {
    CategoryDistributionMetric.count => totalCount,
    CategoryDistributionMetric.duration => totalDuration,
  };

  final sorted = [...categories]
    ..sort((a, b) => valueOf(b).compareTo(valueOf(a)));
  final visible = sorted.take(limit).toList();
  final maxValue = visible.isEmpty ? 0 : valueOf(visible.first);

  double shareOf(CategoryStat category) =>
      total <= 0 ? 0 : valueOf(category) / total;

  final rows = [
    for (final category in visible)
      CategoryDistributionRow(
        name: category.name,
        count: category.count,
        durationSeconds: category.sumDurationSeconds,
        share: shareOf(category),
        barFraction: maxValue <= 0 ? 0 : valueOf(category) / maxValue,
      ),
  ];

  final hidden = sorted.skip(limit).toList();
  var hiddenShare = 0.0;
  for (final category in hidden) {
    hiddenShare += shareOf(category);
  }

  return CategoryDistributionView(
    rows: rows,
    totalCount: totalCount,
    totalDurationSeconds: totalDuration,
    hiddenCount: hidden.length,
    hiddenShare: hiddenShare,
  );
}
