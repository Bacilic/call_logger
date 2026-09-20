// Κείμενα πλαισίου/ακύρωσης της διαγραφής τμήματος και της φόρμας τμήματος.
//
//   flutter test test/features/directory/services/department_deletion_messages_test.dart

import 'package:call_logger/features/directory/models/department_kind.dart';
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

  group('το Είδος της καρτέλας φτάνει στα κείμενα', () {
    test('η ακύρωση αποθήκευσης ονομάζει την εταιρεία, όχι «τμήμα»', () {
      expect(
        departmentFormSaveCancelScopeDescription(
          'DataMed',
          kind: DepartmentKind.company,
        ),
        'η αποθήκευση της εταιρείας «DataMed»',
      );
    });

    test('η εξωτερική μονάδα κλίνεται σωστά', () {
      expect(
        departmentFormSaveCancelScopeDescription(
          'ΚΕΦΙΑΠ',
          kind: DepartmentKind.externalUnit,
        ),
        'η αποθήκευση της εξωτερικής μονάδας «ΚΕΦΙΑΠ»',
      );
    });

    test('χωρίς όνομα, το Είδος εξακολουθεί να μετράει', () {
      expect(
        departmentFormSaveCancelScopeDescription(
          '   ',
          kind: DepartmentKind.company,
        ),
        'η αποθήκευση της εταιρείας',
      );
    });
  });

  group('το snackbar μετά τη διαγραφή', () {
    const target = (name: 'Γραμματεία ΤΕΠ', isNew: false);

    test('ένα τμήμα χωρίς μεταφορές το λέει στον ενικό', () {
      expect(
        departmentDeletionSummaryMessage(
          displayNames: 'Ακτινολογικό',
          deletedCount: 1,
          transferTargets: const [],
          transferredEmployees: false,
          transferredEquipment: false,
          transferredPhones: false,
          fallbackMessage: 'δεν πρέπει να φανεί',
        ),
        'Το τμήμα Ακτινολογικό διαγράφηκε.',
      );
    });

    test('πολλά τμήματα το λένε στον πληθυντικό', () {
      expect(
        departmentDeletionSummaryMessage(
          displayNames: 'Ακτινολογικό, Μικροβιολογικό',
          deletedCount: 2,
          transferTargets: const [],
          transferredEmployees: false,
          transferredEquipment: false,
          transferredPhones: false,
          fallbackMessage: 'δεν πρέπει να φανεί',
        ),
        'Τα τμήματα Ακτινολογικό, Μικροβιολογικό διαγράφηκαν.',
      );
    });

    test('ένας προορισμός ονομάζεται, με τις κατηγορίες που μετακινήθηκαν', () {
      expect(
        departmentDeletionSummaryMessage(
          displayNames: 'Ακτινολογικό',
          deletedCount: 1,
          transferTargets: const [target],
          transferredEmployees: true,
          transferredEquipment: false,
          transferredPhones: true,
          fallbackMessage: 'δεν πρέπει να φανεί',
        ),
        'Το τμήμα Ακτινολογικό διαγράφηκε. Επιτυχής μεταφορά υπαλλήλων και '
        'τηλεφώνων στο υπάρχον Γραμματεία ΤΕΠ.',
      );
    });

    // Με δύο προορισμούς το μήνυμα θα γινόταν κατάλογος.
    test('δύο προορισμοί δεν ονομάζονται', () {
      expect(
        departmentDeletionSummaryMessage(
          displayNames: 'Ακτινολογικό',
          deletedCount: 1,
          transferTargets: const [target, (name: 'Παθολογικό', isNew: true)],
          transferredEmployees: true,
          transferredEquipment: false,
          transferredPhones: false,
          fallbackMessage: 'δεν πρέπει να φανεί',
        ),
        'Το τμήμα Ακτινολογικό διαγράφηκε. Τα στοιχεία μεταφέρθηκαν σε άλλα '
        'τμήματα.',
      );
    });

    // Χωρίς όνομα το «Το τμήμα Χ διαγράφηκε» δεν έχει τι να πει.
    test('χωρίς κανένα όνομα μιλά η πολιτική αναίρεσης', () {
      expect(
        departmentDeletionSummaryMessage(
          displayNames: '',
          deletedCount: 0,
          transferTargets: const [],
          transferredEmployees: false,
          transferredEquipment: false,
          transferredPhones: false,
          fallbackMessage: 'Η διαγραφή ολοκληρώθηκε.',
        ),
        'Η διαγραφή ολοκληρώθηκε.',
      );
    });
  });

  group('τα ονόματα που χωρούν στη γραμμή', () {
    test('λίγα ονόματα μπαίνουν ακέραια', () {
      final shown = departmentDeletionNames(const [
        'Ακτινολογικό',
        'Παθολογικό',
      ]);
      expect(shown.display, 'Ακτινολογικό, Παθολογικό');
      expect(shown.allNames, 'Ακτινολογικό, Παθολογικό');
    });

    // Η υπόδειξη κρατά ΟΛΑ τα ονόματα — αλλιώς όσα κόπηκαν χάνονται.
    test('πολλά ονόματα κόβονται, αλλά η υπόδειξη τα κρατά όλα', () {
      final many = List.generate(12, (i) => 'Τμήμα $i');
      final shown = departmentDeletionNames(many);
      expect(shown.display.endsWith('...'), isTrue);
      expect(shown.display.length, lessThan(shown.allNames!.length));
      expect(shown.allNames, many.join(', '));
    });

    test('τμήμα χωρίς όνομα γράφεται ως ερωτηματικό', () {
      expect(departmentDeletionNames(const ['   ']).display, '?');
    });

    test('καμία διαγραφή δεν δίνει ούτε υπόδειξη', () {
      final shown = departmentDeletionNames(const []);
      expect(shown.display, '');
      expect(shown.allNames, isNull);
    });
  });
}
