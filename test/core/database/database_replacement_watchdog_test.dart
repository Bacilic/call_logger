// Ο περιοδικός φρουρός αντικατάστασης αρχείου βάσης.
//
//   flutter test test/core/database/database_replacement_watchdog_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_replacement_watchdog.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('δεν φωνάζει όσο η ανίχνευση λέει «όλα καλά»', () {
    var checks = 0;
    var alarms = 0;
    fakeAsync((async) {
      DatabaseReplacementWatchdog(
        interval: const Duration(seconds: 10),
        detect: () async {
          checks++;
          return false;
        },
        onDetected: () async => alarms++,
      ).start();

      async.elapse(const Duration(seconds: 35));
    });

    expect(checks, 3);
    expect(alarms, 0);
  });

  test('φωνάζει μία φορά και σταματά', () {
    var alarms = 0;
    late DatabaseReplacementWatchdog watchdog;
    fakeAsync((async) {
      watchdog = DatabaseReplacementWatchdog(
        interval: const Duration(seconds: 10),
        detect: () async => true,
        onDetected: () async => alarms++,
      )..start();

      async.elapse(const Duration(seconds: 60));
    });

    expect(alarms, 1, reason: 'ένα περιστατικό, μία ειδοποίηση');
    expect(watchdog.isRunning, isFalse);
    expect(watchdog.hasFired, isTrue);
  });

  test('αργή ανίχνευση δεν στοιβάζει ελέγχους', () {
    var running = 0;
    var maxConcurrent = 0;
    fakeAsync((async) {
      DatabaseReplacementWatchdog(
        interval: const Duration(seconds: 10),
        detect: () async {
          running++;
          if (running > maxConcurrent) maxConcurrent = running;
          // Ο έλεγχος αργεί περισσότερο από το διάστημα — δικτυακός φάκελος.
          await Future<void>.delayed(const Duration(seconds: 25));
          running--;
          return false;
        },
        onDetected: () async {},
      ).start();

      async.elapse(const Duration(seconds: 90));
    });

    expect(maxConcurrent, 1, reason: 'ποτέ δύο έλεγχοι ταυτόχρονα');
  });

  test('σφάλμα στην ανίχνευση δεν φτάνει ποτέ στον χρήστη', () {
    var alarms = 0;
    fakeAsync((async) {
      DatabaseReplacementWatchdog(
        interval: const Duration(seconds: 10),
        detect: () async => throw const FileSystemException('άφταστο δίκτυο'),
        onDetected: () async => alarms++,
      ).start();

      async.elapse(const Duration(seconds: 40));
    });

    expect(alarms, 0);
  });

  test('μετά το stop δεν ξαναρωτά', () {
    var checks = 0;
    fakeAsync((async) {
      final watchdog = DatabaseReplacementWatchdog(
        interval: const Duration(seconds: 10),
        detect: () async {
          checks++;
          return false;
        },
        onDetected: () async {},
      )..start();

      async.elapse(const Duration(seconds: 25));
      watchdog.stop();
      async.elapse(const Duration(seconds: 60));
    });

    expect(checks, 2);
  });
}
