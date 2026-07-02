// Τεστ-φρουροί διπλής εκτέλεσης exit backup (Άξονας 3, Φάση 4).
//
//   flutter test test/features/database/services/database_exit_backup_test.dart

import 'dart:io';

import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/services/database_exit_backup.dart';
import 'package:call_logger/features/database/utils/backup_schedule_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../test_setup.dart';

DatabaseBackupSettings _exitBackupSettings({
  required String destinationDirectory,
  DateTime? lastBackupAttempt,
  String lastBackupStatus = BackupScheduleStatus.none,
}) {
  final now = DateTime.now();
  return DatabaseBackupSettings(
    destinationDirectory: destinationDirectory,
    namingFormat: DatabaseBackupNamingFormat.dateTimeThenBase,
    zipOutput: false,
    includeMapImagesInBackup: false,
    includeToolImages: false,
    includeLexicon: false,
    includeLampDb: false,
    backupOnExit: true,
    interval: DatabaseBackupInterval.never,
    backupDays: [now.weekday],
    backupTime: '00:00',
    lastBackupAttempt: lastBackupAttempt,
    lastManualBackupAttempt: null,
    lastBackupStatus: lastBackupStatus,
    retentionMaxCopiesEnabled: false,
    retentionMaxCopies: 30,
    retentionMaxAgeEnabled: false,
    retentionMaxAgeDays: 60,
  );
}

Future<void> _saveBackupSettings(DatabaseBackupSettings settings) async {
  final db = await DatabaseHelper.instance.database;
  final repo = SettingsRepository(db);
  await repo.saveSetting(
    DatabaseBackupSettings.appSettingsKey,
    settings.toJsonString(),
  );
}

Future<List<FileSystemEntity>> _listBackupDbFiles(String destinationDir) async {
  final dir = Directory(destinationDir);
  if (!await dir.exists()) return const [];
  return dir
      .listSync()
      .where(
        (e) =>
            e is File &&
            (e.path.endsWith('.db') || e.path.endsWith('.zip')),
      )
      .toList();
}

Future<List<Map<String, dynamic>>> _exitBackupAuditRows() async {
  final db = await DatabaseHelper.instance.database;
  return db.query(
    'audit_log',
    where: 'entity_type = ?',
    whereArgs: [AuditEntityTypes.backup],
    orderBy: 'id ASC',
  );
}

void main() {
  late Directory tempRoot;
  late String backupDestDir;
  late String dbBaseName;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    initSqfliteFfiForTests();
    tempRoot = await Directory.systemTemp.createTemp('exit_backup_test_');
    backupDestDir = p.join(tempRoot.path, 'backups');
    await Directory(backupDestDir).create(recursive: true);

    final dbPath = p.join(tempRoot.path, 'exit_backup.db');
    await DatabaseHelper.bindTestDatabaseFile(dbPath);
    await DatabaseHelper.instance.database;
    dbBaseName = p.basenameWithoutExtension(dbPath);
    await seedIsolatedTestDatabase();
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    final db = await DatabaseHelper.instance.database;
    await db.delete('audit_log');

    for (final entity in Directory(backupDestDir).listSync()) {
      if (entity is File) {
        await entity.delete();
      }
    }
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('DatabaseExitBackup.runIfEnabled (τεστ-φρουρός)', () {
    test('μία κλήση exit backup δημιουργεί αρχείο και audit', () async {
      await _saveBackupSettings(_exitBackupSettings(
        destinationDirectory: backupDestDir,
      ));

      await DatabaseExitBackup.runIfEnabled();

      final backupFiles = await _listBackupDbFiles(backupDestDir);
      expect(backupFiles, hasLength(1));

      final audits = await _exitBackupAuditRows();
      expect(
        audits.where((r) => r['action'] == 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΕΠΙΤΥΧΙΑ'),
        hasLength(1),
      );
    });

    test('διπλή παράλληλη κλήση → ένα αρχείο backup και ένα audit επιτυχίας', () async {
      await _saveBackupSettings(_exitBackupSettings(
        destinationDirectory: backupDestDir,
      ));

      await Future.wait([
        DatabaseExitBackup.runIfEnabled(),
        DatabaseExitBackup.runIfEnabled(),
      ]);

      final backupFiles = await _listBackupDbFiles(backupDestDir);
      expect(
        backupFiles,
        hasLength(1),
        reason: 'Δύο ταυτόχρονες κλήσεις exit backup πρέπει να παράγουν ένα αρχείο',
      );
      expect(
        p.basename(backupFiles.single.path),
        contains(dbBaseName),
      );

      final audits = await _exitBackupAuditRows();
      final successAudits = audits
          .where((r) => r['action'] == 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΕΠΙΤΥΧΙΑ')
          .toList();
      expect(
        successAudits,
        hasLength(1),
        reason: 'Μία επιτυχής καταγραφή audit για exit backup',
      );
    });

    test(
      'αποτυχία backup (ανύπαρκτος φάκελος) δεν αφήνει τη βάση κλειδωμένη',
      () async {
        final missingDest = p.join(tempRoot.path, 'missing_backup_folder');
        await _saveBackupSettings(_exitBackupSettings(
          destinationDirectory: missingDest,
        ));

        await DatabaseExitBackup.runIfEnabled();

        final db = await DatabaseHelper.instance.database;
        final probe = await db.rawQuery('SELECT COUNT(*) AS c FROM calls');
        expect((probe.first['c'] as int?) ?? 0, greaterThanOrEqualTo(0));

        await DatabaseHelper.instance.closeConnection();
        await DatabaseHelper.instance.database;
        final reopened = await DatabaseHelper.instance.database;
        expect(reopened.isOpen, isTrue);

        final audits = await _exitBackupAuditRows();
        final failedAudits = audits
            .where((r) => r['action'] == 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΑΠΟΤΥΧΙΑ')
            .toList();
        expect(failedAudits, isNotEmpty);

        final repo = SettingsRepository(reopened);
        final raw = await repo.getSetting(DatabaseBackupSettings.appSettingsKey);
        final saved = DatabaseBackupSettings.fromJsonString(raw);
        expect(
          BackupScheduleStatus.normalize(saved.lastBackupStatus),
          BackupScheduleStatus.folderMissing,
        );
      },
    );

    test(
      'η ροή δεν ρίχνει εξαίρεση προς τα έξω — καταγράφει αποτυχία στο audit',
      () async {
        final blockedDest = p.join(tempRoot.path, 'blocked_dest_file');
        await File(blockedDest).writeAsString('not-a-directory');

        await _saveBackupSettings(_exitBackupSettings(
          destinationDirectory: blockedDest,
        ));

        await expectLater(
          DatabaseExitBackup.runIfEnabled(),
          completes,
        );

        final backupFiles = await _listBackupDbFiles(blockedDest);
        expect(backupFiles, isEmpty);

        final audits = await _exitBackupAuditRows();
        expect(
          audits.any((r) => r['action'] == 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΑΠΟΤΥΧΙΑ'),
          isTrue,
          reason:
              'Σημερινή συμπεριφορά: αποτυχία backup καταγράφεται στο audit, '
              'χωρίς εξαίρεση προς τον καλούντα',
        );
      },
    );
  });
}
