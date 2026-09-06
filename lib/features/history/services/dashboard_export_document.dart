/// Τι περιέχει μια εξαγωγή των Στατιστικών Κλήσεων — ανεξάρτητα από τη μορφή.
///
/// **Το Excel και το PDF χτίζονται από αυτή τη μία δομή.** Αν καθένα ρωτούσε
/// μόνο του τη σύνοψη, τα δύο αρχεία θα άρχιζαν να λένε διαφορετικά πράγματα
/// για τις ίδιες κλήσεις — και η απόκλιση θα φαινόταν μόνο όταν κάποιος τα
/// άνοιγε δίπλα-δίπλα.
///
/// Όλες οι τιμές είναι **έτοιμο κείμενο**: η μορφοποίηση των διαρκειών και των
/// ποσοστών γίνεται μία φορά εδώ, με τους ίδιους κανόνες που βλέπει ο χρήστης
/// στην οθόνη.
library;

import 'package:intl/intl.dart';

import '../models/dashboard_active_filter.dart';
import '../models/dashboard_filter_model.dart';
import '../models/dashboard_summary_model.dart';
import '../screens/dashboard_kpi_cards.dart';

/// Ένας πίνακας της εξαγωγής — γίνεται φύλλο στο Excel και ενότητα στο PDF.
class DashboardExportTable {
  const DashboardExportTable({
    required this.title,
    required this.columns,
    required this.rows,
  });

  /// Τίτλος ενότητας· γίνεται και όνομα φύλλου στο Excel.
  final String title;

  final List<String> columns;
  final List<List<String>> rows;

  bool get isEmpty => rows.isEmpty;
}

/// Ολόκληρη η εξαγωγή: τι δείχνει, με ποια φίλτρα, και πότε φτιάχτηκε.
class DashboardExportDocument {
  const DashboardExportDocument({
    required this.title,
    required this.rangeLabel,
    required this.generatedAtLabel,
    required this.activeFilterLabels,
    required this.tables,
  });

  final String title;

  /// Το διάστημα που καλύπτει η εξαγωγή, με λόγια.
  final String rangeLabel;

  final String generatedAtLabel;

  /// Τα φίλτρα που ίσχυαν τη στιγμή της εξαγωγής.
  ///
  /// Γράφονται μέσα στο αρχείο επειδή ένα αρχείο ταξιδεύει: χωρίς αυτά, ο
  /// παραλήπτης βλέπει 228 κλήσεις και δεν έχει τρόπο να μάθει 228 από ποιες.
  final List<String> activeFilterLabels;

  final List<DashboardExportTable> tables;
}

/// Προτεινόμενο όνομα αρχείου, χωρίς επέκταση.
///
/// Κρατά την ημερομηνία ώστε δύο εξαγωγές της ίδιας οθόνης να μη σκεπάζουν η
/// μία την άλλη κατά λάθος.
String dashboardExportFileBaseName({DateTime? now}) {
  final stamp = DateFormat('yyyy-MM-dd_HH-mm').format(now ?? DateTime.now());
  return 'Στατιστικά Κλήσεων $stamp';
}

/// Συνθέτει την εξαγωγή από ό,τι δείχνει αυτή τη στιγμή η οθόνη.
DashboardExportDocument buildDashboardExportDocument({
  required DashboardSummaryModel data,
  required DashboardFilterModel filter,
  DateTime? now,
}) {
  final moment = now ?? DateTime.now();
  final activeFilters = describeActiveDashboardFilters(filter, now: moment);

  return DashboardExportDocument(
    title: 'Στατιστικά Κλήσεων',
    rangeLabel:
        data.totalCallsKpiTitleAllDates(now: moment) ??
        filter.kpiTotalCallsRangeTitle(now: moment),
    generatedAtLabel: DateFormat('dd/MM/yyyy HH:mm').format(moment),
    activeFilterLabels: activeFilters.isEmpty
        ? const ['Χωρίς φίλτρα — όλες οι κλήσεις']
        : [for (final entry in activeFilters) entry.label],
    tables: [
      _summaryTable(data),
      _topCallersTable(data),
      _longestCallsTable(data),
      _byDepartmentTable(data),
      _byCategoryTable(data),
      _hourlyTable(data),
      _trendTable(data),
    ],
  );
}

DashboardExportTable _summaryTable(DashboardSummaryModel data) {
  final rows = <List<String>>[
    ['Συνολικές κλήσεις', '${data.totalCalls}'],
    [
      'Συνολική διάρκεια',
      formatDashboardAggregateDuration(data.totalDurationSeconds),
    ],
    [
      'Μέσος όρος ανά κλήση',
      formatDashboardCallDuration(data.avgDurationSeconds),
    ],
    [
      'Διάμεσος χρόνος ανά κλήση',
      formatDashboardCallDuration(data.medianDurationSeconds),
    ],
    ['Ημέρες με κλήσεις', '${data.totalActiveDays}'],
  ];

  // Η σύγκριση με την προηγούμενη περίοδο έχει νόημα μόνο όταν υπάρχει
  // περίοδος — χωρίς φίλτρο ημερομηνιών δεν υπάρχει «προηγούμενη».
  if (!data.isAllDatesMode) {
    rows.addAll([
      [
        'Κλήσεις προηγούμενης περιόδου',
        '${data.previousPeriodTotalCalls}',
      ],
      [
        'Μεταβολή κλήσεων',
        formatDashboardDeltaPercent(
          data.totalCalls,
          data.previousPeriodTotalCalls,
        ),
      ],
      [
        'Διάρκεια προηγούμενης περιόδου',
        formatDashboardAggregateDuration(
          data.previousPeriodTotalDurationSeconds,
        ),
      ],
      [
        'Μεταβολή διάρκειας',
        formatDashboardDeltaPercent(
          data.totalDurationSeconds,
          data.previousPeriodTotalDurationSeconds,
        ),
      ],
    ]);
  }

  return DashboardExportTable(
    title: 'Σύνοψη',
    columns: const ['Μέγεθος', 'Τιμή'],
    rows: rows,
  );
}

DashboardExportTable _topCallersTable(DashboardSummaryModel data) {
  return DashboardExportTable(
    title: 'Κορυφαίοι καλούντες',
    columns: const ['#', 'Καλών', 'Κλήσεις'],
    rows: [
      for (final (index, caller) in data.topCallers.indexed)
        ['${index + 1}', caller.name, '${caller.count}'],
    ],
  );
}

DashboardExportTable _longestCallsTable(DashboardSummaryModel data) {
  return DashboardExportTable(
    title: 'Πιο χρονοβόρες κλήσεις',
    columns: const ['#', 'Καλών', 'Τμήμα', 'Διάρκεια'],
    rows: [
      for (final (index, call) in data.longestCalls.indexed)
        [
          '${index + 1}',
          call.callerName,
          call.department,
          formatDashboardCallDuration(call.durationSeconds),
        ],
    ],
  );
}

DashboardExportTable _byDepartmentTable(DashboardSummaryModel data) {
  return DashboardExportTable(
    title: 'Ανά τμήμα',
    columns: const ['Τμήμα', 'Κλήσεις', 'Συνολική διάρκεια'],
    rows: [
      for (final entry in data.byDepartment)
        [
          entry.name,
          '${entry.count}',
          formatDashboardAggregateDuration(entry.sumDurationSeconds),
        ],
    ],
  );
}

DashboardExportTable _byCategoryTable(DashboardSummaryModel data) {
  return DashboardExportTable(
    title: 'Ανά κατηγορία',
    columns: const ['Κατηγορία', 'Κλήσεις', 'Συνολική διάρκεια'],
    rows: [
      for (final entry in data.byIssue)
        [
          entry.name,
          '${entry.count}',
          formatDashboardAggregateDuration(entry.sumDurationSeconds),
        ],
    ],
  );
}

DashboardExportTable _hourlyTable(DashboardSummaryModel data) {
  return DashboardExportTable(
    title: 'Ανά ώρα',
    columns: const ['Ώρα', 'Κλήσεις'],
    rows: [
      for (final bucket in data.hourlyDistribution)
        ['${bucket.hour.toString().padLeft(2, '0')}:00', '${bucket.callCount}'],
    ],
  );
}

DashboardExportTable _trendTable(DashboardSummaryModel data) {
  return DashboardExportTable(
    title: 'Ανά ημέρα',
    columns: const ['Ημερομηνία', 'Κλήσεις', 'Συνολική διάρκεια'],
    rows: [
      for (final day in data.dailyTrend)
        [
          DateFormat('dd/MM/yyyy').format(day.date),
          '${day.callCount}',
          formatDashboardAggregateDuration(day.totalDurationSeconds),
        ],
    ],
  );
}
