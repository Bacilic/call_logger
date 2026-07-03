part of 'settings_service.dart';

/// Κατάλογοι, λεξικό, audit retention και timeout ανοίγματος βάσης.
mixin SettingsServiceCatalogsMixin {
  static const String _keyDatabaseOpenTimeoutSeconds =
      'database_open_timeout_seconds';
  static const String _keyDatabaseOpenMaxAttempts =
      'database_open_max_attempts';
  static const String _keyDictionarySourcePath = 'dictionary_source_path';
  static const String _keyDictionaryExportPath = 'dictionary_export_path';
  static const String _keyEquipmentTypes = 'equipment_types';
  static const String _keyLexiconCategories = 'lexicon_categories';
  static const String _keyAuditRetentionConfig = 'audit_retention_config_v1';

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

  /// Timeout ανοίγματος βάσης σε δευτερόλεπτα. Προεπιλογή: [AppConfig.databaseOpenTimeoutSeconds].
  Future<int> getDatabaseOpenTimeoutSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(SettingsService._prefKey(_keyDatabaseOpenTimeoutSeconds));
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
    await prefs.setInt(SettingsService._prefKey(_keyDatabaseOpenTimeoutSeconds), normalized);
  }

  /// Μέγιστες προσπάθειες ανοίγματος βάσης. Προεπιλογή: [AppConfig.databaseOpenMaxAttempts].
  Future<int> getDatabaseOpenMaxAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(SettingsService._prefKey(_keyDatabaseOpenMaxAttempts));
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
    await prefs.setInt(SettingsService._prefKey(_keyDatabaseOpenMaxAttempts), normalized);
  }

  /// Διαδρομή αρχείου TXT λεξικού-πυρήνα (ορθογραφία). Κενό/null = δεν έχει φορτωθεί πυρήνας.
  Future<String?> getDictionarySourcePath() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(SettingsService._prefKey(_keyDictionarySourcePath));
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> setDictionarySourcePath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.trim().isEmpty) {
      await prefs.remove(SettingsService._prefKey(_keyDictionarySourcePath));
    } else {
      await prefs.setString(SettingsService._prefKey(_keyDictionarySourcePath), path.trim());
    }
  }

  /// Διαδρομή εξόδου για Compile (`exportToTxt`).
  Future<String?> getDictionaryExportPath() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(SettingsService._prefKey(_keyDictionaryExportPath));
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> setDictionaryExportPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.trim().isEmpty) {
      await prefs.remove(SettingsService._prefKey(_keyDictionaryExportPath));
    } else {
      await prefs.setString(SettingsService._prefKey(_keyDictionaryExportPath), path.trim());
    }
  }

  /// Πολιτική εκκαθάρισης audit log (ηλικία / max rows).
  Future<AuditRetentionConfig> getAuditRetentionConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(SettingsService._prefKey(_keyAuditRetentionConfig));
    return AuditRetentionConfig.fromJsonString(raw);
  }

  Future<void> setAuditRetentionConfig(AuditRetentionConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyAuditRetentionConfig,
      jsonEncode(config.toJson()),
    );
  }

  /// Επιστρέφει λίστα επιλογών για dropdown (split by comma, trim, μη κενά). Τελευταία επιλογή "Κανένα" προστίθεται στα dialogs.
  /// Αν η ρύθμιση είναι κενή, επιστρέφει ["AnyDesk", "VNC"].

  // --- Τύποι εξοπλισμού (app_settings, comma-separated) ---

  /// Επιστρέφει το ακατέργαστο string τύπων εξοπλισμού (διαχωρισμένα με κόμμα).
  /// Χρήση στο UI ρυθμίσεων. Προεπιλογή: "Υπολογιστής, Εκτυπωτής".
  Future<String> getEquipmentTypesRaw() async {
    final value = SettingsService._getAppSetting != null
        ? await SettingsService._getAppSetting!(_keyEquipmentTypes)
        : null;
    if (value == null || value.trim().isEmpty) return 'Υπολογιστής, Εκτυπωτής';
    return value.trim();
  }

  /// Αποθηκεύει τους τύπους εξοπλισμού (comma-separated).
  Future<void> setEquipmentTypes(String value) async {
    if (SettingsService._setAppSetting != null) {
      await SettingsService._setAppSetting!(_keyEquipmentTypes, value.trim());
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
    final value = SettingsService._getAppSetting != null
        ? await SettingsService._getAppSetting!(_keyLexiconCategories)
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
    if (SettingsService._setAppSetting != null) {
      final filtered = value
          .split(',')
          .map((s) => s.trim())
          .where(
            (s) => s.isNotEmpty && s != AppConfig.lexiconCategoryUnspecified,
          )
          .join(', ');
      await SettingsService._setAppSetting!(_keyLexiconCategories, filtered);
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
