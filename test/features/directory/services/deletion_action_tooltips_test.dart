// Υποδείξεις (tooltip) των κουμπιών απόφασης στους οδηγούς διαγραφής και
// αποδέσμευσης: ενικός/πληθυντικός και υπό όρους τμήματα.
//
//   flutter test test/features/directory/services/deletion_action_tooltips_test.dart

import 'package:call_logger/features/directory/services/asset_disconnect_models.dart';
import 'package:call_logger/features/directory/services/asset_disconnect_texts.dart';
import 'package:call_logger/features/directory/services/department_deletion_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('προεπισκόπηση διαγραφής τμήματος', () {
    test('«Αναλυτικά» δηλώνει ερώτηση ανά τηλέφωνο και εξοπλισμό', () {
      final text = departmentDeletionDetailedTooltip(
        assetCount: 6,
        employeeCount: 0,
      );
      expect(text, contains('κάθε τηλέφωνο και εξοπλισμό ξεχωριστά'));
      expect(text, contains('διαφορετική απόφαση για το καθένα'));
      expect(text, contains('6 ερωτήσεις'));
    });

    test('ένα μόνο στοιχείο δίνει ενικό «ερώτηση»', () {
      final text = departmentDeletionDetailedTooltip(
        assetCount: 1,
        employeeCount: 0,
      );
      expect(text, contains('1 ερώτηση'));
      expect(text, isNot(contains('ερωτήσεις')));
    });

    test('χωρίς κοινόχρηστα δεν αναφέρεται πλήθος ερωτήσεων', () {
      final text = departmentDeletionDetailedTooltip(
        assetCount: 0,
        employeeCount: 3,
      );
      expect(text, isNot(contains('ερωτήσεις')));
      expect(
        text,
        contains('υπαλλήλους'),
        reason: 'Οι υπάλληλοι ρωτιούνται ούτως ή άλλως — πρέπει να το λέει.',
      );
    });

    test('χωρίς υπαλλήλους δεν προστίθεται η φράση για υπαλλήλους', () {
      final text = departmentDeletionDetailedTooltip(
        assetCount: 2,
        employeeCount: 0,
      );
      expect(text, isNot(contains('υπαλλήλους')));
    });

    test('«Μεταφορά όλων» δηλώνει ΜΙΑ ερώτηση και καμία διαγραφή', () {
      final text = departmentDeletionQuickTransferTooltip(assetCount: 6);
      expect(text, contains('Μία ερώτηση για όλα'));
      expect(text, contains('6 στοιχεία'));
      expect(text, contains('Τίποτα δεν διαγράφεται'));
    });

    test('«Διαγραφή» χωρίς εξαρτήματα δηλώνει ότι αναιρείται', () {
      expect(
        departmentDeletionPlainDeleteTooltip(departmentCount: 1),
        allOf(contains('Το τμήμα'), contains('αναιρέσετε')),
      );
      expect(
        departmentDeletionPlainDeleteTooltip(departmentCount: 4),
        contains('Τα 4 τμήματα'),
      );
    });
  });

  group('ενέργειες οδηγού αποδέσμευσης', () {
    test('καθολική διαγραφή δηλώνει προεπισκόπηση πριν την εκτέλεση', () {
      final text = deleteEverythingTooltip(count: 5, scope: 'τα τηλέφωνα');
      expect(text, contains('5 στοιχεία'));
      expect(text, contains('τα τηλέφωνα'));
      expect(
        text,
        contains('επιβεβαιώσετε'),
        reason: 'Το «όλα» δεν πρέπει να διαβάζεται ως άμεση εκτέλεση.',
      );
    });

    test('ένα στοιχείο δίνει ενικό «στοιχείο»', () {
      final text = deleteEverythingTooltip(count: 1, scope: 'ο εξοπλισμός');
      expect(text, contains('1 στοιχείο'));
      expect(text, isNot(contains('1 στοιχεία')));
    });

    test('«Παραμονή — όλα» ονομάζει το τμήμα και αποκλείει διαγραφή', () {
      final text = keepEverythingTooltip(
        count: 3,
        departmentName: 'Ψυχιατρική',
      );
      expect(text, contains('Ψυχιατρική'));
      expect(text, contains('Δεν διαγράφεται τίποτα'));
    });

    test('«Μεταφορά όλων» αντιπαραβάλλει μία ερώτηση με τις πολλές', () {
      final text = transferEverythingTooltip(count: 7);
      expect(text, contains('ένα μόνο τμήμα'));
      expect(text, contains('Μία ερώτηση αντί για 7'));
    });

    test('ατομική «Παραμονή» ονομάζει το τμήμα όταν το ξέρει', () {
      expect(
        keepInDepartmentTooltip(
          SharedAssetDisconnectMode.sharedAsset,
          sourceDepartmentName: 'Ακτινολογικό',
        ),
        contains('«Ακτινολογικό»'),
      );
    });

    test(
      'ατομική «Παραμονή» χωρίς όνομα τμήματος δεν αφήνει κενά εισαγωγικά',
      () {
        final text = keepInDepartmentTooltip(
          SharedAssetDisconnectMode.sharedAsset,
        );
        expect(text, isNot(contains('«»')));
        expect(text, contains('στο τμήμα του'));
      },
    );

    test('ατομική «Διαγραφή» προσαρμόζεται σε τηλέφωνο ή εξοπλισμό', () {
      expect(deleteSingleTooltip(isPhone: true), startsWith('Ο αριθμός'));
      expect(deleteSingleTooltip(isPhone: false), startsWith('Ο εξοπλισμός'));
    });

    test('ατομική «Μεταφορά» δηλώνει ότι αφορά μόνο αυτό το στοιχείο', () {
      final text = transferSingleTooltip();
      expect(text, contains('μόνο αυτό το στοιχείο'));
      expect(text, contains('χωριστά'));
    });
  });

  group('καμία υπόδειξη δεν περιέχει markdown', () {
    test('οι υποδείξεις είναι σκέτο κείμενο — το Tooltip δεν το αποδίδει', () {
      final texts = <String>[
        departmentDeletionDetailedTooltip(assetCount: 3, employeeCount: 2),
        departmentDeletionQuickTransferTooltip(assetCount: 3),
        departmentDeletionPlainDeleteTooltip(departmentCount: 2),
        deleteEverythingTooltip(count: 2, scope: 'τα πάντα'),
        keepEverythingTooltip(count: 2, departmentName: 'Τμήμα'),
        transferEverythingTooltip(count: 2),
        transferSingleTooltip(),
        deleteSingleTooltip(isPhone: true),
        keepInDepartmentTooltip(SharedAssetDisconnectMode.sharedAsset),
      ];
      for (final t in texts) {
        expect(t, isNot(contains('**')), reason: 'markdown σε tooltip: $t');
        expect(t.trim(), isNotEmpty);
      }
    });
  });
}
