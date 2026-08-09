// Ταύτιση ονομάτων υπαλλήλων που διαφέρουν σε λίγα γράμματα.
//
// Τα ζεύγη είναι αληθινά, από τη Λάμπα της 08/08: το πρώτο είναι ο ίδιος
// άνθρωπος γραμμένος με δύο τρόπους, το δεύτερο δύο διαφορετικοί άνθρωποι
// που ένα χαλαρό κριτήριο τους μπερδεύει.
//
//   flutter test test/core/database/old_database/lamp_owner_name_similarity_test.dart

import 'package:call_logger/core/database/old_database/lamp_owner_name_similarity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

void main() {
  LampOwnerNameDeviation? deviation(
    String candidateLast,
    String candidateFirst,
    String ownerLast,
    String ownerFirst,
  ) => lampOwnerNameDeviation(
    candidateLastName: candidateLast,
    candidateFirstName: candidateFirst,
    ownerLastName: ownerLast,
    ownerFirstName: ownerFirst,
  );

  group('βρίσκει τον ίδιο άνθρωπο', () {
    test('«Μαλατέστα Καλλή» είναι η «Μαλατέστα Καλή»', () {
      final result = deviation('Μαλατέστα', 'Καλλή', 'Μαλατέστα', 'Καλή');

      expect(
        result,
        isNotNull,
        reason: greekExpectMsg(
          'Ένα «λ» διαφορά έκρυβε υπάλληλο με 21 εξοπλισμούς και ο οδηγός '
          'πρότεινε δημιουργία διπλοεγγραφής',
        ),
      );
      expect(result!.lastNameDistance, 0);
      expect(result.firstNameDistance, 1);
      expect(result.description, 'το μικρό όνομα διαφέρει σε 1 γράμμα');
    });

    test('η απόκλιση μπορεί να είναι και στο επώνυμο', () {
      final result = deviation('Κουτσογκίλα', 'Μαρία', 'Κουτσογκύλα', 'Μαρία');

      expect(result, isNotNull);
      expect(result!.description, 'το επώνυμο διαφέρει σε 1 γράμμα');
    });

    test('οι τόνοι δεν μετρούν ως διαφορά', () {
      final result = deviation('Μαλατεστα', 'Καλη', 'Μαλατέστα', 'Καλή');

      expect(result, isNotNull);
      expect(result!.isExact, isTrue);
      expect(result.description, 'ίδιο όνομα');
    });

    test('δύο γράμματα στο μικρό όνομα περνούν', () {
      expect(deviation('Παππάς', 'Ελευθερία', 'Παππάς', 'Ελευθερίου'), isNotNull);
    });
  });

  group('απορρίπτει διαφορετικούς ανθρώπους', () {
    test('«Δρόσος Βασίλης» δεν είναι ο «Πρόβος Βασίλης»', () {
      expect(
        deviation('Δρόσος', 'Βασίλης', 'Πρόβος', 'Βασίλης'),
        isNull,
        reason: greekExpectMsg(
          'Δύο γράμματα στο επώνυμο σημαίνουν άλλο πρόσωπο· ο «Πρόβος» έχει '
          '14 εξοπλισμούς και θα έδειχνε πειστική επιλογή',
        ),
      );
    });

    test('κοινό μικρό όνομα δεν φτάνει', () {
      expect(deviation('Κυζιρίδου', 'Μαρία', 'Κουτσογκίλα', 'Μαρία'), isNull);
    });

    test('κοινό επώνυμο με άλλο μικρό όνομα δεν φτάνει', () {
      expect(
        deviation('Μαλατέστα', 'Γεωργία', 'Μαλατέστα', 'Καλή'),
        isNull,
        reason: greekExpectMsg(
          'Δύο συνώνυμοι υπάλληλοι υπάρχουν όντως στη βάση — δεν επιτρέπεται '
          'να συγχωνευτούν από μόνοι τους',
        ),
      );
    });

    test('και τα δύο ονόματα αλλού: καμία ανοχή δεν σωρεύεται', () {
      expect(
        deviation('Καλλή', 'Μαλατεστα', 'Καλή', 'Μαλατέστο'),
        isNull,
        reason: greekExpectMsg(
          'Ο κανόνας θέλει το ένα όνομα απόλυτα ίδιο· αλλιώς δύο μικρές '
          'αποκλίσεις μαζί φτιάχνουν άλλον άνθρωπο',
        ),
      );
    });

    test('σε κοντά ονόματα ένα γράμμα είναι ήδη άλλος άνθρωπος', () {
      expect(deviation('Ζωή', 'Άννα', 'Ζωγ', 'Άννα'), isNull);
      expect(deviation('Λύκα', 'Ζωή', 'Λύκα', 'Ζωγ'), isNull);
    });
  });

  group('κενά ονόματα', () {
    test('υπάλληλος χωρίς μικρό όνομα δεν ταιριάζει με ονοματεπώνυμο', () {
      expect(deviation('Μαλατέστα', 'Καλλή', 'Μαλατέστα', ''), isNull);
    });

    test('δύο άδειες εγγραφές δεν είναι ο ίδιος άνθρωπος', () {
      expect(deviation('', '', '', ''), isNull);
      expect(deviation('Μαλατέστα', 'Καλή', '', ''), isNull);
    });

    test('κοινό κενό μικρό όνομα δεν ακυρώνει την ταύτιση επωνύμου', () {
      final result = deviation('ΟΔΗΓΟΙ', '', 'ΟΔΗΓΟΙ', '');
      expect(result, isNotNull);
      expect(result!.isExact, isTrue);
    });
  });
}
