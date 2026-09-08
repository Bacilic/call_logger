// Το συμβόλαιο: **όταν ο φύλακας ξέρει ότι η βάση δεν απαντά, καμία οθόνη δεν
// ξαναδοκιμάζει και καμία δεν δείχνει φόρτωση — το σφάλμα βγαίνει αμέσως.**
//
// Το Riverpod 3 ξαναδοκιμάζει μόνο του κάθε provider που πετάει: 10 φορές, με
// καθυστερήσεις 200ms→6.4s, δηλαδή ~38 δευτερόλεπτα. Όσο κρατούν, η οθόνη
// δείχνει κύκλο φόρτωσης — κάτω από μια κόκκινη λωρίδα που ήδη λέει «δεν
// αποκρίνεται». Ο φύλακας το ξέρει σε ~10 δευτερόλεπτα· απλώς δεν το έλεγε.
//
//   flutter test test/core/database/reachability_stops_retry_test.dart

import 'package:call_logger/core/database/database_reachability.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(DatabaseReachabilitySignal.resetForTest);
  tearDown(DatabaseReachabilitySignal.resetForTest);

  final error = Exception('disk I/O error (code 3338)');

  group('ο κανόνας επανάληψης ακούει τον φύλακα', () {
    test('με τη βάση χαμένη, καμία επανάληψη', () {
      DatabaseReachabilitySignal.publish(DatabaseReachability.lost);

      expect(databaseAwareRetry(0, error), isNull);
      expect(databaseAwareRetry(3, error), isNull);
    });

    test('με τη βάση εντάξει, η επανάληψη μένει ως έχει', () {
      DatabaseReachabilitySignal.publish(DatabaseReachability.ok);

      // Το παροδικό κλείδωμα κοινόχρηστης βάσης λύνεται μόνο του και η
      // επανάληψη το γεφυρώνει — δεν καταργείται.
      expect(
        databaseAwareRetry(0, error),
        ProviderContainer.defaultRetry(0, error),
      );
      expect(databaseAwareRetry(0, error), isNotNull);
    });

    test('η επανάληψη έχει τέλος ακόμη και με τη βάση εντάξει', () {
      DatabaseReachabilitySignal.publish(DatabaseReachability.ok);

      // Δέκα προσπάθειες και τέλος — αυτό είναι το συμβόλαιο του Riverpod, και
      // το φυλάμε ώστε μια αναβάθμιση που το αλλάζει να μη μας βρει αδιάβαστους.
      expect(databaseAwareRetry(9, error), isNotNull);
      expect(databaseAwareRetry(10, error), isNull);
    });
  });

  group('η επιστροφή ξαναφορτώνει — και μόνο η επιστροφή', () {
    test('«χαμένη → εντάξει» είναι επιστροφή', () {
      expect(
        isDatabaseReturn(DatabaseReachability.lost, DatabaseReachability.ok),
        isTrue,
      );
    });

    test('επιτυχημένος έλεγχος σε υγιή βάση ΔΕΝ είναι επιστροφή', () {
      // Αλλιώς η εφαρμογή θα ξαναφόρτωνε τις κοινές όψεις κάθε είκοσι
      // δευτερόλεπτα, σε βάση που μοιράζονται δεκάδες σταθμοί.
      expect(
        isDatabaseReturn(DatabaseReachability.ok, DatabaseReachability.ok),
        isFalse,
      );
    });

    test('η στιγμή της απώλειας ΔΕΝ είναι επιστροφή', () {
      expect(
        isDatabaseReturn(DatabaseReachability.ok, DatabaseReachability.lost),
        isFalse,
      );
    });

    test('η πρώτη μέτρηση της συνεδρίας ΔΕΝ είναι επιστροφή', () {
      expect(isDatabaseReturn(null, DatabaseReachability.ok), isFalse);
    });
  });

  group('ο φύλακας δημοσιεύει κάθε αλλαγή', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('η απώλεια φτάνει στο σήμα', () {
      final notifier = container.read(databaseReachabilityProvider.notifier);
      expect(DatabaseReachabilitySignal.isLost, isFalse);

      // Ο φύλακας θέλει δύο συνεχόμενες αποτυχίες πριν σημάνει συναγερμό.
      notifier.recordProbeResult(succeeded: false);
      expect(DatabaseReachabilitySignal.isLost, isFalse);
      notifier.recordProbeResult(succeeded: false);

      expect(
        DatabaseReachabilitySignal.isLost,
        isTrue,
        reason:
            'Ο φύλακας κατέγραψε την απώλεια αλλά ο κανόνας επανάληψης δεν το '
            'έμαθε ποτέ — οι οθόνες θα συνεχίσουν να ξαναδοκιμάζουν.',
      );
    });

    test('η επιστροφή σβήνει το σήμα με μία επιτυχία', () {
      final notifier = container.read(databaseReachabilityProvider.notifier);
      notifier.recordProbeResult(succeeded: false);
      notifier.recordProbeResult(succeeded: false);
      expect(DatabaseReachabilitySignal.isLost, isTrue);

      notifier.recordProbeResult(succeeded: true);

      expect(DatabaseReachabilitySignal.isLost, isFalse);
    });

    test('το σταμάτημα του φύλακα δεν αφήνει τις οθόνες κλειδωμένες', () {
      final notifier = container.read(databaseReachabilityProvider.notifier);
      notifier.recordProbeResult(succeeded: false);
      notifier.recordProbeResult(succeeded: false);
      expect(DatabaseReachabilitySignal.isLost, isTrue);

      notifier.stop();

      // Χωρίς φύλακα δεν υπάρχει γνώση· η άγνοια δεν επιτρέπεται να κρατά την
      // επανάληψη σβηστή για την υπόλοιπη συνεδρία.
      expect(DatabaseReachabilitySignal.isLost, isFalse);
    });
  });
}
