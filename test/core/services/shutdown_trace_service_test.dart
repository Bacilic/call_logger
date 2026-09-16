import 'dart:io';

import 'package:call_logger/core/services/crash_log_service.dart';
import 'package:call_logger/core/services/shutdown_coordinator.dart';
import 'package:call_logger/core/services/shutdown_trace_incident.dart';
import 'package:call_logger/core/services/shutdown_trace_service.dart';
import 'package:call_logger/core/services/station_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late Directory logsDir;
  final fixedNow = DateTime(2026, 8, 9, 14, 30, 12);

  const thisStation = 'ΣΤΑΘΜΟΣ-ΔΟΚΙΜΗΣ';

  setUp(() async {
    // Το προσωρινό ίχνος φέρει τον σταθμό στο όνομά του· χωρίς κάρφωμα, το
    // τεστ θα εξαρτιόταν από το όνομα του υπολογιστή που το τρέχει.
    StationName.reader = () => thisStation;
    tempRoot = await Directory.systemTemp.createTemp('shutdown_trace_test_');
    logsDir = Directory('${tempRoot.path}${Platform.pathSeparator}logs');
    await logsDir.create(recursive: true);
  });

  tearDown(() async {
    StationName.reader = StationName.defaultReader;
    try {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    } catch (_) {}
  });

  List<String> filesNamed(String prefix) {
    return logsDir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.startsWith(prefix))
        .toList()
      ..sort();
  }

  List<String> sessionFiles() => filesNamed(CrashLogService.sessionLogPrefix);

  List<String> workingFiles() =>
      filesNamed(CrashLogService.legacyShutdownTracePrefix);

  String sessionContent() {
    final buffer = StringBuffer();
    for (final name in sessionFiles()) {
      buffer.write(
        File(
          '${logsDir.path}${Platform.pathSeparator}$name',
        ).readAsStringSync(),
      );
    }
    return buffer.toString();
  }

  /// Πόσα μπλοκ τερματισμού έχουν γραφτεί συνολικά. Τα περιστατικά της ίδιας
  /// ημέρας μοιράζονται αρχείο, οπότε το πλήθος αρχείων δεν τα μετρά πια.
  int incidentBlocks() => 'ΤΕΡΜΑΤΙΣΜΟΣ'.allMatches(sessionContent()).length;

  /// Ο παραλήπτης που στην εφαρμογή είναι το ημερήσιο αρχείο συνεδριών.
  void Function(String) appenderFor(DateTime when) {
    return (String text) {
      File(
        '${logsDir.path}${Platform.pathSeparator}'
        '${CrashLogService.sessionLogFileName(when)}',
      ).writeAsStringSync(text, mode: FileMode.append, flush: true);
    };
  }

  ShutdownTraceService service({
    Duration slowThreshold = ShutdownCoordinator.progressRevealDelay,
    DateTime? now,
  }) {
    final clock = now ?? fixedNow;
    return ShutdownTraceService(
      logsDirectory: logsDir.path,
      appendToSessionLog: appenderFor(clock),
      slowThreshold: slowThreshold,
      now: () => clock,
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
    test('φυσιολογικό γρήγορο κλείσιμο: τίποτα δεν μένει πίσω', () async {
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
        workingFiles(),
        isEmpty,
        reason: greekExpectMsg('Το προσωρινό ίχνος σβήνεται'),
      );
      expect(
        sessionFiles(),
        isEmpty,
        reason: greekExpectMsg(
          'Χωρίς πρόβλημα δεν γράφεται τίποτα — ούτε στο αρχείο συνεδρίας',
        ),
      );
      expect(trace.keptIncident, isFalse);
    });

    test(
      'αργό κλείσιμο πάνω από το κατώφλι: προσαρτάται στο αρχείο συνεδρίας',
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

        expect(sessionFiles(), ['session_2026-08-09.log']);
        expect(
          workingFiles(),
          isEmpty,
          reason: greekExpectMsg('Το προσωρινό δεν μένει μετά την προσάρτηση'),
        );
        expect(trace.keptIncident, isTrue);

        final content = sessionContent();
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
        expect(incidentBlocks(), 1);

        final below = service(
          slowThreshold: const Duration(seconds: 1),
          now: DateTime(2026, 8, 9, 15, 0, 0),
        );
        await below.beginSession();
        runStep(below, index: 0, label: 'Βήμα', durationMs: 999);
        await below.endSession();
        expect(
          incidentBlocks(),
          1,
          reason: greekExpectMsg('Κάτω από το κατώφλι δεν γράφεται τίποτα'),
        );
      },
    );

    test(
      'αποτυχία βήματος καταγράφεται ακόμη κι αν το κλείσιμο ήταν γρήγορο',
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

        expect(incidentBlocks(), 1);
        final incident = await ShutdownTraceIncident.findLatest(logsDir.path);
        expect(incident!.hadFailure, isTrue);
        expect(incident.slowestStepLabel, 'Κλείσιμο σύνδεσης βάσης');
        expect(incident.describe(), contains('απέτυχε το βήμα'));
      },
    );

    test(
      'διακοπή από το όριο ασφαλείας καταγράφεται και ονομάζει το βήμα',
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

        expect(incidentBlocks(), 1);
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
          workingFiles(),
          [ShutdownTraceService.workingFileName],
          reason: greekExpectMsg(
            'Το ίχνος γράφεται ΤΗΝ ΩΡΑ του κλεισίματος, όχι στο τέλος',
          ),
        );
      },
    );

    test(
      'ορφανό προσωρινό από crash προάγεται στην ΕΠΟΜΕΝΗ ΕΚΚΙΝΗΣΗ',
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
        // Χωρίς endSession — η εφαρμογή σκοτώθηκε στη μέση του κλεισίματος.

        final nextBoot = DateTime(2026, 8, 10, 8, 0, 0);
        final promoted = await ShutdownTraceService.promoteOrphanedTrace(
          logsDirectory: logsDir.path,
          appendToSessionLog: appenderFor(nextBoot),
          now: () => nextBoot,
        );

        expect(
          promoted,
          isTrue,
          reason: greekExpectMsg(
            'Η εκκίνηση βρίσκει το διακοπέν κλείσιμο — όχι το επόμενο κλείσιμο',
          ),
        );
        expect(workingFiles(), isEmpty);
        expect(incidentBlocks(), 1);

        final incident = await ShutdownTraceIncident.findLatest(logsDir.path);
        expect(incident!.wasInterrupted, isTrue);
        expect(
          incident.slowestStepLabel,
          'Αντίγραφο ασφαλείας εξόδου',
          reason: greekExpectMsg('Κόλλησε στο τελευταίο βήμα που ξεκίνησε'),
        );
      },
    );

    test(
      'το ζωντανό ίχνος ΑΛΛΟΥ υπολογιστή δεν προάγεται και δεν σβήνεται',
      () async {
        final other = File(
          '${logsDir.path}${Platform.pathSeparator}'
          'shutdown_trace_ΑΛΛΟΣ-ΣΤΑΘΜΟΣ.log',
        );
        await other.writeAsString(
          '[2026-08-09 14:00:00] step=0 "Αντίγραφο ασφαλείας εξόδου" START',
        );

        final promoted = await ShutdownTraceService.promoteOrphanedTrace(
          logsDirectory: logsDir.path,
          appendToSessionLog: appenderFor(fixedNow),
        );

        expect(promoted, isFalse);
        expect(
          other.existsSync(),
          isTrue,
          reason: greekExpectMsg(
            'Σε κοινόχρηστο φάκελο, ο διπλανός υπολογιστής μπορεί να κλείνει '
            'ΑΥΤΗ ΤΗ ΣΤΙΓΜΗ — το ίχνος του δεν είναι δικό μας περιστατικό',
          ),
        );
        expect(sessionFiles(), isEmpty);
      },
    );

    test('καθαρός φάκελος: η προαγωγή δεν βρίσκει τίποτα', () async {
      final promoted = await ShutdownTraceService.promoteOrphanedTrace(
        logsDirectory: logsDir.path,
        appendToSessionLog: appenderFor(fixedNow),
      );
      expect(promoted, isFalse);
      expect(sessionFiles(), isEmpty);
    });

    test(
      'εκκίνηση και τερματισμός της ίδιας ημέρας μοιράζονται ΕΝΑ αρχείο',
      () async {
        appenderFor(fixedNow)('[2026-08-09 08:12:33] ══ ΕΚΚΙΝΗΣΗ v1.0.0 ══\n');
        final trace = service();
        await trace.beginSession();
        runStep(trace, index: 0, label: 'Βήμα', durationMs: 900);
        await trace.endSession();

        expect(sessionFiles(), ['session_2026-08-09.log']);
        final content = sessionContent();
        expect(content, contains('ΕΚΚΙΝΗΣΗ'));
        expect(content, contains('ΤΕΡΜΑΤΙΣΜΟΣ'));
        expect(
          content.indexOf('ΕΚΚΙΝΗΣΗ'),
          lessThan(content.indexOf('ΤΕΡΜΑΤΙΣΜΟΣ')),
          reason: greekExpectMsg(
            'Η σειρά του αρχείου είναι η σειρά του χρόνου',
          ),
        );
      },
    );
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
        DateTime(2026, 8, 7, 9, 0, 0),
        DateTime(2026, 8, 9, 18, 0, 0),
        DateTime(2026, 8, 8, 12, 0, 0),
      ]) {
        final trace = service(now: stamp);
        await trace.beginSession();
        runStep(trace, index: 0, label: 'Βήμα ${stamp.day}', durationMs: 700);
        await trace.endSession();
      }

      final incident = await ShutdownTraceIncident.findLatest(logsDir.path);
      expect(incident!.slowestStepLabel, 'Βήμα 9');
      expect(incident.occurredAt, DateTime(2026, 8, 9, 18, 0, 0));
    });

    test(
      'μέσα στο ίδιο αρχείο κερδίζει η ΤΕΛΕΥΤΑΙΑ σύνοψη της ημέρας',
      () async {
        for (final stamp in [
          DateTime(2026, 8, 9, 9, 0, 0),
          DateTime(2026, 8, 9, 18, 0, 0),
        ]) {
          final trace = service(now: stamp);
          await trace.beginSession();
          runStep(
            trace,
            index: 0,
            label: 'Βήμα ${stamp.hour}',
            durationMs: 700,
          );
          await trace.endSession();
        }

        final incident = await ShutdownTraceIncident.findLatest(logsDir.path);
        expect(incident!.slowestStepLabel, 'Βήμα 18');
      },
    );

    test('αλλοιωμένη σύνοψη δεν ρίχνει την οθόνη — απλώς αγνοείται', () async {
      final file = File(
        '${logsDir.path}${Platform.pathSeparator}session_2026-08-09.log',
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
        filePath: 'C:/logs/session_2026-08-09.log',
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
      expect(incident.fileName, 'session_2026-08-09.log');
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
