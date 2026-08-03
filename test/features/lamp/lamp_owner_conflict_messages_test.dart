// Unit tests: κείμενα διενέξεων του οδηγού μεταφοράς Λάμπας.
//
//   flutter test test/features/lamp/lamp_owner_conflict_messages_test.dart

import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:call_logger/features/lamp/services/lamp_owner_conflict_messages.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

LampOwnerConflict _phoneConflict({
  List<String> owners = const [],
  String? sharedDepartment,
}) {
  return LampOwnerConflict(
    conflictId: 'phone:2914',
    kind: LampOwnerConflictKind.phone,
    value: '2914',
    currentOwners: owners,
    sharedDepartmentName: sharedDepartment,
  );
}

void main() {
  group('lampConflictAssignTargetLabel', () {
    test('υπάλληλος: «Όνομα Επώνυμο (Τμήμα)»', () {
      expect(
        lampConflictAssignTargetLabel(
          target: LampTransferTarget.owner,
          formValues: const {
            'first_name': 'Μαρία',
            'last_name': 'Παπαλαμπροπούλου',
            'department_name': 'Φαρμακείο',
          },
        ),
        'Μαρία Παπαλαμπροπούλου (Φαρμακείο)',
      );
    });

    test('τμήμα: το ίδιο το τμήμα είναι ο παραλήπτης', () {
      expect(
        lampConflictAssignTargetLabel(
          target: LampTransferTarget.department,
          formValues: const {'name': 'Γραμματεία ΤΕΙ'},
        ),
        'το τμήμα Γραμματεία ΤΕΙ',
      );
    });

    test('εξοπλισμός χωρίς κάτοχο: κενός παραλήπτης', () {
      expect(
        lampConflictAssignTargetLabel(
          target: LampTransferTarget.equipment,
          formValues: const {'owner_name': '', 'department_name': 'Φαρμακείο'},
        ),
        '',
        reason: greekExpectMsg(
          'Χωρίς κάτοχο στη φόρμα δεν υπάρχει παραλήπτης να ονομαστεί',
        ),
      );
    });
  });

  group('lampConflictTransferLabel', () {
    test('ονομάζει κάτοχο και παραλήπτη', () {
      expect(
        lampConflictTransferLabel(
          _phoneConflict(owners: const ['Βασίλης Πρόβος (Φαρμακείο)']),
          targetLabel: 'Βίκυ Κίτσιου (Γραφείο Κίνησης)',
        ),
        'Αφαίρεση από Βασίλης Πρόβος (Φαρμακείο) και σύνδεση με '
        'Βίκυ Κίτσιου (Γραφείο Κίνησης)',
      );
    });

    test('κοινόχρηστο και κάτοχος μαζί δηλώνονται και τα δύο', () {
      expect(
        lampConflictTransferLabel(
          _phoneConflict(
            owners: const ['Μαρία Παπαδοπούλου (Τμήμα Α)'],
            sharedDepartment: 'Τμήμα Β',
          ),
          targetLabel: 'Νέος Χρήστης (Τμήμα Γ)',
        ),
        'Αφαίρεση από Τμήμα Β (κοινόχρηστο) και από '
        'Μαρία Παπαδοπούλου (Τμήμα Α) και σύνδεση με Νέος Χρήστης (Τμήμα Γ)',
        reason: greekExpectMsg(
          'Η μεταφορά αφαιρεί και το κοινόχρηστο και τους κατόχους',
        ),
      );
    });

    test('χωρίς παραλήπτη το λέει αντί να το αποσιωπήσει', () {
      expect(
        lampConflictTransferLabel(
          LampOwnerConflict(
            conflictId: 'equipment:1001',
            kind: LampOwnerConflictKind.equipment,
            value: '1001',
            currentOwners: const ['Άννα Πατσαρίκα (Ακτινολογικό)'],
          ),
          targetLabel: '',
        ),
        'Αφαίρεση από Άννα Πατσαρίκα (Ακτινολογικό), χωρίς νέα σύνδεση',
      );
    });

    test('πάνω από τρεις κάτοχοι συμπτύσσονται σε πλήθος', () {
      expect(
        lampConflictTransferLabel(
          _phoneConflict(
            owners: const ['Α (Τ1)', 'Β (Τ2)', 'Γ (Τ3)', 'Δ (Τ4)', 'Ε (Τ5)'],
          ),
          targetLabel: 'Ζ (Τ6)',
        ),
        'Αφαίρεση από Α (Τ1), Β (Τ2), Γ (Τ3) και άλλους 2 χρήστες '
        'και σύνδεση με Ζ (Τ6)',
      );
    });
  });

  group('lampConflictTitle', () {
    test('κοινόχρηστο χωρίς κατόχους δεν μιλά για κατόχους', () {
      expect(
        lampConflictTitle(_phoneConflict(sharedDepartment: 'Φαρμακείο')),
        'Το τηλέφωνο 2914 είναι κοινόχρηστο στο τμήμα Φαρμακείο',
      );
    });

    test('κάτοχοι και κοινόχρηστο μαζί', () {
      expect(
        lampConflictTitle(
          _phoneConflict(
            owners: const ['Μαρία Παπαδοπούλου (Τμήμα Α)'],
            sharedDepartment: 'Τμήμα Β',
          ),
        ),
        'Το τηλέφωνο 2914 είναι κοινόχρηστο στο τμήμα Τμήμα Β και ανήκει σε: '
        'Μαρία Παπαδοπούλου (Τμήμα Α)',
      );
    });
  });
}
