// Ο φύλακας ρωτούσε με ΑΝΑΓΝΩΣΗ, ενώ ο χειριστής πονά από τις ΕΓΓΡΑΦΕΣ.
//
// Δοκιμή πεδίου 24/09: ενώ κρατούσε αποκλειστικό κλείδωμα 45 δευτερολέπτων,
// ο διπλανός σταθμός έχασε τον παλμό παρουσίας του στα 18 δευτερόλεπτα —
// και καμία λωρίδα δεν άναψε πουθενά. Το `PRAGMA data_version` του φύλακα
// είναι ανάγνωση, και το κλείδωμα την αφήνει να περάσει.
//
//   flutter test test/core/database/real_stall_lights_the_banner_test.dart

import 'dart:async';

import 'package:call_logger/core/database/database_reachability.dart';
import 'package:call_logger/core/database/database_stall.dart';
import 'package:call_logger/core/database/timeout_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Βάση που απαντά ό,τι της πει ο έλεγχος.
class _FakeDatabase implements Database {
  _FakeDatabase(this._answer);

  final Future<int> Function() _answer;

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) => _answer();

  @override
  String get path => r'\SERVER\share\hospital.db';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Η πράξη που κόλλησε το λέει', () {
    setUp(DatabaseStallReports.resetForTest);
    tearDown(DatabaseStallReports.resetForTest);

    test('πράξη που χτυπά το όριο χρόνου αναφέρει μπλοκάρισμα', () async {
      var reports = 0;
      DatabaseStallReports.listen(() => reports++);

      final db = TimeoutDatabase(
        _FakeDatabase(() => Completer<int>().future),
        timeout: const Duration(milliseconds: 30),
      );

      await expectLater(
        db.rawUpdate('UPDATE operator_presence SET last_seen = ?'),
        throwsA(isA<DatabaseUnresponsiveException>()),
      );
      expect(reports, 1);
    });

    test('πράξη που βρίσκει τη βάση πιασμένη αναφέρει μπλοκάρισμα', () async {
      var reports = 0;
      DatabaseStallReports.listen(() => reports++);

      final db = TimeoutDatabase(
        _FakeDatabase(
          () async => throw Exception('DatabaseException(database is locked)'),
        ),
        timeout: const Duration(seconds: 5),
      );

      await expectLater(db.rawUpdate('UPDATE x SET y = 1'), throwsException);
      expect(reports, 1);
    });

    test('κάθε άλλο σφάλμα ΔΕΝ είναι μπλοκάρισμα', () async {
      // Ένα λάθος ερώτημα δεν έχει καμία σχέση με τη διαθεσιμότητα της βάσης,
      // και μια λωρίδα «απασχολημένη» θα έστελνε τον χειριστή να περιμένει.
      var reports = 0;
      DatabaseStallReports.listen(() => reports++);

      final db = TimeoutDatabase(
        _FakeDatabase(() async => throw Exception('no such column: banana')),
        timeout: const Duration(seconds: 5),
      );

      await expectLater(db.rawUpdate('UPDATE x SET y = 1'), throwsException);
      expect(reports, 0);
    });

    test('πράξη που πετυχαίνει δεν αναφέρει τίποτα', () async {
      var reports = 0;
      DatabaseStallReports.listen(() => reports++);

      final db = TimeoutDatabase(
        _FakeDatabase(() async => 1),
        timeout: const Duration(seconds: 5),
      );

      expect(await db.rawUpdate('UPDATE x SET y = 1'), 1);
      expect(reports, 0);
    });
  });

  group('Ο φύλακας ακούει την πραγματική αποτυχία', () {
    final t0 = DateTime(2026, 9, 24, 20, 23);

    test('μία πραγματική αποτυχία αρκεί για την κίτρινη', () {
      // Δεν είναι δείγμα, είναι ζημιά: κάποιος περίμενε 18 δευτερόλεπτα και
      // έχασε την αποθήκευσή του. Δεν χρειάζεται δεύτερη απόδειξη.
      final tracker = DatabaseReachabilityTracker();

      expect(tracker.recordRealStall(t0), DatabaseReachability.busy);
    });

    test('η πραγματική αποτυχία ΔΕΝ δείχνει νεκρή σύνδεση', () {
      // Το ίδιο όριο των 18 δευτερολέπτων χτυπά και σε κλείδωμα συναδέλφου.
      // Αν αυτό έδειχνε πορτοκαλί, κάθε αργό αντίγραφο ασφαλείας θα ζητούσε
      // από τον χειριστή να κλείσει και να ξανανοίξει την εφαρμογή.
      final tracker = DatabaseReachabilityTracker();

      expect(
        tracker.recordRealStall(t0),
        isNot(DatabaseReachability.staleConnection),
      );
    });

    test('η λωρίδα δεν σβήνει με την πρώτη ανάγνωση που περνά', () {
      // Ακριβώς το σφάλμα που διορθώνουμε: η ανάγνωση του φύλακα περνά μέσα
      // από το κλείδωμα. Αν την πίστευε, η λωρίδα θα ζούσε πέντε δευτερόλεπτα
      // και η υπόσχεσή της («ξαναδοκίμασε μόλις φύγει») θα ήταν ψέμα.
      final tracker = DatabaseReachabilityTracker()..recordRealStall(t0);

      expect(
        tracker.recordSample(
          DatabaseProbeSample.ok,
          now: t0.add(const Duration(seconds: 5)),
        ),
        DatabaseReachability.busy,
      );
    });

    test('μόλις περάσει το παράθυρο, η επιτυχία σβήνει τη λωρίδα', () {
      final tracker = DatabaseReachabilityTracker()..recordRealStall(t0);

      expect(
        tracker.recordSample(
          DatabaseProbeSample.ok,
          now: t0.add(const Duration(minutes: 1)),
        ),
        DatabaseReachability.ok,
      );
    });

    test('ο χαμένος φάκελος υπερισχύει και σβήνει το παράθυρο', () {
      // Η βαρύτερη είδηση παίρνει το τιμόνι, και η επιστροφή του δικτύου
      // πρέπει να φαίνεται αμέσως — όχι να περιμένει το παράθυρο.
      final tracker = DatabaseReachabilityTracker()
        ..recordRealStall(t0)
        ..recordSample(DatabaseProbeSample.unreachable, now: t0)
        ..recordSample(DatabaseProbeSample.unreachable, now: t0);

      expect(tracker.state, DatabaseReachability.lost);
      expect(
        tracker.recordSample(
          DatabaseProbeSample.ok,
          now: t0.add(const Duration(seconds: 2)),
        ),
        DatabaseReachability.ok,
      );
    });

    test('η νεκρή σύνδεση δεν υποβαθμίζεται σε «απασχολημένη»', () {
      // Όταν ο φύλακας έχει ήδη κρίνει τη σύνδεση νεκρή, κάθε πράξη αποτυγχάνει
      // — και κάθε μία θα ανέφερε. Η πορτοκαλί λωρίδα έχει τη σωστή διέξοδο
      // και δεν επιτρέπεται να την αντικαταστήσει η κίτρινη.
      final tracker = DatabaseReachabilityTracker()
        ..recordSample(DatabaseProbeSample.staleConnection, now: t0)
        ..recordSample(DatabaseProbeSample.staleConnection, now: t0);

      expect(tracker.recordRealStall(t0), DatabaseReachability.staleConnection);
    });
  });
}
