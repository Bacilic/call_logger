import 'package:call_logger/features/directory/services/category_deletion_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('μηνύματα διαγραφής κατηγοριών — αριθμός και γένος', () {
    test('τίτλος και ερώτηση για μία και για πολλές', () {
      expect(categoryDeleteDialogTitle(1), 'Διαγραφή κατηγορίας');
      expect(categoryDeleteDialogTitle(3), 'Διαγραφή κατηγοριών');
      expect(
        categoryDeleteConfirmMessage(1),
        'Μόνιμη σήμανση 1 κατηγορίας ως διαγραμμένης;',
      );
      expect(
        categoryDeleteConfirmMessage(3),
        'Μόνιμη σήμανση 3 κατηγοριών ως διαγραμμένων;',
      );
    });

    test('μήνυμα μετά τη διαγραφή, με και χωρίς ονόματα', () {
      expect(
        categoryDeletedMessage(1, 'Εκτυπωτές'),
        'Σημειώθηκε ως διαγραμμένη 1 κατηγορία: Εκτυπωτές',
      );
      expect(
        categoryDeletedMessage(3, ''),
        'Σημειώθηκαν ως διαγραμμένες 3 κατηγορίες.',
      );
    });
  });
}
