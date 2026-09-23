// Ο φύλακας που καταλαβαίνει ότι χάθηκε η πρόσβαση στη βάση.
//
// Δύο αποφάσεις φυλάγονται εδώ, και οι δύο ουσιαστικές για τον χειριστή:
// πότε σημαίνει ο συναγερμός, και ποια λωρίδα κερδίζει όταν συμπέσουν.
//
//   flutter test test/core/database/database_reachability_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_reachability.dart';
import 'package:call_logger/core/database/database_switch_success_notice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

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

  group('Πότε λέμε ότι η βάση είναι απασχολημένη', () {
    // Το αρχείο απαντά, αλλά η βάση μένει κλειδωμένη — π.χ. αντίγραφο
    // ασφαλείας από άλλον σταθμό. Ο φύλακας του αρχείου έλεγε «όλα καλά», και
    // ο χειριστής έβλεπε «Χρήστης #2» χωρίς καμία εξήγηση.
    test('μία κλειδωμένη μέτρηση ΔΕΝ ανάβει λωρίδα', () {
      // Κάθε κανονική εγγραφή κλειδώνει τη βάση για κλάσματα δευτερολέπτου.
      final tracker = DatabaseReachabilityTracker();

      expect(
        tracker.recordSample(DatabaseProbeSample.locked),
        DatabaseReachability.ok,
      );
    });

    test('δύο συνεχόμενες κλειδωμένες μετρήσεις: απασχολημένη', () {
      final tracker = DatabaseReachabilityTracker();

      tracker.recordSample(DatabaseProbeSample.locked);

      expect(
        tracker.recordSample(DatabaseProbeSample.locked),
        DatabaseReachability.busy,
      );
    });

    test('η ελευθέρωση σβήνει αμέσως τη λωρίδα', () {
      final tracker = DatabaseReachabilityTracker()
        ..recordSample(DatabaseProbeSample.locked)
        ..recordSample(DatabaseProbeSample.locked);

      expect(
        tracker.recordSample(DatabaseProbeSample.ok),
        DatabaseReachability.ok,
      );
    });

    test('κλειδωμένη και μετά άφταστη: μετρά μόνο η απώλεια', () {
      // Δύο διαφορετικές αιτίες δεν αθροίζονται σε συναγερμό.
      final tracker = DatabaseReachabilityTracker()
        ..recordSample(DatabaseProbeSample.locked);

      expect(
        tracker.recordSample(DatabaseProbeSample.unreachable),
        DatabaseReachability.ok,
      );
      expect(
        tracker.recordSample(DatabaseProbeSample.unreachable),
        DatabaseReachability.lost,
      );
    });

    test('η λήξη της απασχόλησης είναι επιστροφή — οι οθόνες ξαναρωτούν', () {
      // Όσο η βάση ήταν κλειδωμένη, ερωτήματα μπορεί να έληξαν· χωρίς
      // ξαναφόρτωμα οι οθόνες θα έμεναν με το σφάλμα τους.
      expect(
        isDatabaseReturn(DatabaseReachability.busy, DatabaseReachability.ok),
        isTrue,
      );
      expect(
        isDatabaseReturn(DatabaseReachability.ok, DatabaseReachability.ok),
        isFalse,
      );
    });

    test('η απασχολημένη βάση ΔΕΝ σταματά τις επαναλήψεις', () {
      // Το κλείδωμα λύνεται μόνο του· η επανάληψη το γεφυρώνει σιωπηλά.
      DatabaseReachabilitySignal.publish(DatabaseReachability.busy);
      addTearDown(DatabaseReachabilitySignal.resetForTest);

      expect(databaseAwareRetry(0, Exception('database is locked')), isNotNull);
    });
  });

  group('Ποια λωρίδα κερδίζει όταν η βάση είναι απασχολημένη', () {
    test('η χαμένη βάση υπερισχύει της απασχολημένης', () {
      expect(
        topDatabaseBanner(
          showStateNotice: false,
          hasSwitchSuccess: false,
          isUnreachable: true,
          isBusy: true,
        ),
        TopDatabaseBanner.unreachable,
      );
    });

    test('η απασχολημένη υπερισχύει της προειδοποίησης και της επιτυχίας', () {
      expect(
        topDatabaseBanner(
          showStateNotice: true,
          hasSwitchSuccess: true,
          isBusy: true,
        ),
        TopDatabaseBanner.busy,
      );
    });
  });

  group('Ο έλεγχος κλειδώματος', () {
    late Directory dir;
    late String path;

    setUpAll(initSqfliteFfiForTests);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('reachability_lock_test');
      path = p.join(dir.path, 'vasi.db');
      final db = await openDatabase(path, singleInstance: false);
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      await db.close();
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('ελεύθερη βάση: καμία ένδειξη', () async {
      expect(await probeDatabaseLock(path), DatabaseProbeSample.ok);
    });

    test('βάση που την κρατά κάποιος για εγγραφή: κλειδωμένη', () async {
      final holder = await openDatabase(path, singleInstance: false);
      addTearDown(holder.close);
      await holder.execute('BEGIN EXCLUSIVE');
      addTearDown(() => holder.execute('COMMIT'));

      expect(await probeDatabaseLock(path), DatabaseProbeSample.locked);
    });

    test('αρχείο που δεν ανοίγει ως βάση: ΔΕΝ λέγεται απασχολημένο', () async {
      // Άλλο πρόβλημα, με δικό του φρουρό — εδώ θα ήταν ψέμα.
      final text = p.join(dir.path, 'keimeno.db');
      await File(text).writeAsString('απλό κείμενο\n' * 100);

      expect(await probeDatabaseLock(text), DatabaseProbeSample.ok);
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
