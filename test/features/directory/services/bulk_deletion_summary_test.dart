// Κοινή σύνοψη μαζικής διαγραφής — μία μορφή για τμήματα, υπαλλήλους,
// εξοπλισμό.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/services/bulk_deletion_summary_test.dart

import 'package:call_logger/features/directory/services/bulk_deletion_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ετικέτα σκέλους', () {
    test('ενικός και πληθυντικός', () {
      expect(
        const SummaryCount(1, 'υπάλληλος', 'υπάλληλοι').label,
        '1 υπάλληλος',
      );
      expect(
        const SummaryCount(4, 'υπάλληλος', 'υπάλληλοι').label,
        '4 υπάλληλοι',
      );
    });

    test('μηδέν παίρνει πληθυντικό — αλλά συνήθως παραλείπεται', () {
      expect(const SummaryCount(0, 'τηλέφωνο', 'τηλέφωνα').label, '0 τηλέφωνα');
    });
  });

  group('Κύρια γραμμή', () {
    test('αντικείμενο και λεπτομέρειες με μεσαία τελεία', () {
      final line = buildBulkDeletionHeadline(
        subject: const SummaryCount(3, 'τμήμα', 'τμήματα'),
        details: const [
          SummaryCount(12, 'υπάλληλος', 'υπάλληλοι'),
          SummaryCount(2, 'κοινόχρηστο τηλέφωνο', 'κοινόχρηστα τηλέφωνα'),
        ],
      );

      expect(line, '3 τμήματα · 12 υπάλληλοι · 2 κοινόχρηστα τηλέφωνα');
    });

    test('τα μηδενικά σκέλη παραλείπονται', () {
      final line = buildBulkDeletionHeadline(
        subject: const SummaryCount(3, 'τμήμα', 'τμήματα'),
        details: const [
          SummaryCount(0, 'υπάλληλος', 'υπάλληλοι'),
          SummaryCount(2, 'τηλέφωνο', 'τηλέφωνα'),
        ],
      );

      expect(line, '3 τμήματα · 2 τηλέφωνα');
    });

    test('το αντικείμενο γράφεται ακόμα κι όταν είναι μόνο του', () {
      final line = buildBulkDeletionHeadline(
        subject: const SummaryCount(2, 'τμήμα', 'τμήματα'),
      );

      expect(line, '2 τμήματα');
    });

    test('μηδενικό αντικείμενο δεν εξαφανίζεται', () {
      final line = buildBulkDeletionHeadline(
        subject: const SummaryCount(0, 'τμήμα', 'τμήματα'),
      );

      expect(line, '0 τμήματα');
    });
  });

  group('Όταν ο χρήστης αφαίρεσε στοιχεία', () {
    test('το πρώτο σκέλος γίνεται «Ν από τα Μ επιλεγμένα»', () {
      final line = buildBulkDeletionHeadline(
        subject: const SummaryCount(3, 'τμήμα', 'τμήματα'),
        initiallySelected: 6,
        details: const [SummaryCount(2, 'τηλέφωνο', 'τηλέφωνα')],
      );

      expect(line, '3 από τα 6 επιλεγμένα · 2 τηλέφωνα');
    });

    test('χωρίς αφαίρεση μένει η κανονική μορφή', () {
      final line = buildBulkDeletionHeadline(
        subject: const SummaryCount(6, 'τμήμα', 'τμήματα'),
        initiallySelected: 6,
      );

      expect(line, '6 τμήματα');
    });

    test('ένα από πολλά: πάλι «1 από τα Μ»', () {
      final line = buildBulkDeletionHeadline(
        subject: const SummaryCount(1, 'υπάλληλος', 'υπάλληλοι'),
        initiallySelected: 9,
      );

      expect(line, '1 από τα 9 επιλεγμένα');
    });
  });
}
