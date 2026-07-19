import 'dart:io';

import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/core/services/shutdown_coordinator.dart';
import 'package:call_logger/core/services/shutdown_trace_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_reporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late Directory logsDir;
  final fixedNow = DateTime(2026, 7, 19, 9, 56, 0);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempRoot = await Directory.systemTemp.createTemp('shutdown_trace_test_');
    logsDir = Directory('${tempRoot.path}${Platform.pathSeparator}logs');
    await logsDir.create(recursive: true);
  });

  tearDown(() async {
    try {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('ShutdownTraceService', () {
    test('ενεργός: γράφει γεγονότα με flush και χρονοσφραγίδα', () async {
      final service = ShutdownTraceService(
        logsDirectory: logsDir.path,
        enabled: true,
        retentionCount: 5,
        now: () => fixedNow,
      );
      await service.beginSession();
      service.recordEvent(
        const ShutdownStepEvent(
          stepIndex: 0,
          label: 'Αποθήκευση θέσης παραθύρου',
          phase: ShutdownStepPhase.started,
        ),
      );
      service.recordEvent(
        const ShutdownStepEvent(
          stepIndex: 0,
          label: 'Αποθήκευση θέσης παραθύρου',
          phase: ShutdownStepPhase.completed,
          durationMs: 8,
        ),
      );
      await service.endSession();

      final file = service.currentFile;
      expect(file, isNotNull);
      expect(
        file!.uri.pathSegments.last,
        'shutdown_trace_2026-07-19_09-56-00.log',
      );
      final content = await file.readAsString();
      expect(content, contains('[2026-07-19 09:56:00]'));
      expect(content, contains('Αποθήκευση θέσης παραθύρου'));
      expect(content, contains('START'));
      expect(content, contains('OK'));
      expect(content, contains('durationMs=8'));
    });

    test('απενεργοποιημένος: δεν γράφει τίποτα', () async {
      final service = ShutdownTraceService(
        logsDirectory: logsDir.path,
        enabled: false,
        retentionCount: 5,
        now: () => fixedNow,
      );
      await service.beginSession();
      service.recordEvent(
        const ShutdownStepEvent(
          stepIndex: 0,
          label: 'Αποθήκευση θέσης παραθύρου',
          phase: ShutdownStepPhase.started,
        ),
      );
      await service.endSession();

      expect(service.currentFile, isNull);
      final files = logsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('shutdown_trace_'))
          .toList();
      expect(files, isEmpty);
    });

    test('διατήρηση μόνο των N πιο πρόσφατων αρχείων', () async {
      for (var i = 1; i <= 4; i++) {
        final stamp = DateTime(2026, 7, i, 10, 0, 0);
        final service = ShutdownTraceService(
          logsDirectory: logsDir.path,
          enabled: true,
          retentionCount: 2,
          now: () => stamp,
        );
        await service.beginSession();
        service.recordEvent(
          ShutdownStepEvent(
            stepIndex: 0,
            label: 'Αποθήκευση θέσης παραθύρου',
            phase: ShutdownStepPhase.started,
          ),
        );
        await service.endSession();
      }

      final files = logsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('shutdown_trace_'))
          .map((f) => f.uri.pathSegments.last)
          .toList()
        ..sort();
      expect(
        files.length,
        2,
        reason: greekExpectMsg('Πρέπει να μείνουν μόνο 2 αρχεία ιχνηλάτησης'),
      );
      expect(files, [
        'shutdown_trace_2026-07-03_10-00-00.log',
        'shutdown_trace_2026-07-04_10-00-00.log',
      ]);
    });
  });

  group('SettingsService · shutdown trace', () {
    test('προεπιλογές και αποθήκευση των δύο νέων ρυθμίσεων', () async {
      final settings = SettingsService();
      expect(await settings.getShutdownTraceEnabled(), isTrue);
      expect(
        await settings.getShutdownTraceRetentionCount(),
        SettingsService.defaultCrashLogRetentionCount,
      );

      await settings.setShutdownTraceEnabled(false);
      await settings.setShutdownTraceRetentionCount(5);
      expect(await settings.getShutdownTraceEnabled(), isFalse);
      expect(await settings.getShutdownTraceRetentionCount(), 5);

      await settings.setShutdownTraceRetentionCount(1);
      expect(
        await settings.getShutdownTraceRetentionCount(),
        SettingsService.minShutdownTraceRetentionCount,
      );
    });
  });
}
