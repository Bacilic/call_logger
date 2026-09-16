import 'dart:io';

import 'package:call_logger/core/services/crash_log_service.dart';
import 'package:call_logger/core/services/session_liveness_mark.dart';
import 'package:call_logger/core/services/station_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  late Directory tempRoot;
  late Directory logsDir;
  late CrashLogService service;
  final fixedNow = DateTime(2026, 7, 11, 9, 41, 0);

  const thisStation = 'ΣΤΑΘΜΟΣ-ΔΟΚΙΜΗΣ';

  setUp(() async {
    // Καρφωμένος σταθμός: το όνομα του ίχνους εξαρτάται από αυτόν, και ένα
    // τεστ που διαβάζει τον πραγματικό υπολογιστή δίνει άλλο αποτέλεσμα σε
    // κάθε μηχάνημα.
    StationName.reader = () => thisStation;
    tempRoot = await Directory.systemTemp.createTemp('crash_log_test_');
    logsDir = Directory('${tempRoot.path}${Platform.pathSeparator}logs');
    await logsDir.create(recursive: true);
    service = CrashLogService(
      logsDirectory: logsDir.path,
      appVersion: '0.22.2-test',
      now: () => fixedNow,
    );
  });

  tearDown(() async {
    StationName.reader = StationName.defaultReader;
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  /// Το ίχνος «τρέχω τώρα» αυτού του σταθμού.
  File lockFile() => File(
    '${logsDir.path}${Platform.pathSeparator}'
    '${CrashLogService.sessionLockFileNameFor(thisStation)}',
  );

  File todayLogFile() => File(
    '${logsDir.path}${Platform.pathSeparator}${CrashLogService.dailyLogFileName(fixedNow)}',
  );

  Object sampleError([String message = 'Δοκιμαστικό σφάλμα']) =>
      Exception(message);

  StackTrace sampleStack() => StackTrace.fromString(
    '#0      main.<fn> (file:///test.dart:10:5)\n'
    '#1      main (file:///test.dart:5:3)\n',
  );

  group('CrashLogService', () {
    test('logsDirectoryForDatabasePath — φάκελος logs δίπλα στη βάση', () {
      expect(
        CrashLogService.logsDirectoryForDatabasePath(
          r'F:\Data Base\call_logger.db',
        ),
        r'F:\Data Base\logs',
      );
    });

    test('dailyLogFileName — errors_YYYY-MM-DD.log', () {
      expect(
        CrashLogService.dailyLogFileName(fixedNow),
        'errors_2026-07-11.log',
      );
    });

    test('logError — μορφή εγγραφής με ημερομηνία, έκδοση και ένδειξη', () {
      service.logError(
        sampleError('Σφάλμα δοκιμής'),
        sampleStack(),
        fatal: false,
      );

      final content = todayLogFile().readAsStringSync();
      expect(
        content,
        contains('[2026-07-11 09:41:00] v0.22.2-test ΜΗ-ΚΡΙΣΙΜΟ'),
      );
      expect(content, contains('Exception: Σφάλμα δοκιμής'));
      expect(content, contains('#0      main.<fn> (file:///test.dart:10:5)'));
      expect(content, endsWith('\n\n'));
    });

    test('logError — τα συνοδευτικά μπαίνουν στην εγγραφή', () {
      service.logError(
        sampleError('A RenderFlex overflowed by 25 pixels'),
        StackTrace.empty,
        fatal: false,
        diagnostics:
            'Φάση: during layout\n'
            'debugCreator: Column ← Padding ← CallsScreen',
      );

      final content = todayLogFile().readAsStringSync();
      expect(content, contains('debugCreator: Column ← Padding ← CallsScreen'));
      expect(content, contains('Φάση: during layout'));
    });

    test('logError — χωρίς συνοδευτικά η εγγραφή μένει όπως ήταν', () {
      service.logError(sampleError('Απλό'), sampleStack(), fatal: false);

      final content = todayLogFile().readAsStringSync();
      expect(content, contains('Exception: Απλό'));
      expect(content, contains('#0      main.<fn>'));
    });

    test('logError — ΚΡΙΣΙΜΟ για fatal σφάλματα', () {
      service.logError(sampleError('Κρίσιμο'), sampleStack(), fatal: true);

      final content = todayLogFile().readAsStringSync();
      expect(content, contains('ΚΡΙΣΙΜΟ'));
      expect(content, isNot(contains('ΜΗ-ΚΡΙΣΙΜΟ')));
    });

    test(
      'dedup — έως 20 αναλυτικές εγγραφές, μετά σύνοψη επαναλήψεων',
      () async {
        for (var i = 0; i < 25; i++) {
          service.logError(sampleError(), sampleStack(), fatal: false);
        }
        await service.onShutdown();

        final content = todayLogFile().readAsStringSync();
        expect(content.split('#0      main.<fn>').length - 1, 20);
        expect(content, contains('επαναλήφθηκε 5 φορές'));
      },
    );

    test(
      'dedup — γραμμή σύνοψης ανά 100 επαναλήψεις ενώ τρέχει η εφαρμογή',
      () {
        for (var i = 0; i < 120; i++) {
          service.logError(sampleError(), sampleStack(), fatal: false);
        }

        final content = todayLogFile().readAsStringSync();
        expect(content, contains('επαναλήφθηκε 100 φορές'));
      },
    );

    test(
      'onStartup — εκκαθάριση παλαιότερων errors_*.log σύμφωνα με τη ρύθμιση',
      () async {
        for (final day in ['01', '02', '03', '04', '05']) {
          await File(
            '${logsDir.path}${Platform.pathSeparator}errors_2026-06-$day.log',
          ).writeAsString('παλιό');
        }

        await service.onStartup(retentionCount: 3);

        final remaining =
            logsDir
                .listSync()
                .whereType<File>()
                .map((f) => f.uri.pathSegments.last)
                .where((name) => name.startsWith('errors_'))
                .toList()
              ..sort();
        expect(remaining, [
          'errors_2026-06-03.log',
          'errors_2026-06-04.log',
          'errors_2026-06-05.log',
        ]);
      },
    );

    test('onStartup — τα αρχεία συνεδρίας έχουν ΔΙΚΗ ΤΟΥΣ διατήρηση', () async {
      for (final day in ['01', '02', '03', '04', '05']) {
        await File(
          '${logsDir.path}${Platform.pathSeparator}errors_2026-06-$day.log',
        ).writeAsString('παλιό σφάλμα');
        await File(
          '${logsDir.path}${Platform.pathSeparator}session_2026-06-$day.log',
        ).writeAsString('παλιά συνεδρία');
      }

      await service.onStartup(retentionCount: 3);

      List<String> remaining(String prefix) =>
          logsDir
              .listSync()
              .whereType<File>()
              .map((f) => f.uri.pathSegments.last)
              // Μόνο ημερολόγια: το ίχνος «τρέχω τώρα» μοιράζεται το
              // πρόθεμα αλλά δεν είναι αρχείο ημέρας.
              .where((name) => name.startsWith(prefix) && name.endsWith('.log'))
              .toList()
            ..sort();

      expect(
        remaining('session_'),
        [
          'session_2026-06-03.log',
          'session_2026-06-04.log',
          'session_2026-06-05.log',
        ],
        reason: greekExpectMsg(
          'Οι δύο οικογένειες μετρούν χωριστά — μια πολυήμερη σειρά '
          'σφαλμάτων δεν σβήνει το ιστορικό εκκινήσεων',
        ),
      );
      expect(remaining('errors_'), hasLength(3));
    });

    test(
      'onStartup — μαζεύονται ΜΟΝΟ τα παλιά περιστατικά κλεισίματος',
      () async {
        for (final name in [
          'shutdown_trace_2026-06-01_120000.log',
          'shutdown_trace_2026-06-02_17-29-10.log',
          'shutdown_trace_2026-06-03.log',
        ]) {
          await File(
            '${logsDir.path}${Platform.pathSeparator}$name',
          ).writeAsString('παλιό περιστατικό');
        }
        for (final name in [
          'shutdown_trace_current.log',
          'shutdown_trace_ΑΛΛΟΣ-ΣΤΑΘΜΟΣ.log',
        ]) {
          await File(
            '${logsDir.path}${Platform.pathSeparator}$name',
          ).writeAsString('ίχνος που ίσως τρέχει τώρα');
        }

        await service.onStartup(retentionCount: 14);

        final remaining =
            logsDir
                .listSync()
                .whereType<File>()
                .map((f) => f.uri.pathSegments.last)
                .where(
                  (name) => name.startsWith(
                    CrashLogService.legacyShutdownTracePrefix,
                  ),
                )
                .toList()
              ..sort();
        expect(
          remaining,
          ['shutdown_trace_current.log', 'shutdown_trace_ΑΛΛΟΣ-ΣΤΑΘΜΟΣ.log'],
          reason: greekExpectMsg(
            'Τα ίχνη εργασίας δεν αγγίζονται — ούτε το δικό μας που περιμένει '
            'προαγωγή, ούτε άλλου υπολογιστή που ίσως κλείνει αυτή τη στιγμή',
          ),
        );
      },
    );

    test('sessionLogFileName — session_YYYY-MM-DD.log', () {
      expect(
        CrashLogService.sessionLogFileName(fixedNow),
        'session_2026-07-11.log',
      );
    });

    test('appendSessionText — σιωπά όταν ο φάκελος δεν απάντησε', () async {
      final broken = CrashLogService(
        logsDirectory:
            '${tempRoot.path}${Platform.pathSeparator}δεν-υπάρχει'
            '${Platform.pathSeparator}logs',
        appVersion: '1.0.0',
        now: () => fixedNow,
      );
      try {
        await broken.onStartup(
          retentionCount: 14,
          createDirectory: (_) async =>
              throw const FileSystemException('ο φάκελος δεν απαντά'),
        );
      } catch (_) {}

      expect(broken.isDiskAvailable, isFalse);
      broken.appendSessionText('δεν πρέπει να φτάσει πουθενά');
      expect(
        Directory(broken.logsDirectory).existsSync(),
        isFalse,
        reason: greekExpectMsg(
          'Χωρίς δίσκο, το ημερολόγιο συνεδρίας δεν ξαναγγίζει τη διαδρομή',
        ),
      );
    });

    test(
      'onStartup — ίχνος παλιάς μορφής: αναφέρεται, χωρίς εφευρέσεις',
      () async {
        await lockFile().writeAsString('1');

        await service.onStartup(retentionCount: 14);

        final content = todayLogFile().readAsStringSync();
        expect(content, contains(CrashLogService.abnormalTerminationMessage));
        expect(
          content,
          contains('ΚΡΙΣΙΜΟ'),
          reason: greekExpectMsg('Η χαμένη εκτέλεση είναι κρίσιμο συμβάν'),
        );
        expect(lockFile().existsSync(), isTrue);
      },
    );

    test(
      'onStartup — το ίχνος λέει ποια εκτέλεση χάθηκε, πότε και για πόσο',
      () async {
        await lockFile().writeAsString(
          SessionLivenessMark(
            station: 'PC-3',
            version: '0.46.0',
            startedAt: DateTime(2026, 7, 11, 8, 12),
            lastSeen: DateTime(2026, 7, 11, 14, 53),
          ).encode(),
        );

        await service.onStartup(retentionCount: 14);

        final content = todayLogFile().readAsStringSync();
        expect(content, contains('έκδοση 0.46.0'));
        expect(content, contains('σταθμός PC-3'));
        expect(content, contains('ξεκίνησε 11/07/2026 08:12'));
        expect(content, contains('6 ώρες και 41 λεπτά'));
      },
    );

    test(
      'onStartup — ΔΕΝ αναφέρει το ίχνος ΑΛΛΟΥ υπολογιστή ως κατάρρευση',
      () async {
        await File(
          '${logsDir.path}${Platform.pathSeparator}'
          '${CrashLogService.sessionLockFileNameFor('ΑΛΛΟΣ-ΣΤΑΘΜΟΣ')}',
        ).writeAsString(
          SessionLivenessMark(
            station: 'ΑΛΛΟΣ-ΣΤΑΘΜΟΣ',
            version: '0.46.0',
            startedAt: DateTime(2026, 7, 11, 8, 0),
            lastSeen: DateTime(2026, 7, 11, 8, 30),
          ).encode(),
        );

        await service.onStartup(retentionCount: 14);

        expect(
          todayLogFile().existsSync(),
          isFalse,
          reason: greekExpectMsg(
            'Σε κοινόχρηστο φάκελο, το ίχνος του συναδέλφου δεν είναι δική '
            'μας κατάρρευση — και συνήθως ούτε καν κατάρρευση',
          ),
        );
      },
    );

    test('onStartup — το ίχνος ΑΛΛΟΥ υπολογιστή μένει ανέπαφο', () async {
      final other = File(
        '${logsDir.path}${Platform.pathSeparator}'
        '${CrashLogService.sessionLockFileNameFor('ΑΛΛΟΣ-ΣΤΑΘΜΟΣ')}',
      );
      await other.writeAsString('ζωντανό ίχνος');

      await service.onStartup(retentionCount: 14);
      await service.onShutdown();

      expect(
        other.existsSync(),
        isTrue,
        reason: greekExpectMsg(
          'Το κλείσιμό μας δεν σβήνει το ίχνος εκτέλεσης που ίσως τρέχει',
        ),
      );
    });

    test('onShutdown — διαγραφή session.lock και σύνοψη επαναλήψεων', () async {
      await service.onStartup(retentionCount: 14);
      for (var i = 0; i < 25; i++) {
        service.logError(sampleError(), sampleStack(), fatal: false);
      }

      await service.onShutdown();

      expect(lockFile().existsSync(), isFalse);
      final content = todayLogFile().readAsStringSync();
      expect(content, contains('επαναλήφθηκε 5 φορές'));
    });

    test('fail-safe — εξαίρεση μέσα στο service δεν διαδίδεται', () {
      final broken = CrashLogService(
        logsDirectory: '\u0000invalid',
        appVersion: 'test',
        now: () => fixedNow,
      );

      expect(
        () => broken.logError(sampleError(), sampleStack(), fatal: true),
        returnsNormally,
      );
      expect(() => broken.onStartup(retentionCount: 14), throwsA(anything));
      expect(broken.onShutdown, returnsNormally);
    });
  });
}
