// «Ένα αντίγραφο τη φορά»: όποιος κι αν το ζητήσει, δύο αντίγραφα δεν γράφουν
// ποτέ ταυτόχρονα, και «ΕΠΙΤΥΧΙΑ» σημαίνει ότι το αρχείο υπάρχει στον δίσκο.
//
//   flutter test test/features/database/services/database_backup_service_test.dart

import 'dart:async';
import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/services/backup_run_gate.dart';
import 'package:call_logger/features/database/services/backup_work_folder.dart';
import 'package:call_logger/features/database/services/database_backup_service.dart';
import 'package:call_logger/features/database/services/manual_backup_runner.dart';
import 'package:call_logger/features/database/utils/backup_destination_folder_validator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_setup.dart';

List<File> _backupFilesIn(Directory dir) => dir
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.db') || f.path.endsWith('.zip'))
    .toList();

Future<List<String>> _backupAuditActions() async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query(
    'audit_log',
    columns: ['action'],
    where: 'action LIKE ?',
    whereArgs: ['ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ%'],
  );
  return [for (final row in rows) row['action']! as String];
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  late Directory destDir;

  setUp(() async {
    destDir = Directory.systemTemp.createTempSync('backup_one_at_a_time_');
    addTearDown(() {
      if (destDir.existsSync()) destDir.deleteSync(recursive: true);
    });
    final db = await DatabaseHelper.instance.database;
    await db.delete('audit_log');
  });

  DatabaseBackupSettings settings() =>
      DatabaseBackupSettings.defaults().copyWith(
        destinationDirectory: destDir.path,
        backupOnExit: true,
        includeToolImages: false,
      );

  Future<ManualBackupResult> runManual({required void Function() onMarked}) =>
      runManualBackup(
        settings: settings(),
        inspectDestination: () =>
            BackupDestinationFolderValidator.inspectDestinationContent(
              destinationDirectory: destDir.path,
              dbBaseName: 'τεστ',
            ),
        markBackupTaken: ({
          required int auditId,
          required DateTime at,
          required String? fullFingerprint,
          required DateTime? fullAt,
        }) async => onMarked(),
      );

  test('διπλό πάτημα: μένει αρχείο στον δίσκο, και σημειώνεται μία φορά '
      'ότι πάρθηκε αντίγραφο', () async {
    var marks = 0;

    await Future.wait([
      runManual(onMarked: () => marks++),
      runManual(onMarked: () => marks++),
    ]);

    expect(_backupFilesIn(destDir), hasLength(1));
    expect(marks, 1);
  });

  test('διπλό πάτημα: το δεύτερο δεν ξεκινά δεύτερη εκτέλεση — το Ιστορικό '
      'γράφει μία «ΕΠΙΤΥΧΙΑ» και καμία «ΑΠΟΤΥΧΙΑ»', () async {
    await Future.wait([runManual(onMarked: () {}), runManual(onMarked: () {})]);

    expect(await _backupAuditActions(), ['ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΕΠΙΤΥΧΙΑ']);
  });

  test('ζητώντας αντίγραφο ενώ τρέχει άλλο: επιστρέφει «τρέχει ήδη» και δεν '
      'γράφει τίποτα στον φάκελο', () async {
    final release = Completer<void>();
    final holding = BackupRunGate.tryRun<Object>(() async {
      await release.future;
      return 'τέλος';
    });

    final manual = await runManual(onMarked: () {});
    final direct = await DatabaseBackupService.runBackupCreatingFolderIfNeeded(
      settings(),
    );

    release.complete();
    await holding;

    expect(manual.outcome, ManualBackupOutcome.alreadyRunning);
    expect(direct.wasAlreadyRunning, isTrue);
    expect(destDir.listSync(), isEmpty);
    expect(await _backupAuditActions(), isEmpty);
  });

  test(
    'η αναμονή τελειώνει μόνο όταν τελειώσει το αντίγραφο που τρέχει',
    () async {
      final release = Completer<void>();
      final holding = BackupRunGate.tryRun<Object>(() async {
        await release.future;
        return 'τέλος';
      });

      var waited = false;
      final waiting = BackupRunGate.whenIdle().then((_) => waited = true);
      await Future<void>.delayed(Duration.zero);
      expect(waited, isFalse);

      release.complete();
      await holding;
      await waiting;
      expect(waited, isTrue);
      expect(BackupRunGate.isRunning, isFalse);
    },
  );

  test('δεύτερο αντίγραφο στο ίδιο λεπτό: αντικαθιστά το πρώτο και δεν μένει '
      'προσωρινός φάκελος', () async {
    final first = await DatabaseBackupService.runBackup(settings());
    final second = await DatabaseBackupService.runBackup(settings());

    expect(first.success, isTrue);
    expect(second.success, isTrue);
    expect(File(second.outputPath!).existsSync(), isTrue);
    expect(destDir.listSync().whereType<Directory>(), isEmpty);
  });

  group('προσωρινός φάκελος', () {
    test('μισό αρχείο δεν φτάνει ποτέ στον φάκελο αντιγράφων, και το '
        'προηγούμενο αντίγραφο μένει άθικτο', () async {
      final finalPath = '${destDir.path}/αντίγραφο.zip';
      File(finalPath).writeAsStringSync('προηγούμενο καλό');

      final work = await BackupWorkFolder.create(destDir.path);
      File(work.pathFor(finalPath)).writeAsStringSync('μισό');
      await work.dispose();

      expect(File(finalPath).readAsStringSync(), 'προηγούμενο καλό');
      expect(destDir.listSync(), hasLength(1));
    });

    test('στο κανονικό όνομα αντικαθιστά ό,τι υπήρχε', () async {
      final finalPath = '${destDir.path}/αντίγραφο.db';
      File(finalPath).writeAsStringSync('παλιό');

      final work = await BackupWorkFolder.create(destDir.path);
      File(work.pathFor(finalPath)).writeAsStringSync('νέο');
      await work.publish(finalPath);
      await work.dispose();

      expect(File(finalPath).readAsStringSync(), 'νέο');
    });

    test(
      'εγκαταλειμμένος μαζεύεται, ενώ αυτός που γράφεται τώρα όχι',
      () async {
        final work = await BackupWorkFolder.create(destDir.path);

        await BackupWorkFolder.removeAbandoned(destDir.path);
        expect(destDir.listSync(), hasLength(1));

        await BackupWorkFolder.removeAbandoned(
          destDir.path,
          now: DateTime.now().add(const Duration(days: 3)),
        );
        expect(destDir.listSync(), isEmpty);
        await work.dispose();
      },
    );
  });
}
