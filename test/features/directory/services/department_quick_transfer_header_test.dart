// Κεφαλίδα του ενός επιλογέα προορισμού στη «Μεταφορά όλων σε ένα τμήμα».
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/services/department_quick_transfer_header_test.dart

import 'package:call_logger/features/directory/services/department_deletion_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Κεφαλίδα μαζικής μεταφοράς', () {
    test('ένα τμήμα: ονομάζεται', () {
      expect(
        departmentQuickTransferHeader(const ['Αιμοδοσία']),
        'Πού μεταφέρονται όλα από «Αιμοδοσία»;',
      );
    });

    test('ένα ανώνυμο τμήμα: παύλα αντί για κενά εισαγωγικά', () {
      expect(
        departmentQuickTransferHeader(const ['   ']),
        'Πού μεταφέρονται όλα από «—»;',
      );
    });

    test('πολλά τμήματα: μετριούνται, δεν ονομάζεται ένα', () {
      expect(
        departmentQuickTransferHeader(const [
          'Α',
          'Β',
          'Γ',
          'Δ',
          'Ε',
          'Ζ',
          'Η',
        ]),
        'Πού μεταφέρονται όλα από τα 7 τμήματα;',
      );
    });

    test('δύο τμήματα: ήδη πληθυντικός', () {
      expect(
        departmentQuickTransferHeader(const ['Α', 'Β']),
        'Πού μεταφέρονται όλα από τα 2 τμήματα;',
      );
    });
  });
}
