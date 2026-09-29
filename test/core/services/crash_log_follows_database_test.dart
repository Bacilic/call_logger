import 'dart:io';

import 'package:call_logger/core/database/schema_upgrade_station_guard.dart';
import 'package:call_logger/core/services/crash_log_service.dart';
import 'package:call_logger/core/services/session_liveness_mark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Το ημερολόγιο ακολουθεί τη βάση — και μαζί του η απάντηση στο «ποιος άλλος
/// την κρατά τώρα;».
///
/// **Το σενάριο πεδίου (28/09):** ο σταθμός είχε ανοιχτή τη μία βάση, πέρασε με
/// «Αλλαγή βάσης» σε άλλη που κρατούσε ήδη συνάδελφος, και η μόνιμη αναβάθμιση
/// σχήματος πέρασε σιωπηλά — επειδή ο φρουρός ρωτούσε ακόμη τον φάκελο της
/// **προηγούμενης** βάσης, όπου κανένας συνάδελφος δεν θα μπορούσε να φαίνεται.
void main() {
  late Directory root;
  late String firstDatabase;
  late String secondDatabase;

  String logsOf(String databasePath) =>
      CrashLogService.logsDirectoryForDatabasePath(databasePath);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('crash_log_follows');
    firstDatabase = p.join(root.path, 'local', 'Hospital.db');
    secondDatabase = p.join(root.path, 'shared', 'integrity_debug.db');
    for (final path in [firstDatabase, secondDatabase]) {
      await Directory(p.dirname(path)).create(recursive: true);
    }
    await CrashLogService.initialize(
      databasePath: firstDatabase,
      appVersion: '0.58.0',
      retentionCount: 5,
    );
  });

  tearDown(() async {
    CrashLogService.instanceOrNull?.stopLivenessHeartbeat();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'η μετακόμιση φέρνει το ημερολόγιο στον φάκελο της νέας βάσης',
    () async {
      final log = CrashLogService.instance;
      expect(log.logsDirectory, logsOf(firstDatabase));

      await log.retargetTo(databasePath: secondDatabase, retentionCount: 5);

      expect(log.logsDirectory, logsOf(secondDatabase));
    },
  );

  test('το ίχνος δηλώνει τη ΝΕΑ βάση, όχι την προηγούμενη', () async {
    final log = CrashLogService.instance;
    await log.retargetTo(databasePath: secondDatabase, retentionCount: 5);

    final marks = await readSessionLivenessMarks(logsOf(secondDatabase));

    expect(marks, hasLength(1));
    expect(marks.single.database, 'integrity_debug.db');
  });

  test('κανένα ίχνος-φάντασμα δεν μένει στον παλιό φάκελο', () async {
    final log = CrashLogService.instance;
    await log.retargetTo(databasePath: secondDatabase, retentionCount: 5);

    final leftovers = await readSessionLivenessMarks(logsOf(firstDatabase));

    expect(leftovers, isEmpty);
  });

  test(
    'ο φρουρός βλέπει τον συνάδελφο της ΝΕΑΣ βάσης μετά τη μετακόμιση',
    () async {
      final log = CrashLogService.instance;
      // Ο συνάδελφος κρατά τη δεύτερη βάση και άφησε ίχνος στον φάκελό της.
      await Directory(logsOf(secondDatabase)).create(recursive: true);
      final colleague = SessionLivenessMark(
        station: 'POPINIO',
        version: '0.57.1',
        startedAt: DateTime.now().subtract(const Duration(minutes: 30)),
        lastSeen: DateTime.now(),
      );
      await File(
        p.join(logsOf(secondDatabase), 'session_POPINIO.lock'),
      ).writeAsString(colleague.encode());

      // ΠΡΙΝ τη μετακόμιση ο φρουρός ρωτά τον παλιό φάκελο: τυφλός.
      final blind = await otherStationsHoldingDatabase(
        logsDirectory: log.logsDirectory,
        myStation: 'PICINIO',
        myDatabase: log.databaseFileName,
        myInstance: log.instanceId,
      );
      expect(blind, isEmpty);

      await log.retargetTo(databasePath: secondDatabase, retentionCount: 5);

      final seeing = await otherStationsHoldingDatabase(
        logsDirectory: log.logsDirectory,
        myStation: 'PICINIO',
        myDatabase: log.databaseFileName,
        myInstance: log.instanceId,
      );

      expect(seeing, hasLength(1));
      expect(seeing.single.station, 'POPINIO');
    },
  );

  test('φάκελος που δεν αλλάζει δεν πληρώνει τίποτα', () async {
    final log = CrashLogService.instance;
    final before = log.logsDirectory;

    await log.retargetTo(databasePath: firstDatabase, retentionCount: 5);

    expect(log.logsDirectory, before);
    expect(log.databaseFileName, 'Hospital.db');
  });
}
