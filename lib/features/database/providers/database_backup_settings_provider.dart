import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/current_operator.dart';
import '../models/database_backup_settings.dart';
import '../services/active_backup_settings.dart';
import '../utils/backup_schedule_utils.dart';

/// Φόρτωση και αποθήκευση [DatabaseBackupSettings] — **μία κοινή ρύθμιση της
/// βάσης** (Φάση 2 του μηχανισμού αντιγράφων): το «δέμα» ζει στο
/// `app_settings`, ίδιο για όλους· ο διαχειριστής το ορίζει και όποιος έχει
/// το δικαίωμα το εκτελεί απαράλλαχτο. Ανάγνωση και εγγραφή περνούν από την
/// [ActiveBackupSettings], όπως όλα τα μονοπάτια.
final databaseBackupSettingsProvider =
    NotifierProvider<DatabaseBackupSettingsNotifier, DatabaseBackupSettings>(
      DatabaseBackupSettingsNotifier.new,
    );

class DatabaseBackupSettingsNotifier extends Notifier<DatabaseBackupSettings> {
  @override
  DatabaseBackupSettings build() {
    // «Αλλαγή χρήστη» εν λειτουργία: η τιμή είναι πια κοινή, αλλά το ξαναφόρτωμα
    // ειδοποιεί όσους ακούν τον provider να ξαναχτιστούν — μαζί και τους
    // ελέγχους δικαιώματος στην οθόνη ρυθμίσεων.
    void onIdentityChanged() => unawaited(load());
    CurrentOperator.listenable.addListener(onIdentityChanged);
    ref.onDispose(
      () => CurrentOperator.listenable.removeListener(onIdentityChanged),
    );
    return DatabaseBackupSettings.defaults();
  }

  Future<void> load() async {
    try {
      state = await ActiveBackupSettings.read();
    } catch (_) {
      state = DatabaseBackupSettings.defaults();
    }
  }

  /// Υιοθέτηση τιμής που διαβάστηκε ήδη φρέσκια από τη βάση (χρονιστής):
  /// ενημερώνει την οθόνη χωρίς δεύτερη ανάγνωση και ΧΩΡΙΣ εγγραφή.
  void adopt(DatabaseBackupSettings value) {
    state = value;
  }

  Future<void> _persist() async {
    await ActiveBackupSettings.write(state);
  }

  Future<void> setDestinationDirectory(String value) async {
    state = state.copyWith(destinationDirectory: value);
    await _persist();
  }

  Future<void> setNamingFormat(DatabaseBackupNamingFormat value) async {
    state = state.copyWith(namingFormat: value);
    await _persist();
  }

  Future<void> setIncludeMapImagesInBackup(bool value) async {
    state = state.copyWith(includeMapImagesInBackup: value);
    await _persist();
  }

  Future<void> setIncludeToolImages(bool value) async {
    state = state.copyWith(includeToolImages: value);
    await _persist();
  }

  Future<void> setIncludeLexicon(bool value) async {
    state = state.copyWith(includeLexicon: value);
    await _persist();
  }

  Future<void> setIncludeLampDb(bool value) async {
    state = state.copyWith(includeLampDb: value);
    await _persist();
  }

  Future<void> setBackupOnExit(bool value) async {
    state = state.copyWith(backupOnExit: value);
    await _persist();
  }

  Future<void> setChangeThreshold(int value) async {
    state = state.copyWith(changeThreshold: value.clamp(1, 9999));
    await _persist();
  }

  Future<void> setMinSpacingMinutes(int value) async {
    state = state.copyWith(
      minSpacingMinutes: value.clamp(
        DatabaseBackupSettings.minAllowedSpacingMinutes,
        1440,
      ),
    );
    await _persist();
  }

  Future<void> setMaxWaitMinutes(int value) async {
    state = state.copyWith(
      maxWaitMinutes: value.clamp(
        DatabaseBackupSettings.minAllowedSpacingMinutes,
        10080,
      ),
    );
    await _persist();
  }

  Future<void> setBackupOnCloseIfPending(bool value) async {
    state = state.copyWith(backupOnCloseIfPending: value);
    await _persist();
  }

  /// Σφραγίζει επιτυχές αντίγραφο: μέχρι ποιον αύξοντα αριθμό Ιστορικού είναι
  /// πια φυλαγμένες οι αλλαγές — μία εγγραφή, ώστε σημάδι και ώρα να μην
  /// αποκλίνουν ποτέ.
  Future<void> markBackupTaken({
    required int auditId,
    required DateTime at,
    bool manual = false,
    String? fullFingerprint,
    DateTime? fullAt,
  }) async {
    state = state.copyWith(
      lastBackupAuditId: auditId,
      lastBackupAttempt: manual ? null : at,
      lastManualBackupAttempt: manual ? at : null,
      lastFullBackupFingerprint: fullFingerprint,
      lastFullBackupAt: fullAt,
      lastBackupStatus: BackupScheduleStatus.success,
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

  Future<void> setRetentionQuickMaxCopiesEnabled(bool value) async {
    state = state.copyWith(retentionQuickMaxCopiesEnabled: value);
    await _persist();
  }

  Future<void> setRetentionQuickMaxCopies(int value) async {
    state = state.copyWith(retentionQuickMaxCopies: value.clamp(1, 9999));
    await _persist();
  }

  Future<void> setRetentionQuickMaxAgeEnabled(bool value) async {
    state = state.copyWith(retentionQuickMaxAgeEnabled: value);
    await _persist();
  }

  Future<void> setRetentionQuickMaxAgeDays(int value) async {
    state = state.copyWith(retentionQuickMaxAgeDays: value.clamp(1, 9999));
    await _persist();
  }

  Future<void> setRetentionFullMaxCopiesEnabled(bool value) async {
    state = state.copyWith(retentionFullMaxCopiesEnabled: value);
    await _persist();
  }

  Future<void> setRetentionFullMaxCopies(int value) async {
    state = state.copyWith(retentionFullMaxCopies: value.clamp(1, 9999));
    await _persist();
  }
}
