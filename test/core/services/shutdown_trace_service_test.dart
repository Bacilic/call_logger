import 'dart:io';

import 'package:call_logger/core/services/shutdown_coordinator.dart';
import 'package:call_logger/core/services/shutdown_trace_incident.dart';
import 'package:call_logger/core/services/shutdown_trace_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late Directory logsDir;
  final fixedNow = DateTime(2026, 8, 9, 14, 30, 12);

  setUp(() async {
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

  List<String> traceFiles() {
    return logsDir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.startsWith('shutdown_trace_'))
        .toList()
      ..sort();
  }

  ShutdownTraceService service({
    int retentionCount = 5,
    Duration slowThreshold = ShutdownCoordinator.progressRevealDelay,
    DateTime? now,
  }) {
    return ShutdownTraceService(
      logsDirectory: logsDir.path,
      retentionCount: retentionCount,
      slowThreshold: slowThreshold,
      now: () => now ?? fixedNow,
    );
  }

  /// Ένα ολοκληρωμένο βήμα με τη δοσμένη διάρκεια.
  void runStep(
    ShutdownTraceService trace, {
    required int index,
    required String label,
    required int durationMs,
    ShutdownStepPhase endPhase = ShutdownStepPhase.completed,
  }) {
    trace.recordEvent(
      ShutdownStepEvent(
        stepIndex: index,
        label: label,
        phase: ShutdownStepPhase.started,
      ),
    );
    trace.recordEvent(
      ShutdownStepEvent(
        stepIndex: index,
        label: label,
        phase: endPhase,
        durationMs: durationMs,
        error: endPhase == ShutdownStepPhase.failed ? 'σφάλμα δοκιμής' : null,
      ),
    );
  }

  group('ShutdownTraceService · σιωπηλός φρουρός', () {
    test(
      'φυσιολογικό γρήγορο κλείσιμο: ΚΑΝΕΝΑ αρχείο δεν μένει πίσω',
      () async {
        final trace = service();
        await trace.beginSession();
        runStep(
          trace,
          index: 0,
          label: 'Αποθήκευση θέσης παραθύρου',
          durationMs: 5,
        );
        runStep(
          trace,
          index: 1,
          label: 'Αντίγραφο ασφαλείας εξόδου',
          durationMs: 40,
        );
        await trace.endSession();

        expect(
          traceFiles(),
          isEmpty,
          reason: greekExpectMsg(
            'Χωρίς πρόβλημα δεν γράφεται τίποτα — ο φάκελος logs μένει καθαρός',
          ),
        );
        expect(trace.incidentFile, isNull);
      },
    );

    test(
      'αργό κλείσιμο πάνω από το κατώφλι: κρατιέται αρχείο περιστατικού',
      () async {
        final trace = service();
        await trace.beginSession();
        runStep(
          trace,
          index: 0,
          label: 'Αποθήκευση θέσης παραθύρου',
          durationMs: 20,
        );
        runStep(
          trace,
          index: 1,
          label: 'Αντίγραφο ασφαλείας εξόδου',
          durationMs: 900,
        );
        await trace.endSession();

        expect(traceFiles(), ['shutdown_trace_2026-08-09_143012.log']);
        final content = await trace.incidentFile!.readAsString();
        expect(content, contains('Αντίγραφο ασφαλείας εξόδου'));
        expect(content, contains('durationMs=900'));

        final incident = await ShutdownTraceIncident.findLatest(logsDir.path);
        expect(incident, isNotNull);
        expect(incident!.totalMs, 920);
        expect(incident.slowestStepLabel, 'Αντίγραφο ασφαλείας εξόδου');
        expect(incident.slowestStepMs, 900);
        expect(incident.hadFailure, isFalse);
        expect(incident.wasInterrupted, isFalse);
      },
    );

    test(
      'ακριβώς στο κατώφλι μετράει ως περιστατικό, ένα ms κάτω όχι',
      () async {
        final atThreshold = service(slowThreshold: const Duration(seconds: 1));
        await atThreshold.beginSession();
        runStep(atThreshold, index: 0, label: 'Βήμα', durationMs: 1000);
        await atThreshold.endSession();
        expect(traceFiles(), hasLength(1));

        final below = service(
          slowThreshold: const Duration(seconds: 1),
          now: DateTime(2026, 8, 9, 15, 0, 0),
        );
        await below.beginSession();
        runStep(below, index: 0, label: 'Βήμα', durationMs: 999);
        await below.endSession();
        expect(
          traceFiles(),
          hasLength(1),
          reason: greekExpectMsg('Κάτω από το κατώφλι δεν προστίθεται αρχείο'),
        );
      },
    );

    test(
      'αποτυχία βήματος κρατά αρχείο ακόμη κι αν το κλείσιμο ήταν γρήγορο',
      () async {
        final trace = service();
        await trace.beginSession();
        runStep(
          trace,
          index: 2,
          label: 'Κλείσιμο σύνδεσης βάσης',
          durationMs: 12,
          endPhase: ShutdownStepPhase.failed,
        );
        await trace.endSession();

        expect(traceFiles(), hasLength(1));
        final incident = await ShutdownTraceIncident.findLatest(logsDir.path);
        expect(incident!.hadFailure, isTrue);
        expect(incident.slowestStepLabel, 'Κλείσιμο σύνδεσης βάσης');
        expect(incident.describe(), contains('απέτυχε το βήμα'));
      },
    );

    test(
      'διακοπή από το όριο ασφαλείας κρατά αρχείο και ονομάζει το βήμα',
      () async {
        final trace = service();
        await trace.beginSession();
        trace.recordEvent(
          const ShutdownStepEvent(
            stepIndex: 1,
            label: 'Αντίγραφο ασφαλείας εξόδου',
            phase: ShutdownStepPhase.started,
          ),
        );
        trace.recordEvent(
          const ShutdownStepEvent(
            stepIndex: 1,
            label: 'Αντίγραφο ασφαλείας εξόδου',
            phase: ShutdownStepPhase.interrupted,
          ),
        );
        await trace.endSession();

        expect(traceFiles(), hasLength(1));
        final incident = await ShutdownTraceIncident.findLatest(logsDir.path);
        expect(incident!.wasInterrupted, isTrue);
        expect(incident.slowestStepLabel, 'Αντίγραφο ασφαλείας εξόδου');
        expect(incident.describe(), contains('διακόπηκε στο βήμα'));
      },
    );

    test(
      'το προσωρινό αρχείο ζει όσο τρέχει το κλείσιμο — επιβιώνει σε crash',
      () async {
        final trace = service();
        await trace.beginSession();
        runStep(trace, index: 0, label: 'Βήμα', durationMs: 3);

        // Καμία κλήση endSession: η διεργασία «σκοτώθηκε» στη μέση.
        expect(
          traceFiles(),
          [ShutdownTraceService.workingFileName],
          reason: greekExpectMsg(
            'Το ίχνος γράφεται ΤΗΝ ΩΡΑ του κλεισίματος, όχι στο τέλος',
          ),
        );
      },
    );

    test(
      'ορφανό προσωρινό από προηγούμενο crash προάγεται σε περιστατικό',
      () async {
        final crashed = service();
        await crashed.beginSession();
        runStep(
          crashed,
          index: 0,
          label: 'Αποθήκευση θέσης παραθύρου',
          durationMs: 4,
        );
        crashed.recordEvent(
          const ShutdownStepEvent(
            stepIndex: 1,
            label: 'Αντίγραφο ασφαλείας εξόδου',
            phase: ShutdownStepPhase.started,
          ),
        );
        // Χωρίς endSession — το επόμενο άνοιγμα της εφαρμογής το βρίσκει.

        final next = service(now: DateTime(2026, 8, 10, 8, 0, 0));
        await next.beginSession();
        await next.endSession();

        expect(
          traceFiles(),
          hasLength(1),
          reason: greekExpectMsg(
            'Το ορφανό γίνεται περιστατικό· το νέο καθαρό κλείσιμο δεν αφήνει '
            'δικό του αρχείο',
          ),
        );
        final incident = await ShutdownTraceIncident.findLatest(logsDir.path);
        expect(incident!.wasInterrupted, isTrue);
        expect(
          incident.slowestStepLabel,
          'Αντίγραφο ασφαλείας εξόδου',
          reason: greekExpectMsg('Κόλλησε στο τελευταίο βήμα που ξεκίνησε'),
        );
      },
    );

    test('διατηρούνται μόνο τα N πιο πρόσφατα περιστατικά', () async {
      for (var minute = 1; minute <= 4; minute++) {
        final trace = service(
          retentionCount: 2,
          now: DateTime(2026, 8, 9, 10, minute, 0),
        );
        await trace.beginSession();
        runStep(trace, index: 0, label: 'Βήμα', durationMs: 800);
        await trace.endSession();
      }

      expect(traceFiles(), [
        'shutdown_trace_2026-08-09_100300.log',
        'shutdown_trace_2026-08-09_100400.log',
      ]);
    });
  });

  group('ShutdownTraceIncident', () {
    test('καθαρός φάκελος: κανένα περιστατικό', () async {
      expect(await ShutdownTraceIncident.findLatest(logsDir.path), isNull);
    });

    test('ανύπαρκτος φάκελος δεν σκάει', () async {
      final missing = '${tempRoot.path}${Platform.pathSeparator}δεν-υπάρχει';
      expect(await ShutdownTraceIncident.findLatest(missing), isNull);
    });

    test('επιστρέφει το ΠΙΟ ΠΡΟΣΦΑΤΟ όταν υπάρχουν πολλά', () async {
      for (final stamp in [
        DateTime(2026, 8, 9, 9, 0, 0),
        DateTime(2026, 8, 9, 18, 0, 0),
        DateTime(2026, 8, 9, 12, 0, 0),
      ]) {
        final trace = service(now: stamp);
        await trace.beginSession();
        runStep(trace, index: 0, label: 'Βήμα ${stamp.hour}', durationMs: 700);
        await trace.endSession();
      }

      final incident = await ShutdownTraceIncident.findLatest(logsDir.path);
      expect(incident!.slowestStepLabel, 'Βήμα 18');
      expect(incident.occurredAt, DateTime(2026, 8, 9, 18, 0, 0));
    });

    test('αλλοιωμένη σύνοψη δεν ρίχνει την οθόνη — απλώς αγνοείται', () async {
      final file = File(
        '${logsDir.path}${Platform.pathSeparator}'
        'shutdown_trace_2026-08-09_120000.log',
      );
      await file.writeAsString(
        '[2026-08-09 12:00:00] κάτι\nSUMMARY={σκουπίδια',
      );
      expect(await ShutdownTraceIncident.findLatest(logsDir.path), isNull);
    });

    test('μορφοποίηση χρόνου: ms κάτω από το δευτερόλεπτο, δευτ. από πάνω', () {
      expect(ShutdownTraceIncident.formatDuration(850), '850 ms');
      expect(ShutdownTraceIncident.formatDuration(999), '999 ms');
      expect(ShutdownTraceIncident.formatDuration(1000), '1,0 δευτ.');
      expect(ShutdownTraceIncident.formatDuration(1240), '1,2 δευτ.');
      expect(ShutdownTraceIncident.formatDuration(20000), '20,0 δευτ.');
    });

    test('το μήνυμα καθυστέρησης ονομάζει χρόνο και βήμα', () {
      final incident = ShutdownTraceIncident(
        filePath: 'C:/logs/shutdown_trace_2026-08-09_143012.log',
        occurredAt: fixedNow,
        totalMs: 1240,
        slowestStepLabel: 'Αντίγραφο ασφαλείας εξόδου',
        slowestStepMs: 1200,
        hadFailure: false,
        wasInterrupted: false,
      );
      expect(
        incident.describe(),
        'Στο προηγούμενο κλείσιμο της εφαρμογής εντοπίστηκε καθυστέρηση '
        '1,2 δευτ. στο βήμα «Αντίγραφο ασφαλείας εξόδου».',
      );
      expect(incident.fileName, 'shutdown_trace_2026-08-09_143012.log');
    });

    test('η διακοπή υπερισχύει της αποτυχίας στο μήνυμα', () {
      final incident = ShutdownTraceIncident(
        filePath: 'x.log',
        occurredAt: fixedNow,
        totalMs: 20000,
        slowestStepLabel: 'Αντίγραφο ασφαλείας εξόδου',
        slowestStepMs: 20000,
        hadFailure: true,
        wasInterrupted: true,
      );
      expect(incident.describe(), contains('διακόπηκε'));
    });
  });
}
