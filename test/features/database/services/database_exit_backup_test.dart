// Τεστ-φρουροί διπλής εκτέλεσης exit backup (Άξονας 3, Φάση 4).
//
//   flutter test test/features/database/services/database_exit_backup_test.dart

import 'dart:io';

import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/operator_settings_repository.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/services/active_backup_settings.dart';
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
  bool backupOnCloseIfPending = true,
}) => DatabaseBackupSettings.defaults().copyWith(
  destinationDirectory: destinationDirectory,
  backupOnExit: true,
  backupOnCloseIfPending: backupOnCloseIfPending,
  includeToolImages: false,
  lastBackupAttempt: lastBackupAttempt,
  lastBackupStatus: lastBackupStatus,
);

/// Μία αφύλακτη αλλαγή στο Ιστορικό — το κλείσιμο παίρνει αντίγραφο ΜΟΝΟ όταν
/// υπάρχει κάτι να προστατεύσει (Φάση 3).
Future<void> _seedPendingChange() async {
  final db = await DatabaseHelper.instance.database;
  await db.insert('audit_log', {
    'action': 'ΔΟΚΙΜΑΣΤΙΚΗ ΑΛΛΑΓΗ',
    'timestamp': DateTime.now().toIso8601String(),
    'user_performing': 'τεστ',
    'details': 'αφύλακτη αλλαγή',
  });
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
        (e) => e is File && (e.path.endsWith('.db') || e.path.endsWith('.zip')),
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
    CurrentOperator.reset();
    await seedIsolatedTestDatabase();
    final db = await DatabaseHelper.instance.database;
    await db.delete('audit_log');
    await db.delete(OperatorSettingsRepository.tableName);
    await db.delete('operator_presence');
    await db.delete('operators');
    // Η σημαία μετάπτωσης καθαρίζεται ώστε κάθε τεστ να ορίζει μόνο του αν η
    // επιστροφή στα κοινά έχει ήδη γίνει.
    await db.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: [ActiveBackupSettings.migrationMarkerKey],
    );

    for (final entity in Directory(backupDestDir).listSync()) {
      if (entity is File) {
        await entity.delete();
      }
    }
  });

  tearDown(CurrentOperator.reset);

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('DatabaseExitBackup.runIfEnabled (τεστ-φρουρός)', () {
    test('μία κλήση exit backup δημιουργεί αρχείο και audit', () async {
      await _saveBackupSettings(
        _exitBackupSettings(destinationDirectory: backupDestDir),
      );
      await _seedPendingChange();

      await DatabaseExitBackup.runIfEnabled();

      final backupFiles = await _listBackupDbFiles(backupDestDir);
      expect(backupFiles, hasLength(1));

      final audits = await _exitBackupAuditRows();
      expect(
        audits.where((r) => r['action'] == 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΕΠΙΤΥΧΙΑ'),
        hasLength(1),
      );
    });

    test(
      'διπλή παράλληλη κλήση → ένα αρχείο backup και ένα audit επιτυχίας',
      () async {
        await _saveBackupSettings(
          _exitBackupSettings(destinationDirectory: backupDestDir),
        );
        await _seedPendingChange();

        await Future.wait([
          DatabaseExitBackup.runIfEnabled(),
          DatabaseExitBackup.runIfEnabled(),
        ]);

        final backupFiles = await _listBackupDbFiles(backupDestDir);
        expect(
          backupFiles,
          hasLength(1),
          reason:
              'Δύο ταυτόχρονες κλήσεις exit backup πρέπει να παράγουν ένα αρχείο',
        );
        expect(p.basename(backupFiles.single.path), contains(dbBaseName));

        final audits = await _exitBackupAuditRows();
        final successAudits = audits
            .where((r) => r['action'] == 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΕΠΙΤΥΧΙΑ')
            .toList();
        expect(
          successAudits,
          hasLength(1),
          reason: 'Μία επιτυχής καταγραφή audit για exit backup',
        );
      },
    );

    test(
      'αποτυχία backup (ανύπαρκτος φάκελος) δεν αφήνει τη βάση κλειδωμένη',
      () async {
        final missingDest = p.join(tempRoot.path, 'missing_backup_folder');
        await _saveBackupSettings(
          _exitBackupSettings(destinationDirectory: missingDest),
        );
        await _seedPendingChange();

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
        final raw = await repo.getSetting(
          DatabaseBackupSettings.appSettingsKey,
        );
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

        await _saveBackupSettings(
          _exitBackupSettings(destinationDirectory: blockedDest),
        );
        await _seedPendingChange();

        await expectLater(DatabaseExitBackup.runIfEnabled(), completes);

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

  // Φάσεις 0 & 2 του μηχανισμού αντιγράφων: το exit backup περνά από τη μία
  // πύλη ρυθμίσεων (κοινό δέμα, με μετάπτωση επιστροφής από τα προσωπικά) και
  // σέβεται το δικαίωμα του πλήρους αντιγράφου.
  group('DatabaseExitBackup — μία πηγή ρυθμίσεων και δικαίωμα', () {
    Operator operatorWith({
      required int id,
      bool isAdmin = false,
      Map<String, bool> overrides = const <String, bool>{},
    }) => Operator(
      id: id,
      displayName: 'Χρήστης $id',
      isAdmin: isAdmin,
      permissionOverrides: overrides,
      createdAt: DateTime(2026, 8, 20),
    );

    Future<void> insertOperatorRow(int id, {bool isAdmin = false}) async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('operators', {
        'id': id,
        'display_name': 'Χρήστης $id',
        'is_admin': isAdmin ? 1 : 0,
        'is_active': 1,
        'created_at': '2026-08-20T00:00:00.000',
      });
    }

    Future<String> makeDest(String name) async {
      final dir = p.join(tempRoot.path, name);
      await Directory(dir).create(recursive: true);
      for (final entity in Directory(dir).listSync()) {
        if (entity is File) await entity.delete();
      }
      return dir;
    }

    test('με συνδεδεμένο διαχειριστή διαβάζεται το κοινό δέμα και η '
        'κατάσταση γράφεται πίσω σε αυτό', () async {
      final dest = await makeDest('shared_dest');
      await _saveBackupSettings(
        _exitBackupSettings(destinationDirectory: dest),
      );
      await _seedPendingChange();
      CurrentOperator.activate(operatorWith(id: 71, isAdmin: true));

      await DatabaseExitBackup.runIfEnabled();

      expect(await _listBackupDbFiles(dest), hasLength(1));
      final db = await DatabaseHelper.instance.database;
      final raw = await SettingsRepository(
        db,
      ).getSetting(DatabaseBackupSettings.appSettingsKey);
      final saved = DatabaseBackupSettings.fromJsonString(raw);
      expect(
        BackupScheduleStatus.normalize(saved.lastBackupStatus),
        BackupScheduleStatus.success,
        reason: 'Μία κοινή κατάσταση — τη βλέπουν όλοι, όχι μόνο όποιος έτρεξε',
      );
    });

    test('μεταβατικά: το φρέσκο προσωπικό δέμα του διαχειριστή προωθείται '
        'στα κοινά πριν από το αντίγραφο', () async {
      final staleDest = await makeDest('stale_shared_dest');
      final promotedDest = await makeDest('promoted_dest');

      // Η κοινή θέση κρατά την παγωμένη προ-προφίλ τιμή· το φρέσκο δέμα ζει
      // ακόμη στο προσωπικό αντίτυπο του διαχειριστή (κατάσταση 0.43).
      await _saveBackupSettings(
        _exitBackupSettings(destinationDirectory: staleDest),
      );
      await _seedPendingChange();
      await insertOperatorRow(71, isAdmin: true);
      final db = await DatabaseHelper.instance.database;
      await OperatorSettingsRepository(db).setValue(
        71,
        DatabaseBackupSettings.appSettingsKey,
        _exitBackupSettings(destinationDirectory: promotedDest).toJsonString(),
      );
      CurrentOperator.activate(operatorWith(id: 71, isAdmin: true));

      await DatabaseExitBackup.runIfEnabled();

      expect(
        await _listBackupDbFiles(promotedDest),
        hasLength(1),
        reason: 'Η μετάπτωση προηγείται: το αντίγραφο πάει στον φρέσκο φάκελο',
      );
      expect(await _listBackupDbFiles(staleDest), isEmpty);
      final raw = await SettingsRepository(
        db,
      ).getSetting(DatabaseBackupSettings.appSettingsKey);
      expect(
        raw,
        contains('promoted_dest'),
        reason: 'Το προωθημένο δέμα έγινε η κοινή αλήθεια',
      );
    });

    test(
      'χρήστης χωρίς δικαίωμα πλήρους αντιγράφου δεν παίρνει exit backup',
      () async {
        final dest = await makeDest('no_permission_dest');

        // Το κοινό δέμα είναι πλήρες και έγκυρο — μόνο το δικαίωμα (κλειστό
        // από προεπιλογή για μη διαχειριστές) σταματά το αντίγραφο.
        await _saveBackupSettings(
          _exitBackupSettings(destinationDirectory: dest),
        );
        await _seedPendingChange();
        CurrentOperator.activate(operatorWith(id: 72));

        await DatabaseExitBackup.runIfEnabled();

        expect(await _listBackupDbFiles(dest), isEmpty);
        final audits = await _exitBackupAuditRows();
        expect(
          audits.where((r) => r['action'] == 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΕΠΙΤΥΧΙΑ'),
          isEmpty,
          reason: 'Χωρίς δικαίωμα, το κλείσιμο δεν παίρνει αντίγραφο',
        );
      },
    );

    test('χρήστης με ρητό τικ πλήρους αντιγράφου παίρνει exit backup', () async {
      final dest = await makeDest('deputy_dest');

      await _saveBackupSettings(
        _exitBackupSettings(destinationDirectory: dest),
      );
      await _seedPendingChange();
      CurrentOperator.activate(
        operatorWith(id: 73, overrides: const {'full_backup': true}),
      );

      await DatabaseExitBackup.runIfEnabled();

      expect(
        await _listBackupDbFiles(dest),
        hasLength(1),
        reason:
            'Το ρητό τικ δίνει στον εφεδρικό το αντίγραφο του κλεισίματος — '
            'με τις ΙΔΙΕΣ κοινές ρυθμίσεις που όρισε ο διαχειριστής',
      );
    });

    test('χωρίς αφύλακτες αλλαγές το κλείσιμο δεν παίρνει αντίγραφο', () async {
      final dest = await makeDest('no_pending_dest');
      // Έγκυρο δέμα, αλλά το Ιστορικό είναι καθαρό — τίποτα να προστατευτεί.
      await _saveBackupSettings(
        _exitBackupSettings(destinationDirectory: dest),
      );
      await _seedPendingChange();
      // Το σημάδι καλύπτει ήδη την αλλαγή — σαν να πάρθηκε μόλις αντίγραφο.
      final db = await DatabaseHelper.instance.database;
      final maxRow = await db.rawQuery('SELECT MAX(id) AS m FROM audit_log');
      await _saveBackupSettings(
        _exitBackupSettings(destinationDirectory: dest).copyWith(
          lastBackupAuditId: (maxRow.first['m'] as int?) ?? 0,
          lastBackupAttempt: DateTime.now(),
        ),
      );
      CurrentOperator.activate(operatorWith(id: 71, isAdmin: true));

      await DatabaseExitBackup.runIfEnabled();

      expect(
        await _listBackupDbFiles(dest),
        isEmpty,
        reason: 'Βάση χωρίς νέες αλλαγές δεν αντιγράφεται ποτέ (Φάση 3)',
      );
    });

    test('ο διακόπτης «και στο κλείσιμο» το απενεργοποιεί', () async {
      final dest = await makeDest('close_switch_off_dest');
      await _saveBackupSettings(
        _exitBackupSettings(
          destinationDirectory: dest,
          backupOnCloseIfPending: false,
        ),
      );
      await _seedPendingChange();
      CurrentOperator.activate(operatorWith(id: 71, isAdmin: true));

      await DatabaseExitBackup.runIfEnabled();

      expect(await _listBackupDbFiles(dest), isEmpty);
    });

    test('το κλείσιμο του εφεδρικού παραχωρεί σε παρόντα διαχειριστή', () async {
      final dest = await makeDest('deputy_defer_dest');
      await _saveBackupSettings(
        _exitBackupSettings(destinationDirectory: dest),
      );
      await _seedPendingChange();

      final db = await DatabaseHelper.instance.database;
      await db.insert('operators', {
        'id': 71,
        'display_name': 'Διαχειριστής',
        'is_admin': 1,
        'is_active': 1,
        'created_at': '2026-08-20T00:00:00.000',
      });
      await db.insert('operator_presence', {
        'operator_id': 71,
        'station': 'PC-ADMIN',
        'last_seen_at': DateTime.now().toIso8601String(),
        'instance': 'inst-admin',
      });
      CurrentOperator.activate(
        operatorWith(id: 73, overrides: const {'full_backup': true}),
      );

      await DatabaseExitBackup.runIfEnabled();

      expect(
        await _listBackupDbFiles(dest),
        isEmpty,
        reason:
            'Ο χρονιστής του παρόντος διαχειριστή θα καλύψει τις αλλαγές — '
            'το κλείσιμο του εφεδρικού δεν παίρνει αντίγραφο.',
      );
    });
  });
}
