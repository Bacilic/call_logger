import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../models/database_backup_settings.dart';

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
      final raw = await DatabaseHelper.instance
          .getSetting(DatabaseBackupSettings.appSettingsKey);
      state = DatabaseBackupSettings.fromJsonString(raw);
    } catch (_) {
      state = DatabaseBackupSettings.defaults();
    }
  }

  Future<void> _persist() async {
    await DatabaseHelper.instance.setSetting(
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
