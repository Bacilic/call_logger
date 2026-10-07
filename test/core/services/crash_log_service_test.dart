import 'dart:io';

import 'package:call_logger/core/services/crash_log_service.dart';
import 'package:call_logger/core/services/log_record.dart';
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
  // Ρητή ταυτότητα εκτέλεσης: η προεπιλογή διαβάζει τη διαδρομή του
  // εκτελέσιμου, οπότε το όνομα του αρχείου θα άλλαζε ανά μηχάνημα.
  const thisInstance = 'ΑΝΤΙΓΡΑΦΟ-ΔΟΚΙΜΗΣ';

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
      instanceId: thisInstance,
    );
  });

  tearDown(() async {
    StationName.reader = StationName.defaultReader;
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  /// Το ίχνος «τρέχω τώρα» αυτής της εκτέλεσης.
  File lockFile() => File(
    '${logsDir.path}${Platform.pathSeparator}'
    '${CrashLogService.sessionLockFileNameFor(thisStation, thisInstance)}',
  );

  /// Το ίχνος όπως το ονόμαζε η έκδοση ΠΡΙΝ μπει η εκτέλεση στο όνομα.
  File legacyLockFile() => File(
    '${logsDir.path}${Platform.pathSeparator}'
    '${CrashLogService.sessionLockFileNameFor(thisStation)}',
  );

  File todayLogFile() => File(
    '${logsDir.path}${Platform.pathSeparator}${CrashLogService.dailyLogFileName(fixedNow)}',
  );

  /// Οι εγγραφές της ημέρας, με τη σειρά που γράφτηκαν.
  List<LogRecord> todayRecords() => todayLogFile()
      .readAsLinesSync()
      .map(LogRecord.tryParse)
      .whereType<LogRecord>()
      .toList();

  Iterable<LogRecord> recordsOf(LogKind kind) =>
      todayRecords().where((record) => record.kind == kind);

  List<String> dailyFiles(bool Function(String name) keep) =>
      logsDir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where(keep)
          .toList()
        ..sort();

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

    test('dailyLogFileName — events_YYYY-MM-DD.jsonl', () {
      expect(
        CrashLogService.dailyLogFileName(fixedNow),
        'events_2026-07-11.jsonl',
      );
    });

    test(
      'logError — μία εγγραφή με ώρα, ΣΤΑΘΜΟ, έκδοση, βαρύτητα και στοίβα',
      () {
        service.logError(
          sampleError('Σφάλμα δοκιμής'),
          sampleStack(),
          fatal: false,
        );

        final records = todayRecords();
        expect(records, hasLength(1));
        final record = records.single;
        expect(record.time, fixedNow);
        expect(
          record.station,
          thisStation,
          reason: greekExpectMsg(
            'Στον κοινό φάκελο, η εγγραφή λέει από ποιον υπολογιστή ήρθε',
          ),
        );
        expect(record.version, '0.22.2-test');
        expect(record.kind, LogKind.error);
        expect(record.severity, LogSeverity.nonCritical);
        expect(record.message, 'Exception: Σφάλμα δοκιμής');
        expect(
          record.details,
          contains('#0      main.<fn> (file:///test.dart:10:5)'),
        );
      },
    );

    test('logError — τα συνοδευτικά μπαίνουν στην εγγραφή', () {
      service.logError(
        sampleError('A RenderFlex overflowed by 25 pixels'),
        StackTrace.empty,
        fatal: false,
        diagnostics:
            'Φάση: during layout\n'
            'debugCreator: Column ← Padding ← CallsScreen',
      );

      final details = todayRecords().single.details;
      expect(details, contains('debugCreator: Column ← Padding ← CallsScreen'));
      expect(details, contains('Φάση: during layout'));
    });

    test('logError — χωρίς συνοδευτικά η εγγραφή μένει όπως ήταν', () {
      service.logError(sampleError('Απλό'), sampleStack(), fatal: false);

      final record = todayRecords().single;
      expect(record.message, 'Exception: Απλό');
      expect(record.details, contains('#0      main.<fn>'));
    });

    test('logError — κρίσιμη βαρύτητα για fatal σφάλματα', () {
      service.logError(sampleError('Κρίσιμο'), sampleStack(), fatal: true);

      expect(todayRecords().single.severity, LogSeverity.critical);
    });

    test(
      'dedup — έως 20 αναλυτικές εγγραφές, μετά σύνοψη επαναλήψεων',
      () async {
        for (var i = 0; i < 25; i++) {
          service.logError(sampleError(), sampleStack(), fatal: false);
        }
        await service.onShutdown();

        expect(recordsOf(LogKind.error), hasLength(20));
        final repeat = recordsOf(LogKind.repeat).single;
        expect(repeat.message, contains('επαναλήφθηκε 5 φορές'));
        expect(repeat.data['count'], 5);
      },
    );

    test(
      'dedup — γραμμή σύνοψης ανά 100 επαναλήψεις ενώ τρέχει η εφαρμογή',
      () {
        for (var i = 0; i < 120; i++) {
          service.logError(sampleError(), sampleStack(), fatal: false);
        }

        expect(
          recordsOf(LogKind.repeat).single.message,
          contains('επαναλήφθηκε 100 φορές'),
        );
      },
    );

    test(
      'onStartup — κρατά τις τελευταίες Ν ΗΜΕΡΕΣ ΜΕ ΚΑΤΑΓΡΑΦΕΣ, όχι ημερολογιακές',
      () async {
        for (final day in ['01', '02', '03', '04', '05']) {
          await File(
            '${logsDir.path}${Platform.pathSeparator}events_2026-06-$day.jsonl',
          ).writeAsString('');
        }

        await service.onStartup(retentionCount: 3);

        expect(
          dailyFiles(CrashLogService.isDailyLogFileName),
          [
            'events_2026-06-03.jsonl',
            'events_2026-06-04.jsonl',
            'events_2026-06-05.jsonl',
          ],
          reason: greekExpectMsg(
            'Υπολογιστής κλειστός έναν μήνα δεν χάνει το ιστορικό του',
          ),
        );
      },
    );

    test(
      'onStartup — τα αρχεία της ΠΑΛΙΑΣ μορφής σβήνονται όταν παλιώσουν',
      () async {
        for (final day in ['05', '06', '07', '08', '09', '10', '11']) {
          for (final prefix in ['errors_', 'session_']) {
            await File(
              '${logsDir.path}${Platform.pathSeparator}$prefix'
              '2026-07-$day.log',
            ).writeAsString('παλιά μορφή');
          }
        }
        final liveMark = File(
          '${logsDir.path}${Platform.pathSeparator}'
          '${CrashLogService.sessionLockFileNameFor('ΑΛΛΟΣ-ΣΤΑΘΜΟΣ')}',
        )..writeAsStringSync('ζωντανό ίχνος');

        await service.onStartup(retentionCount: 3);

        expect(
          dailyFiles(CrashLogService.isLegacyDailyLogFileName),
          [
            'errors_2026-07-09.log',
            'errors_2026-07-10.log',
            'errors_2026-07-11.log',
            'session_2026-07-09.log',
            'session_2026-07-10.log',
            'session_2026-07-11.log',
          ],
          reason: greekExpectMsg(
            'Δεν πληθαίνουν πια, οπότε σβήνονται με την ηλικία τους — όχι '
            'όλα μαζί, γιατί σταθμός με παλιά έκδοση τα γράφει ακόμη',
          ),
        );
        expect(
          liveMark.existsSync(),
          isTrue,
          reason: greekExpectMsg(
            'Το ίχνος «τρέχω τώρα» μοιράζεται το πρόθεμα αλλά δεν είναι '
            'αρχείο ημέρας — δεν αγγίζεται',
          ),
        );
      },
    );

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

    test(
      'appendRecord — η εγγραφή άλλης πηγής σφραγίζεται με σταθμό και έκδοση',
      () {
        service.appendRecord(
          LogRecord(
            time: fixedNow,
            kind: LogKind.startup,
            severity: LogSeverity.info,
            message: 'ΕΚΚΙΝΗΣΗ',
          ),
        );

        final record = todayRecords().single;
        expect(record.station, thisStation);
        expect(record.version, '0.22.2-test');
      },
    );

    test('appendRecord — σιωπά όταν ο φάκελος δεν απάντησε', () async {
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
      broken.appendRecord(
        LogRecord(
          time: fixedNow,
          kind: LogKind.startup,
          severity: LogSeverity.info,
          message: 'δεν πρέπει να φτάσει πουθενά',
        ),
      );
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

        final lost = recordsOf(LogKind.abnormalEnd).single;
        expect(lost.message, CrashLogService.abnormalTerminationMessage);
        expect(
          lost.severity,
          LogSeverity.critical,
          reason: greekExpectMsg('Η χαμένη εκτέλεση είναι κρίσιμο συμβάν'),
        );
        expect(lockFile().existsSync(), isTrue);
        final mark = SessionLivenessMark.decode(lockFile().readAsStringSync());
        expect(
          mark?.instance,
          thisInstance,
          reason: greekExpectMsg(
            'Το νέο ίχνος δηλώνει ποια εκτέλεση το έγραψε',
          ),
        );
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

        final lost = recordsOf(LogKind.abnormalEnd).single;
        expect(lost.message, contains('έκδοση 0.46.0'));
        expect(lost.message, contains('σταθμός PC-3'));
        expect(lost.message, contains('ξεκίνησε 11/07/2026 08:12'));
        expect(lost.message, contains('6 ώρες και 41 λεπτά'));
        expect(
          lost.data['last_seen'],
          DateTime(2026, 7, 11, 14, 53).toIso8601String(),
          reason: greekExpectMsg(
            'Η τελευταία στιγμή ζωής μένει ως στοιχείο, ώστε να συγκριθεί '
            'με τα συμβάντα των Windows της ίδιας ώρας',
          ),
        );
      },
    );

    test(
      'onStartup — το ίχνος της ΠΡΟΗΓΟΥΜΕΝΗΣ ονοματοδοσίας αναφέρεται και μαζεύεται',
      () async {
        // Η έκδοση πριν μπει η εκτέλεση στο όνομα άφηνε «session_<σταθμός>.lock».
        // Χωρίς μάζεμα θα έμενε για πάντα στον κοινόχρηστο φάκελο, και για τρία
        // λεπτά μετά από κάθε εκκίνηση θα περνούσε για ζωντανός συνάδελφος.
        await legacyLockFile().writeAsString(
          SessionLivenessMark(
            station: thisStation,
            version: '0.55.0',
            startedAt: DateTime(2026, 9, 20, 9, 0),
            lastSeen: DateTime(2026, 9, 20, 9, 45),
          ).encode(),
        );

        await service.onStartup(retentionCount: 14);

        expect(
          legacyLockFile().existsSync(),
          isFalse,
          reason: greekExpectMsg('Το ίχνος της παλιάς μορφής δεν μένει πίσω'),
        );
        expect(lockFile().existsSync(), isTrue);
        expect(
          todayLogFile().readAsStringSync(),
          contains('έκδοση 0.55.0'),
          reason: greekExpectMsg('Η χαμένη εκτέλεση εξακολουθεί να αναφέρεται'),
        );
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
      expect(
        recordsOf(LogKind.repeat).single.message,
        contains('επαναλήφθηκε 5 φορές'),
      );
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
