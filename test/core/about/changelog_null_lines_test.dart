// Στην οθόνη του Ιστορικού Αλλαγών φτάνει μόνο ό,τι είναι πράγματι κείμενο.
//
// Οι κάρτες 0.1.0 έως 0.8.2 έχουν `improvements: [null]`. Το `null.toString()`
// δίνει το **κείμενο** «null» — τεσσάρων χαρακτήρων, άρα περνούσε κάθε φίλτρο
// «πέτα τα κενά» και εμφανιζόταν ως γραμμή μικροβελτίωσης.
//
//   flutter test test/core/about/changelog_null_lines_test.dart

import 'package:call_logger/core/about/models/changelog_entry.dart';
import 'package:call_logger/core/about/models/changelog_text_lines.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ανάγνωση κάρτας για την οθόνη', () {
    test('το null ΔΕΝ γίνεται γραμμή «null»', () {
      final entry = ChangelogEntry.fromJson({
        'version': '0.1.0',
        'date': '2026-03-12',
        'added': ['Βασική οθόνη Κλήσεων'],
        'improvements': [null],
        'changed': [],
        'fixed': [],
      });

      expect(
        entry.improvements,
        isEmpty,
        reason: 'Η κάρτα v0.1.0 έδειχνε «• null» κάτω από τις Μικροβελτιώσεις.',
      );
      expect(entry.added, ['Βασική οθόνη Κλήσεων']);
    });

    test('κείμενο με μόνο κενά δεν γίνεται γραμμή', () {
      final entry = ChangelogEntry.fromJson({
        'version': '0.2.0',
        'improvements': ['   ', '\n', 'Πραγματική βελτίωση'],
      });

      expect(entry.improvements, ['Πραγματική βελτίωση']);
    });

    test('ό,τι δεν είναι κείμενο αγνοείται, χωρίς να ρίξει την οθόνη', () {
      final entry = ChangelogEntry.fromJson({
        'version': '0.3.0',
        'fixed': [null, 42, true, 'Πραγματική διόρθωση'],
      });

      expect(entry.fixed, ['Πραγματική διόρθωση']);
    });

    test('κανονική κάρτα μένει ανέπαφη', () {
      final entry = ChangelogEntry.fromJson({
        'version': '0.56.0',
        'date': '2026-09-20',
        'added': ['Πρώτο', 'Δεύτερο'],
        'improvements': ['Τρίτο'],
        'changed': [],
        'fixed': ['Τέταρτο'],
      });

      expect(entry.added, ['Πρώτο', 'Δεύτερο']);
      expect(entry.improvements, ['Τρίτο']);
      expect(entry.fixed, ['Τέταρτο']);
      expect(entry.entryCount, 4);
    });
  });

  group('Το κοινό φίλτρο', () {
    // Η σφράγιση έκδοσης ξαναγράφει την κορυφαία κάρτα περνώντας την από την
    // ΙΔΙΑ συνάρτηση: εκεί το «null» θα γινόταν μόνιμο κείμενο μέσα στο αρχείο.
    test('κρατά μόνο κείμενο με περιεχόμενο', () {
      expect(changelogTextLines([null, 'Κάτι', '  ', 42]), ['Κάτι']);
    });

    test('ό,τι δεν είναι λίστα δίνει άδεια λίστα', () {
      expect(changelogTextLines(null), isEmpty);
      expect(changelogTextLines('σκέτο κείμενο'), isEmpty);
    });
  });
}
