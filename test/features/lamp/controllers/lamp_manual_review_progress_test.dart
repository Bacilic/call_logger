// Πρόοδος στη σειρά χειροκίνητων βημάτων επίλυσης της Λάμπας.
//
// Δύο μετρήσεις με διαφορετικό νόημα: τα ΒΗΜΑΤΑ λένε πόσες φορές θα ρωτηθεί ο
// χρήστης, οι ΠΡΟΤΑΣΕΙΣ πόσα από τα σφάλματα που είδε στη λίστα καλύφθηκαν.
//
//   flutter test test/features/lamp/controllers/lamp_manual_review_progress_test.dart

import 'package:call_logger/features/lamp/controllers/lamp_manual_review_progress.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

void main() {
  LampManualReviewProgress at({
    int step = 3,
    int steps = 47,
    int done = 12,
    int total = 121,
  }) => LampManualReviewProgress(
    stepNumber: step,
    totalSteps: steps,
    proposalsDone: done,
    totalProposals: total,
  );

  group('ετικέτες', () {
    test('θέση, εναπομείναντα και προτάσεις', () {
      final p = at();

      expect(p.stepLabel, 'Βήμα 3 από 47');
      expect(p.remainingLabel, 'απομένουν 44');
      expect(
        p.proposalsLabel,
        '12 από 121 προτάσεις',
        reason: greekExpectMsg(
          'Το 121 είναι ο αριθμός που είδε ο χρήστης ως σφάλματα — χωρίς '
          'αυτόν δεν συνδέει την πρόοδο με ό,τι ξεκίνησε',
        ),
      );
    });

    test('ενικός στο ένα εναπομείναν', () {
      expect(at(step: 46, steps: 47).remainingLabel, 'απομένει 1');
    });

    test('στο τελευταίο βήμα δεν απομένει τίποτα', () {
      expect(at(step: 47, steps: 47).remainingLabel, 'τελευταίο βήμα');
      expect(at(step: 47, steps: 47).remainingSteps, 0);
    });

    test('μοναδικό βήμα είναι εξαρχής το τελευταίο', () {
      final p = at(step: 1, steps: 1);
      expect(p.stepLabel, 'Βήμα 1 από 1');
      expect(p.remainingLabel, 'τελευταίο βήμα');
    });
  });

  group('μπάρα προόδου', () {
    test('οδηγείται από τις προτάσεις, όχι τα βήματα', () {
      // Βήμα 1 από 2, αλλά το πρώτο κάλυψε ήδη 90 από 100 προτάσεις.
      final p = at(step: 1, steps: 2, done: 90, total: 100);

      expect(
        p.fraction,
        0.9,
        reason: greekExpectMsg(
          'Ένα βήμα που καλύπτει 30 όμοιες εγγραφές είναι πολύ μεγαλύτερη '
          'πρόοδος από ένα που καλύπτει μία — η μπάρα πρέπει να το δείχνει',
        ),
      );
    });

    test('ξεκινά στο μηδέν και δεν ξεπερνά τη μονάδα', () {
      expect(at(done: 0, total: 121).fraction, 0);
      expect(at(done: 200, total: 121).fraction, 1);
      expect(at(done: -5, total: 121).fraction, 0);
    });

    test('χωρίς προτάσεις δεν διαιρεί με το μηδέν', () {
      expect(at(done: 0, total: 0).fraction, 0);
    });
  });

  test('άγνωστο σύνολο βημάτων: σκέτη θέση χωρίς ψευδή ακρίβεια', () {
    expect(at(step: 3, steps: 0).stepLabel, 'Βήμα 3');
  });
}
