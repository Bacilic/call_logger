// Ποιο κομμάτι του `details` διαβάζει ο χειριστής και ποιο ο τεχνικός.
//
// Σενάριο 14/09: η οθόνη σφάλματος της εκκίνησης τύπωνε ολόκληρο το πεδίο
// αυτούσιο, οπότε μέσα στη συμβουλή φαίνονταν οι δείκτες «--- Diagnostics ---»
// και «--- Lock diagnostics ---», και η ωμή εντολή SQL. Ο διάλογος χώριζε
// σωστά, αλλά γνώριζε έναν μόνο δείκτη από τους τρεις.
//
//   flutter test test/core/database/database_details_split_test.dart

import 'package:call_logger/core/database/database_init_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('χωρισμός συμβουλής και διαγνωστικών', () {
    test('χωρίς δείκτη, όλα είναι συμβουλή', () {
      final split = splitDatabaseDetails('Ελέγξτε τη διαδρομή στις ρυθμίσεις.');
      expect(split.advice, 'Ελέγξτε τη διαδρομή στις ρυθμίσεις.');
      expect(split.diagnostics, isEmpty);
    });

    test('κενό ή ανύπαρκτο πεδίο δεν σπάει', () {
      expect(splitDatabaseDetails(null).advice, isEmpty);
      expect(splitDatabaseDetails('   ').diagnostics, isEmpty);
    });

    for (final marker in kDetailsSectionMarkers) {
      test('ο δείκτης «$marker» κόβει και δεν τυπώνεται', () {
        final split = splitDatabaseDetails(
          'Η συμβουλή.\n\n$marker\nΤο τεχνικό υλικό.',
        );
        expect(split.advice, 'Η συμβουλή.');
        expect(
          split.advice,
          isNot(contains('---')),
          reason: 'Δείκτης μηχανής μέσα σε κείμενο για άνθρωπο',
        );
        expect(split.diagnostics, 'Το τεχνικό υλικό.');
      });
    }

    test('με πολλά τμήματα, κόβει στο ΠΡΩΤΟ που εμφανίζεται', () {
      final split = splitDatabaseDetails(
        'Η συμβουλή.\n\n'
        '$kLockDiagnosticsSectionMarker\n'
        'Το αρχείο το κρατά η διεργασία 15580.\n\n'
        '$kDiagnosticsSectionMarker\n'
        'Έγκυρη κεφαλίδα SQLite.',
      );
      expect(split.advice, 'Η συμβουλή.');
      expect(split.diagnostics, contains('15580'));
      expect(
        split.diagnostics,
        contains(kDiagnosticsSectionMarker),
        reason: 'Οι επόμενοι δείκτες χωρίζουν τα τμήματα μεταξύ τους',
      );
    });

    test('συμβουλή που λείπει αφήνει μόνο διαγνωστικά', () {
      final split = splitDatabaseDetails(
        '$kDiagnosticsSectionMarker\nΜόνο τεχνικά.',
      );
      expect(split.advice, isEmpty);
      expect(split.diagnostics, 'Μόνο τεχνικά.');
    });
  });

  group('η συμβουλή δεν κουβαλά ωμό SQL', () {
    test('αποτυχία μετάπτωσης: καμία εντολή SQL στο κείμενο του χειριστή', () {
      final result = DatabaseInitResult.fromException(
        Exception(
          'SqfliteFfiException(sqlite_error: 1, , SqliteException(1): while '
          'executing, no such table: audit_log, SQL logic error (code 1)\n'
          '  Causing statement: ALTER TABLE audit_log ADD COLUMN entity_type '
          'TEXT, parameters: })',
        ),
        r'F:\Data Base\call_logger.db',
      );

      final advice = splitDatabaseDetails(result.details).advice;
      expect(advice, isNot(contains('Causing statement')));
      expect(advice, isNot(contains('ALTER TABLE')));
      expect(advice, contains('Μην διαγράψετε'));
    });

    test('η εντολή δεν χάνεται — ζει στο ωμό μήνυμα', () {
      final result = DatabaseInitResult.fromException(
        Exception(
          'DatabaseException(SqliteException(1): no such table: audit_log\n'
          '  Causing statement: ALTER TABLE audit_log ADD COLUMN x TEXT)',
        ),
      );
      expect(result.originalExceptionText, contains('ALTER TABLE audit_log'));
    });
  });
}
