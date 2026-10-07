// Όταν η βάση δεν απαντά για λίγο (διακοπή δικτύου, κλείδωμα από άλλον
// σταθμό), ένα σφάλμα που φτάνει ως την κορυφή έβγαζε ολόκληρη την οθόνη
// «Σφάλμα εφαρμογής» (23/09/2026, «το βλέπω συνέχεια στη δουλειά»). Τέτοιο
// σφάλμα αναγνωρίζεται πλέον ως παροδικό: μικρό μήνυμα, όχι πλήρης οθόνη.
//
//   flutter test test/core/errors/transient_database_failure_test.dart

import 'dart:async';
import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/database/timeout_database.dart';
import 'package:call_logger/core/errors/fatal_error_routing.dart';
import 'package:call_logger/core/services/crash_log_service.dart';
import 'package:call_logger/core/services/log_record.dart';
import 'package:call_logger/core/utils/background_task.dart';
import 'package:call_logger/core/widgets/transient_database_notice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/src/exception.dart'
    show SqfliteDatabaseException;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  setUpAll(initSqfliteFfiForTests);

  group('Ποιο σφάλμα είναι παροδική απώλεια της βάσης', () {
    test('η βάση δεν απάντησε εγκαίρως', () {
      expect(
        isTransientDatabaseFailure(
          const DatabaseUnresponsiveException(Duration(seconds: 18), 'execute'),
        ),
        isTrue,
      );
    });

    test('σφάλμα δίσκου/δικτύου — το ίδιο που έπεσε 23/09 στις 22:49', () {
      expect(
        isTransientDatabaseFailure(
          SqfliteDatabaseException(
            'disk I/O error (code 1802)',
            null,
            resultCode: 1802,
          ),
        ),
        isTrue,
      );
    });

    test('πραγματικά κλειδωμένη βάση από άλλη σύνδεση', () async {
      final dir = await Directory.systemTemp.createTemp('transient_lock_');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'vasi.db');
      final holder = await openDatabase(path, singleInstance: false);
      await holder.execute('CREATE TABLE t (id INTEGER)');
      await holder.execute('BEGIN EXCLUSIVE');
      final other = await openDatabase(path, singleInstance: false);
      Object? caught;
      try {
        await other.rawQuery('SELECT count(*) FROM t');
      } catch (e) {
        caught = e;
      } finally {
        await holder.execute('COMMIT');
        await other.close();
        await holder.close();
      }

      expect(caught, isNotNull, reason: 'η βάση έπρεπε να βρεθεί κλειδωμένη');
      expect(isTransientDatabaseFailure(caught!), isTrue);
    });

    test('αποτυχία ανοίγματος βάσης ΜΕΝΕΙ στην οθόνη με τις διεξόδους της', () {
      // Εκεί ο χρήστης χρειάζεται επιλογή άλλου αρχείου, επαναφορά κ.λπ.
      expect(
        isTransientDatabaseFailure(
          DatabaseInitException(
            const DatabaseInitResult(
              status: DatabaseStatus.corruptedOrInvalid,
              message: 'δεν ανοίγει',
            ),
          ),
        ),
        isFalse,
      );
    });

    test('φθορά και άσχετα σφάλματα δεν κρύβονται', () {
      expect(
        isTransientDatabaseFailure(
          SqfliteDatabaseException(
            'database disk image is malformed (code 11)',
            null,
            resultCode: 11,
          ),
        ),
        isFalse,
      );
      expect(isTransientDatabaseFailure(StateError('άλλο')), isFalse);
    });
  });

  group('Το μήνυμα εμφανίζεται μία φορά ανά διακοπή', () {
    test('δεύτερο σφάλμα μέσα στη σιωπή δεν ξαναβγάζει μήνυμα', () {
      final throttle = TransientDatabaseNoticeThrottle(
        quietPeriod: const Duration(seconds: 60),
      );
      final t0 = DateTime(2026, 9, 23, 22, 49);

      expect(throttle.shouldShow(t0), isTrue);
      expect(throttle.shouldShow(t0.add(const Duration(seconds: 30))), isFalse);
      expect(throttle.shouldShow(t0.add(const Duration(seconds: 61))), isTrue);
    });
  });

  group('Φόρτωση στο παρασκήνιο', () {
    test('η αποτυχία της δεν φτάνει ποτέ στην κορυφή', () async {
      final escaped = <Object>[];
      final done = Completer<void>();
      runZonedGuarded(() {
        runBackgroundTask(
          Future<void>(
            () => throw const DatabaseUnresponsiveException(
              Duration(seconds: 18),
              'execute',
            ),
          ),
        );
        Timer(const Duration(milliseconds: 50), done.complete);
      }, (error, _) => escaped.add(error));
      await done.future;

      expect(escaped, isEmpty);
    });
  });

  group('Αποτυχία που την πρόλαβε κλείσιμο της σύνδεσης', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('background_closed_');
      await CrashLogService.initialize(
        databasePath: p.join(dir.path, 'vasi.db'),
        appVersion: 'test',
        retentionCount: 14,
      );
    });

    tearDown(() async {
      CrashLogService.resetForTest();
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    /// Πόσα σφάλματα γράφτηκαν στο ημερολόγιο.
    Future<int> loggedErrors() async {
      final logs = Directory(p.join(dir.path, 'logs'));
      if (!logs.existsSync()) return 0;
      var count = 0;
      for (final file in logs.listSync().whereType<File>()) {
        for (final line in await file.readAsLines()) {
          if (LogRecord.tryParse(line)?.kind == LogKind.error) count++;
        }
      }
      return count;
    }

    /// Εργασία που αποτυγχάνει μόλις της το πεις — όπως η φόρτωση υπαλλήλων
    /// που έπεσε πάνω σε κλειστή βάση στις 19:43:08.
    Future<void> runAndFail({required bool closeConnectionMeanwhile}) async {
      final release = Completer<void>();
      final finished = Completer<void>();
      runBackgroundTask(
        release.future.then<void>((_) {
          finished.complete();
          throw Exception('DatabaseException(error database_closed)');
        }),
      );
      if (closeConnectionMeanwhile) {
        await DatabaseHelper.instance.closeConnection();
      }
      release.complete();
      await finished.future;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    test(
      'κλείσιμο σύνδεσης στη μέση της εργασίας: δεν γράφεται ψεύτικο σφάλμα',
      () async {
        await runAndFail(closeConnectionMeanwhile: true);

        expect(
          await loggedErrors(),
          0,
          reason:
              'Η εφαρμογή έκλεινε (ή άλλαζε βάση) — η εργασία διακόπηκε, δεν '
              'απέτυχε. Ως «σφάλμα» θολώνει κάθε εξαγωγή διαγνωστικών.',
        );
      },
    );

    test('χωρίς κλείσιμο, η πραγματική αποτυχία γράφεται κανονικά', () async {
      await runAndFail(closeConnectionMeanwhile: false);

      expect(await loggedErrors(), 1);
    });
  });
}
