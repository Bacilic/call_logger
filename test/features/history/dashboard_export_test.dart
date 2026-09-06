// Η εξαγωγή των Στατιστικών λέει τα ίδια με την οθόνη, σε Excel και σε PDF.
//
// Το αρχείο ταξιδεύει μακριά από την οθόνη που το γέννησε: αν δεν κουβαλούσε τα
// φίλτρα της στιγμής, ο παραλήπτης θα έβλεπε έναν αριθμό κλήσεων χωρίς τρόπο να
// μάθει από ποιες. Και οι δύο μορφές χτίζονται από την ίδια δομή, ώστε να μην
// μπορούν να αποκλίνουν.
//
//   flutter test test/features/history/dashboard_export_test.dart

import 'dart:io';

import 'package:call_logger/features/history/models/dashboard_filter_model.dart';
import 'package:call_logger/features/history/models/dashboard_summary_model.dart';
import 'package:call_logger/features/history/services/dashboard_excel_export.dart';
import 'package:call_logger/features/history/services/dashboard_export_document.dart';
import 'package:call_logger/features/history/services/dashboard_pdf_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

DashboardSummaryModel buildSummary() {
  return DashboardSummaryModel(
    totalCalls: 228,
    totalDurationSeconds: 80340,
    avgDurationSeconds: 352,
    previousPeriodTotalCalls: 110,
    previousPeriodTotalDurationSeconds: 53820,
    previousPeriodAvgDurationSeconds: 489,
    totalActiveDays: 21,
    medianDurationSeconds: 240,
    dailyTrend: [
      DailyTrendPoint(
        date: DateTime(2026, 9, 4),
        callCount: 12,
        totalDurationSeconds: 3600,
      ),
      DailyTrendPoint(
        date: DateTime(2026, 9, 5),
        callCount: 9,
        totalDurationSeconds: 2400,
      ),
    ],
    sparklineLast7Days: const [],
    topCallers: const [
      CallerStat(name: 'Αφροδίτη Καρρά', count: 8),
      CallerStat(name: 'Γεωργία Τσίλη', count: 8),
    ],
    longestCalls: const [
      LongestCallEntry(
        callerName: 'Μιχάλης Σαββανός',
        department: 'Διευθυντής Διοικητικού',
        durationSeconds: 3221,
      ),
    ],
    hourlyDistribution: const [
      HourlyBucket(hour: 9, callCount: 30),
      HourlyBucket(hour: 10, callCount: 41),
    ],
    byDepartment: const [
      DepartmentStat(
        name: 'Γραμματεία ΤΕΠ',
        count: 25,
        sumDurationSeconds: 7200,
      ),
    ],
    byIssue: const [
      IssueStat(name: 'Medico', count: 53, sumDurationSeconds: 12420),
    ],
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('el');
  });

  final now = DateTime(2026, 9, 5, 14, 30);

  group('Τι περιέχει η εξαγωγή', () {
    test('τα ενεργά φίλτρα γράφονται μέσα στο αρχείο', () {
      final document = buildDashboardExportDocument(
        data: buildSummary(),
        filter: DashboardFilterModel(
          dateFrom: DateTime(2026, 8, 7),
          dateTo: DateTime(2026, 9, 5),
          department: 'Γραμματεία ΤΕΠ',
          category: 'Medico',
        ),
        now: now,
      );
      expect(
        document.activeFilterLabels,
        containsAll(<String>['Τμήμα: Γραμματεία ΤΕΠ', 'Κατηγορία: Medico']),
        reason:
            'Χωρίς τα φίλτρα, το αρχείο δείχνει 228 κλήσεις και δεν λέει 228 '
            'από ποιες.',
      );
    });

    test('χωρίς φίλτρα το αρχείο το δηλώνει, δεν σωπαίνει', () {
      final document = buildDashboardExportDocument(
        data: buildSummary(),
        filter: const DashboardFilterModel(),
        now: now,
      );
      expect(document.activeFilterLabels, ['Χωρίς φίλτρα — όλες οι κλήσεις']);
    });

    test('κάθε κάρτα της οθόνης έχει τον πίνακά της', () {
      final document = buildDashboardExportDocument(
        data: buildSummary(),
        filter: const DashboardFilterModel(),
        now: now,
      );
      expect(document.tables.map((t) => t.title).toList(), [
        'Σύνοψη',
        'Κορυφαίοι καλούντες',
        'Πιο χρονοβόρες κλήσεις',
        'Ανά τμήμα',
        'Ανά κατηγορία',
        'Ανά ώρα',
        'Ανά ημέρα',
      ]);
    });

    test('οι διάρκειες γράφονται όπως στην οθόνη, όχι σε δευτερόλεπτα', () {
      final document = buildDashboardExportDocument(
        data: buildSummary(),
        filter: const DashboardFilterModel(),
        now: now,
      );
      final summary = document.tables.first;
      final totalDurationRow = summary.rows.firstWhere(
        (row) => row.first == 'Συνολική διάρκεια',
      );
      expect(
        totalDurationRow.last,
        isNot(contains('80340')),
        reason:
            'Ο παραλήπτης του αρχείου διαβάζει ώρες και λεπτά, όπως και στην '
            'οθόνη — όχι ακατέργαστα δευτερόλεπτα.',
      );
    });

    test('χωρίς φίλτρο ημερομηνιών δεν υπάρχει σύγκριση περιόδου', () {
      final document = buildDashboardExportDocument(
        data: DashboardSummaryModel(
          totalCalls: 228,
          totalDurationSeconds: 80340,
          avgDurationSeconds: 352,
          previousPeriodTotalCalls: 0,
          previousPeriodTotalDurationSeconds: 0,
          previousPeriodAvgDurationSeconds: 0,
          isAllDatesMode: true,
          dailyTrend: const [],
          sparklineLast7Days: const [],
          topCallers: const [],
          longestCalls: const [],
          hourlyDistribution: const [],
          byDepartment: const [],
          byIssue: const [],
        ),
        filter: const DashboardFilterModel(),
        now: now,
      );
      final summaryLabels = document.tables.first.rows
          .map((row) => row.first)
          .toList();
      expect(
        summaryLabels,
        isNot(contains('Κλήσεις προηγούμενης περιόδου')),
        reason:
            'Χωρίς επιλεγμένο διάστημα δεν υπάρχει «προηγούμενη» περίοδος — '
            'ένα μηδενικό εκεί θα διαβαζόταν ως πτώση 100%.',
      );
    });
  });

  group('Το αρχείο Excel', () {
    test('παράγεται και δεν είναι άδειο', () {
      final document = buildDashboardExportDocument(
        data: buildSummary(),
        filter: const DashboardFilterModel(category: 'Medico'),
        now: now,
      );
      final bytes = buildDashboardExcel(document);
      expect(bytes.length, greaterThan(1000));
      // Κάθε .xlsx είναι αρχείο ZIP: τα δύο πρώτα byte το λένε.
      expect(bytes.sublist(0, 2), [0x50, 0x4B]);
    });

    test('τα ονόματα φύλλων χωρούν στο όριο του Excel', () {
      final name = sanitizeExcelSheetName(
        'Ένας πάρα πολύ μακρύς τίτλος ενότητας που δεν χωρά',
      );
      expect(name.length, lessThanOrEqualTo(31));
    });

    test('τα σημεία που απαγορεύει το Excel φεύγουν από το όνομα', () {
      expect(sanitizeExcelSheetName('Ανά ώρα / ημέρα'), isNot(contains('/')));
      expect(sanitizeExcelSheetName('Σύνοψη [2026]'), isNot(contains('[')));
    });
  });

  group('Το αρχείο PDF', () {
    test(
      'πίνακας μεγαλύτερος από μία σελίδα μοιράζεται σε σελίδες',
      () async {
        // Ο κατάλογος έχει δεκάδες τμήματα· με πραγματικά δεδομένα ο πίνακας
        // «Ανά τμήμα» ξεπερνά τη μία σελίδα. Όσο ο πίνακας ζούσε μέσα σε
        // στήλη, το έγγραφο δεν μπορούσε να τον τοποθετήσει και γεννούσε κενές
        // σελίδες μέχρι να σκάσει — η εξαγωγή αποτύγχανε ολόκληρη.
        final document = DashboardExportDocument(
          title: 'Στατιστικά Κλήσεων',
          rangeLabel: 'Όλες οι ημερομηνίες',
          generatedAtLabel: '05/09/2026 14:30',
          activeFilterLabels: const ['Χωρίς φίλτρα — όλες οι κλήσεις'],
          tables: [
            DashboardExportTable(
              title: 'Ανά τμήμα',
              columns: const ['Τμήμα', 'Κλήσεις', 'Συνολική διάρκεια'],
              rows: [
                for (var i = 1; i <= 200; i++)
                  ['Τμήμα $i', '$i', '$i ω:00λ'],
              ],
            ),
          ],
        );
        final font = await File('assets/fonts/Inter-Regular.ttf').readAsBytes();
        final bytes = await buildDashboardPdf(document, fontData: font);
        expect(bytes.length, greaterThan(1000));
      },
    );

    test('παράγεται με ελληνικά και δεν είναι άδειο', () async {
      final document = buildDashboardExportDocument(
        data: buildSummary(),
        filter: const DashboardFilterModel(category: 'Medico'),
        now: now,
      );
      final font = await File('assets/fonts/Inter-Regular.ttf').readAsBytes();
      final bytes = await buildDashboardPdf(document, fontData: font);
      expect(bytes.length, greaterThan(1000));
      // Κάθε PDF ξεκινά με «%PDF».
      expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    });
  });
}
