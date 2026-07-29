// Κείμενα πλαισίου/ακύρωσης της διαγραφής τμήματος και της φόρμας τμήματος.
//
//   flutter test test/features/directory/services/department_deletion_messages_test.dart

import 'package:call_logger/features/directory/services/department_deletion_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ετικέτα πλαισίου', () {
    test('ένα τμήμα δεν χρειάζεται ετικέτα', () {
      expect(
        departmentDeletionContextLabel(departmentIndex: 1, departmentCount: 1),
        isNull,
      );
    });

    test('πολλά τμήματα δηλώνουν σε ποιο βρισκόμαστε', () {
      expect(
        departmentDeletionContextLabel(departmentIndex: 2, departmentCount: 3),
        'Τμήμα 2 από 3',
      );
    });
  });

  group('εύρος ακύρωσης', () {
    test('ενικός και πληθυντικός στη διαγραφή τμήματος', () {
      expect(
        departmentDeletionCancelScopeDescription(1),
        'η διαγραφή του τμήματος',
      );
      expect(
        departmentDeletionCancelScopeDescription(3),
        'η διαγραφή 3 τμημάτων',
      );
    });

    test('η φόρμα τμήματος ονομάζει το τμήμα όταν το ξέρει', () {
      expect(
        departmentFormSaveCancelScopeDescription('Γραμματεία'),
        'η αποθήκευση του τμήματος «Γραμματεία»',
      );
      expect(
        departmentFormSaveCancelScopeDescription('   '),
        'η αποθήκευση του τμήματος',
      );
      expect(
        departmentFormSaveCancelScopeDescription(null),
        'η αποθήκευση του τμήματος',
      );
    });
  });
}
