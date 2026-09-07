import 'dart:async';
import 'dart:io';

import 'package:call_logger/core/services/crash_log_service.dart';
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
      final service = CrashLogService(
        logsDirectory: p.join(temp.path, 'logs'),
      );

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

  test('όταν ο δίσκος έχει σβήσει, καμία καταγραφή δεν αγγίζει τη διαδρομή',
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

    // Μετά τη σίγαση, η καταγραφή σφάλματος δεν δημιουργεί τίποτα: η σύγχρονη
    // δημιουργία φακέλου τρέχει στο νήμα της διεπαφής και θα την πάγωνε.
    service.logError(StateError('δοκιμή'), StackTrace.current, fatal: true);

    expect(await Directory(unreachable).exists(), isFalse);
  });

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
}
