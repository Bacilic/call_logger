/// Ποια φίλτρα των Στατιστικών ισχύουν αυτή τη στιγμή, και πώς λέγονται.
///
/// Ζει χωριστά από την οθόνη γιατί απαντά σε ερώτημα δεδομένων, όχι εμφάνισης:
/// «τι περιορίζει αυτή τη στιγμή τους αριθμούς που βλέπω;». Η οθόνη απλώς
/// ζωγραφίζει τη λίστα — και επειδή η λίστα παράγεται από το ίδιο το φίλτρο,
/// ένα φίλτρο που προστίθεται αργότερα δεν μπορεί να μείνει αόρατο.
library;

import 'dashboard_filter_model.dart';

/// Το είδος ενός ενεργού φίλτρου — χρησιμεύει και ως εντολή καθαρισμού του.
enum DashboardFilterKind {
  dateRange,
  keyword,
  department,
  userName,
  equipmentCode,
  category,
}

/// Ένα ενεργό φίλτρο: τι είναι και πώς διαβάζεται.
class DashboardActiveFilter {
  const DashboardActiveFilter({required this.kind, required this.label});

  final DashboardFilterKind kind;

  /// Το κείμενο της μάρκας, π.χ. «Τμήμα: Γραμματεία ΤΕΠ».
  final String label;

  @override
  bool operator ==(Object other) =>
      other is DashboardActiveFilter &&
      other.kind == kind &&
      other.label == label;

  @override
  int get hashCode => Object.hash(kind, label);

  @override
  String toString() => 'DashboardActiveFilter($kind, $label)';
}

/// Τα ενεργά φίλτρα του [filter], με τη σειρά που τα διαβάζει ο χρήστης.
///
/// Το εύρος ημερομηνιών μπαίνει **μόνο όταν περιορίζει**: το «Όλα» δεν είναι
/// φίλτρο, είναι η απουσία του, και μια μάρκα που δεν αφαιρείται θα ήταν
/// θόρυβος. Η [now] περνά ως όρισμα ώστε η ετικέτα «Σήμερα» να ελέγχεται χωρίς
/// δεύτερο ρολόι.
List<DashboardActiveFilter> describeActiveDashboardFilters(
  DashboardFilterModel filter, {
  DateTime? now,
}) {
  final active = <DashboardActiveFilter>[];

  if (filter.dateFrom != null || filter.dateTo != null) {
    active.add(
      DashboardActiveFilter(
        kind: DashboardFilterKind.dateRange,
        label: filter.kpiTotalCallsRangeTitle(now: now),
      ),
    );
  }

  final keyword = filter.keyword.trim();
  if (keyword.isNotEmpty) {
    active.add(
      DashboardActiveFilter(
        kind: DashboardFilterKind.keyword,
        label: 'Αναζήτηση: $keyword',
      ),
    );
  }

  final department = filter.department?.trim();
  if (department != null && department.isNotEmpty) {
    active.add(
      DashboardActiveFilter(
        kind: DashboardFilterKind.department,
        label: 'Τμήμα: $department',
      ),
    );
  }

  final userName = filter.userName?.trim();
  if (userName != null && userName.isNotEmpty) {
    active.add(
      DashboardActiveFilter(
        kind: DashboardFilterKind.userName,
        label: 'Υπάλληλος: $userName',
      ),
    );
  }

  final equipmentCode = filter.equipmentCode?.trim();
  if (equipmentCode != null && equipmentCode.isNotEmpty) {
    active.add(
      DashboardActiveFilter(
        kind: DashboardFilterKind.equipmentCode,
        label: 'Εξοπλισμός: $equipmentCode',
      ),
    );
  }

  final category = filter.category?.trim();
  if (category != null && category.isNotEmpty) {
    active.add(
      DashboardActiveFilter(
        kind: DashboardFilterKind.category,
        label: 'Κατηγορία: $category',
      ),
    );
  }

  return active;
}
