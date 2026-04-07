import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_repository.dart';
import '../models/database_backup_settings.dart';
import '../utils/backup_schedule_utils.dart';

/// Φόρτωση και αποθήκευση [DatabaseBackupSettings] στον πίνακα `app_settings`.
final databaseBackupSettingsProvider =
    NotifierProvider<DatabaseBackupSettingsNotifier, DatabaseBackupSettings>(
  DatabaseBackupSettingsNotifier.new,
);

class DatabaseBackupSettingsNotifier
    extends Notifier<DatabaseBackupSettings> {
  @override
  DatabaseBackupSettings build() => DatabaseBackupSettings.defaults();

  Future<void> load() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final raw = await DirectoryRepository(db)
          .getSetting(DatabaseBackupSettings.appSettingsKey);
      state = DatabaseBackupSettings.fromJsonString(raw);
    } catch (_) {
      state = DatabaseBackupSettings.defaults();
    }
  }

  Future<void> _persist() async {
    final db = await DatabaseHelper.instance.database;
    await DirectoryRepository(db).setSetting(
      DatabaseBackupSettings.appSettingsKey,
      state.toJsonString(),
    );
  }

  Future<void> setDestinationDirectory(String value) async {
    state = state.copyWith(destinationDirectory: value);
    await _persist();
  }

  Future<void> setNamingFormat(DatabaseBackupNamingFormat value) async {
    state = state.copyWith(namingFormat: value);
    await _persist();
  }

  Future<void> setZipOutput(bool value) async {
    state = state.copyWith(zipOutput: value);
    await _persist();
  }

  Future<void> setBackupOnExit(bool value) async {
    state = state.copyWith(backupOnExit: value);
    await _persist();
  }

  Future<void> setInterval(DatabaseBackupInterval value) async {
    state = state.copyWith(interval: value);
    await _persist();
  }

  Future<void> setBackupScheduleDays(List<int> value) async {
    final normalized = BackupScheduleUtils.normalizeDays(value);
    state = state.copyWith(
      backupDays: normalized,
      interval: normalized.isNotEmpty
          ? DatabaseBackupInterval.never
          : state.interval,
    );
    await _persist();
  }

  Future<void> setBackupTime(String value) async {
    state = state.copyWith(backupTime: value.trim());
    await _persist();
  }

  Future<void> setLastBackupAttempt(DateTime? value) async {
    if (value == null) {
      state = state.copyWith(clearLastBackupAttempt: true);
    } else {
      state = state.copyWith(
        lastBackupAttempt: value,
        clearLastBackupAttempt: false,
      );
    }
    await _persist();
  }

  Future<void> setLastBackupStatus(String value) async {
    state = state.copyWith(
      lastBackupStatus: BackupScheduleStatus.normalize(value),
    );
    await _persist();
  }

  Future<void> setRetentionMaxCopiesEnabled(bool value) async {
    state = state.copyWith(retentionMaxCopiesEnabled: value);
    await _persist();
  }

  Future<void> setRetentionMaxCopies(int value) async {
    state = state.copyWith(
      retentionMaxCopies: value.clamp(1, 9999),
    );
    await _persist();
  }

  Future<void> setRetentionMaxAgeEnabled(bool value) async {
    state = state.copyWith(retentionMaxAgeEnabled: value);
    await _persist();
  }

  Future<void> setRetentionMaxAgeDays(int value) async {
    state = state.copyWith(
      retentionMaxAgeDays: value.clamp(1, 9999),
    );
    await _persist();
  }
}
