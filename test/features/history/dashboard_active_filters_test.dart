// Τα ενεργά φίλτρα των Στατιστικών φαίνονται και αφαιρούνται ένα-ένα.
//
// Το ζητούμενο ήταν να μη χρειάζεται ο χρήστης να ανοίξει τίποτα για να μάθει
// τι περιορίζει τους αριθμούς που κοιτάζει. Η λίστα παράγεται από το ίδιο το
// φίλτρο, ώστε ένα φίλτρο που προστίθεται αργότερα να μη μείνει αόρατο.
//
//   flutter test test/features/history/dashboard_active_filters_test.dart

import 'package:call_logger/features/history/models/dashboard_active_filter.dart';
import 'package:call_logger/features/history/models/dashboard_filter_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 5);

  List<DashboardFilterKind> kindsOf(DashboardFilterModel filter) =>
      describeActiveDashboardFilters(
        filter,
        now: now,
      ).map((entry) => entry.kind).toList();

  String labelOf(DashboardFilterModel filter, DashboardFilterKind kind) =>
      describeActiveDashboardFilters(
        filter,
        now: now,
      ).firstWhere((entry) => entry.kind == kind).label;

  group('Ποια φίλτρα δηλώνονται ως ενεργά', () {
    test('χωρίς κανένα φίλτρο δεν υπάρχει τίποτα να δείξει', () {
      expect(describeActiveDashboardFilters(
        const DashboardFilterModel(),
        now: now,
      ), isEmpty);
    });

    test(
      'το «Όλα» στις ημερομηνίες δεν είναι φίλτρο — είναι η απουσία του',
      () {
        expect(
          kindsOf(const DashboardFilterModel(department: 'Αιματολογικό')),
          [DashboardFilterKind.department],
          reason:
              'Μια μάρκα ημερομηνίας που δεν περιορίζει τίποτα θα ήταν θόρυβος '
              'και δεν θα είχε νόημα να αφαιρεθεί.',
        );
      },
    );

    test('κάθε φίλτρο που ισχύει αποκτά τη δική του μάρκα', () {
      final filter = DashboardFilterModel(
        keyword: 'Ψαρρά',
        dateFrom: DateTime(2026, 8, 7),
        dateTo: DateTime(2026, 9, 5),
        department: 'Γραμματεία ΤΕΠ',
        userName: 'Αφροδίτη Καρρά',
        equipmentCode: '5010',
        category: 'Medico',
      );
      expect(kindsOf(filter), [
        DashboardFilterKind.dateRange,
        DashboardFilterKind.keyword,
        DashboardFilterKind.department,
        DashboardFilterKind.userName,
        DashboardFilterKind.equipmentCode,
        DashboardFilterKind.category,
      ]);
    });

    test('η μάρκα λέει τι είναι το φίλτρο, όχι μόνο την τιμή του', () {
      final filter = const DashboardFilterModel(
        department: 'Γραμματεία ΤΕΠ',
        category: 'Medico',
      );
      expect(
        labelOf(filter, DashboardFilterKind.department),
        'Τμήμα: Γραμματεία ΤΕΠ',
      );
      expect(
        labelOf(filter, DashboardFilterKind.category),
        'Κατηγορία: Medico',
      );
    });

    test('τα κενά διαστήματα δεν μετρούν ως φίλτρο', () {
      expect(
        kindsOf(
          const DashboardFilterModel(
            keyword: '   ',
            department: '  ',
            userName: '',
            category: '   ',
          ),
        ),
        isEmpty,
        reason:
            'Ένα πεδίο με κενά μοιάζει γεμάτο στον κώδικα αλλά δεν περιορίζει '
            'καμία κλήση — μια μάρκα γι\' αυτό θα ήταν ψέμα.',
      );
    });
  });

  group('Το φίλτρο κατηγορίας μέσα στο μοντέλο', () {
    test('η αντιγραφή κρατά την κατηγορία', () {
      const filter = DashboardFilterModel(category: 'Medico');
      expect(filter.copyWith(department: 'ΤΕΠ').category, 'Medico');
    });

    test('ο ρητός καθαρισμός τη σβήνει', () {
      const filter = DashboardFilterModel(category: 'Medico');
      expect(filter.copyWith(clearCategory: true).category, isNull);
    });
  });

  group('Το κείμενο σύγκρισης των καρτών', () {
    test('μονοήμερο διάστημα λέει «χθες»', () {
      final filter = DashboardFilterModel(
        dateFrom: DateTime(2026, 9, 5),
        dateTo: DateTime(2026, 9, 5),
      );
      expect(filter.kpiComparisonRangeShortHint(), 'χθες');
    });

    test('τριακονθήμερο λέει το μήκος του, όχι δύο ημερομηνίες', () {
      final filter = DashboardFilterModel(
        dateFrom: DateTime(2026, 8, 7),
        dateTo: DateTime(2026, 9, 5),
      );
      expect(
        filter.kpiComparisonRangeShortHint(),
        'προηγ. 30 ημέρες',
        reason:
            'Με τις ημερομηνίες γραμμένες ολόκληρες ο υπότιτλος κοβόταν πριν '
            'προλάβει να πει τον αριθμό σύγκρισης.',
      );
    });

    test('εβδομάδα λέγεται εβδομάδα', () {
      final filter = DashboardFilterModel(
        dateFrom: DateTime(2026, 8, 30),
        dateTo: DateTime(2026, 9, 5),
      );
      expect(filter.kpiComparisonRangeShortHint(), 'προηγ. εβδομάδα');
    });
  });
}
