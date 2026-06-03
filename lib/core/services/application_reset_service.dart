import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/calls/provider/call_entry_provider.dart';
import '../../features/database/providers/backup_scheduler_provider.dart';
import '../../features/database/providers/database_backup_settings_provider.dart';
import '../database/database_helper.dart';
import '../init/app_init_provider.dart';
import '../providers/application_reset_provider.dart';
import '../providers/core_lexicon_provider.dart';
import '../providers/settings_provider.dart';
import 'core_lexicon_service.dart';
import 'application_prefs_snapshot.dart';
import 'settings_service.dart';

/// Συντονισμός «Ξεκίνα από την αρχή»: snapshot, επαναφορά prefs, commit ή rollback.
class ApplicationResetService {
  ApplicationResetService._();

  static final ApplicationResetService instance = ApplicationResetService._();

  final SettingsService _settings = SettingsService();

  Future<bool> hasPendingReset() => _settings.isApplicationResetPending();

  /// Πριν την επαναφορά: snapshot → καθάρισμα prefs → unconfigured + pending.
  Future<void> beginPendingReset() async {
    await ApplicationPrefsSnapshot.writeToDisk();
    try {
      await DatabaseHelper.instance.closeConnection();
    } catch (_) {}
    await _settings.clearAllPreferencesForCurrentProfile();
    CoreLexiconService.instance.unload();
    await _settings.markDatabaseUnconfigured();
    await _settings.setApplicationResetPending(true);
  }

  /// Επιτυχής σύνδεση σε βάση — διαγραφή snapshot, αφαίρεση pending.
  Future<void> commitPendingReset() async {
    await ApplicationPrefsSnapshot.deleteSnapshotFile();
    await _settings.setApplicationResetPending(false);
    await _settings.markDatabaseConfigured();
  }

  /// Άκυρο χωρίς νέα βάση — επαναφορά snapshot και σύνδεση όπως πριν.
  Future<bool> rollbackPendingReset() async {
    final restored = await ApplicationPrefsSnapshot.restoreFromDisk();
    if (!restored) {
      await _settings.setApplicationResetPending(false);
      await _settings.markDatabaseConfigured();
      return false;
    }
    await _settings.setApplicationResetPending(false);
    try {
      await DatabaseHelper.instance.closeConnection();
    } catch (_) {}
    return true;
  }

  void invalidateAfterResetLifecycle(WidgetRef ref) {
    ref.invalidate(applicationResetPendingProvider);
    ref.invalidate(appInitProvider);
    ref.invalidate(showActiveTimerProvider);
    ref.invalidate(showTasksBadgeProvider);
    ref.invalidate(enableSpellCheckProvider);
    ref.invalidate(showDatabaseNavProvider);
    ref.invalidate(showLampNavProvider);
    ref.invalidate(showDictionaryNavProvider);
    ref.invalidate(coreLexiconProvider);
    ref.invalidate(callsScreenCardsVisibilityProvider);
    ref.invalidate(databaseBackupSettingsProvider);
    ref.invalidate(backupSchedulerProvider);
    ref.read(callEntryProvider.notifier).reset();
  }
}
