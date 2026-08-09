// Κάρτα «Αντίγραφα της εφαρμογής» — το κείμενο που εξηγεί ΓΙΑΤΙ αυτά τα
// εκτελέσιμα μοιράζονται δεδομένα.
//
// Το μητρώο αντιγράφων αποθηκεύεται με πρόθεμα προφίλ, οπότε η λίστα δείχνει
// πάντα μόνο εκτελέσεις του ΙΔΙΟΥ προφίλ. Αν το κείμενο δεν το πει, ο χρήστης
// βλέπει μια λίστα που μοιάζει με απογραφή του υπολογιστή ενώ δεν είναι.
//
//   flutter test test/core/providers/app_instances_scope_text_test.dart

import 'package:call_logger/core/providers/app_instances_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  group('χωρίς ενεργό προφίλ', () {
    test('ονομάζει την αιτία αντί για παύλα', () {
      final text = appInstancesSharedScopeText(null);

      expect(
        text,
        contains('κανένα δεν τρέχει με προφίλ'),
        reason: greekExpectMsg(
          'Το «Ενεργό προφίλ: —» δεν λέει τίποτα σε όποιον δεν ξέρει τι είναι '
          'το προφίλ· η αιτία πρέπει να γράφεται με λέξεις',
        ),
      );
      expect(text, contains('--profile <όνομα>'));
      expect(
        text,
        isNot(contains('—')),
        reason: greekExpectMsg('Η κρυπτική παύλα δεν επιστρέφει'),
      );
    });

    test('κενό ή διάστημα μετρά ως απουσία προφίλ', () {
      expect(appInstancesSharedScopeText(''), appInstancesSharedScopeText(null));
      expect(
        appInstancesSharedScopeText('   '),
        appInstancesSharedScopeText(null),
      );
    });
  });

  group('με ενεργό προφίλ', () {
    test('ονομάζει το προφίλ και δηλώνει τι ΔΕΝ φαίνεται στη λίστα', () {
      final text = appInstancesSharedScopeText('Test1');

      expect(text, contains('«Test1»'));
      expect(
        text,
        contains('δεν εμφανίζονται εδώ'),
        reason: greekExpectMsg(
          'Χωρίς αυτό, η λίστα διαβάζεται ως πλήρης απογραφή του υπολογιστή '
          'ενώ κρύβει όλες τις εκτελέσεις άλλων προφίλ',
        ),
      );
    });

    test('δεν προτρέπει σε --profile όταν τρέχει ήδη με προφίλ', () {
      expect(
        appInstancesSharedScopeText('Test1'),
        isNot(contains('--profile')),
        reason: greekExpectMsg(
          'Η προτροπή «εκτελέστε με --profile» για κάποιον που ΗΔΗ τρέχει με '
          'προφίλ είναι οδηγία που δεν οδηγεί πουθενά',
        ),
      );
    });

    test('το όνομα του προφίλ μπαίνει αυτούσιο', () {
      expect(appInstancesSharedScopeText('dev'), contains('«dev»'));
      expect(appInstancesSharedScopeText(' Test1 '), contains('«Test1»'));
    });
  });
}
