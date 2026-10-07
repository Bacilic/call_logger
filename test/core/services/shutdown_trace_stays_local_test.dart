// Το προσωρινό ίχνος του κλεισίματος δεν περιμένει το δίκτυο.
//
//   flutter test test/core/services/shutdown_trace_stays_local_test.dart

import 'dart:io';

import 'package:call_logger/core/services/crash_log_service.dart';
import 'package:call_logger/core/services/log_record.dart';
import 'package:call_logger/core/services/shutdown_coordinator.dart';
import 'package:call_logger/core/services/shutdown_trace_service.dart';
import 'package:call_logger/core/services/station_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late Directory sharedLogs;
  late Directory localWork;
  final fixedNow = DateTime(2026, 9, 21, 8, 38, 0);

  const thisStation = 'PC3569';

  setUp(() async {
    StationName.reader = () => thisStation;
    tempRoot = await Directory.systemTemp.createTemp('trace_local_test_');
    sharedLogs = Directory('${tempRoot.path}${Platform.pathSeparator}logs');
    localWork = Directory('${tempRoot.path}${Platform.pathSeparator}local');
    await sharedLogs.create(recursive: true);
    await localWork.create(recursive: true);
  });

  tearDown(() async {
    StationName.reader = StationName.defaultReader;
    try {
      if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
    } catch (_) {}
  });

  List<String> namesIn(Directory dir) =>
      dir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList()
        ..sort();

  void appendToShared(LogRecord record) => CrashLogService(
    logsDirectory: sharedLogs.path,
    now: () => fixedNow,
  ).appendRecord(record);

  ShutdownTraceService serviceUnderTest() => ShutdownTraceService(
    workingDirectory: localWork.path,
    appendRecord: appendToShared,
    now: () => fixedNow,
  );

  test('όσο γράφεται, το ίχνος δεν αγγίζει τον φάκελο της βάσης', () async {
    // Ο φάκελος της βάσης είναι δικτυακός όταν η βάση είναι κοινή, και κάθε
    // γραμμή του ίχνους περιμένει εκεί να πατήσει δίσκο. Μετρημένο κόστος:
    // 6,2 δευτερόλεπτα για οκτώ γραμμές — χρόνος που έλειπε από το αντίγραφο.
    final trace = serviceUnderTest();
    await trace.beginSession();

    trace.recordEvent(
      const ShutdownStepEvent(
        stepIndex: 3,
        label: 'Αντίγραφο ασφαλείας εξόδου',
        phase: ShutdownStepPhase.started,
      ),
    );

    expect(
      namesIn(sharedLogs),
      isEmpty,
      reason: greekExpectMsg(
        'Τίποτα δεν γράφεται δίπλα στη βάση όσο το κλείσιμο τρέχει',
      ),
    );
    expect(
      namesIn(localWork),
      hasLength(1),
      reason: greekExpectMsg('Το προσωρινό ίχνος ζει τοπικά'),
    );
  });

  test('το ίχνος που αξίζει ανεβαίνει στον κοινό φάκελο μία φορά', () async {
    final trace = serviceUnderTest();
    await trace.beginSession();
    trace.recordEvent(
      const ShutdownStepEvent(
        stepIndex: 3,
        label: 'Αντίγραφο ασφαλείας εξόδου',
        phase: ShutdownStepPhase.interrupted,
      ),
    );
    await trace.endSession();

    expect(trace.keptIncident, isTrue);
    expect(
      namesIn(localWork),
      isEmpty,
      reason: greekExpectMsg('Το τοπικό προσωρινό καθαρίζεται μετά την άνοδο'),
    );
    expect(namesIn(sharedLogs), hasLength(1));
    expect(
      File(
        '${sharedLogs.path}${Platform.pathSeparator}'
        '${namesIn(sharedLogs).single}',
      ).readAsStringSync(),
      contains('Αντίγραφο ασφαλείας εξόδου'),
    );
  });

  test('ομαλό κλείσιμο δεν αφήνει τίποτα πουθενά', () async {
    final trace = serviceUnderTest();
    await trace.beginSession();
    trace.recordEvent(
      const ShutdownStepEvent(
        stepIndex: 0,
        label: 'Αποθήκευση θέσης παραθύρου',
        phase: ShutdownStepPhase.completed,
        durationMs: 4,
      ),
    );
    await trace.endSession();

    expect(trace.keptIncident, isFalse);
    expect(namesIn(localWork), isEmpty);
    expect(namesIn(sharedLogs), isEmpty);
  });

  group('η προαγωγή ορφανού στην εκκίνηση', () {
    test('βρίσκει το τοπικό ίχνος που έμεινε στη μέση', () async {
      final trace = serviceUnderTest();
      await trace.beginSession();
      trace.recordEvent(
        const ShutdownStepEvent(
          stepIndex: 3,
          label: 'Αντίγραφο ασφαλείας εξόδου',
          phase: ShutdownStepPhase.started,
        ),
      );
      // Χωρίς endSession: η διεργασία σκοτώθηκε στη μέση του κλεισίματος.

      final promoted = await ShutdownTraceService.promoteOrphanedTrace(
        workingDirectory: localWork.path,
        appendRecord: appendToShared,
        now: () => fixedNow,
      );

      expect(promoted, isTrue);
      expect(namesIn(localWork), isEmpty);
      expect(namesIn(sharedLogs), hasLength(1));
    });

    test(
      'μετακομίζει μία τελευταία φορά ό,τι έμεινε στην παλιά θέση',
      () async {
        // Το ίχνος της προηγούμενης έκδοσης ζούσε στον κοινό φάκελο, με όνομα
        // χωρίς την ταυτότητα της εκτέλεσης. Δεν επιτρέπεται να μείνει εκεί
        // αδιάβαστο για πάντα.
        final legacy = File(
          '${sharedLogs.path}${Platform.pathSeparator}'
          '${ShutdownTraceService.legacySharedWorkingFileName}',
        );
        await legacy.writeAsString(
          '[2026-09-21 08:38:10] step=3 "Αντίγραφο ασφαλείας εξόδου" START\n',
        );

        final promoted = await ShutdownTraceService.promoteOrphanedTrace(
          workingDirectory: localWork.path,
          legacySharedDirectory: sharedLogs.path,
          appendRecord: appendToShared,
          now: () => fixedNow,
        );

        expect(promoted, isTrue);
        expect(
          legacy.existsSync(),
          isFalse,
          reason: greekExpectMsg('Η παλιά θέση καθαρίζει μόλις διαβαστεί'),
        );
      },
    );

    test('το ζωντανό ίχνος άλλου υπολογιστή δεν αγγίζεται', () async {
      final other = File(
        '${sharedLogs.path}${Platform.pathSeparator}'
        'shutdown_trace_ΑΛΛΟΣ-ΣΤΑΘΜΟΣ.log',
      );
      await other.writeAsString('[2026-09-21 08:38:10] step=0 "X" START\n');

      final promoted = await ShutdownTraceService.promoteOrphanedTrace(
        workingDirectory: localWork.path,
        legacySharedDirectory: sharedLogs.path,
        appendRecord: appendToShared,
        now: () => fixedNow,
      );

      expect(promoted, isFalse);
      expect(
        other.existsSync(),
        isTrue,
        reason: greekExpectMsg(
          'Ο διπλανός υπολογιστής μπορεί να κλείνει ΑΥΤΗ ΤΗ ΣΤΙΓΜΗ',
        ),
      );
    });

    test('καθαρά και τα δύο: η προαγωγή δεν βρίσκει τίποτα', () async {
      final promoted = await ShutdownTraceService.promoteOrphanedTrace(
        workingDirectory: localWork.path,
        legacySharedDirectory: sharedLogs.path,
        appendRecord: appendToShared,
        now: () => fixedNow,
      );

      expect(promoted, isFalse);
      expect(namesIn(sharedLogs), isEmpty);
    });
  });

  test('το όνομα του προσωρινού ξεχωρίζει τα δύο αντίγραφα του υπολογιστή', () {
    // Τώρα που ο φάκελος είναι τοπικός, η κανονική και η δοκιμαστική έκδοση
    // του ίδιου υπολογιστή θα μοιραζόταν ένα αρχείο χωρίς την ταυτότητα της
    // εκτέλεσης στο όνομα.
    expect(
      ShutdownTraceService.workingFileName,
      isNot(ShutdownTraceService.legacySharedWorkingFileName),
    );
    expect(ShutdownTraceService.workingFileName, contains(thisStation));
  });
}
