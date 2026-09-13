import 'package:call_logger/core/database/old_database/lamp_cross_check_snapshot.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/services/lamp_entity_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Η ταύτιση Καταλόγου και Λάμπας: ποιος είναι ο ίδιος άνθρωπος, ποιο είναι
/// το ίδιο τμήμα, και πότε η εφαρμογή παραδέχεται ότι δεν ξέρει.
void main() {
  LampOwnerRecord owner(int id, String last, String first) {
    return LampOwnerRecord(
      id: id,
      lastName: last,
      firstName: first,
      officeId: null,
      phones: const [],
    );
  }

  LampCrossCheckSnapshot snapshotWithOwners(List<LampOwnerRecord> owners) {
    return LampCrossCheckSnapshot(
      offices: const {},
      owners: {for (final o in owners) o.id: o},
      equipmentByCode: const {},
    );
  }

  LampCrossCheckSnapshot snapshotWithOffices(List<LampOfficeRecord> offices) {
    return LampCrossCheckSnapshot(
      offices: {for (final o in offices) o.id: o},
      owners: const {},
      equipmentByCode: const {},
    );
  }

  group('υπάλληλοι', () {
    test('ίδιο ονοματεπώνυμο: ακριβής ταύτιση', () {
      final matches = LampEntityMatcher.matchUsers(
        [UserModel(id: 1, lastName: 'Ψαρρά', firstName: 'Σοφία')],
        snapshotWithOwners([owner(10, 'Ψαρρά', 'Σοφία')]),
      );
      expect(matches[1]!.outcome, LampMatchOutcome.exact);
      expect(matches[1]!.owner!.id, 10);
    });

    test('ένα γράμμα διαφορά στο μικρό όνομα: ταύτιση με σημείωση', () {
      final matches = LampEntityMatcher.matchUsers(
        [UserModel(id: 1, lastName: 'Αποστολοπούλου', firstName: 'Νατάσσα')],
        snapshotWithOwners([owner(10, 'Αποστολοπούλου', 'Νατάσα')]),
      );
      expect(matches[1]!.outcome, LampMatchOutcome.spelling);
      expect(matches[1]!.owner!.id, 10);
      expect(matches[1]!.note, contains('1 γράμμα'));
    });

    test('δύο γράμματα διαφορά στο επώνυμο: άλλος άνθρωπος', () {
      final matches = LampEntityMatcher.matchUsers(
        [UserModel(id: 1, lastName: 'Δρόσος', firstName: 'Βασίλης')],
        snapshotWithOwners([owner(10, 'Πρόβος', 'Βασίλης')]),
      );
      expect(matches[1]!.outcome, LampMatchOutcome.missing);
      expect(matches[1]!.owner, isNull);
    });

    test('δύο ίδια ονοματεπώνυμα στη Λάμπα: αβέβαιη ταύτιση', () {
      final matches = LampEntityMatcher.matchUsers(
        [UserModel(id: 1, lastName: 'Τσουκαλά', firstName: 'Μαρία')],
        snapshotWithOwners([
          owner(10, 'Τσουκαλά', 'Μαρία'),
          owner(11, 'Τσουκαλά', 'Μαρία'),
        ]),
      );
      expect(matches[1]!.outcome, LampMatchOutcome.ambiguous);
      expect(matches[1]!.owner, isNull);
      expect(matches[1]!.candidates, hasLength(2));
    });

    test('κανένας υποψήφιος: δεν βρέθηκε', () {
      final matches = LampEntityMatcher.matchUsers(
        [UserModel(id: 1, lastName: 'Νομικού', firstName: 'Μαριάντζελα')],
        snapshotWithOwners([owner(10, 'Ψαρρά', 'Σοφία')]),
      );
      expect(matches[1]!.outcome, LampMatchOutcome.missing);
    });
  });

  group('τμήματα', () {
    LampOfficeRecord office(int id, String name, {String department = ''}) {
      return LampOfficeRecord(
        id: id,
        name: name,
        departmentName: department,
        phones: const [],
      );
    }

    test('ίδια ονομασία γραφείου: ακριβής ταύτιση', () {
      final matches = LampEntityMatcher.matchDepartments(
        [DepartmentModel(id: 1, name: 'Αιματολογικό')],
        snapshotWithOffices([office(10, 'Αιματολογικό')]),
      );
      expect(matches[1]!.outcome, LampMatchOutcome.exact);
      expect(matches[1]!.offices.single.id, 10);
    });

    test('πολλά γραφεία με το ίδιο όνομα ενώνονται σε ένα τμήμα', () {
      final matches = LampEntityMatcher.matchDepartments(
        [DepartmentModel(id: 1, name: 'Αιματολογικό')],
        snapshotWithOffices([
          office(10, 'Αιματολογικό'),
          office(11, 'Αιματολογικό'),
        ]),
      );
      expect(matches[1]!.outcome, LampMatchOutcome.exact);
      expect(matches[1]!.offices, hasLength(2));
    });

    test('μικρή διαφορά γραφής σε μεγάλη ονομασία: ταύτιση με σημείωση', () {
      final matches = LampEntityMatcher.matchDepartments(
        [DepartmentModel(id: 1, name: 'Μικροβιολογικό')],
        snapshotWithOffices([office(10, 'Μικροβιολογικο')]),
      );
      expect(matches[1]!.outcome, LampMatchOutcome.exact);
    });

    test('άγνωστη ονομασία: δεν βρέθηκε', () {
      final matches = LampEntityMatcher.matchDepartments(
        [DepartmentModel(id: 1, name: 'Γραφείο Κίνησης')],
        snapshotWithOffices([office(10, 'Αιματολογικό')]),
      );
      expect(matches[1]!.outcome, LampMatchOutcome.missing);
    });

    test('ο ανώτερος φορέας μετρά ως δεύτερη ευκαιρία ταύτισης', () {
      final matches = LampEntityMatcher.matchDepartments(
        [DepartmentModel(id: 1, name: 'Οικονομικό')],
        snapshotWithOffices([
          office(10, 'Χρηματικού #1', department: 'Οικονομικό'),
        ]),
      );
      expect(matches[1]!.outcome, LampMatchOutcome.exact);
      expect(matches[1]!.offices.single.id, 10);
    });
  });
}
