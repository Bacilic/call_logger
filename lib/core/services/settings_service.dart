import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../config/audit_retention_config.dart';

/// Υπηρεσία αποθήκευσης και ανάκτησης ρυθμίσεων (key-value) τοπικά.
class SettingsService {
  static const String _keyDatabasePath = 'database_path';
  static const String _keyRecentPaths = 'recent_database_paths';
  static const String _keyShowImportExcelButton = 'show_import_excel_button';
  static const String _keyShowActiveTimer = 'show_active_timer';
  static const String _keyShowTasksBadge = 'show_tasks_badge';
  static const String _keyNavRailShowLabels = 'nav_rail_show_labels';
  static const String _keyDatabaseBrowserStatsCardExpanded =
      'database_browser_stats_card_expanded';
  static const String _keyEquipmentLocationShowBuilding =
      'equipment_location_show_building';
  static const String _keyEnableSpellCheck = 'enable_spell_check';
  static const String _keyDatabaseOpenTimeoutSeconds =
      'database_open_timeout_seconds';
  static const String _keyDictionarySourcePath = 'dictionary_source_path';
  static const String _keyDictionaryExportPath = 'dictionary_export_path';
  static const String _keyShowDatabaseNav = 'show_database_nav';
  static const String _keyShowDictionaryNav = 'show_dictionary_nav';
  static const String _keyRemoteToolPrioritySwapMode =
      'remote_tool_priority_swap_mode';
  static const int _maxRecentPaths = 3;

  /// Κλειδιά για ρυθμίσεις απομακρυσμένης σύνδεσης (πίνακας app_settings).
  static const String _keyVncPaths = 'vnc_paths';
  static const String _keyAnydeskPath = 'anydesk_path';
  static const String _keyRemoteSurfaceApps = 'remote_surface_apps';
  static const String _keyCallsPrimaryToolId = 'calls_primary_tool_id';
  static const String _keyCallsShowSecondaryRemoteActions =
      'calls_show_secondary_remote_actions';
  static const String _keyCallsShowEmptyRemoteLaunchers =
      'calls_show_empty_remote_launchers';
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

  /// Προεπιλεγμένη διαδρομή TightVNC Viewer (μία μόνο).
  static const String _defaultVncPath =
      r'C:\Program Files\TightVNC\tvnviewer.exe';

  /// Προεπιλεγμένη διαδρομή AnyDesk.
  static const String _defaultAnydeskPath =
      r'C:\Program Files (x86)\AnyDesk\AnyDesk.exe';

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

  /// Επιστρέφει την αποθηκευμένη διαδρομή βάσης δεδομένων.
  /// Αν δεν υπάρχει ή είναι κενή, επιστρέφει το [AppConfig.defaultDbPath]
  /// (`..\Data Base\call_logger.db` δίπλα στο εκτελέσιμο).
  Future<String> getDatabasePath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_keyDatabasePath);
    if (path == null || path.trim().isEmpty) {
      return AppConfig.defaultDbPath;
    }
    return path;
  }

  /// Αποθηκεύει τη νέα διαδρομή βάσης δεδομένων (trim() εφαρμόζεται αυτόματα).
  /// Προσθέτει τη διαδρομή στη λίστα των τελευταίων έγκυρων διαδρομών.
  Future<void> setDatabasePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = path.trim();
    await prefs.setString(_keyDatabasePath, trimmed);
    await _addToRecentPaths(prefs, trimmed);
  }

  /// Επιστρέφει τις 3 τελευταίες έγκυρες (χρησιμοποιημένες) διαδρομές για dropdown.
  Future<List<String>> getRecentDatabasePaths() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyRecentPaths);
    if (list == null || list.isEmpty) {
      return [AppConfig.defaultDbPath];
    }
    return list.take(_maxRecentPaths).toList();
  }

  Future<void> _addToRecentPaths(SharedPreferences prefs, String path) async {
    final list = prefs.getStringList(_keyRecentPaths) ?? [];
    final updated = [
      path,
      ...list.where((p) => p != path),
    ].take(_maxRecentPaths).toList();
    await prefs.setStringList(_keyRecentPaths, updated);
  }

  /// Επαναφορά σε προεπιλεγμένη διαδρομή (αφαίρεση αποθηκευμένης ρύθμισης).
  /// Προσθέτει την προεπιλογή στη λίστα recent ώστε να εμφανίζεται στο dropdown.
  Future<void> resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDatabasePath);
    await _addToRecentPaths(prefs, AppConfig.defaultDbPath);
  }

  /// Εμφάνιση κουμπιού Import Excel στη βασική οθόνη. Προεπιλογή: false (απόκρυψη).
  Future<bool> getShowImportExcelButton() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowImportExcelButton) ?? false;
  }

  /// Ορίζει αν θα εμφανίζεται το κουμπί Import Excel.
  Future<void> setShowImportExcelButton(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowImportExcelButton, value);
  }

  /// Εμφάνιση ενεργού χρονομέτρου στη φόρμα κλήσεων. Προεπιλογή: true.
  Future<bool> getShowActiveTimer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowActiveTimer) ?? true;
  }

  /// Ορίζει αν θα εμφανίζεται το ενεργό χρονόμετρο (MM:SS) στη φόρμα κλήσεων.
  Future<void> setShowActiveTimer(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowActiveTimer, value);
  }

  /// Εμφάνιση μετρητή (badge) εκκρεμοτήτων στο κεντρικό μενού. Προεπιλογή: true.
  Future<bool> getShowTasksBadge() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowTasksBadge) ?? true;
  }

  Future<void> setShowTasksBadge(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowTasksBadge, value);
  }

  /// Εμφάνιση λεζαντών στην πλευρική μπάρα (NavigationRail extended) όταν το πλάτος επιτρέπει.
  /// Προεπιλογή: true.
  Future<bool> getNavRailShowLabels() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyNavRailShowLabels) ?? true;
  }

  Future<void> setNavRailShowLabels(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNavRailShowLabels, value);
  }

  /// Κάρτα «Στατιστικά Βάσης Δεδομένων» στην οθόνη περιήγησης βάσης — ανοιχτή/κλειστή.
  /// Προεπιλογή: false (συμπτυγμένη).
  Future<bool> getDatabaseBrowserStatsCardExpanded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDatabaseBrowserStatsCardExpanded) ?? false;
  }

  Future<void> setDatabaseBrowserStatsCardExpanded(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDatabaseBrowserStatsCardExpanded, value);
  }

  /// Εμφάνιση κωδικού κτιρίου `[...]` στη στήλη Τοποθεσία (πίνακας εξοπλισμού). Προεπιλογή: true.
  Future<bool> getEquipmentLocationShowBuilding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEquipmentLocationShowBuilding) ?? true;
  }

  Future<void> setEquipmentLocationShowBuilding(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEquipmentLocationShowBuilding, value);
  }

  /// Ενεργοποίηση ενσωματωμένου ορθογραφικού ελέγχου σημειώσεων (Windows). Προεπιλογή: true.
  Future<bool> getEnableSpellCheck() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnableSpellCheck) ?? true;
  }

  Future<void> setEnableSpellCheck(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableSpellCheck, value);
  }

  /// Timeout ανοίγματος βάσης σε δευτερόλεπτα. Προεπιλογή: [AppConfig.databaseOpenTimeoutSeconds].
  Future<int> getDatabaseOpenTimeoutSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_keyDatabaseOpenTimeoutSeconds);
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
    await prefs.setInt(_keyDatabaseOpenTimeoutSeconds, normalized);
  }

  /// Διαδρομή αρχείου TXT που φορτώνει το runtime λεξικό ορθογραφίας (μετά το Compile).
  /// Κενό/null = χρήση bundled asset.
  Future<String?> getDictionarySourcePath() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyDictionarySourcePath);
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> setDictionarySourcePath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.trim().isEmpty) {
      await prefs.remove(_keyDictionarySourcePath);
    } else {
      await prefs.setString(_keyDictionarySourcePath, path.trim());
    }
  }

  /// Διαδρομή εξόδου για Compile (`exportToTxt`).
  Future<String?> getDictionaryExportPath() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyDictionaryExportPath);
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> setDictionaryExportPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.trim().isEmpty) {
      await prefs.remove(_keyDictionaryExportPath);
    } else {
      await prefs.setString(_keyDictionaryExportPath, path.trim());
    }
  }

  /// Εμφάνιση στοιχείου πλοήγησης «Βάση Δεδομένων». Προεπιλογή: true.
  Future<bool> getShowDatabaseNav() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowDatabaseNav) ?? true;
  }

  Future<void> setShowDatabaseNav(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowDatabaseNav, value);
  }

  /// Εμφάνιση στοιχείου πλοήγησης «Λεξικό». Προεπιλογή: true.
  Future<bool> getShowDictionaryNav() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowDictionaryNav) ?? true;
  }

  Future<void> setShowDictionaryNav(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowDictionaryNav, value);
  }

  /// Πολιτική εκκαθάρισης audit log (ηλικία / max rows).
  Future<AuditRetentionConfig> getAuditRetentionConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyAuditRetentionConfig);
    return AuditRetentionConfig.fromJsonString(raw);
  }

  Future<void> setAuditRetentionConfig(AuditRetentionConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyAuditRetentionConfig,
      jsonEncode(config.toJson()),
    );
  }

  /// Καθολική λειτουργία πεδίου «Προτεραιότητα» στη φόρμα εργαλείου:
  /// `false` = ταξινόμιση (ολίσθηση), `true` = αντιμετάθεση θέσεων.
  /// Δεν αποθηκεύεται ανά εργαλείο· κοινή για όλα τα διαλόγους.
  Future<bool> getRemoteToolPrioritySwapMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyRemoteToolPrioritySwapMode) ?? false;
  }

  Future<void> setRemoteToolPrioritySwapMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRemoteToolPrioritySwapMode, value);
  }

  // --- Ρυθμίσεις απομακρυσμένης σύνδεσης (app_settings) ---

  /// Επιστρέφει τη μοναδική διαδρομή για TightVNC Viewer.
  /// Αν δεν υπάρχει τιμή στη βάση, επιστρέφει την προεπιλεγμένη.
  /// Υποστηρίζει και παλιά αποθηκευμένη λίστα (JSON array): χρησιμοποιεί το πρώτο στοιχείο.
  Future<String> getVncPath() async {
    final raw = _getAppSetting != null
        ? await _getAppSetting!(_keyVncPaths)
        : null;
    if (raw == null || raw.trim().isEmpty) {
      return _defaultVncPath;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List && decoded.isNotEmpty) {
        return decoded.first.toString().trim();
      }
      if (decoded is String && decoded.trim().isNotEmpty) {
        return decoded.trim();
      }
    } catch (_) {}
    return _defaultVncPath;
  }

  /// Αποθηκεύει τη διαδρομή VNC στη βάση (JSON array με ένα στοιχείο για συμβατότητα).
  Future<void> setVncPath(String path) async {
    if (_setAppSetting != null) {
      await _setAppSetting!(_keyVncPaths, jsonEncode([path.trim()]));
    }
  }

  /// Επιστρέφει την αποθηκευμένη διαδρομή AnyDesk. Αν δεν υπάρχει ή είναι κενή, η προεπιλογή.
  Future<String> getAnydeskPath() async {
    final value = _getAppSetting != null
        ? await _getAppSetting!(_keyAnydeskPath)
        : null;
    if (value == null || value.trim().isEmpty) return _defaultAnydeskPath;
    return value.trim();
  }

  /// Αποθηκεύει τη διαδρομή AnyDesk στη βάση.
  Future<void> setAnydeskPath(String path) async {
    if (_setAppSetting != null) {
      await _setAppSetting!(_keyAnydeskPath, path.trim());
    }
  }

  /// Επιστρέφει το ακατέργαστο string επιλογών εφαρμογής απομακρυσμένης επιφάνειας (διαχωρισμένα με κόμμα).
  /// Χρήση στο UI ρυθμίσεων. Προεπιλογή: "AnyDesk, VNC".
  Future<String> getRemoteSurfaceAppsRaw() async {
    final value = _getAppSetting != null
        ? await _getAppSetting!(_keyRemoteSurfaceApps)
        : null;
    if (value == null || value.trim().isEmpty) return 'AnyDesk, VNC';
    return value.trim();
  }

  /// Αποθηκεύει τις επιλογές εφαρμογής απομακρυσμένης επιφάνειας (comma-separated).
  Future<void> setRemoteSurfaceApps(String value) async {
    if (_setAppSetting != null) {
      await _setAppSetting!(_keyRemoteSurfaceApps, value.trim());
    }
  }

  /// Προεπιλεγμένο κύριο εργαλείο στην οθόνη κλήσεων (`remote_tools.id`)· null = πρώτο ενεργό.
  Future<int?> getCallsPrimaryToolId() async {
    final value = _getAppSetting != null
        ? await _getAppSetting!(_keyCallsPrimaryToolId)
        : null;
    if (value == null || value.trim().isEmpty) return null;
    return int.tryParse(value.trim());
  }

  Future<void> setCallsPrimaryToolId(int? id) async {
    if (_setAppSetting == null) return;
    if (id == null) {
      await _setAppSetting!(_keyCallsPrimaryToolId, '');
    } else {
      await _setAppSetting!(_keyCallsPrimaryToolId, id.toString());
    }
  }

  /// Αν false, τα δευτερεύοντα εργαλεία μπαίνουν σε overflow menu.
  Future<bool> getCallsShowSecondaryRemoteActions() async {
    final value = _getAppSetting != null
        ? await _getAppSetting!(_keyCallsShowSecondaryRemoteActions)
        : null;
    if (value == null || value.trim().isEmpty) return true;
    final lower = value.trim().toLowerCase();
    return lower != '0' && lower != 'false' && lower != 'no';
  }

  Future<void> setCallsShowSecondaryRemoteActions(bool value) async {
    if (_setAppSetting == null) return;
    await _setAppSetting!(
      _keyCallsShowSecondaryRemoteActions,
      value ? '1' : '0',
    );
  }

  /// Εμφάνιση κουμπιών «εκκίνηση χωρίς παραμέτρους» δίπλα στα εργαλεία κλήσεων.
  /// Προεπιλογή: true.
  Future<bool> getCallsShowEmptyRemoteLaunchers() async {
    final value = _getAppSetting != null
        ? await _getAppSetting!(_keyCallsShowEmptyRemoteLaunchers)
        : null;
    if (value == null || value.trim().isEmpty) return true;
    final lower = value.trim().toLowerCase();
    return lower != '0' && lower != 'false' && lower != 'no';
  }

  Future<void> setCallsShowEmptyRemoteLaunchers(bool value) async {
    if (_setAppSetting == null) return;
    await _setAppSetting!(
      _keyCallsShowEmptyRemoteLaunchers,
      value ? '1' : '0',
    );
  }

  /// Επιστρέφει λίστα επιλογών για dropdown (split by comma, trim, μη κενά). Τελευταία επιλογή "Κανένα" προστίθεται στα dialogs.
  /// Αν η ρύθμιση είναι κενή, επιστρέφει ["AnyDesk", "VNC"].
  Future<List<String>> getRemoteSurfaceAppsList() async {
    final raw = await getRemoteSurfaceAppsRaw();
    final list = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (list.isEmpty) return ['AnyDesk', 'VNC'];
    return list;
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
        .where((s) =>
            s.isNotEmpty && s != AppConfig.lexiconCategoryUnspecified)
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
          .where((s) =>
              s.isNotEmpty && s != AppConfig.lexiconCategoryUnspecified)
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
        .where((s) =>
            s.isNotEmpty && s != AppConfig.lexiconCategoryUnspecified)
        .toList();
    if (list.isEmpty) return defaultLexiconCategoriesList;
    return list;
  }
}
