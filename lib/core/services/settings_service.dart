import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../config/audit_retention_config.dart';
import '../models/calls_screen_cards_visibility.dart';
import '../models/window_placement_mode.dart';
import '../../features/database/debug/publish_cli.dart';

part 'settings_service_window_ui.dart';
part 'settings_service_analytics_filters.dart';
part 'settings_service_remote_lansweeper.dart';
part 'settings_service_catalogs.dart';

/// Υπηρεσία αποθήκευσης και ανάκτησης ρυθμίσεων (key-value) τοπικά.
class SettingsService
    with
        SettingsServiceWindowUiMixin,
        SettingsServiceAnalyticsFiltersMixin,
        SettingsServiceRemoteLansweeperMixin,
        SettingsServiceCatalogsMixin {
  static const String _keyDatabasePath = 'database_path';
  static const String _keyDatabaseSetupState = 'database_setup_state_v1';
  static const String _keyApplicationResetPending = 'application_reset_pending_v1';
  static const String _keyRecentPaths = 'recent_database_paths';
  static const int _maxRecentPaths = 3;

  /// Τιμή [database_setup_state_v1] όταν η εφαρμογή περιμένει επιλογή/δημιουργία βάσης.
  static const String databaseSetupStateUnconfigured = 'unconfigured';

  /// Προώθηση στατικών προεπιλογών κατηγοριών λεξικού από [SettingsServiceCatalogsMixin].
  static const String defaultLexiconCategoriesCsv =
      SettingsServiceCatalogsMixin.defaultLexiconCategoriesCsv;

  static List<String> get defaultLexiconCategoriesList =>
      SettingsServiceCatalogsMixin.defaultLexiconCategoriesList;

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

  static const int defaultCrashLogRetentionCount =
      SettingsServiceCatalogsMixin.defaultCrashLogRetentionCount;
  static const int minCrashLogRetentionCount =
      SettingsServiceCatalogsMixin.minCrashLogRetentionCount;
  static const int maxCrashLogRetentionCount =
      SettingsServiceCatalogsMixin.maxCrashLogRetentionCount;

  static const bool defaultShutdownTraceEnabled =
      SettingsServiceCatalogsMixin.defaultShutdownTraceEnabled;
  static const int defaultShutdownTraceRetentionCount =
      SettingsServiceCatalogsMixin.defaultShutdownTraceRetentionCount;
  static const int minShutdownTraceRetentionCount =
      SettingsServiceCatalogsMixin.minShutdownTraceRetentionCount;
  static const int maxShutdownTraceRetentionCount =
      SettingsServiceCatalogsMixin.maxShutdownTraceRetentionCount;

  /// Κλειδί αποθήκευσης SharedPreferences (με πρόθεμα προφίλ όταν υπάρχει CLI `--profile`).
  static String _prefKey(String baseKey) =>
      AppConfig.prefixedPreferencesKey(baseKey);

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
      p.join(
        support.path,
        'unconfigured',
        'pending_database_connection.db',
      ),
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
  /// Προσθέτει τη διαδρομή στη λίστα των τελευταίων έγκυρων διαδρομών.
  Future<void> setDatabasePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = path.trim();
    await markDatabaseConfigured();
    await prefs.setString(_prefKey(_keyDatabasePath), trimmed);
    await _addToRecentPaths(prefs, trimmed);
  }

  /// Επιστρέφει τις 3 τελευταίες έγκυρες (χρησιμοποιημένες) διαδρομές για dropdown.
  Future<List<String>> getRecentDatabasePaths() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefKey(_keyRecentPaths));
    if (list == null || list.isEmpty) {
      return [AppConfig.defaultDbPath];
    }
    return list.take(_maxRecentPaths).toList();
  }

  Future<void> _addToRecentPaths(SharedPreferences prefs, String path) async {
    final list = prefs.getStringList(_prefKey(_keyRecentPaths)) ?? [];
    final updated = [
      path,
      ...list.where((p) => p != path),
    ].take(_maxRecentPaths).toList();
    await prefs.setStringList(_prefKey(_keyRecentPaths), updated);
  }

  /// Επαναφορά σε προεπιλεγμένη διαδρομή (αφαίρεση αποθηκευμένης ρύθμισης).
  /// Προσθέτει την προεπιλογή στη λίστα recent ώστε να εμφανίζεται στο dropdown.
  Future<void> resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey(_keyDatabasePath));
    await _addToRecentPaths(prefs, AppConfig.defaultDbPath);
  }
}
