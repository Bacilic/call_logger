import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../utils/database_path_identity.dart';
import 'app_instance_registry.dart';

import 'settings_service_analytics_filters.dart';
import 'settings_service_catalogs.dart';
import 'settings_service_remote_lansweeper.dart';
import 'settings_service_window_ui.dart';

/// Υπηρεσία αποθήκευσης και ανάκτησης ρυθμίσεων (key-value) τοπικά.
///
/// Οι θεματικές ομάδες ρυθμίσεων ζουν σε συνεργάτες (Σύνθεση):
/// [windowUi], [analyticsFilters], [remoteLansweeper], [catalogs].
class SettingsService {
  /// Ρυθμίσεις παραθύρου, πλοήγησης και ορατότητας UI.
  final SettingsServiceWindowUi windowUi = const SettingsServiceWindowUi();

  /// Φίλτρα ημερομηνιών για στατιστικά κλήσεων και εκκρεμοτήτων.
  final SettingsServiceAnalyticsFilters analyticsFilters =
      const SettingsServiceAnalyticsFilters();

  /// Ρυθμίσεις απομακρυσμένης σύνδεσης, Lansweeper και προτεραιότητας εργαλείων.
  final SettingsServiceRemoteLansweeper remoteLansweeper =
      const SettingsServiceRemoteLansweeper();

  /// Κατάλογοι, λεξικό, audit retention και timeout ανοίγματος βάσης.
  final SettingsServiceCatalogs catalogs = const SettingsServiceCatalogs();

  static const String _keyDatabasePath = 'database_path';
  static const String _keyDatabaseSetupState = 'database_setup_state_v1';
  static const String _keyApplicationResetPending =
      'application_reset_pending_v1';
  static const String _keyRecentPaths = 'recent_database_paths';
  static const String _keyAcknowledgedDatabaseNoticeIdentity =
      'acknowledged_database_notice_identity_v1';
  static const String _keyLastOpenedDatabasePath =
      'last_opened_database_path_v1';
  static const String _keySchemaUpgradeConsentIdentity =
      'schema_upgrade_consent_identity_v1';
  static const String _keyKnownAppInstances = 'known_app_instances_v1';
  static const String _keyDismissedInstancesSignature =
      'dismissed_app_instances_signature_v1';
  static const int _maxRecentPaths = 3;

  /// Τιμή [database_setup_state_v1] όταν η εφαρμογή περιμένει επιλογή/δημιουργία βάσης.
  static const String databaseSetupStateUnconfigured = 'unconfigured';

  /// Προώθηση στατικών προεπιλογών κατηγοριών λεξικού από [SettingsServiceCatalogs].
  static const String defaultLexiconCategoriesCsv =
      SettingsServiceCatalogs.defaultLexiconCategoriesCsv;

  static List<String> get defaultLexiconCategoriesList =>
      SettingsServiceCatalogs.defaultLexiconCategoriesList;

  /// Πρόσβαση σε ρυθμίσεις από πίνακα app_settings (ορίζεται μετά το άνοιγμα βάσης).
  static Future<String?> Function(String key)? _getAppSetting;
  static Future<void> Function(String key, String value)? _setAppSetting;

  /// Καθιστά διαθέσιμη την πρόσβαση στις ρυθμίσεις app_settings (κλήση μετά το άνοιγμα βάσης).
  static void registerAppSettingsProvider(
    Future<String?> Function(String key) get,
    Future<void> Function(String key, String value) set,
  ) {
    _getAppSetting = get;
    _setAppSetting = set;
  }

  /// Ανάγνωση ρύθμισης app_settings — για τους συνεργάτες ([remoteLansweeper], [catalogs]).
  static Future<String?> Function(String key)? get appSettingReader =>
      _getAppSetting;

  /// Εγγραφή ρύθμισης app_settings — για τους συνεργάτες ([remoteLansweeper], [catalogs]).
  static Future<void> Function(String key, String value)?
  get appSettingWriter => _setAppSetting;

  static const int defaultCrashLogRetentionCount =
      SettingsServiceCatalogs.defaultCrashLogRetentionCount;
  static const int minCrashLogRetentionCount =
      SettingsServiceCatalogs.minCrashLogRetentionCount;
  static const int maxCrashLogRetentionCount =
      SettingsServiceCatalogs.maxCrashLogRetentionCount;

  static const bool defaultShutdownTraceEnabled =
      SettingsServiceCatalogs.defaultShutdownTraceEnabled;
  static const int defaultShutdownTraceRetentionCount =
      SettingsServiceCatalogs.defaultShutdownTraceRetentionCount;
  static const int minShutdownTraceRetentionCount =
      SettingsServiceCatalogs.minShutdownTraceRetentionCount;
  static const int maxShutdownTraceRetentionCount =
      SettingsServiceCatalogs.maxShutdownTraceRetentionCount;

  /// Κλειδί αποθήκευσης SharedPreferences (με πρόθεμα προφίλ όταν υπάρχει CLI `--profile`).
  static String _prefKey(String baseKey) =>
      AppConfig.prefixedPreferencesKey(baseKey);

  /// Ταυτότητα περιεχομένου βάσης για την οποία ο χρήστης έκλεισε τη λωρίδα ειδοποίησης.
  Future<String?> getAcknowledgedDatabaseNoticeIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(
      _prefKey(_keyAcknowledgedDatabaseNoticeIdentity),
    );
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  /// Αποθηκεύει την ταυτότητα περιεχομένου μετά το κλείσιμο της λωρίδας ειδοποίησης.
  Future<void> setAcknowledgedDatabaseNoticeIdentity(String identity) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = identity.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(_prefKey(_keyAcknowledgedDatabaseNoticeIdentity));
      return;
    }
    await prefs.setString(
      _prefKey(_keyAcknowledgedDatabaseNoticeIdentity),
      trimmed,
    );
  }

  /// Διαδρομή βάσης που άνοιξε επιτυχώς τελευταία φορά (για σιωπηλή αναβάθμιση).
  Future<String?> getLastOpenedDatabasePath() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_prefKey(_keyLastOpenedDatabasePath));
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  /// Καταγράφει τη διαδρομή μετά από πλήρως επιτυχημένο άνοιγμα βάσης.
  Future<void> setLastOpenedDatabasePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(_prefKey(_keyLastOpenedDatabasePath));
      return;
    }
    await prefs.setString(_prefKey(_keyLastOpenedDatabasePath), trimmed);
  }

  /// Μητρώο αντιγράφων της εφαρμογής που μοιράζονται αυτές τις ρυθμίσεις.
  ///
  /// Το κλειδί παίρνει πρόθεμα προφίλ όπως όλα τα υπόλοιπα: κάθε προφίλ έχει
  /// δικό του μητρώο, αφού δικά του κλειδιά μοιράζεται.
  Future<List<AppInstanceRecord>> getKnownAppInstances() async {
    final prefs = await SharedPreferences.getInstance();
    return AppInstanceRegistry.decode(
      prefs.getString(_prefKey(_keyKnownAppInstances)),
    );
  }

  Future<void> setKnownAppInstances(List<AppInstanceRecord> instances) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKey(_keyKnownAppInstances),
      AppInstanceRegistry.encode(instances),
    );
  }

  /// Υπογραφή συνόλου αντιγράφων για την οποία ο χρήστης έκλεισε τη λωρίδα.
  Future<String?> getDismissedAppInstancesSignature() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_prefKey(_keyDismissedInstancesSignature));
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> setDismissedAppInstancesSignature(String signature) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKey(_keyDismissedInstancesSignature),
      signature,
    );
  }

  /// Ταυτότητα περιεχομένου για την οποία δόθηκε συγκατάθεση μόνιμης αναβάθμισης.
  Future<String?> getSchemaUpgradeConsentIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_prefKey(_keySchemaUpgradeConsentIdentity));
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  /// Καταγράφει συγκατάθεση αναβάθμισης σχήματος για συγκεκριμένη ταυτότητα.
  Future<void> setSchemaUpgradeConsentIdentity(String identity) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = identity.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(_prefKey(_keySchemaUpgradeConsentIdentity));
      return;
    }
    await prefs.setString(_prefKey(_keySchemaUpgradeConsentIdentity), trimmed);
  }

  /// Επιστρέφει την αποθηκευμένη διαδρομή βάσης δεδομένων.
  /// Σε κατάσταση [databaseSetupStateUnconfigured] επιστρέφει placeholder που δεν υπάρχει.
  /// Αλλιώς, αν δεν υπάρχει αποθηκευμένη τιμή, [AppConfig.defaultDbPath].
  Future<String> getDatabasePath() async {
    if (await isDatabaseUnconfigured()) {
      return getUnconfiguredPlaceholderDatabasePath();
    }
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_prefKey(_keyDatabasePath));
    if (path == null || path.trim().isEmpty) {
      return AppConfig.defaultDbPath;
    }
    return path;
  }

  /// Placeholder `.db` (δεν δημιουργείται) για έλεγχο «δεν βρέθηκε βάση» μετά επαναφορά.
  Future<String> getUnconfiguredPlaceholderDatabasePath() async {
    final support = await getApplicationSupportDirectory();
    return p.normalize(
      p.join(support.path, 'unconfigured', 'pending_database_connection.db'),
    );
  }

  Future<bool> isDatabaseUnconfigured() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey(_keyDatabaseSetupState)) ==
        databaseSetupStateUnconfigured;
  }

  Future<void> markDatabaseUnconfigured() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKey(_keyDatabaseSetupState),
      databaseSetupStateUnconfigured,
    );
    await prefs.remove(_prefKey(_keyDatabasePath));
    await prefs.remove(_prefKey(_keyRecentPaths));
  }

  Future<void> markDatabaseConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey(_keyDatabaseSetupState));
  }

  Future<bool> isApplicationResetPending() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(_keyApplicationResetPending)) ?? false;
  }

  Future<void> setApplicationResetPending(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value) {
      await prefs.setBool(_prefKey(_keyApplicationResetPending), true);
    } else {
      await prefs.remove(_prefKey(_keyApplicationResetPending));
    }
  }

  /// Διαγραφή όλων των prefs του τρέχοντος CLI προφίλ (ή παραγωγής χωρίς πρόθεμα).
  Future<void> clearAllPreferencesForCurrentProfile() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (_keyBelongsToCurrentProfile(key)) {
        await prefs.remove(key);
      }
    }
  }

  static bool _keyBelongsToCurrentProfile(String key) {
    final profile = AppConfig.activeProfile?.trim();
    if (profile == null || profile.isEmpty) {
      return !key.startsWith('profile_');
    }
    return key.startsWith('profile_${profile}_');
  }

  /// Αποθηκεύει τη νέα διαδρομή βάσης δεδομένων (trim() εφαρμόζεται αυτόματα).
  /// Δεν αγγίζει τη λίστα πρόσφατων — αυτή ενημερώνεται μόνο μετά από επιτυχή
  /// επαλήθευση μέσω [recordVerifiedDatabasePath].
  Future<void> setDatabasePath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        path,
        'path',
        'Η διαδρομή βάσης δεν επιτρέπεται να είναι κενή — για αφαίρεση '
            'διαδρομής χρησιμοποιήστε markDatabaseUnconfigured().',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await markDatabaseConfigured();
    await prefs.setString(_prefKey(_keyDatabasePath), trimmed);
  }

  /// Επιστρέφει τις έως 3 τελευταίες διαδρομές που καταγράφηκαν μετά από επιτυχή
  /// επαλήθευση. Κενή λίστα όταν δεν υπάρχει ιστορικό — χωρίς συνθετικές εγγραφές.
  Future<List<String>> getRecentDatabasePaths() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefKey(_keyRecentPaths));
    if (list == null || list.isEmpty) {
      return const <String>[];
    }
    return list
        .where((entry) => entry.trim().isNotEmpty)
        .take(_maxRecentPaths)
        .toList();
  }

  /// Καταγράφει διαδρομή στη λίστα πρόσφατων.
  /// Καλείται ΜΟΝΟ μετά από επιτυχή επαλήθευση βάσης.
  Future<void> recordVerifiedDatabasePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    await _addToRecentPaths(prefs, trimmed);
  }

  /// Αφαιρεί από τη λίστα πρόσφατων κάθε εγγραφή που δείχνει στο ίδιο αρχείο.
  Future<void> forgetRecentDatabasePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    final list = prefs.getStringList(_prefKey(_keyRecentPaths)) ?? [];
    final updated = list
        .where((entry) => !databasePathsReferToSameFile(entry, trimmed))
        .toList();
    await prefs.setStringList(_prefKey(_keyRecentPaths), updated);
  }

  Future<void> _addToRecentPaths(SharedPreferences prefs, String path) async {
    final list = prefs.getStringList(_prefKey(_keyRecentPaths)) ?? [];
    final updated = [
      path,
      ...list.where((entry) => !databasePathsReferToSameFile(entry, path)),
    ].take(_maxRecentPaths).toList();
    await prefs.setStringList(_prefKey(_keyRecentPaths), updated);
  }
}
