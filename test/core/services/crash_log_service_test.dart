import 'dart:io';

import 'package:call_logger/core/services/crash_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempRoot;
  late Directory logsDir;
  late CrashLogService service;
  final fixedNow = DateTime(2026, 7, 11, 9, 41, 0);

  setUp(() async {
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
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

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
      expect(content, contains('[2026-07-11 09:41:00] v0.22.2-test ΜΗ-ΜΟΙΡΑΙΟ'));
      expect(content, contains('Exception: Σφάλμα δοκιμής'));
      expect(content, contains('#0      main.<fn> (file:///test.dart:10:5)'));
      expect(content, endsWith('\n\n'));
    });

    test('logError — ΜΟΙΡΑΙΟ για fatal σφάλματα', () {
      service.logError(
        sampleError('Κρίσιμο'),
        sampleStack(),
        fatal: true,
      );

      final content = todayLogFile().readAsStringSync();
      expect(content, contains('ΜΟΙΡΑΙΟ'));
      expect(content, isNot(contains('ΜΗ-ΜΟΙΡΑΙΟ')));
    });

    test('dedup — έως 20 αναλυτικές εγγραφές, μετά σύνοψη επαναλήψεων', () async {
      for (var i = 0; i < 25; i++) {
        service.logError(sampleError(), sampleStack(), fatal: false);
      }
      await service.onShutdown();

      final content = todayLogFile().readAsStringSync();
      expect(
        content.split('#0      main.<fn>').length - 1,
        20,
      );
      expect(content, contains('επαναλήφθηκε 5 φορές'));
    });

    test('dedup — γραμμή σύνοψης ανά 100 επαναλήψεις ενώ τρέχει η εφαρμογή', () {
      for (var i = 0; i < 120; i++) {
        service.logError(sampleError(), sampleStack(), fatal: false);
      }

      final content = todayLogFile().readAsStringSync();
      expect(content, contains('επαναλήφθηκε 100 φορές'));
    });

    test('onStartup — εκκαθάριση παλαιότερων errors_*.log σύμφωνα με τη ρύθμιση', () async {
      for (final day in ['01', '02', '03', '04', '05']) {
        await File('${logsDir.path}${Platform.pathSeparator}errors_2026-06-$day.log')
            .writeAsString('παλιό');
      }

      await service.onStartup(retentionCount: 3);

      final remaining = logsDir
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
    });

    test(
      'onStartup — ανίχνευση μη ομαλού τερματισμού μέσω session.lock',
      () async {
        await File(
          '${logsDir.path}${Platform.pathSeparator}${CrashLogService.sessionLockFileName}',
        ).writeAsString('1');

        await service.onStartup(retentionCount: 14);

        final content = todayLogFile().readAsStringSync();
        expect(
          content,
          contains(CrashLogService.abnormalTerminationMessage),
        );
        expect(
          File(
            '${logsDir.path}${Platform.pathSeparator}${CrashLogService.sessionLockFileName}',
          ).existsSync(),
          isTrue,
        );
      },
    );

    test('onShutdown — διαγραφή session.lock και σύνοψη επαναλήψεων', () async {
      await service.onStartup(retentionCount: 14);
      for (var i = 0; i < 25; i++) {
        service.logError(sampleError(), sampleStack(), fatal: false);
      }

      await service.onShutdown();

      expect(
        File(
          '${logsDir.path}${Platform.pathSeparator}${CrashLogService.sessionLockFileName}',
        ).existsSync(),
        isFalse,
      );
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
      expect(() => broken.onStartup(retentionCount: 14), returnsNormally);
      expect(broken.onShutdown, returnsNormally);
    });
  });
}
