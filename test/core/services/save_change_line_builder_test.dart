// Οι γραμμές αλλαγών του μηνύματος αποθήκευσης — καθαρές συναρτήσεις, χωρίς
// βάση και χωρίς widget.
//
//   flutter test test/core/services/save_change_line_builder_test.dart

import 'package:call_logger/core/services/save_change_line_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildCollectionChangeLines — τηλέφωνα', () {
    test('ένα προστέθηκε: ενικός στο ρήμα και στο ουσιαστικό', () {
      final lines = buildCollectionChangeLines(
        field: 'phones',
        oldValue: const ['2531'],
        newValue: const ['2531', '2839'],
      );

      expect(lines, ['Προστέθηκε τηλέφωνο: 2839']);
    });

    test('πολλά προστέθηκαν: πληθυντικός και στα δύο', () {
      final lines = buildCollectionChangeLines(
        field: 'phones',
        oldValue: const ['2531'],
        newValue: const ['2531', '2839', '2840'],
      );

      expect(lines, ['Προστέθηκαν τηλέφωνα: 2839, 2840']);
    });

    test('ένα αφαιρέθηκε — τα υπόλοιπα δεν αναφέρονται καθόλου', () {
      final lines = buildCollectionChangeLines(
        field: 'phones',
        oldValue: const ['2531', '2839'],
        newValue: const ['2531'],
      );

      expect(lines, ['Αφαιρέθηκε τηλέφωνο: 2839']);
    });

    test('ένα έφυγε και ένα ήρθε: μία γραμμή επεξεργασίας, όχι δύο', () {
      final lines = buildCollectionChangeLines(
        field: 'phones',
        oldValue: const ['2531'],
        newValue: const ['2532'],
      );

      expect(lines, ['Επεξεργασία τηλεφώνου: 2531 → 2532']);
    });

    test('δύο έφυγαν και δύο ήρθαν: χωριστές γραμμές, καμία εικασία', () {
      // Με πάνω από ένα ζευγάρι δεν ξέρουμε ποιο αντικατέστησε ποιο — και δεν
      // το μαντεύουμε.
      final lines = buildCollectionChangeLines(
        field: 'phones',
        oldValue: const ['1', '2'],
        newValue: const ['3', '4'],
      );

      expect(lines, [
        'Προστέθηκαν τηλέφωνα: 3, 4',
        'Αφαιρέθηκαν τηλέφωνα: 1, 2',
      ]);
    });

    test('καμία αλλαγή: καμία γραμμή', () {
      final lines = buildCollectionChangeLines(
        field: 'phones',
        oldValue: const ['2531', '2839'],
        newValue: const ['2531', '2839'],
      );

      expect(lines, isEmpty);
    });
  });

  group('buildCollectionChangeLines — περιληπτικό ουσιαστικό', () {
    test('ο «εξοπλισμός» μένει σε ενικό ακόμη και για πολλά κομμάτια', () {
      final lines = buildCollectionChangeLines(
        field: 'shared_equipment_codes',
        oldValue: const <String>[],
        newValue: const ['πισι1', 'πισι2'],
      );

      expect(lines, ['Προστέθηκε εξοπλισμός: πισι1, πισι2']);
    });
  });

  group('buildCollectionChangeLines — αναγνωριστικά Lansweeper', () {
    const stored =
        r'[{"username":"gnk\\loimokseis1","label":"Γραφείο Λοιμώξεων"},'
        r'{"username":"gnk\\testaki"}]';
    const withoutSecond = r'[{"username":"gnk\\loimokseis1","label":"Γραφείο Λοιμώξεων"}]';

    test('αφαίρεση ενός λογαριασμού δεν ξεβράζει ολόκληρο το JSON', () {
      final lines = buildCollectionChangeLines(
        field: 'lansweeper_usernames',
        oldValue: stored,
        newValue: withoutSecond,
      );

      expect(lines, hasLength(1));
      expect(lines.single, startsWith('Αφαιρέθηκε αναγνωριστικό Lansweeper: '));
      expect(lines.single, contains(r'gnk\testaki'));
      expect(
        lines.single,
        isNot(contains('username')),
        reason: 'το μήνυμα δεν δείχνει ποτέ ωμά κλειδιά JSON',
      );
      expect(lines.single, isNot(contains('{')));
    });

    test('ίδιο αναγνωριστικό με νέα ετικέτα μετράει ως επεξεργασία', () {
      // Χωρίς τη σύγκριση εμφάνισης, η αλλαγή θα ήταν εντελώς αόρατη: το
      // αναγνωριστικό είναι το ίδιο, άρα ούτε προστέθηκε ούτε αφαιρέθηκε.
      final lines = buildCollectionChangeLines(
        field: 'lansweeper_usernames',
        oldValue: r'[{"username":"gnk\\loimokseis1","label":"Παλιά"}]',
        newValue: r'[{"username":"gnk\\loimokseis1","label":"Νέα"}]',
      );

      expect(lines, hasLength(1));
      expect(lines.single, startsWith('Επεξεργασία αναγνωριστικού Lansweeper:'));
      expect(lines.single, contains('Παλιά'));
      expect(lines.single, contains('Νέα'));
    });

    test('κενή αποθηκευμένη τιμή δεν σκάει', () {
      expect(
        buildCollectionChangeLines(
          field: 'lansweeper_usernames',
          oldValue: null,
          newValue: '',
        ),
        isEmpty,
      );
    });
  });

  group('buildRenameLine', () {
    test('τμήμα: μία γραμμή μετονομασίας', () {
      expect(
        buildRenameLine(
          entityType: 'department',
          oldMap: const {'name': 'Λοιμώξεων'},
          newMap: const {'name': 'Γραφείο Λοιμώξεων'},
        ),
        'Μετονομασία: Λοιμώξεων → Γραφείο Λοιμώξεων',
      );
    });

    test('υπάλληλος: όνομα και επώνυμο ενώνονται σε ΜΙΑ γραμμή', () {
      expect(
        buildRenameLine(
          entityType: 'user',
          oldMap: const {'first_name': 'Βάσω', 'last_name': 'Αναγνωστοπούλου'},
          newMap: const {'first_name': 'Θάνια', 'last_name': 'Αναγνωστοπούλου'},
        ),
        'Μετονομασία: Βάσω Αναγνωστοπούλου → Θάνια Αναγνωστοπούλου',
      );
    });

    test('ίδιο όνομα: καμία γραμμή', () {
      expect(
        buildRenameLine(
          entityType: 'department',
          oldMap: const {'name': 'Λοιμώξεων'},
          newMap: const {'name': 'Λοιμώξεων'},
        ),
        isNull,
      );
    });

    test('οντότητα χωρίς όνομα (κλήση): καμία γραμμή', () {
      expect(
        buildRenameLine(
          entityType: 'call',
          oldMap: const {'issue': 'παλιό'},
          newMap: const {'issue': 'νέο'},
        ),
        isNull,
      );
    });

    test('τα πεδία ταυτότητας δηλώνονται, ώστε να μη μετρηθούν δεύτερη φορά', () {
      expect(renameFieldsFor('user'), {'first_name', 'last_name'});
      expect(renameFieldsFor('department'), {'name'});
      expect(renameFieldsFor('call'), isEmpty);
    });
  });

  group('isCollectionField', () {
    test('ξεχωρίζει τις συλλογές από τα πεδία απλής τιμής', () {
      expect(isCollectionField('phones'), isTrue);
      expect(isCollectionField('lansweeper_usernames'), isTrue);
      expect(isCollectionField('shared_equipment_codes'), isTrue);
      expect(
        isCollectionField('color'),
        isFalse,
        reason: 'το χρώμα διαβάζεται ως «παλιό → νέο» και δεν το πειράζουμε',
      );
      expect(isCollectionField('notes'), isFalse);
    });
  });
}
