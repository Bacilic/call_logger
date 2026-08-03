// Τα μηνύματα της ροής «νέα βάση» ανακοινώνουν το ΠΡΑΓΜΑΤΙΚΟ όνομα που θα
// πάρει η τρέχουσα βάση — ίδια συνάρτηση με αυτήν που κάνει τη μετονομασία.
//
//   flutter test test/features/database/services/create_new_database_texts_test.dart

import 'package:call_logger/core/database/database_file_bundle.dart';
import 'package:call_logger/features/database/services/create_new_database_texts.dart';
import 'package:flutter_test/flutter_test.dart';

/// Σταθερή στιγμή αναφοράς: χωρίς αυτήν το τεστ κοκκινίζει μία μέρα τον χρόνο.
final _fixedNow = DateTime(2026, 8, 2, 14, 30);

String _renamedFor(String path, {bool Function(String)? exists}) {
  return resolveRenamedOldDatabaseFileName(
    currentDatabasePath: path,
    now: _fixedNow,
    fileExists: exists ?? (_) => false,
  );
}

void main() {
  group('όνομα μετονομασίας — μία πηγή αλήθειας', () {
    test('το όνομα φέρει το «_old_» και την ημερομηνία', () {
      expect(
        _renamedFor(r'F:\Data Base\Hospital.db'),
        'Hospital_old_02-08-2026.db',
      );
    });

    test('αν το όνομα της ημέρας υπάρχει ήδη, κλιμακώνει σε ώρα', () {
      final taken = {'Hospital_old_02-08-2026.db'};
      final name = _renamedFor(
        r'F:\Data Base\Hospital.db',
        exists: (full) => taken.any(full.endsWith),
      );
      expect(name, 'Hospital_old_02-08-2026_14-30.db');
    });

    test('κενή διαδρομή δίνει κενό όνομα αντί για σκουπίδια', () {
      expect(_renamedFor('   '), '');
    });
  });

  group('οδηγία κάτω από τον τίτλο', () {
    test('δείχνει το πραγματικό όνομα ως ξεχωριστό, τονίσιμο κομμάτι', () {
      final parts = currentDatabaseRenameNotice(
        renamedFileName: _renamedFor(r'F:\Data Base\Hospital.db'),
      );
      expect(parts.fileName, 'Hospital_old_02-08-2026.db');
      expect(parts.before, contains('μετονομάζεται'));
      expect(parts.after, contains('χωρίς διαγραφή'));
      expect(
        '${parts.before}${parts.fileName}${parts.after}',
        isNot(contains('όνομα_old_ημερομηνία')),
        reason: 'Το placeholder δεν επιτρέπεται να επιβιώνει.',
      );
    });

    test('χωρίς ενεργή βάση πέφτει σε γενική διατύπωση χωρίς κενό όνομα', () {
      final parts = currentDatabaseRenameNotice(renamedFileName: '');
      expect(parts.fileName, isEmpty);
      expect(parts.before, contains('κατάληξη ημερομηνίας'));
      expect(parts.before, isNot(contains('««')));
    });
  });

  group('διάλογοι επιβεβαίωσης', () {
    test('η νέα διαδρομή αναφέρεται μαζί με το πραγματικό παλιό όνομα', () {
      final parts = createNewDatabaseConfirmation(
        targetPath: r'F:\Data Base\dokimi.db',
        renamedFileName: _renamedFor(r'F:\Data Base\Hospital.db'),
      );
      expect(parts.before, contains(r'F:\Data Base\dokimi.db'));
      expect(parts.fileName, 'Hospital_old_02-08-2026.db');
      expect(parts.after, contains('επανασυνδεθεί'));
    });

    test('αντικατάσταση στη θέση της τρέχουσας δείχνει επίσης το όνομα', () {
      final parts = replaceCurrentDatabaseConfirmation(
        targetPath: r'F:\Data Base\Hospital.db',
        renamedFileName: _renamedFor(r'F:\Data Base\Hospital.db'),
      );
      expect(parts.fileName, 'Hospital_old_02-08-2026.db');
      expect(parts.after, contains(r'F:\Data Base\Hospital.db'));
    });

    test('κανένα μήνυμα δεν κρατά το παλιό placeholder', () {
      final all = <RenameNoticeParts>[
        createNewDatabaseConfirmation(
          targetPath: 'x.db',
          renamedFileName: 'a_old_02-08-2026.db',
        ),
        replaceCurrentDatabaseConfirmation(
          targetPath: 'x.db',
          renamedFileName: 'a_old_02-08-2026.db',
        ),
        currentDatabaseRenameNotice(renamedFileName: 'a_old_02-08-2026.db'),
      ];
      for (final p in all) {
        final whole = '${p.before}${p.fileName}${p.after}';
        expect(whole, isNot(contains('όνομα_old_ημερομηνία')));
        expect(whole, isNot(contains('όνομα_αρχείου_old_ημερομηνία')));
      }
    });
  });

  group('υπόδειξη κουμπιού', () {
    test('αναφέρει και τα δύο βήματα και την προεπιλογή ονόματος', () {
      final text = createNewDatabaseButtonTooltip(
        suggestedFileName: 'call_logger_2026-08-02.db',
      );
      expect(text, contains('εξερεύνηση των Windows'));
      expect(text, contains('τοποθεσία και όνομα'));
      expect(text, contains('(προεπιλογή: call_logger_2026-08-02.db)'));
      expect(text, contains('επιβεβαίωση'));
    });

    test('χωρίς προτεινόμενο όνομα δεν αφήνει κενή παρένθεση', () {
      final text = createNewDatabaseButtonTooltip(suggestedFileName: '  ');
      expect(text, isNot(contains('(προεπιλογή')));
      expect(text, isNot(contains('()')));
      expect(text, contains('εξερεύνηση των Windows'));
    });
  });
}
