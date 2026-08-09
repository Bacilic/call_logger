// Ετικέτες οντοτήτων αναφοράς της Λάμπας.
//
// Συμβόλαιο: «η ετικέτα ξεκινά από το όνομα της ίδιας της οντότητας· τα
// ονόματα γονέων μπαίνουν ως πλαίσιο δίπλα, ποτέ στη θέση της».
//
// Το σενάριο-σπόρος είναι πραγματικό (lampa.db): πέντε διαφορετικά γραφεία του
// τμήματος 43 εμφανίζονταν ΟΛΑ ως «Αιματολογικό Εργαστήριο» στη χειροκίνητη
// επίλυση, επειδή η ετικέτα έδειχνε το τμήμα αντί για το όνομα του γραφείου.
//
//   flutter test test/core/database/old_database/lamp_reference_labels_test.dart

import 'package:call_logger/core/database/old_database/lamp_reference_labels.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

void main() {
  group('lampOfficeDisplayLabel — τα πέντε γραφεία του Αιματολογικού', () {
    // Ακριβώς οι εγγραφές της lampa.db: office 66/186/281/282/283, όλες με
    // department_name «Αιματολογικό Εργαστήριο».
    const department = 'Αιματολογικό Εργαστήριο';

    String label(String officeName) => lampOfficeDisplayLabel(
      officeName: officeName,
      departmentName: department,
      organizationName: 'Εργαστηριακός τομέας',
    );

    test('κάθε γραφείο ξεχωρίζει από τα υπόλοιπα', () {
      final labels = <String>{
        label('Αιματολογικό Εργαστήριο'),
        label('Διευθυντής Αιματολογικού'),
        label('Αίθουσα Αιματολογικού#2'),
        label('Αιματολογικό (Χρόνοι)'),
        label('Αίθουσα Αιματολογικού#1'),
      };

      expect(
        labels.length,
        5,
        reason: greekExpectMsg(
          'Πέντε γραφεία, πέντε διαφορετικές ετικέτες — αλλιώς ο χρήστης δεν '
          'έχει κανένα κριτήριο επιλογής στη χειροκίνητη επίλυση',
        ),
      );
    });

    test('το όνομα του γραφείου μπαίνει πρώτο, το τμήμα ως πλαίσιο', () {
      expect(
        label('Διευθυντής Αιματολογικού'),
        'Διευθυντής Αιματολογικού · τμήμα=Αιματολογικό Εργαστήριο',
      );
    });

    test('όταν γραφείο και τμήμα ταυτίζονται, το πλαίσιο παραλείπεται', () {
      expect(
        label('Αιματολογικό Εργαστήριο'),
        'Αιματολογικό Εργαστήριο',
        reason: greekExpectMsg(
          'Η επανάληψη «Χ · τμήμα=Χ» δεν προσθέτει πληροφορία, μόνο θόρυβο',
        ),
      );
    });
  });

  group('lampOfficeDisplayLabel — εκφυλισμένες τιμές', () {
    test('χωρίς όνομα γραφείου πέφτει στο τμήμα', () {
      expect(
        lampOfficeDisplayLabel(
          officeName: '  ',
          departmentName: 'Ακτινολογικό',
          organizationName: 'Τομέας',
        ),
        'Ακτινολογικό',
      );
    });

    test('σκέτος αριθμός δεν μετρά ως όνομα', () {
      expect(
        lampOfficeDisplayLabel(officeName: '281', departmentName: 'ΤΕΠ'),
        'ΤΕΠ',
        reason: greekExpectMsg(
          'Ένα «281» ως όνομα δεν βοηθά κανέναν να αναγνωρίσει το γραφείο',
        ),
      );
    });

    test('χωρίς τίποτα επιστρέφει κενό αντί να σκάσει', () {
      expect(lampOfficeDisplayLabel(), '');
    });
  });

  group('lampOwnerDisplayLabel — δύο συνώνυμοι υποψήφιοι', () {
    // Πραγματικό σενάριο 08/08: εξοπλισμός 5010, πεδίο «υπάλληλος», δύο
    // υποψήφιοι «Παπαβασιλείου» — χωρίς το γραφείο δεν ξεχωρίζουν.
    test('το γραφείο μπαίνει δίπλα στο όνομα', () {
      expect(
        lampOwnerDisplayLabel(
          lastName: 'Παπαβασιλείου',
          firstName: 'Τζένη',
          officeName: 'Φαρμακείο',
          departmentName: 'Φαρμακείο',
        ),
        'Παπαβασιλείου Τζένη · γραφείο=Φαρμακείο',
      );
    });

    test('δύο συνώνυμοι σε διαφορετικά γραφεία ξεχωρίζουν', () {
      final first = lampOwnerDisplayLabel(
        lastName: 'Παπαβασιλείου',
        firstName: 'Τζένη',
        officeName: 'Φαρμακείο',
      );
      final second = lampOwnerDisplayLabel(
        lastName: 'Παπαβασιλείου',
        firstName: 'Ελένη',
        officeName: 'Πληροφορική',
      );

      expect(
        first,
        isNot(second),
        reason: greekExpectMsg(
          'Χωρίς διάκριση, ο χρήστης διαλέγει στα τυφλά',
        ),
      );
    });

    test('χωρίς γραφείο πέφτει στο τμήμα', () {
      expect(
        lampOwnerDisplayLabel(
          lastName: 'Νικολάου',
          firstName: 'Άννα',
          departmentName: 'Ακτινολογικό',
        ),
        'Νικολάου Άννα · γραφείο=Ακτινολογικό',
      );
    });

    test('χωρίς καμία θέση μένει σκέτο το όνομα', () {
      expect(
        lampOwnerDisplayLabel(lastName: 'Νικολάου', firstName: 'Άννα'),
        'Νικολάου Άννα',
      );
    });

    test('εκφυλισμένες τιμές δεν αφήνουν κενά ή σκουπίδια', () {
      expect(lampOwnerDisplayLabel(lastName: '  ', firstName: 'Άννα'), 'Άννα');
      expect(lampOwnerDisplayLabel(), '');
      expect(
        lampOwnerDisplayLabel(officeName: 'Φαρμακείο'),
        'γραφείο=Φαρμακείο',
      );
    });
  });

  group('lampFirstInformativeText', () {
    test('προσπερνά κενά και σκέτους αριθμούς', () {
      expect(lampFirstInformativeText('  ', '42', 'Καρδιολογική'), 'Καρδιολογική');
      expect(lampFirstInformativeText(null, null, null), isNull);
      expect(lampFirstInformativeText('12-34', 'Παθολογική', null), 'Παθολογική');
    });
  });
}
