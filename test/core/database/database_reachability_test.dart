// Ο φύλακας που καταλαβαίνει ότι χάθηκε η πρόσβαση στη βάση.
//
// Δύο αποφάσεις φυλάγονται εδώ, και οι δύο ουσιαστικές για τον χειριστή:
// πότε σημαίνει ο συναγερμός, και ποια λωρίδα κερδίζει όταν συμπέσουν.
//
//   flutter test test/core/database/database_reachability_test.dart

import 'package:call_logger/core/database/database_reachability.dart';
import 'package:call_logger/core/database/database_switch_success_notice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Πότε λέμε ότι χάθηκε η βάση', () {
    test('μία αποτυχία ΔΕΝ σημαίνει συναγερμό', () {
      // Μια στιγμιαία αναλαμπή του δικτύου δεν πρέπει να πετά κόκκινη λωρίδα
      // στα μούτρα του χειριστή τη στιγμή που γράφει μια κλήση.
      final tracker = DatabaseReachabilityTracker();

      expect(tracker.record(probeSucceeded: false), DatabaseReachability.ok);
    });

    test('δύο συνεχόμενες αποτυχίες σημαίνουν συναγερμό', () {
      final tracker = DatabaseReachabilityTracker();

      tracker.record(probeSucceeded: false);

      expect(tracker.record(probeSucceeded: false), DatabaseReachability.lost);
    });

    test('μία επιτυχία στο ενδιάμεσο μηδενίζει τον μετρητή', () {
      final tracker = DatabaseReachabilityTracker();

      tracker.record(probeSucceeded: false);
      tracker.record(probeSucceeded: true);

      expect(tracker.record(probeSucceeded: false), DatabaseReachability.ok);
    });

    test('η επιστροφή είναι άμεση — μία επιτυχία σβήνει τον συναγερμό', () {
      // Όταν το δίκτυο γυρίσει, δεν έχει νόημα να κρατάμε τον χειριστή σε
      // συναγερμό περιμένοντας δεύτερη επιβεβαίωση.
      final tracker = DatabaseReachabilityTracker();

      tracker.record(probeSucceeded: false);
      tracker.record(probeSucceeded: false);

      expect(tracker.record(probeSucceeded: true), DatabaseReachability.ok);
    });
  });

  group('Ποια λωρίδα κερδίζει', () {
    test(
      'η χαμένη βάση υπερισχύει και της προειδοποίησης και της επιτυχίας',
      () {
        // Μια «παλιά βάση» ή ένα «άλλαξε η βάση» είναι παραπλανητικά όσο το
        // αρχείο δεν απαντά καν.
        expect(
          topDatabaseBanner(
            showStateNotice: true,
            hasSwitchSuccess: true,
            isUnreachable: true,
          ),
          TopDatabaseBanner.unreachable,
        );
      },
    );

    test('χωρίς απώλεια, η σειρά προτεραιότητας μένει όπως ήταν', () {
      expect(
        topDatabaseBanner(showStateNotice: true, hasSwitchSuccess: true),
        TopDatabaseBanner.warning,
      );
      expect(
        topDatabaseBanner(showStateNotice: false, hasSwitchSuccess: true),
        TopDatabaseBanner.success,
      );
      expect(
        topDatabaseBanner(showStateNotice: false, hasSwitchSuccess: false),
        TopDatabaseBanner.none,
      );
    });
  });

  group('Ρυθμός ελέγχου', () {
    test('ο ρυθμός συναγερμού είναι αισθητά πυκνότερος του ήρεμου', () {
      // Ο χειριστής παραπονέθηκε ότι «άργησε»: με έναν μόνο ρυθμό, η
      // ειδοποίηση αργούσε ως ένα λεπτό και η ΕΠΙΣΤΡΟΦΗ άλλο τόσο.
      expect(
        DatabaseReachabilityNotifier.alertInterval,
        lessThan(DatabaseReachabilityNotifier.calmInterval),
      );
    });

    test('ο ήρεμος ρυθμός δεν κουράζει τον κοινόχρηστο φάκελο', () {
      // Δεκάδες σταθμοί ρωτούν το ίδιο αρχείο· κάθε δευτερόλεπτο μετράει.
      expect(
        DatabaseReachabilityNotifier.calmInterval,
        greaterThanOrEqualTo(const Duration(seconds: 15)),
      );
    });
  });

  group('Ο έλεγχος του αρχείου', () {
    test('διαδρομή που δεν υπάρχει δηλώνεται ως μη προσβάσιμη', () async {
      // Σε άφταστη διαδρομή δικτύου τα Windows ΠΕΤΟΥΝ αντί να απαντήσουν
      // «δεν υπάρχει» — ο έλεγχος οφείλει να το αντέχει και να μη σκάει.
      final ok = await probeDatabaseFile(
        r'\\anyparkto.local\den\yparxei\vasi.db',
        timeout: const Duration(seconds: 2),
      );

      expect(ok, isFalse);
    });

    test('κενή διαδρομή δεν σημαίνει απώλεια', () async {
      // Πριν επιλεγεί βάση δεν υπάρχει τίποτα να χαθεί· ένας συναγερμός εδώ
      // θα ήταν ψέμα.
      expect(await probeDatabaseFile('   '), isTrue);
    });
  });
}
