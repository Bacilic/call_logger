import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../config/audit_retention_config.dart';
import '../../features/database/debug/publish_cli.dart';
import 'settings_service.dart';

/// Κατάλογοι, λεξικό, audit retention και timeout ανοίγματος βάσης.
///
/// Συνεργάτης του `SettingsService` (Σύνθεση) — πρόσβαση μέσω
/// `SettingsService().catalogs`. Οι ρυθμίσεις app_settings διαβάζονται
/// μέσω του καταχωρημένου παρόχου του [SettingsService] (μετά το άνοιγμα βάσης).
class SettingsServiceCatalogs {
  const SettingsServiceCatalogs();

  static const String _keyDatabaseOpenTimeoutSeconds =
      'database_open_timeout_seconds';
  static const String _keyDatabaseOpenMaxAttempts =
      'database_open_max_attempts';
  static const String _keyDictionarySourcePath = 'dictionary_source_path';
  static const String _keyDictionaryExportPath = 'dictionary_export_path';
  static const String _keyEquipmentTypes = 'equipment_types';
  static const String _keyLexiconCategories = 'lexicon_categories';
  static const String _keyAuditRetentionConfig = 'audit_retention_config_v1';
  static const String _keyCrashLogRetentionCount =
      'crash_log_retention_count_v1';
  static const String _keyShutdownTraceEnabled = 'shutdown_trace_enabled_v1';
  static const String _keyShutdownTraceRetentionCount =
      'shutdown_trace_retention_count_v1';
  static const String _keyUpdateFolderPath = 'update_folder_path';
  static const String _keyPublishCliCommandTemplate =
      'publish_cli_command_template';
  static const String _keyShowUpdateOnStartup = 'show_update_on_startup';

  static const int defaultCrashLogRetentionCount = 14;
  static const int minCrashLogRetentionCount = 3;
  static const int maxCrashLogRetentionCount = 90;

  static const bool defaultShutdownTraceEnabled = true;
  static const int defaultShutdownTraceRetentionCount =
      defaultCrashLogRetentionCount;
  static const int minShutdownTraceRetentionCount = minCrashLogRetentionCount;
  static const int maxShutdownTraceRetentionCount = maxCrashLogRetentionCount;

  /// Προεπιλεγμένες κατηγορίες λεξικού (CSV για ρυθμίσεις / dropdown).
  static const String defaultLexiconCategoriesCsv =
      'Γενική, Τεχνικός Όρος, Όνομα';

  static List<String> get defaultLexiconCategoriesList {
    return defaultLexiconCategoriesCsv
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Κλειδί αποθήκευσης SharedPreferences (με πρόθεμα προφίλ όταν υπάρχει CLI `--profile`).
  static String _prefKey(String baseKey) =>
      AppConfig.prefixedPreferencesKey(baseKey);

  static Future<String?> Function(String key)? get _getAppSetting =>
      SettingsService.appSettingReader;
  static Future<void> Function(String key, String value)? get _setAppSetting =>
      SettingsService.appSettingWriter;

  /// Timeout ανοίγματος βάσης σε δευτερόλεπτα. Προεπιλογή: [AppConfig.databaseOpenTimeoutSeconds].
  Future<int> getDatabaseOpenTimeoutSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_prefKey(_keyDatabaseOpenTimeoutSeconds));
    if (value == null || value <= 0) {
      return AppConfig.databaseOpenTimeoutSeconds;
    }
    return value;
  }

  Future<void> setDatabaseOpenTimeoutSeconds(int value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value <= 0
        ? AppConfig.databaseOpenTimeoutSeconds
        : value;
    await prefs.setInt(_prefKey(_keyDatabaseOpenTimeoutSeconds), normalized);
  }

  /// Μέγιστες προσπάθειες ανοίγματος βάσης. Προεπιλογή: [AppConfig.databaseOpenMaxAttempts].
  Future<int> getDatabaseOpenMaxAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_prefKey(_keyDatabaseOpenMaxAttempts));
    if (value == null || value <= 0) {
      return AppConfig.databaseOpenMaxAttempts;
    }
    return value.clamp(1, 5);
  }

  Future<void> setDatabaseOpenMaxAttempts(int value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value <= 0
        ? AppConfig.databaseOpenMaxAttempts
        : value.clamp(1, 5);
    await prefs.setInt(_prefKey(_keyDatabaseOpenMaxAttempts), normalized);
  }

  /// Διαδρομή αρχείου TXT λεξικού-πυρήνα (ορθογραφία). Κενό/null = δεν έχει φορτωθεί πυρήνας.
  Future<String?> getDictionarySourcePath() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_prefKey(_keyDictionarySourcePath));
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> setDictionarySourcePath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.trim().isEmpty) {
      await prefs.remove(_prefKey(_keyDictionarySourcePath));
    } else {
      await prefs.setString(_prefKey(_keyDictionarySourcePath), path.trim());
    }
  }

  /// Διαδρομή εξόδου για Compile (`exportToTxt`).
  Future<String?> getDictionaryExportPath() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_prefKey(_keyDictionaryExportPath));
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> setDictionaryExportPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.trim().isEmpty) {
      await prefs.remove(_prefKey(_keyDictionaryExportPath));
    } else {
      await prefs.setString(_prefKey(_keyDictionaryExportPath), path.trim());
    }
  }

  /// Πολιτική εκκαθάρισης audit log (ηλικία / max rows).
  Future<AuditRetentionConfig> getAuditRetentionConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey(_keyAuditRetentionConfig));
    return AuditRetentionConfig.fromJsonString(raw);
  }

  Future<void> setAuditRetentionConfig(AuditRetentionConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKey(_keyAuditRetentionConfig),
      jsonEncode(config.toJson()),
    );
  }

  /// Πόσα πρόσφατα ημερήσια αρχεία errors_*.log διατηρούνται στον φάκελο logs.
  Future<int> getCrashLogRetentionCount() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_prefKey(_keyCrashLogRetentionCount));
    if (value == null) return defaultCrashLogRetentionCount;
    return value.clamp(minCrashLogRetentionCount, maxCrashLogRetentionCount);
  }

  Future<void> setCrashLogRetentionCount(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _prefKey(_keyCrashLogRetentionCount),
      value.clamp(minCrashLogRetentionCount, maxCrashLogRetentionCount),
    );
  }

  /// Ενεργοποίηση αρχείου ιχνηλάτησης βημάτων κλεισίματος.
  Future<bool> getShutdownTraceEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(_keyShutdownTraceEnabled)) ??
        defaultShutdownTraceEnabled;
  }

  Future<void> setShutdownTraceEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(_keyShutdownTraceEnabled), value);
  }

  /// Πόσα πρόσφατα αρχεία shutdown_trace_*.log διατηρούνται στον φάκελο logs.
  Future<int> getShutdownTraceRetentionCount() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_prefKey(_keyShutdownTraceRetentionCount));
    if (value == null) return defaultShutdownTraceRetentionCount;
    return value.clamp(
      minShutdownTraceRetentionCount,
      maxShutdownTraceRetentionCount,
    );
  }

  Future<void> setShutdownTraceRetentionCount(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _prefKey(_keyShutdownTraceRetentionCount),
      value.clamp(
        minShutdownTraceRetentionCount,
        maxShutdownTraceRetentionCount,
      ),
    );
  }

  /// Διαδρομή κοινόχρηστου φακέλου ενημερώσεων. Κενό/null = χωρίς τοπική ρύθμιση.
  Future<String?> getUpdateFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_prefKey(_keyUpdateFolderPath));
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> setUpdateFolderPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.trim().isEmpty) {
      await prefs.remove(_prefKey(_keyUpdateFolderPath));
    } else {
      await prefs.setString(_prefKey(_keyUpdateFolderPath), path.trim());
    }
  }

  /// Πρότυπο εντολής δημοσίευσης μέσω τερματικού.
  /// Κενό/null = [kDefaultPublishCliCommandTemplate].
  Future<String> getPublishCliCommandTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_prefKey(_keyPublishCliCommandTemplate));
    if (s == null) return kDefaultPublishCliCommandTemplate;
    final t = s.trim();
    return t.isEmpty ? kDefaultPublishCliCommandTemplate : t;
  }

  Future<void> setPublishCliCommandTemplate(String? template) async {
    final prefs = await SharedPreferences.getInstance();
    if (template == null || template.trim().isEmpty) {
      await prefs.remove(_prefKey(_keyPublishCliCommandTemplate));
    } else {
      await prefs.setString(
        _prefKey(_keyPublishCliCommandTemplate),
        template.trim(),
      );
    }
  }

  /// Εμφάνιση αυτόματου μηνύματος διαθέσιμης ενημέρωσης στην εκκίνηση.
  /// Προεπιλογή: true. Δεν επηρεάζει την κόκκινη κουκίδα ούτε τον έλεγχο.
  Future<bool> getShowUpdateOnStartup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(_keyShowUpdateOnStartup)) ?? true;
  }

  Future<void> setShowUpdateOnStartup(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(_keyShowUpdateOnStartup), value);
  }

  // --- Τύποι εξοπλισμού (app_settings, comma-separated) ---

  /// Επιστρέφει το ακατέργαστο string τύπων εξοπλισμού (διαχωρισμένα με κόμμα).
  /// Χρήση στο UI ρυθμίσεων. Προεπιλογή: "Υπολογιστής, Εκτυπωτής".
  Future<String> getEquipmentTypesRaw() async {
    final value = _getAppSetting != null
        ? await _getAppSetting!(_keyEquipmentTypes)
        : null;
    if (value == null || value.trim().isEmpty) return 'Υπολογιστής, Εκτυπωτής';
    return value.trim();
  }

  /// Αποθηκεύει τους τύπους εξοπλισμού (comma-separated).
  Future<void> setEquipmentTypes(String value) async {
    if (_setAppSetting != null) {
      await _setAppSetting!(_keyEquipmentTypes, value.trim());
    }
  }

  /// Επιστρέφει λίστα τύπων για dropdown. Αν η ρύθμιση είναι κενή, επιστρέφει ["Υπολογιστής", "Εκτυπωτής"].
  Future<List<String>> getEquipmentTypesList() async {
    final raw = await getEquipmentTypesRaw();
    final list = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (list.isEmpty) return ['Υπολογιστής', 'Εκτυπωτής'];
    return list;
  }

  // --- Κατηγορίες λεξικού (app_settings, comma-separated) ---

  /// Ακατέργαστο string κατηγοριών λεξικού (διαχωρισμένα με κόμμα).
  /// Αφαιρεί [AppConfig.lexiconCategoryUnspecified] από την εμφάνιση/αποθήκευση λίστας.
  Future<String> getLexiconCategoriesRaw() async {
    final value = _getAppSetting != null
        ? await _getAppSetting!(_keyLexiconCategories)
        : null;
    if (value == null || value.trim().isEmpty) {
      return defaultLexiconCategoriesCsv;
    }
    final filtered = value
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s != AppConfig.lexiconCategoryUnspecified)
        .join(', ');
    return filtered.isEmpty ? defaultLexiconCategoriesCsv : filtered;
  }

  /// Αποθήκευση κατηγοριών λεξικού (comma-separated).
  /// Αφαιρεί την εσωτερική τιμή [AppConfig.lexiconCategoryUnspecified] (δεν ορίζεται από τον χρήστη).
  Future<void> setLexiconCategories(String value) async {
    if (_setAppSetting != null) {
      final filtered = value
          .split(',')
          .map((s) => s.trim())
          .where(
            (s) => s.isNotEmpty && s != AppConfig.lexiconCategoryUnspecified,
          )
          .join(', ');
      await _setAppSetting!(_keyLexiconCategories, filtered);
    }
  }

  /// Λίστα κατηγοριών για dropdown. Κενό μετά το split → [defaultLexiconCategoriesList].
  /// Εξαιρεί [AppConfig.lexiconCategoryUnspecified].
  Future<List<String>> getLexiconCategoriesList() async {
    final raw = await getLexiconCategoriesRaw();
    final list = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s != AppConfig.lexiconCategoryUnspecified)
        .toList();
    if (list.isEmpty) return defaultLexiconCategoriesList;
    return list;
  }
}
