// Η ΖΩΝΤΑΝΗ σύνδεση πέθανε — ο φύλακας οφείλει να το δει.
//
// Το σενάριο του πεδίου (23/09, δίκτυο δοκιμών): στιγμιαία διακοπή, και από
// εκεί και πέρα κάθε εγγραφή της ανοιχτής σύνδεσης αποτυγχάνει με «disk I/O
// error (code 1802)» — για πάνω από είκοσι λεπτά. Το αρχείο όμως απαντούσε
// κανονικά και μια ΚΑΙΝΟΥΡΓΙΑ σύνδεση δούλευε αμέσως, οπότε ο φύλακας, που
// ρωτούσε ακριβώς αυτά τα δύο, έλεγε «όλα καλά».
//
//   flutter test test/core/database/live_connection_death_test.dart

import 'dart:async';

import 'package:call_logger/core/database/database_reachability.dart';
import 'package:call_logger/core/database/database_switch_success_notice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Σύνδεση που απαντά ό,τι της πει το τεστ.
class _FakeConnection implements DatabaseExecutor {
  _FakeConnection(this._answer);

  final Future<List<Map<String, Object?>>> Function() _answer;
  int queries = 0;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    queries++;
    return _answer();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Τι σημαίνει ένα σφάλμα της ζωντανής σύνδεσης', () {
    test('σφάλμα εισόδου/εξόδου σημαίνει νεκρή σύνδεση', () {
      // Το ακριβές μήνυμα του πεδίου.
      expect(
        classifyLiveConnectionError(
          Exception('DatabaseException(disk I/O error (code 1802))'),
        ),
        DatabaseProbeSample.staleConnection,
      );
    });

    test('κλειδωμένη βάση ΔΕΝ είναι νεκρή σύνδεση', () {
      // Το κλείδωμα λύνεται μόνο του· η νεκρή σύνδεση όχι. Αν τα δύο
      // μπερδεύονταν, κάθε αντίγραφο ασφαλείας συναδέλφου θα έδειχνε «χάθηκε
      // η βάση» αντί για «απασχολημένη».
      expect(
        classifyLiveConnectionError(
          Exception('DatabaseException(database is locked)'),
        ),
        DatabaseProbeSample.locked,
      );
      expect(
        classifyLiveConnectionError(Exception('SQLITE_BUSY')),
        DatabaseProbeSample.locked,
      );
    });

    test('κλειστή σύνδεση σημαίνει νεκρή σύνδεση', () {
      expect(
        classifyLiveConnectionError(Exception('error database_closed')),
        DatabaseProbeSample.staleConnection,
      );
    });
  });

  group('Το ερώτημα στη ζωντανή σύνδεση', () {
    test('χωρίς ανοιχτή σύνδεση δεν λέει τίποτα', () async {
      // Η άγνοια δεν ανάβει λωρίδα: πριν ανοίξει η βάση δεν υπάρχει σύνδεση
      // να κριθεί, και οι υπόλοιποι έλεγχοι του φύλακα αναλαμβάνουν.
      expect(await probeLiveConnection(null), isNull);
    });

    test('σύνδεση που απαντά είναι εντάξει', () async {
      final db = _FakeConnection(
        () async => [
          {'data_version': 7},
        ],
      );

      expect(await probeLiveConnection(db), DatabaseProbeSample.ok);
      expect(db.queries, 1);
    });

    test('σύνδεση που πετά σφάλμα I/O κρίνεται άφταστη', () async {
      final db = _FakeConnection(
        () async => throw Exception('disk I/O error (code 1802)'),
      );

      expect(
        await probeLiveConnection(db),
        DatabaseProbeSample.staleConnection,
      );
    });

    test('σύνδεση που δεν απαντά ποτέ κρίνεται άφταστη', () async {
      // Ακριβώς το «η βάση δεν απάντησε σε 18 δευτερόλεπτα» του PICINIO.
      final db = _FakeConnection(
        () => Completer<List<Map<String, Object?>>>().future,
      );

      expect(
        await probeLiveConnection(
          db,
          timeout: const Duration(milliseconds: 50),
        ),
        DatabaseProbeSample.staleConnection,
      );
    });
  });

  group('Από το σφάλμα ως τη λωρίδα', () {
    test('δύο συνεχόμενες αποτυχίες της ζωντανής σύνδεσης ανάβουν λωρίδα', () {
      final tracker = DatabaseReachabilityTracker();

      tracker.recordSample(DatabaseProbeSample.staleConnection);
      expect(
        tracker.recordSample(DatabaseProbeSample.staleConnection),
        DatabaseReachability.staleConnection,
        reason:
            'επί είκοσι λεπτά ο χειριστής δεν έμαθε ποτέ ότι τίποτα δεν '
            'γράφεται',
      );
    });

    test('μία μόνο αποτυχία ΔΕΝ ανάβει λωρίδα', () {
      // Μια στιγμιαία αναλαμπή δεν διακόπτει τον άνθρωπο που γράφει κλήση.
      expect(
        DatabaseReachabilityTracker().recordSample(
          DatabaseProbeSample.staleConnection,
        ),
        DatabaseReachability.ok,
      );
    });

    test('η νεκρή σύνδεση ΔΕΝ εμφανίζεται ως χαμένος φάκελος', () {
      // Οι δύο καταστάσεις λένε άλλο πράγμα στον άνθρωπο: στη μία η αναμονή
      // έχει νόημα, στην άλλη μόνο το νέο άνοιγμα.
      final tracker = DatabaseReachabilityTracker()
        ..recordSample(DatabaseProbeSample.staleConnection)
        ..recordSample(DatabaseProbeSample.staleConnection);

      expect(tracker.state, isNot(DatabaseReachability.lost));
      expect(tracker.state, isNot(DatabaseReachability.busy));
    });

    test('ο χαμένος φάκελος υπερισχύει της νεκρής σύνδεσης', () {
      final tracker = DatabaseReachabilityTracker()
        ..recordSample(DatabaseProbeSample.staleConnection)
        ..recordSample(DatabaseProbeSample.staleConnection)
        ..recordSample(DatabaseProbeSample.unreachable);

      expect(
        tracker.recordSample(DatabaseProbeSample.unreachable),
        DatabaseReachability.lost,
      );
    });

    test('μία επιτυχία σβήνει αμέσως τη λωρίδα', () {
      final tracker = DatabaseReachabilityTracker()
        ..recordSample(DatabaseProbeSample.staleConnection)
        ..recordSample(DatabaseProbeSample.staleConnection);

      expect(
        tracker.recordSample(DatabaseProbeSample.ok),
        DatabaseReachability.ok,
      );
    });
  });

  group('Η διέξοδος του ανθρώπου', () {
    setUp(DatabaseReachabilitySignal.resetForTest);
    tearDown(DatabaseReachabilitySignal.resetForTest);

    test('η νεκρή σύνδεση σταματά τις άσκοπες επαναλήψεις', () {
      // Καμία επανάληψη δεν πρόκειται να πετύχει πάνω σε νεκρή σύνδεση· η
      // μόνη τους συνεισφορά θα ήταν να κρύβουν το σφάλμα πίσω από κύκλο
      // φόρτωσης, τη στιγμή που ο άνθρωπος πρέπει να δει τη λωρίδα.
      DatabaseReachabilitySignal.publish(DatabaseReachability.staleConnection);

      expect(DatabaseReachabilitySignal.isLost, isTrue);
      expect(databaseAwareRetry(1, Exception('boom')), isNull);
    });

    test('η λωρίδα της νεκρής σύνδεσης είναι ΔΙΚΗ της, όχι η κόκκινη', () {
      expect(
        topDatabaseBanner(
          showStateNotice: false,
          hasSwitchSuccess: false,
          isStaleConnection: true,
        ),
        TopDatabaseBanner.staleConnection,
      );
    });
  });

  group('Η σειρά των ελέγχων — δοκιμή πεδίου 24/09', () {
    test('επίμονη σιωπή της δικής μας σύνδεσης = ΝΕΚΡΗ ΣΥΝΔΕΣΗ', () {
      // Αυτό ακριβώς μετρήθηκε στο πεδίο: το αρχείο απαντούσε, το δίκτυο
      // είχε επανέλθει, και μόνο η δική μας σύνδεση σώπαινε.
      final tracker = DatabaseReachabilityTracker()
        ..recordSample(DatabaseProbeSample.staleConnection);

      expect(
        tracker.recordSample(DatabaseProbeSample.staleConnection),
        DatabaseReachability.staleConnection,
        reason:
            'η κίτρινη «απασχολημένη» έκρυβε την αλήθεια και ο χειριστής '
            'περίμενε επιστροφή που δεν ερχόταν ποτέ',
      );
    });

    test('το κατώφλι σιωπής αφήνει περιθώριο στο κλείδωμα συναδέλφου', () {
      // Τρία δείγματα με ρυθμό πέντε δευτερολέπτων ≈ 15''. Ένα αντίγραφο
      // ασφαλείας συναδέλφου (μετρημένο: 12'') προλαβαίνει να τελειώσει πριν
      // χαρακτηριστεί νεκρή η σύνδεση.
      expect(
        DatabaseReachabilityNotifier.silentBeatsBeforeStale,
        greaterThanOrEqualTo(3),
      );
    });

    test('κλειδωμένη από άλλον σταθμό παραμένει «απασχολημένη»', () {
      // Όσο η σιωπή είναι νεαρή, το κλείδωμα εξηγεί την καθυστέρηση και έχει
      // τη δική του, ηπιότερη λωρίδα.
      final tracker = DatabaseReachabilityTracker()
        ..recordSample(DatabaseProbeSample.locked);

      expect(
        tracker.recordSample(DatabaseProbeSample.locked),
        DatabaseReachability.busy,
      );
    });
  });
}
