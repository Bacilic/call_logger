// Σύνοψη διαγραφής υπαλλήλων: πόσοι και πόσες ερωτήσεις ακολουθούν.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/services/user_deletion_headline_test.dart

import 'package:call_logger/features/directory/services/user_deletion_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Κύρια γραμμή σύνοψης', () {
    test('υπάλληλοι με τηλέφωνα και εξοπλισμό', () {
      expect(
        userDeletionHeadline(
          userCount: 12,
          exclusivePhoneCount: 8,
          exclusiveEquipmentCount: 5,
        ),
        '12 υπάλληλοι · 8 προσωπικά τηλέφωνα · 5 προσωπικοί εξοπλισμοί',
      );
    });

    test('ενικοί παντού', () {
      expect(
        userDeletionHeadline(
          userCount: 1,
          exclusivePhoneCount: 1,
          exclusiveEquipmentCount: 1,
        ),
        '1 υπάλληλος · 1 προσωπικό τηλέφωνο · 1 προσωπικός εξοπλισμός',
      );
    });

    test('χωρίς στοιχεία: μόνο το πλήθος υπαλλήλων', () {
      expect(
        userDeletionHeadline(
          userCount: 4,
          exclusivePhoneCount: 0,
          exclusiveEquipmentCount: 0,
        ),
        '4 υπάλληλοι',
      );
    });

    test('μετά από αφαίρεση: «Ν από τα Μ επιλεγμένα»', () {
      expect(
        userDeletionHeadline(
          userCount: 3,
          exclusivePhoneCount: 2,
          exclusiveEquipmentCount: 0,
          initiallySelected: 9,
        ),
        '3 από τα 9 επιλεγμένα · 2 προσωπικά τηλέφωνα',
      );
    });
  });

  group('Προειδοποίηση για τις ερωτήσεις που ακολουθούν', () {
    test('χωρίς στοιχεία: καμία προειδοποίηση', () {
      expect(userDeletionPendingQuestionsNotice(0), isNull);
    });

    test('ένα στοιχείο: ενικός', () {
      expect(
        userDeletionPendingQuestionsNotice(1),
        'Θα σας ζητηθεί απόφαση για 1 στοιχείο πριν ολοκληρωθεί η διαγραφή.',
      );
    });

    test('πολλά στοιχεία: πληθυντικός με το πλήθος', () {
      expect(
        userDeletionPendingQuestionsNotice(13),
        'Θα σας ζητηθεί απόφαση για 13 στοιχεία πριν ολοκληρωθεί η διαγραφή.',
      );
    });
  });
}
