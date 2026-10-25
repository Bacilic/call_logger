import 'dart:async';
import 'dart:io';

import 'package:call_logger/core/services/crash_log_service.dart';
import 'package:call_logger/core/services/clean_exit_note.dart';
import 'package:call_logger/core/services/log_record.dart';
import 'package:call_logger/core/services/session_liveness_mark.dart';
import 'package:call_logger/core/services/log_spill_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Το συμβόλαιο: **κανένα βήμα της εκκίνησης πριν από την πρώτη οθόνη δεν
/// επιτρέπεται να περιμένει το σύστημα αρχείων χωρίς όριο χρόνου.**
///
/// Το ημερολόγιο καταρρεύσεων ζει δίπλα στη βάση. Όταν η βάση είναι σε
/// δικτυακό φάκελο που δεν απαντά, το στήσιμό του κρεμούσε επ' αόριστον — και
/// επειδή τρέχει πριν από το `runApp()`, ο χρήστης έβλεπε λευκό παράθυρο.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('crash_log_gate');
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  String dbPathInside(Directory dir) => p.join(dir.path, 'call_logger.db');

  test(
    'φάκελος που δεν απαντά ποτέ δεν κρατά την εκκίνηση πάνω από το όριο',
    () async {
      final service = CrashLogService(logsDirectory: p.join(temp.path, 'logs'));

      final stopwatch = Stopwatch()..start();
      await expectLater(
        service.onStartup(
          retentionCount: 5,
          timeout: const Duration(milliseconds: 200),
          // Το δίκτυο που δεν απαντά ποτέ: ένα Future που δεν ολοκληρώνεται.
          createDirectory: (_) => Completer<void>().future,
        ),
        throwsA(isA<TimeoutException>()),
      );
      stopwatch.stop();

      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason: 'η εκκίνηση περίμενε πέρα από το όριο χρόνου',
      );
      expect(service.isDiskAvailable, isFalse);
      expect(service.diskUnavailableReason, isNotNull);
    },
  );

  test(
    'όταν ο δίσκος έχει σβήσει, καμία καταγραφή δεν αγγίζει τη διαδρομή',
    () async {
      final unreachable = p.join(temp.path, 'άφταστος', 'logs');
      final service = CrashLogService(logsDirectory: unreachable);

      await expectLater(
        service.onStartup(
          retentionCount: 5,
          timeout: const Duration(milliseconds: 200),
          createDirectory: (_) => Completer<void>().future,
        ),
        throwsA(isA<TimeoutException>()),
      );

      // Μετά τη σίγαση, η καταγραφή σφάλματος δεν δημιουργεί τίποτα.
      service.logError(StateError('δοκιμή'), StackTrace.current, fatal: true);
      await service.pendingWrites;

      expect(await Directory(unreachable).exists(), isFalse);
    },
  );

  test('όταν ο φάκελος απαντά, το ημερολόγιο δουλεύει κανονικά', () async {
    final logs = p.join(temp.path, 'logs');
    final service = CrashLogService(logsDirectory: logs);

    await service.onStartup(retentionCount: 5);

    expect(service.isDiskAvailable, isTrue);
    expect(await Directory(logs).exists(), isTrue);
  });

  test('η μετακόμιση ξαναδίνει φωνή στο ημερολόγιο', () async {
    final service = CrashLogService(logsDirectory: p.join(temp.path, 'logs'));

    await expectLater(
      service.onStartup(
        retentionCount: 5,
        timeout: const Duration(milliseconds: 200),
        createDirectory: (_) => Completer<void>().future,
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(service.isDiskAvailable, isFalse);

    final elsewhere = await Directory.systemTemp.createTemp('crash_log_local');
    addTearDown(() async {
      if (await elsewhere.exists()) await elsewhere.delete(recursive: true);
    });

    await service.retargetTo(
      databasePath: dbPathInside(elsewhere),
      retentionCount: 5,
    );

    expect(service.isDiskAvailable, isTrue);
    expect(service.logsDirectory, p.join(elsewhere.path, 'logs'));
    expect(await Directory(service.logsDirectory).exists(), isTrue);
  });

  /// Ο διακομιστής σβήνει **ενώ η εφαρμογή δουλεύει** (μετρημένο 14/10/2026
  /// με τον POPINIO: μία σύγχρονη εγγραφή πάγωσε την οθόνη πάνω από 45
  /// δευτερόλεπτα, με μαύρο παράθυρο) και ξανανάβει αργότερα.
  group('σιωπή στη μέση της δουλειάς', () {
    late _Folder folder;
    late CrashLogService service;
    const limit = Duration(milliseconds: 100);

    setUp(() async {
      folder = _Folder();
      service = CrashLogService(
        logsDirectory: p.join(temp.path, 'logs'),
        now: () => DateTime(2026, 10, 14, 17, 46),
        writeFile: folder.write,
        writeTimeout: limit,
      );
      await service.onStartup(retentionCount: 5);
    });

    test(
      'εγγραφή που δεν απαντά δεν κρατά τον καλούντα και σιγεί το ημερολόγιο',
      () async {
        folder.answers = false;

        final stopwatch = Stopwatch()..start();
        service.logError(
          StateError('δοκιμή'),
          StackTrace.current,
          fatal: false,
        );
        stopwatch.stop();

        expect(
          stopwatch.elapsed,
          lessThan(limit),
          reason: 'η καταγραφή περίμενε τον φάκελο αντί να επιστρέψει αμέσως',
        );
        await service.pendingWrites;
        expect(service.isDiskAvailable, isFalse);
        expect(service.diskAvailability.value, isFalse);
      },
    );

    test('όσο σιωπά, καμία καταγραφή δεν ξαναρωτά τον φάκελο', () async {
      folder.answers = false;
      service.logError(StateError('πρώτο'), StackTrace.current, fatal: false);
      await service.pendingWrites;
      final attemptsAtSilence = folder.attempts;

      service.logError(StateError('δεύτερο'), StackTrace.current, fatal: true);
      await service.pendingWrites;

      expect(folder.attempts, attemptsAtSilence);
    });

    test(
      'ο παλμός ξαναζωντανεύει την καταγραφή μόλις ο φάκελος γυρίσει',
      () async {
        folder.answers = false;
        await service.pulseForTest();
        expect(service.isDiskAvailable, isFalse);

        await service.pulseForTest();
        expect(
          service.isDiskAvailable,
          isFalse,
          reason: 'όσο ο φάκελος σωπαίνει, η καταγραφή μένει σιωπηλή',
        );

        folder.answers = true;
        await service.pulseForTest();
        await service.pendingWrites;

        expect(service.isDiskAvailable, isTrue);
        expect(service.diskAvailability.value, isTrue);
        final today = File(
          p.join(
            service.logsDirectory,
            CrashLogService.dailyLogFileName(DateTime(2026, 10, 14)),
          ),
        );
        expect(
          today
              .readAsLinesSync()
              .map(LogRecord.tryParse)
              .map((r) => r?.data['phase']),
          contains('resumed'),
          reason: 'το ημερολόγιο λέει ότι υπήρξε κενό και από πότε',
        );
      },
    );

    test(
      'εγγραφή που απλώς άργησε: η καταγραφή συνεχίζει μόλις εκείνη τελειώσει',
      () async {
        final slow = Completer<void>();
        folder.slowNext = slow;
        service.logError(StateError('αργό'), StackTrace.current, fatal: false);
        await service.pendingWrites;
        expect(service.isDiskAvailable, isFalse);

        slow.complete();
        await Future<void>.delayed(Duration.zero);

        expect(
          service.isDiskAvailable,
          isTrue,
          reason: 'ο φάκελος ζούσε — δεν περιμένουμε τον παλμό του λεπτού',
        );
        await service.pendingWrites;
      },
    );

    test('η σιωπή της εκκίνησης δεν ξαναζωντανεύει από τον παλμό', () async {
      final silent = CrashLogService(
        logsDirectory: p.join(temp.path, 'άλλο', 'logs'),
        writeFile: folder.write,
        writeTimeout: limit,
      );
      await expectLater(
        silent.onStartup(
          retentionCount: 5,
          timeout: limit,
          createDirectory: (_) => Completer<void>().future,
        ),
        throwsA(isA<TimeoutException>()),
      );

      await silent.pulseForTest();

      expect(silent.isDiskAvailable, isFalse);
    });
  });

  /// Η εφαρμογή στον PICINIO δουλεύει στη βάση του POPINIO. Ο POPINIO σβήνει,
  /// και μετά ο χρήστης κλείνει κανονικά την εφαρμογή.
  group('κανονικό κλείσιμο με σιωπηλό φάκελο', () {
    late String sharedLogs;
    late String noteDir;
    final start = DateTime(2026, 10, 22, 20, 54);
    final nextStart = DateTime(2026, 10, 22, 21, 4);

    setUp(() {
      sharedLogs = p.join(temp.path, 'shared', 'logs');
      noteDir = p.join(temp.path, 'session');
    });

    CrashLogService run(DateTime now) => CrashLogService(
      logsDirectory: sharedLogs,
      now: () => now,
      instanceId: 'dev',
      cleanExitNote: CleanExitNote(noteDir),
    );

    Iterable<LogRecord> lostRunsReportedAt(DateTime day) {
      final file = File(
        p.join(sharedLogs, CrashLogService.dailyLogFileName(day)),
      );
      if (!file.existsSync()) return const [];
      return file
          .readAsLinesSync()
          .map(LogRecord.tryParse)
          .whereType<LogRecord>()
          .where(
            (r) =>
                r.kind == LogKind.abnormalEnd && r.time.isAtSameMomentAs(day),
          );
    }

    test('η επόμενη εκκίνηση δεν το αναφέρει ως κατάρρευση', () async {
      final first = run(start);
      await first.onStartup(retentionCount: 5);
      first.disableDiskForTest('ο POPINIO δεν απαντά');
      await first.onShutdown();

      final second = run(nextStart);
      await second.onStartup(retentionCount: 5);

      expect(
        lostRunsReportedAt(nextStart),
        isEmpty,
        reason:
            'η εφαρμογή έκλεισε κανονικά — απλώς ο διακομιστής ήταν σβηστός',
      );
    });

    test('πραγματικό απρόσμενο τέλος αναφέρεται κανονικά', () async {
      final first = run(start);
      await first.onStartup(retentionCount: 5);
      // Χωρίς onShutdown: η διεργασία τερματίστηκε απότομα.

      final second = run(nextStart);
      await second.onStartup(retentionCount: 5);

      expect(lostRunsReportedAt(nextStart), hasLength(1));
    });

    test(
      'σημείωμα παλιότερου κλεισίματος δεν σκεπάζει νεότερη κατάρρευση',
      () async {
        final first = run(start);
        await first.onStartup(retentionCount: 5);
        first.disableDiskForTest('ο POPINIO δεν απαντά');
        await first.onShutdown();

        // Ο POPINIO ξανανάβει, αλλά ο νέος κάτοχος του ίχνους καταρρέει.
        final crashed = run(DateTime(2026, 10, 22, 20, 58));
        await crashed.onStartup(retentionCount: 5);
        // Το σημείωμα καταναλώθηκε από την εκκίνηση των 20:58· ξαναγράφεται
        // επίτηδες ως αν είχε μείνει, για να δούμε ότι η ώρα το κρατά έξω.
        await CleanExitNote(noteDir).write(
          CrashLogService.instanceSlug('dev'),
          SessionLivenessMark(
            station: '',
            version: '',
            startedAt: start,
            lastSeen: start,
          ),
        );

        final third = run(nextStart);
        await third.onStartup(retentionCount: 5);

        expect(lostRunsReportedAt(nextStart), hasLength(1));
      },
    );

    test('ο παλμός ξεκινά και όταν η εκκίνηση βρήκε σιωπηλό φάκελο', () async {
      final service = CrashLogService(
        logsDirectory: p.join(temp.path, 'άφταστος', 'logs'),
      );
      addTearDown(service.dispose);
      await expectLater(
        service.onStartup(
          retentionCount: 5,
          timeout: const Duration(milliseconds: 100),
          createDirectory: (_) => Completer<void>().future,
        ),
        throwsA(isA<TimeoutException>()),
      );

      service.startLivenessHeartbeat();

      expect(
        service.isLivenessHeartbeatRunning,
        isTrue,
        reason:
            'αλλιώς, μετά τη μετάβαση σε βάση που απαντά, οι συνάδελφοι δεν '
            'βλέπουν ότι η εφαρμογή ζει',
      );
    });
  });

  /// Όσο ο κοινός φάκελος σιωπά, οι εγγραφές περιμένουν σε φάκελο του
  /// υπολογιστή και φτάνουν στον δικό τους φάκελο μόλις εκείνος απαντήσει.
  group('τοπική αναμονή', () {
    late _Folder folder;
    late String spillDir;
    late String sharedLogs;
    final errorTime = DateTime(2026, 10, 14, 17, 46);
    const limit = Duration(milliseconds: 100);

    setUp(() {
      folder = _Folder();
      spillDir = p.join(temp.path, 'pending');
      sharedLogs = p.join(temp.path, 'shared', 'logs');
    });

    CrashLogService station({String? logs, DateTime? now, _Folder? writer}) =>
        CrashLogService(
          logsDirectory: logs ?? sharedLogs,
          now: () => now ?? errorTime,
          writeFile: (writer ?? folder).write,
          writeTimeout: limit,
          spill: LogSpillStore(spillDir),
        );

    List<LogRecord> recordsIn(String logs, DateTime day) {
      final file = File(p.join(logs, CrashLogService.dailyLogFileName(day)));
      if (!file.existsSync()) return const [];
      return file
          .readAsLinesSync()
          .map(LogRecord.tryParse)
          .whereType<LogRecord>()
          .toList();
    }

    File spillFile() => File(p.join(spillDir, LogSpillStore.fileName));

    /// Ο ΠΟΠΙΝΙΟ σβήνει, και η εγγραφή που το διαπιστώνει είναι ένα σφάλμα.
    Future<CrashLogService> silencedWithError() async {
      final service = station();
      await service.onStartup(retentionCount: 5);
      folder.answers = false;
      service.logError(
        StateError('σφάλμα της πτώσης'),
        StackTrace.current,
        fatal: true,
      );
      await service.pendingWrites;
      expect(service.isDiskAvailable, isFalse);
      return service;
    }

    test(
      'η εγγραφή της πτώσης κρατιέται τοπικά και φτάνει μόλις ο φάκελος γυρίσει',
      () async {
        final service = await silencedWithError();
        expect(
          spillFile().existsSync(),
          isTrue,
          reason: 'το σφάλμα δεν πετάχτηκε',
        );

        folder.answers = true;
        await service.pulseForTest();
        await service.pendingWrites;
        await service.pendingDrain;

        final error = recordsIn(
          sharedLogs,
          errorTime,
        ).where((r) => r.message.contains('σφάλμα της πτώσης'));
        expect(error, hasLength(1));
        expect(error.single.time, errorTime, reason: 'με την αρχική του ώρα');
        expect(spillFile().existsSync(), isFalse);
      },
    );

    test('η επόμενη εκκίνηση μεταφέρει ό,τι περίμενε', () async {
      await silencedWithError();

      folder.answers = true;
      final nextDay = station(now: DateTime(2026, 10, 15, 8));
      await nextDay.onStartup(retentionCount: 5);
      await nextDay.pendingDrain;

      expect(
        recordsIn(
          sharedLogs,
          errorTime,
        ).where((r) => r.message.contains('σφάλμα της πτώσης')),
        hasLength(1),
      );
      expect(spillFile().existsSync(), isFalse);
    });

    test('εκκίνηση πάνω σε άλλη βάση δεν παίρνει τις ξένες εγγραφές', () async {
      await silencedWithError();

      folder.answers = true;
      final localLogs = p.join(temp.path, 'local', 'logs');
      final local = station(logs: localLogs);
      await local.onStartup(retentionCount: 5);
      await local.pendingDrain;

      expect(
        recordsIn(
          localLogs,
          errorTime,
        ).where((r) => r.message.contains('σφάλμα της πτώσης')),
        isEmpty,
      );
      expect(
        spillFile().existsSync(),
        isTrue,
        reason: 'περιμένει τον δικό του',
      );
    });

    test('αποτυχημένη μεταφορά δεν σβήνει τις τοπικές εγγραφές', () async {
      await silencedWithError();

      final failing = _Folder()..refuseContaining = 'σφάλμα της πτώσης';
      final next = station(writer: failing);
      await next.onStartup(retentionCount: 5);
      await next.pendingDrain;

      expect(spillFile().readAsStringSync(), contains('σφάλμα της πτώσης'));
    });

    test(
      'εγγραφές παλαιότερες από όσα κρατά το ημερολόγιο σβήνονται',
      () async {
        await silencedWithError();

        folder.answers = true;
        final muchLater = station(now: DateTime(2026, 11, 30));
        await muchLater.onStartup(retentionCount: 5);
        await muchLater.pendingDrain;

        expect(
          recordsIn(
            sharedLogs,
            errorTime,
          ).where((r) => r.message.contains('σφάλμα της πτώσης')),
          isEmpty,
        );
        expect(spillFile().existsSync(), isFalse);
      },
    );
  });
}

/// Ένας φάκελος που απαντά ή σωπαίνει κατά παραγγελία.
class _Folder {
  bool answers = true;
  int attempts = 0;

  /// Αρνείται μόνο τις εγγραφές που περιέχουν αυτό το κείμενο — ο φάκελος
  /// απαντά, αλλά η συγκεκριμένη μεταφορά αποτυγχάνει.
  String? refuseContaining;

  /// Ο αργός αλλά ζωντανός φάκελος: η επόμενη εγγραφή τελειώνει όταν το πει
  /// το τεστ.
  Completer<void>? slowNext;

  Future<void> write(
    String path,
    String content, {
    required bool append,
  }) async {
    attempts++;
    // Ο σβηστός διακομιστής: η εγγραφή δεν τελειώνει ποτέ.
    if (!answers) return Completer<void>().future;
    final refused = refuseContaining;
    if (refused != null && content.contains(refused)) {
      throw const FileSystemException('άρνηση εγγραφής');
    }
    final slow = slowNext;
    if (slow != null) {
      slowNext = null;
      return slow.future;
    }
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      content,
      mode: append ? FileMode.append : FileMode.write,
      flush: true,
    );
  }
}
