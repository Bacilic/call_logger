// Το τικ του χρονιστή άκρη-σε-άκρη (Φάσεις 3–4): μετρητής → πύλες →
// προτεραιότητα παρουσίας → ατομική δέσμευση → αντίγραφο → σημάδι.
//
//   flutter test test/features/database/providers/backup_scheduler_tick_test.dart

import 'dart:io';

import 'package:call_logger/core/database/backup_pending_changes.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/providers/backup_scheduler_provider.dart';
import 'package:call_logger/features/database/services/active_backup_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_setup.dart';

Operator _operator(int id, {bool isAdmin = false}) => Operator(
  id: id,
  displayName: 'Χρήστης $id',
  isAdmin: isAdmin,
  createdAt: DateTime(2026, 8, 20),
);

Future<void> _insertOperatorRow(int id, {bool isAdmin = false}) async {
  final db = await DatabaseHelper.instance.database;
  await db.insert('operators', {
    'id': id,
    'display_name': 'Χρήστης $id',
    'is_admin': isAdmin ? 1 : 0,
    'is_active': 1,
    'created_at': '2026-08-20T00:00:00.000',
  });
}

Future<void> _insertFreshPresence(int operatorId) async {
  final db = await DatabaseHelper.instance.database;
  await db.insert('operator_presence', {
    'operator_id': operatorId,
    'station': 'PC-ADMIN',
    'last_seen_at': DateTime.now().toIso8601String(),
    'instance': 'inst-admin',
  });
}

Future<void> _seedPendingChange() async {
  final db = await DatabaseHelper.instance.database;
  await db.insert('audit_log', {
    'action': 'ΔΟΚΙΜΑΣΤΙΚΗ ΑΛΛΑΓΗ',
    'timestamp': DateTime.now().toIso8601String(),
    'user_performing': 'τεστ',
    'details': 'αφύλακτη αλλαγή',
  });
}

Future<void> _saveSharedBundle(DatabaseBackupSettings settings) async {
  final db = await DatabaseHelper.instance.database;
  await SettingsRepository(
    db,
  ).saveSetting(DatabaseBackupSettings.appSettingsKey, settings.toJsonString());
}

Future<List<File>> _backupFilesIn(String dest) async {
  final dir = Directory(dest);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.db') || f.path.endsWith('.zip'))
      .toList();
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  late Directory destDir;

  setUp(() async {
    CurrentOperator.reset();
    destDir = Directory.systemTemp.createTempSync('sched_tick_');
    addTearDown(() {
      if (destDir.existsSync()) destDir.deleteSync(recursive: true);
    });
    final db = await DatabaseHelper.instance.database;
    await db.delete('audit_log');
    await db.delete('operator_presence');
    await db.delete('operators');
    await db.delete(
      'app_settings',
      where: 'key IN (?, ?)',
      whereArgs: [
        DatabaseBackupSettings.appSettingsKey,
        ActiveBackupSettings.migrationMarkerKey,
      ],
    );
  });

  tearDown(CurrentOperator.reset);

  DatabaseBackupSettings enabledBundle() =>
      DatabaseBackupSettings.defaults().copyWith(
        destinationDirectory: destDir.path,
        backupOnExit: true,
        includeToolImages: false,
      );

  test('οφειλόμενο αντίγραφο: το τικ το παίρνει και προχωρά το σημάδι — '
      'δεύτερο τικ δεν ξαναπαίρνει', () async {
    await _saveSharedBundle(enabledBundle());
    await _seedPendingChange();
    await _insertOperatorRow(71, isAdmin: true);
    CurrentOperator.activate(_operator(71, isAdmin: true));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final scheduler = container.read(backupSchedulerProvider.notifier);

    await scheduler.debugRunTick();

    expect(await _backupFilesIn(destDir.path), hasLength(1));
    final db = await DatabaseHelper.instance.database;
    final saved = await ActiveBackupSettings.read();
    expect(
      await BackupPendingChangesRepository(
        db,
      ).countPendingSince(saved.lastBackupAuditId),
      0,
      reason: 'Το σημάδι καλύπτει τις αλλαγές ΚΑΙ την audit εγγραφή του.',
    );

    await scheduler.debugRunTick();
    expect(
      await _backupFilesIn(destDir.path),
      hasLength(1),
      reason: 'Χωρίς νέες αλλαγές, το επόμενο τικ δεν παίρνει τίποτα.',
    );
  });

  test(
    'ο εφεδρικός παραχωρεί σε παρόντα διαχειριστή — κανένα αρχείο',
    () async {
      await _saveSharedBundle(enabledBundle());
      await _seedPendingChange();
      await _insertOperatorRow(71, isAdmin: true);
      await _insertOperatorRow(72);
      await _insertFreshPresence(71);
      CurrentOperator.activate(
        Operator(
          id: 72,
          displayName: 'Εφεδρικός',
          permissionOverrides: const {'full_backup': true},
          createdAt: DateTime(2026, 8, 20),
        ),
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(backupSchedulerProvider.notifier).debugRunTick();

      expect(await _backupFilesIn(destDir.path), isEmpty);
    },
  );

  test('με τον διαχειριστή απόντα, ο εφεδρικός αναλαμβάνει', () async {
    await _saveSharedBundle(enabledBundle());
    await _seedPendingChange();
    await _insertOperatorRow(71, isAdmin: true);
    await _insertOperatorRow(72);
    CurrentOperator.activate(
      Operator(
        id: 72,
        displayName: 'Εφεδρικός',
        permissionOverrides: const {'full_backup': true},
        createdAt: DateTime(2026, 8, 20),
      ),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(backupSchedulerProvider.notifier).debugRunTick();

    expect(await _backupFilesIn(destDir.path), hasLength(1));
  });

  test('χρήστης χωρίς δικαίωμα: το τικ δεν αγγίζει τίποτα', () async {
    await _saveSharedBundle(enabledBundle());
    await _seedPendingChange();
    await _insertOperatorRow(72);
    CurrentOperator.activate(_operator(72));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(backupSchedulerProvider.notifier).debugRunTick();

    expect(await _backupFilesIn(destDir.path), isEmpty);
  });

  test('χαμένη δέσμευση: το δέμα άλλαξε μετά την ανάγνωση — το τικ του '
      'δεύτερου δεν παίρνει δεύτερο αντίγραφο αμέσως', () async {
    await _saveSharedBundle(enabledBundle());
    await _seedPendingChange();
    await _insertOperatorRow(71, isAdmin: true);
    CurrentOperator.activate(_operator(71, isAdmin: true));

    // Το «άλλο μηχάνημα» μόλις πήρε το αντίγραφο: σημάδι φρέσκο, απόσταση
    // μηδενική. Το δικό μας τικ διαβάζει πια τη φρέσκια αλήθεια και κρίνει
    // «δεν οφείλεται» — καμία κούρσα, κανένα διπλό.
    final db = await DatabaseHelper.instance.database;
    final markId = await BackupPendingChangesRepository(db).latestAuditId();
    await _saveSharedBundle(
      enabledBundle().copyWith(
        lastBackupAuditId: markId,
        lastBackupAttempt: DateTime.now(),
        lastBackupStatus: 'success',
      ),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(backupSchedulerProvider.notifier).debugRunTick();

    expect(await _backupFilesIn(destDir.path), isEmpty);
  });
}
