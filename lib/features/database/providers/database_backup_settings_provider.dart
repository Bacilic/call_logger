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

  /// Κάθε αλλαγή επιλογής περνά από εδώ.
  ///
  /// Η [change] εφαρμόζεται πάνω στη **φρέσκια** αποθηκευμένη τιμή, όχι στην
  /// εικόνα που κρατά η οθόνη: το δέμα είναι κοινό και περιέχει και τη
  /// λογιστική των αντιγράφων, οπότε γράφοντάς το ολόκληρο από παλιά εικόνα
  /// σβήναμε τη σφραγίδα του αντιγράφου που μόλις πήρε το άλλο μηχάνημα.
  /// Η [state] ενημερώνεται με ό,τι όντως αποθηκεύτηκε — έτσι η οθόνη
  /// αυτοδιορθώνεται και δείχνει και τις ξένες αλλαγές.
  Future<void> _update(
    DatabaseBackupSettings Function(DatabaseBackupSettings current) change,
  ) async {
    state = await ActiveBackupSettings.update(change);
  }

  Future<void> setDestinationDirectory(String value) async {
    await _update((current) => current.copyWith(destinationDirectory: value));
  }

  Future<void> setNamingFormat(DatabaseBackupNamingFormat value) async {
    await _update((current) => current.copyWith(namingFormat: value));
  }

  Future<void> setIncludeMapImagesInBackup(bool value) async {
    await _update(
      (current) => current.copyWith(includeMapImagesInBackup: value),
    );
  }

  Future<void> setIncludeToolImages(bool value) async {
    await _update((current) => current.copyWith(includeToolImages: value));
  }

  Future<void> setIncludeLexicon(bool value) async {
    await _update((current) => current.copyWith(includeLexicon: value));
  }

  Future<void> setIncludeLampDb(bool value) async {
    await _update((current) => current.copyWith(includeLampDb: value));
  }

  Future<void> setBackupOnExit(bool value) async {
    await _update((current) => current.copyWith(backupOnExit: value));
  }

  Future<void> setChangeThreshold(int value) async {
    await _update(
      (current) => current.copyWith(changeThreshold: value.clamp(1, 9999)),
    );
  }

  Future<void> setMinSpacingMinutes(int value) async {
    await _update(
      (current) => current.copyWith(
        minSpacingMinutes: value.clamp(
          DatabaseBackupSettings.minAllowedSpacingMinutes,
          1440,
        ),
      ),
    );
  }

  Future<void> setMaxWaitMinutes(int value) async {
    await _update(
      (current) => current.copyWith(
        maxWaitMinutes: value.clamp(
          DatabaseBackupSettings.minAllowedSpacingMinutes,
          10080,
        ),
      ),
    );
  }

  Future<void> setBackupOnCloseIfPending(bool value) async {
    await _update((current) => current.copyWith(backupOnCloseIfPending: value));
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
    await _update(
      (current) => current.copyWith(
        lastBackupAuditId: auditId,
        lastBackupAttempt: manual ? null : at,
        lastManualBackupAttempt: manual ? at : null,
        lastFullBackupFingerprint: fullFingerprint,
        lastFullBackupAt: fullAt,
        lastBackupStatus: BackupScheduleStatus.success,
      ),
    );
  }

  Future<void> setLastBackupAttempt(DateTime? value) async {
    await _update(
      (current) => value == null
          ? current.copyWith(clearLastBackupAttempt: true)
          : current.copyWith(
              lastBackupAttempt: value,
              clearLastBackupAttempt: false,
            ),
    );
  }

  Future<void> setLastBackupStatus(String value) async {
    await _update(
      (current) => current.copyWith(
        lastBackupStatus: BackupScheduleStatus.normalize(value),
      ),
    );
  }

  Future<void> setLastManualBackupAttempt(DateTime value) async {
    await _update(
      (current) => current.copyWith(lastManualBackupAttempt: value),
    );
  }

  Future<void> setRetentionQuickMaxCopiesEnabled(bool value) async {
    await _update(
      (current) => current.copyWith(retentionQuickMaxCopiesEnabled: value),
    );
  }

  Future<void> setRetentionQuickMaxCopies(int value) async {
    await _update(
      (current) =>
          current.copyWith(retentionQuickMaxCopies: value.clamp(1, 9999)),
    );
  }

  Future<void> setRetentionQuickMaxAgeEnabled(bool value) async {
    await _update(
      (current) => current.copyWith(retentionQuickMaxAgeEnabled: value),
    );
  }

  Future<void> setRetentionQuickMaxAgeDays(int value) async {
    await _update(
      (current) =>
          current.copyWith(retentionQuickMaxAgeDays: value.clamp(1, 9999)),
    );
  }

  Future<void> setRetentionFullMaxCopiesEnabled(bool value) async {
    await _update(
      (current) => current.copyWith(retentionFullMaxCopiesEnabled: value),
    );
  }

  Future<void> setRetentionFullMaxCopies(int value) async {
    await _update(
      (current) =>
          current.copyWith(retentionFullMaxCopies: value.clamp(1, 9999)),
    );
  }
}
