import 'dashboard_filter_model.dart';

/// Ποιες κλήσεις δείχνει η Αναφορά Lansweeper.
///
/// Ως τώρα η αναφορά δανειζόταν σιωπηλά τα φίλτρα του Πίνακα Ελέγχου, οπότε δεν
/// μπορούσε να ανοίξει από πουθενά αλλού χωρίς να κουβαλήσει άσχετο διάστημα.
enum LansweeperReportRange {
  /// Η καθημερινή δουλειά: οι κλήσεις της ημέρας, μετά τις 13:00.
  today,

  yesterday,

  /// Οι τελευταίες επτά ημέρες, με σημερινή συμπεριλαμβανόμενη.
  last7Days,

  /// Χωρίς όριο ημερομηνίας — για όσες δεν έχουν περάσει ποτέ στο Lansweeper.
  allUnregistered,

  /// Ό,τι δείχνει εκείνη τη στιγμή ο Πίνακας Ελέγχου (ημερομηνίες, τμήμα,
  /// υπάλληλος, εξοπλισμός) — η είσοδος από την κάρτα των Στατιστικών.
  dashboardFilters,
}

/// Το πλαίσιο της αναφοράς: ένα προκαθορισμένο διάστημα ή τα φίλτρα του
/// Πίνακα Ελέγχου.
class LansweeperReportScope {
  const LansweeperReportScope.range(this.range) : dashboardFilter = null;

  const LansweeperReportScope.dashboard(DashboardFilterModel filter)
    : range = LansweeperReportRange.dashboardFilters,
      dashboardFilter = filter;

  final LansweeperReportRange range;

  /// Συμπληρωμένο μόνο για το [LansweeperReportRange.dashboardFilters].
  final DashboardFilterModel? dashboardFilter;

  static const today = LansweeperReportScope.range(LansweeperReportRange.today);

  /// Το φίλτρο δεδομένων που προκύπτει, με σημείο αναφοράς την [now].
  ///
  /// Η ημέρα αναφοράς περνά ως όρισμα ώστε η αντιστοίχιση να ελέγχεται χωρίς
  /// δεύτερο ρολόι: «σήμερα» σημαίνει διαφορετική ημερομηνία κάθε μέρα, αλλά ο
  /// κανόνας παραμένει ο ίδιος.
  DashboardFilterModel resolveFilter(DateTime now) {
    final today = DashboardFilterModel.dayOnly(now);
    switch (range) {
      case LansweeperReportRange.today:
        return DashboardFilterModel(dateFrom: today, dateTo: today);
      case LansweeperReportRange.yesterday:
        final yesterday = today.subtract(const Duration(days: 1));
        return DashboardFilterModel(dateFrom: yesterday, dateTo: yesterday);
      case LansweeperReportRange.last7Days:
        return DashboardFilterModel(
          dateFrom: today.subtract(const Duration(days: 6)),
          dateTo: today,
        );
      case LansweeperReportRange.allUnregistered:
        return const DashboardFilterModel();
      case LansweeperReportRange.dashboardFilters:
        return dashboardFilter ?? const DashboardFilterModel();
    }
  }

  /// Ετικέτα του πλαισίου για τον τίτλο του διαλόγου.
  ///
  /// Για τα φίλτρα του Πίνακα Ελέγχου επιστρέφει `null`: εκεί τον τίτλο τον
  /// συνθέτει το ίδιο το φίλτρο, που ξέρει και τις ημερομηνίες των δεδομένων.
  String? get label => switch (range) {
    LansweeperReportRange.today => 'Σήμερα',
    LansweeperReportRange.yesterday => 'Χθες',
    LansweeperReportRange.last7Days => '7 ημέρες',
    LansweeperReportRange.allUnregistered => 'Όλες οι ακαταχώρητες',
    LansweeperReportRange.dashboardFilters => null,
  };
}
