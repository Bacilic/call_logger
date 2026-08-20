import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/services/current_operator.dart';
import '../../../core/services/profile_settings.dart';
import '../models/database_backup_settings.dart';
import '../utils/backup_schedule_utils.dart';

/// Φόρτωση και αποθήκευση [DatabaseBackupSettings] — **προσωπικά, ανά χρήστη**
/// (Φάση 2): το «δέμα» ζει στον πίνακα `operator_settings` του συνδεδεμένου
/// χρήστη και τον ακολουθεί σε όποιον υπολογιστή καθίσει. Χωρίς συνδεδεμένο
/// χρήστη, η [ProfileSettings] πέφτει στην παλιά κοινή θέση — όλα όπως χθες.
final databaseBackupSettingsProvider =
    NotifierProvider<DatabaseBackupSettingsNotifier, DatabaseBackupSettings>(
      DatabaseBackupSettingsNotifier.new,
    );

class DatabaseBackupSettingsNotifier extends Notifier<DatabaseBackupSettings> {
  @override
  DatabaseBackupSettings build() {
    // «Αλλαγή χρήστη» εν λειτουργία: το δέμα του προηγούμενου δεν ισχύει πια —
    // ξαναφορτώνεται του νέου, από το ίδιο ένα σημείο (αυτό εδώ).
    void onIdentityChanged() => unawaited(load());
    CurrentOperator.listenable.addListener(onIdentityChanged);
    ref.onDispose(
      () => CurrentOperator.listenable.removeListener(onIdentityChanged),
    );
    return DatabaseBackupSettings.defaults();
  }

  Future<void> load() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final raw = await ProfileSettings(
        db,
      ).read(ProfileSettingKeys.databaseBackupSettings);
      state = DatabaseBackupSettings.fromJsonString(raw);
    } catch (_) {
      state = DatabaseBackupSettings.defaults();
    }
  }

  Future<void> _persist() async {
    final db = await DatabaseHelper.instance.database;
    await ProfileSettings(
      db,
    ).write(ProfileSettingKeys.databaseBackupSettings, state.toJsonString());
  }

  Future<void> setDestinationDirectory(String value) async {
    // Μετάβαση από «χωρίς φάκελο» σε ορισμένο φάκελο = ενεργοποίηση του
    // προγράμματος: αγκυρώνουμε ώστε περασμένα slots να μη λογιστούν «χαμένα».
    final activatesSchedule =
        state.destinationDirectory.trim().isEmpty && value.trim().isNotEmpty;
    state = state.copyWith(
      destinationDirectory: value,
      scheduleAnchorAt: activatesSchedule ? DateTime.now() : null,
    );
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

  Future<void> setIncludeMapImagesInBackup(bool value) async {
    state = state.copyWith(
      includeMapImagesInBackup: value,
      zipOutput: value ? true : state.zipOutput,
    );
    await _persist();
  }

  Future<void> setIncludeToolImages(bool value) async {
    state = state.copyWith(
      includeToolImages: value,
      zipOutput: value ? true : state.zipOutput,
    );
    await _persist();
  }

  Future<void> setIncludeLexicon(bool value) async {
    state = state.copyWith(
      includeLexicon: value,
      zipOutput: value ? true : state.zipOutput,
    );
    await _persist();
  }

  Future<void> setIncludeLampDb(bool value) async {
    state = state.copyWith(
      includeLampDb: value,
      zipOutput: value ? true : state.zipOutput,
    );
    await _persist();
  }

  Future<void> setBackupOnExit(bool value) async {
    final turningOn = value && !state.backupOnExit;
    state = state.copyWith(
      backupOnExit: value,
      scheduleAnchorAt: turningOn ? DateTime.now() : null,
    );
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
      scheduleAnchorAt: DateTime.now(),
    );
    await _persist();
  }

  Future<void> setBackupTime(String value) async {
    state = state.copyWith(
      backupTime: value.trim(),
      scheduleAnchorAt: DateTime.now(),
    );
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

  Future<void> setLastManualBackupAttempt(DateTime value) async {
    state = state.copyWith(lastManualBackupAttempt: value);
    await _persist();
  }

  /// Ρητή παράβλεψη χαμένου αντιγράφου από τον χρήστη: καθαρίζει την ένδειξη
  /// ΚΑΙ αγκυρώνει το πρόγραμμα στο τώρα, ώστε το ίδιο περασμένο slot να μην
  /// ξανα-αναφερθεί «χαμένο» σε κάθε επόμενη εκκίνηση.
  Future<void> acknowledgeMissedBackup() async {
    state = state.copyWith(
      lastBackupStatus: BackupScheduleStatus.none,
      scheduleAnchorAt: DateTime.now(),
    );
    await _persist();
  }

  Future<void> setRetentionMaxCopiesEnabled(bool value) async {
    state = state.copyWith(retentionMaxCopiesEnabled: value);
    await _persist();
  }

  Future<void> setRetentionMaxCopies(int value) async {
    state = state.copyWith(retentionMaxCopies: value.clamp(1, 9999));
    await _persist();
  }

  Future<void> setRetentionMaxAgeEnabled(bool value) async {
    state = state.copyWith(retentionMaxAgeEnabled: value);
    await _persist();
  }

  Future<void> setRetentionMaxAgeDays(int value) async {
    state = state.copyWith(retentionMaxAgeDays: value.clamp(1, 9999));
    await _persist();
  }
}
