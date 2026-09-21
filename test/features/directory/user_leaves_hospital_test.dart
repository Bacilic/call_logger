// Όταν ένας άνθρωπος βγαίνει από το νοσοκομείο, η επιβεβαίωση το λέει.
//
// Ως τις 19/09 ο διάλογος «Αλλαγή τμήματος» έλεγε τα ίδια ακριβώς λόγια είτε ο
// υπάλληλος πήγαινε στο διπλανό γραφείο είτε έφευγε από τον οργανισμό: μόνο
// «Μεταφορά Αντώνης από Χ → Υ». Οι υπόλοιπες ειδοποιήσεις μιλούσαν για τα
// πράγματά του — μηχανήματα, τηλέφωνα, αναγνωριστικό — καμία για τον ίδιο.
//
//   flutter test test/features/directory/user_leaves_hospital_test.dart

import 'package:call_logger/features/directory/models/department_kind.dart';
import 'package:call_logger/features/directory/services/user_move_consequences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('πότε φεύγει κάποιος από το νοσοκομείο', () {
    test('από τμήμα σε εταιρεία — φεύγει', () {
      expect(
        userLeavesHospital(
          previousKind: DepartmentKind.hospital,
          targetKind: DepartmentKind.company,
        ),
        isTrue,
      );
    });

    test('από τμήμα σε εξωτερική μονάδα — φεύγει', () {
      expect(
        userLeavesHospital(
          previousKind: DepartmentKind.hospital,
          targetKind: DepartmentKind.externalUnit,
        ),
        isTrue,
      );
    });

    test('από τμήμα σε τμήμα — δεν φεύγει', () {
      expect(
        userLeavesHospital(
          previousKind: DepartmentKind.hospital,
          targetKind: DepartmentKind.hospital,
        ),
        isFalse,
      );
    });

    test('από εταιρεία σε άλλη εταιρεία — έχει ήδη φύγει', () {
      // Μιλάμε για μετάβαση, όχι για κατάσταση: μια προειδοποίηση εδώ θα ήταν
      // θόρυβος για κάτι που συνέβη παλιά.
      expect(
        userLeavesHospital(
          previousKind: DepartmentKind.company,
          targetKind: DepartmentKind.externalUnit,
        ),
        isFalse,
      );
    });

    test('επιστροφή στο νοσοκομείο — δεν είναι έξοδος', () {
      expect(
        userLeavesHospital(
          previousKind: DepartmentKind.company,
          targetKind: DepartmentKind.hospital,
        ),
        isFalse,
      );
    });
  });

  group('τι λέει η γραμμή για έναν άνθρωπο', () {
    String? messageFor({
      required DepartmentKind from,
      required DepartmentKind to,
      String name = 'Αντώνης Παπαδόπουλος',
      String target = 'Vodafone',
    }) => userLeavesHospitalMessage(
      previousKind: from,
      targetKind: to,
      targetDepartmentName: target,
      userDisplayName: name,
    );

    test('ονομάζει τον άνθρωπο και τον προορισμό', () {
      final message = messageFor(
        from: DepartmentKind.hospital,
        to: DepartmentKind.company,
      )!;

      expect(message, contains('Αντώνης Παπαδόπουλος'));
      expect(message, contains('Vodafone'));
      expect(message, contains('δεν ανήκει στο νοσοκομείο'));
    });

    test('χρησιμοποιεί το σωστό άρθρο ανά Είδος', () {
      expect(
        messageFor(
          from: DepartmentKind.hospital,
          to: DepartmentKind.externalUnit,
          target: 'Κέντρο Υγείας',
        ),
        contains('η εξωτερική μονάδα «Κέντρο Υγείας»'),
      );
      expect(
        messageFor(from: DepartmentKind.hospital, to: DepartmentKind.company),
        contains('η εταιρεία «Vodafone»'),
      );
    });

    test('σιωπά όταν δεν υπάρχει έξοδος', () {
      expect(
        messageFor(from: DepartmentKind.hospital, to: DepartmentKind.hospital),
        isNull,
      );
      expect(
        messageFor(from: DepartmentKind.company, to: DepartmentKind.company),
        isNull,
      );
    });

    test('χωρίς όνομα, μιλά γενικά αντί να αφήνει κενό', () {
      final message = messageFor(
        from: DepartmentKind.hospital,
        to: DepartmentKind.company,
        name: '   ',
      )!;

      expect(message, contains('ο υπάλληλος'));
      expect(message, isNot(contains('  ')));
    });

    test('χωρίς όνομα τμήματος, δεν γράφει άδεια εισαγωγικά', () {
      final message = messageFor(
        from: DepartmentKind.hospital,
        to: DepartmentKind.company,
        target: '',
      )!;

      expect(message, isNot(contains('«»')));
      expect(message, contains('η εταιρεία'));
    });
  });

  group('τι λέει η γραμμή για πολλούς', () {
    test('το πλήθος είναι αυτό που βαραίνει', () {
      final many = usersLeaveHospitalMessage(
        targetKind: DepartmentKind.company,
        targetDepartmentName: 'Vodafone',
        count: 12,
      )!;

      expect(many, contains('12 υπάλληλοι'));
      expect(many, contains('παύουν'));
    });

    test('ένας γράφεται στον ενικό', () {
      final one = usersLeaveHospitalMessage(
        targetKind: DepartmentKind.company,
        targetDepartmentName: 'Vodafone',
        count: 1,
      )!;

      expect(one, contains('1 υπάλληλος'));
      expect(one, contains('παύει'));
    });

    test('σιωπά για προορισμό μέσα στο νοσοκομείο', () {
      expect(
        usersLeaveHospitalMessage(
          targetKind: DepartmentKind.hospital,
          targetDepartmentName: 'Πληροφορική',
          count: 5,
        ),
        isNull,
      );
    });

    test('σιωπά όταν δεν μετακινείται κανείς', () {
      expect(
        usersLeaveHospitalMessage(
          targetKind: DepartmentKind.company,
          targetDepartmentName: 'Vodafone',
          count: 0,
        ),
        isNull,
      );
    });
  });

  group('οι δύο πύλες λένε το ίδιο πράγμα', () {
    test('ίδια κρίση, ίδιος πυρήνας φράσης', () {
      final single = userLeavesHospitalMessage(
        previousKind: DepartmentKind.hospital,
        targetKind: DepartmentKind.company,
        targetDepartmentName: 'Vodafone',
        userDisplayName: 'Αντώνης',
      )!;
      final bulk = usersLeaveHospitalMessage(
        targetKind: DepartmentKind.company,
        targetDepartmentName: 'Vodafone',
        count: 1,
      )!;

      // Ο χειριστής δεν πρέπει να μαθαίνει δύο διατυπώσεις για το ίδιο
      // γεγονός, ανάλογα με το αν μετακίνησε έναν ή πολλούς.
      const core = 'δεν ανήκει στο νοσοκομείο';
      expect(single, contains(core));
      expect(bulk, contains(core));
      expect(single, startsWith('Προσοχή:'));
      expect(bulk, startsWith('Προσοχή:'));
    });
  });
}
