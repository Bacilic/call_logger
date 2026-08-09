import 'package:call_logger/features/audit/services/audit_details_humanizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Τεχνικό ίχνος που δεν πρέπει να φτάσει στον χρήστη', () {
    test('σκέτο «πίνακας id=ν» κρύβεται — η σύνοψη το λέει ήδη', () {
      expect(humanizeAuditDetails('calls id=228'), isNull);
      expect(humanizeAuditDetails('tasks id=5'), isNull);
      expect(humanizeAuditDetails('users id=23'), isNull);
      expect(humanizeAuditDetails('equipment id=97'), isNull);
    });

    test('το «calls count=ν» κρύβεται κι αυτό', () {
      expect(humanizeAuditDetails('calls count=3'), isNull);
    });

    test('όνομα μεθόδου του κώδικα δεν είναι πληροφορία για τον χρήστη', () {
      expect(
        humanizeAuditDetails('updateAssociationsIfNeeded userId=17'),
        isNull,
      );
      expect(
        humanizeAuditDetails('departments id=8 (getOrCreateDepartmentIdByName)'),
        isNull,
      );
      expect(
        humanizeAuditDetails('equipment id=4 (updateEquipmentDepartment)'),
        isNull,
      );
    });

    test('κενό ή απόν details δεν δίνει γραμμή', () {
      expect(humanizeAuditDetails(null), isNull);
      expect(humanizeAuditDetails('   '), isNull);
    });
  });

  group('Ελληνικό σχόλιο που αξίζει να μείνει', () {
    test('κρατά μόνο το σχόλιο, χωρίς το τεχνικό πρόθεμα', () {
      expect(
        humanizeAuditDetails('equipment id=23 (αφαίρεση κοινόχρηστου τμήματος 38)'),
        'Αφαίρεση κοινόχρηστου τμήματος 38',
      );
      expect(
        humanizeAuditDetails('users id=41 (σύνδεση εξοπλισμού)'),
        'Σύνδεση εξοπλισμού',
      );
    });

    test('κεφαλαιοποιεί το πρώτο γράμμα', () {
      expect(
        humanizeAuditDetails('categories id=7 (επαναφορά από διαγραμμένη)'),
        'Επαναφορά από διαγραμμένη',
      );
    });

    test('ελληνικό κείμενο χωρίς τεχνικό πρόθεμα μένει ακέραιο', () {
      expect(
        humanizeAuditDetails('συσχέτιση από κλήση · Δήμητρα'),
        'Συσχέτιση από κλήση · Δήμητρα',
      );
    });
  });
}
