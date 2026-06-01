import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../config/audit_retention_config.dart';
import '../models/calls_screen_cards_visibility.dart';
import '../models/window_placement_mode.dart';

/// Υπηρεσία αποθήκευσης και ανάκτησης ρυθμίσεων (key-value) τοπικά.
class SettingsService {
  static const String _keyDatabasePath = 'database_path';
  static const String _keyRecentPaths = 'recent_database_paths';
  static const String _keyShowActiveTimer = 'show_active_timer';
  static const String _keyShowTasksBadge = 'show_tasks_badge';
  static const String _keyNavRailShowLabels = 'nav_rail_show_labels';
  static const String _keyWindowWidth = 'window_width_v1';
  static const String _keyWindowHeight = 'window_height_v1';
  static const String _keyWindowPositionX = 'window_position_x_v1';
  static const String _keyWindowPositionY = 'window_position_y_v1';
  static const String _keyWindowPlacementMode = 'window_placement_mode_v1';
  static const String _keyDatabaseBrowserStatsCardExpanded =
      'database_browser_stats_card_expanded';
  static const String _keyEquipmentLocationShowBuilding =
      'equipment_location_show_building';
  static const String _keyEnableSpellCheck = 'enable_spell_check';
  static const String _keyShowGlobalCallsDashboard =
      'show_global_calls_dashboard';
  static const String _keyDashboardDatePreset = 'dashboard_date_preset';
  static const String _keyDashboardDateFrom = 'dashboard_date_from';
  static const String _keyDashboardDateTo = 'dashboard_date_to';
  static const String _keyTaskAnalyticsDatePreset =
      'task_analytics_date_preset_v1';
  static const String _keyTaskAnalyticsDateFrom =
      'task_analytics_date_from_v1';
  static const String _keyTaskAnalyticsDateTo = 'task_analytics_date_to_v1';
  static const String _keyDatabaseOpenTimeoutSeconds =
      'database_open_timeout_seconds';
  static const String _keyDatabaseOpenMaxAttempts =
      'database_open_max_attempts';
  static const String _keyDictionarySourcePath = 'dictionary_source_path';
  static const String _keyDictionaryExportPath = 'dictionary_export_path';
  static const String _keyShowDatabaseNav = 'show_database_nav';
  static const String _keyShowLampNav = 'show_lamp_nav';
  static const String _keyShowDictionaryNav = 'show_dictionary_nav';
  static const String _keyCallsScreenCardsVisibility =
      'calls_screen_cards_visibility_v1';
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
  static const String _keyLansweeperApiUrl = 'lansweeper_api_url';
  static const String _keyLansweeperApiKey = 'lansweeper_api_key';
  static const String _keyLansweeperAgentUsername = 'lansweeper_agent_username';
  static const String _legacyKeyLansweeperUrl = 'lansweeper_url';
  static const String _keyLansweeperHelpdeskAutoLogin =
      'lansweeper_helpdesk_auto_login';
  static const String _keyLansweeperHelpdeskLoginUrl =
      'lansweeper_helpdesk_login_url';
  static const String _keyLansweeperHelpdeskWebUsername =
      'lansweeper_helpdesk_web_username';
  static const String _keyLansweeperHelpdeskWebPassword =
      'lansweeper_helpdesk_web_password';

  /// Μία φορά: migration legacy remote_tools → arguments_json (placeholders v2).
  static const String _keyRemoteToolsV2Migrated = 'remote_tools_v2_migrated';
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

  /// Κλειδί αποθήκευσης SharedPreferences (με πρόθεμα προφίλ όταν υπάρχει CLI `--profile`).
  static String _prefKey(String baseKey) =>
      AppConfig.prefixedPreferencesKey(baseKey);

  /// Επιστρέφει την αποθηκευμένη διαδρομή βάσης δεδομένων.
  /// Αν δεν υπάρχει ή είναι κενή, επιστρέφει το [AppConfig.defaultDbPath]
  /// (`..\Data Base\call_logger.db` δίπλα στο εκτελέσιμο).
  Future<String> getDatabasePath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_prefKey(_keyDatabasePath));
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

  /// Εμφάνιση ενεργού χρονομέτρου στη φόρμα κλήσεων. Προεπιλογή: true.
  Future<bool> getShowActiveTimer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(_keyShowActiveTimer)) ?? true;
  }

  /// Ορίζει αν θα εμφανίζεται το ενεργό χρονόμετρο (MM:SS) στη φόρμα κλήσεων.
  Future<void> setShowActiveTimer(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(_keyShowActiveTimer), value);
  }

  /// Εμφάνιση μετρητή (badge) εκκρεμοτήτων στο κεντρικό μενού. Προεπιλογή: true.
  Future<bool> getShowTasksBadge() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(_keyShowTasksBadge)) ?? true;
  }

  Future<void> setShowTasksBadge(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(_keyShowTasksBadge), value);
  }

  /// Εμφάνιση λεζαντών στην πλευρική μπάρα (NavigationRail extended) όταν το πλάτος επιτρέπει.
  /// Προεπιλογή: true.
  Future<bool> getNavRailShowLabels() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(_keyNavRailShowLabels)) ?? true;
  }

  Future<void> setNavRailShowLabels(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(_keyNavRailShowLabels), value);
  }

  /// Τελευταίο πλάτος/ύψος κύριου παραθύρου (Windows desktop)· null αν δεν έχει αποθηκευτεί.
  Future<({double width, double height})?> getSavedWindowSize() async {
    final prefs = await SharedPreferences.getInstance();
    final width = prefs.getDouble(_prefKey(_keyWindowWidth));
    final height = prefs.getDouble(_prefKey(_keyWindowHeight));
    if (width == null ||
        height == null ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      return null;
    }
    return (width: width, height: height);
  }

  /// Αποθήκευση τελευταίου μεγέθους παραθύρου που όρισε ο χρήστης.
  Future<void> setSavedWindowSize({
    required double width,
    required double height,
  }) async {
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefKey(_keyWindowWidth), width);
    await prefs.setDouble(_prefKey(_keyWindowHeight), height);
  }

  /// Τελευταία θέση κύριου παραθύρου (πάνω-αριστερή γωνία)· null αν δεν έχει αποθηκευτεί.
  Future<({double x, double y})?> getSavedWindowPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble(_prefKey(_keyWindowPositionX));
    final y = prefs.getDouble(_prefKey(_keyWindowPositionY));
    if (x == null ||
        y == null ||
        !x.isFinite ||
        !y.isFinite) {
      return null;
    }
    return (x: x, y: y);
  }

  /// Αποθήκευση τελευταίας θέσης παραθύρου (πάνω-αριστερή γωνία).
  Future<void> setSavedWindowPosition({
    required double x,
    required double y,
  }) async {
    if (!x.isFinite || !y.isFinite) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefKey(_keyWindowPositionX), x);
    await prefs.setDouble(_prefKey(_keyWindowPositionY), y);
  }

  /// Πού εμφανίζεται το παράθυρο στην επόμενη εκκίνηση. Προεπιλογή: κέντρο οθόνης.
  Future<WindowPlacementMode> getWindowPlacementMode() async {
    final prefs = await SharedPreferences.getInstance();
    return WindowPlacementModeStorage.fromStorage(
          prefs.getString(_prefKey(_keyWindowPlacementMode)),
        ) ??
        WindowPlacementMode.alwaysCenter;
  }

  Future<void> setWindowPlacementMode(WindowPlacementMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey(_keyWindowPlacementMode), mode.storageValue);
  }

  /// Κάρτα «Στατιστικά Βάσης Δεδομένων» στην οθόνη περιήγησης βάσης — ανοιχτή/κλειστή.
  /// Προεπιλογή: false (συμπτυγμένη).
  Future<bool> getDatabaseBrowserStatsCardExpanded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(_keyDatabaseBrowserStatsCardExpanded)) ?? false;
  }

  Future<void> setDatabaseBrowserStatsCardExpanded(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(_keyDatabaseBrowserStatsCardExpanded), value);
  }

  /// Εμφάνιση κωδικού κτιρίου `[...]` στη στήλη Τοποθεσία (πίνακας εξοπλισμού). Προεπιλογή: true.
  Future<bool> getEquipmentLocationShowBuilding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(_keyEquipmentLocationShowBuilding)) ?? true;
  }

  Future<void> setEquipmentLocationShowBuilding(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(_keyEquipmentLocationShowBuilding), value);
  }

  /// Ενεργοποίηση ενσωματωμένου ορθογραφικού ελέγχου σημειώσεων (Windows). Προεπιλογή: true.
  Future<bool> getEnableSpellCheck() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(_keyEnableSpellCheck)) ?? true;
  }

  Future<void> setEnableSpellCheck(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(_keyEnableSpellCheck), value);
  }

  /// Εμφάνιση κάρτας «Τελευταίες 7 Κλήσεις» στην οθόνη κλήσεων. Προεπιλογή: true.
  Future<bool> getShowGlobalCalls() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(_keyShowGlobalCallsDashboard)) ?? true;
  }

  Future<void> setShowGlobalCalls(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(_keyShowGlobalCallsDashboard), value);
  }

  /// Τελευταία επιλογή εύρους ημερομηνιών στον πίνακα στατιστικών κλήσεων.
  /// Προεπιλογή: `today`.
  Future<String> getDashboardDatePreset() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey(_keyDashboardDatePreset)) ?? 'today';
  }

  Future<DateTime?> getDashboardCustomDateFrom() async {
    final prefs = await SharedPreferences.getInstance();
    return _parseStoredDate(prefs.getString(_prefKey(_keyDashboardDateFrom)));
  }

  Future<DateTime?> getDashboardCustomDateTo() async {
    final prefs = await SharedPreferences.getInstance();
    return _parseStoredDate(prefs.getString(_prefKey(_keyDashboardDateTo)));
  }

  Future<void> setDashboardDateFilter({
    required String preset,
    DateTime? customFrom,
    DateTime? customTo,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey(_keyDashboardDatePreset), preset);
    if (preset == 'custom' && customFrom != null && customTo != null) {
      await prefs.setString(
        _keyDashboardDateFrom,
        _formatStoredDate(customFrom),
      );
      await prefs.setString(_prefKey(_keyDashboardDateTo), _formatStoredDate(customTo));
    } else {
      await prefs.remove(_prefKey(_keyDashboardDateFrom));
      await prefs.remove(_prefKey(_keyDashboardDateTo));
    }
  }

  /// Τελευταία επιλογή εύρους ημερομηνιών στις αναφορές εκκρεμοτήτων.
  /// Προεπιλογή: `all` (πλήρες εύρος δημιουργίας).
  Future<String> getTaskAnalyticsDatePreset() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey(_keyTaskAnalyticsDatePreset)) ?? 'all';
  }

  Future<DateTime?> getTaskAnalyticsCustomDateFrom() async {
    final prefs = await SharedPreferences.getInstance();
    return _parseStoredDate(prefs.getString(_prefKey(_keyTaskAnalyticsDateFrom)));
  }

  Future<DateTime?> getTaskAnalyticsCustomDateTo() async {
    final prefs = await SharedPreferences.getInstance();
    return _parseStoredDate(prefs.getString(_prefKey(_keyTaskAnalyticsDateTo)));
  }

  Future<void> setTaskAnalyticsDateFilter({
    required String preset,
    DateTime? customFrom,
    DateTime? customTo,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey(_keyTaskAnalyticsDatePreset), preset);
    if (preset == 'custom' && customFrom != null && customTo != null) {
      await prefs.setString(
        _keyTaskAnalyticsDateFrom,
        _formatStoredDate(customFrom),
      );
      await prefs.setString(
        _keyTaskAnalyticsDateTo,
        _formatStoredDate(customTo),
      );
    } else {
      await prefs.remove(_prefKey(_keyTaskAnalyticsDateFrom));
      await prefs.remove(_prefKey(_keyTaskAnalyticsDateTo));
    }
  }

  static DateTime? _parseStoredDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static String _formatStoredDate(DateTime d) {
    final y = d.year;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

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

  /// Διαδρομή αρχείου TXT που φορτώνει το runtime λεξικό ορθογραφίας (μετά το Compile).
  /// Κενό/null = χρήση bundled asset.
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

  /// Εμφάνιση στοιχείου πλοήγησης «Βάση Δεδομένων». Προεπιλογή: true.
  Future<bool> getShowDatabaseNav() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(_keyShowDatabaseNav)) ?? true;
  }

  Future<void> setShowDatabaseNav(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(_keyShowDatabaseNav), value);
  }

  /// Εμφάνιση στοιχείου πλοήγησης «Λάμπα» (παλιά βάση). Προεπιλογή: true.
  Future<bool> getShowLampNav() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(_keyShowLampNav)) ?? true;
  }

  Future<void> setShowLampNav(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(_keyShowLampNav), value);
  }

  /// Εμφάνιση στοιχείου πλοήγησης «Λεξικό». Προεπιλογή: true.
  Future<bool> getShowDictionaryNav() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(_keyShowDictionaryNav)) ?? true;
  }

  Future<void> setShowDictionaryNav(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(_keyShowDictionaryNav), value);
  }

  /// Ποια κάρτες εμφανίζονται στην οθόνη κλήσεων. Προεπιλογή: όλες ορατές.
  Future<CallsScreenCardsVisibility> getCallsScreenCardsVisibility() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey(_keyCallsScreenCardsVisibility));
    return CallsScreenCardsVisibility.fromJsonString(raw);
  }

  Future<void> setCallsScreenCardsVisibility(
    CallsScreenCardsVisibility value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey(_keyCallsScreenCardsVisibility), value.toJsonString());
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
      _keyAuditRetentionConfig,
      jsonEncode(config.toJson()),
    );
  }

  /// Καθολική λειτουργία πεδίου «Προτεραιότητα» στη φόρμα εργαλείου:
  /// `false` = ταξινόμιση (ολίσθηση), `true` = αντιμετάθεση θέσεων.
  /// Δεν αποθηκεύεται ανά εργαλείο· κοινή για όλα τα διαλόγους.
  Future<bool> getRemoteToolPrioritySwapMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(_keyRemoteToolPrioritySwapMode)) ?? false;
  }

  Future<void> setRemoteToolPrioritySwapMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(_keyRemoteToolPrioritySwapMode), value);
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
    await _setAppSetting!(_keyCallsShowEmptyRemoteLaunchers, value ? '1' : '0');
  }

  /// Έχει ολοκληρωθεί το one-shot migration legacy remote_tools → arguments_json.
  Future<bool> getRemoteToolsV2Migrated() async {
    final value = _getAppSetting != null
        ? await _getAppSetting!(_keyRemoteToolsV2Migrated)
        : null;
    if (value == null || value.trim().isEmpty) return false;
    final lower = value.trim().toLowerCase();
    return lower == '1' || lower == 'true';
  }

  Future<void> setRemoteToolsV2Migrated(bool value) async {
    if (_setAppSetting == null) return;
    await _setAppSetting!(_keyRemoteToolsV2Migrated, value ? '1' : '0');
  }

  /// URL API Lansweeper (`lansweeper_api_url`). Legacy `lansweeper_url` μόνο αν περιέχει `api.aspx`.
  Future<String?> getLansweeperApiUrl() async {
    if (_getAppSetting == null) return null;
    final direct = await _getAppSetting!(_keyLansweeperApiUrl);
    final normalizedDirect = direct?.trim() ?? '';
    if (_looksLikeLansweeperApiUrl(normalizedDirect)) {
      return normalizedDirect;
    }
    final legacy = await _getAppSetting!(_legacyKeyLansweeperUrl);
    final normalizedLegacy = legacy?.trim() ?? '';
    if (_looksLikeLansweeperApiUrl(normalizedLegacy)) {
      return normalizedLegacy;
    }
    return null;
  }

  static bool _looksLikeLansweeperApiUrl(String value) {
    if (value.isEmpty) return false;
    final u = Uri.tryParse(value);
    if (u == null || !u.hasScheme || u.host.isEmpty) return false;
    if (u.scheme != 'http' && u.scheme != 'https') return false;
    final p = u.path.toLowerCase();
    final v = value.toLowerCase();
    return p.contains('api.aspx') || v.contains('/api.aspx');
  }

  Future<void> setLansweeperApiUrl(String value) async {
    if (_setAppSetting == null) return;
    await _setAppSetting!(_keyLansweeperApiUrl, value.trim());
  }

  /// Κοινό API key Lansweeper στο app_settings.
  Future<String?> getLansweeperApiKey() async {
    if (_getAppSetting == null) return null;
    final value = await _getAppSetting!(_keyLansweeperApiKey);
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> setLansweeperApiKey(String value) async {
    if (_setAppSetting == null) return;
    await _setAppSetting!(_keyLansweeperApiKey, value.trim());
  }

  /// Όνομα χρήστη πράκτορα Lansweeper (μόνιμη ρύθμιση, κοινό σε υποβολές).
  Future<String?> getLansweeperAgentUsername() async {
    if (_getAppSetting == null) return null;
    final value = await _getAppSetting!(_keyLansweeperAgentUsername);
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> setLansweeperAgentUsername(String value) async {
    if (_setAppSetting == null) return;
    await _setAppSetting!(_keyLansweeperAgentUsername, value.trim());
  }

  /// Αυτόματο άνοιγμα σελίδας σύνδεσης πριν τη φόρμα αιτήματος (browser).
  Future<bool> getLansweeperHelpdeskAutoLogin() async {
    if (_getAppSetting == null) return false;
    final raw = await _getAppSetting!(_keyLansweeperHelpdeskAutoLogin);
    final t = (raw ?? '').trim().toLowerCase();
    return t == '1' || t == 'true' || t == 'yes';
  }

  Future<void> setLansweeperHelpdeskAutoLogin(bool value) async {
    if (_setAppSetting == null) return;
    await _setAppSetting!(_keyLansweeperHelpdeskAutoLogin, value ? '1' : '0');
  }

  Future<String?> getLansweeperHelpdeskLoginUrl() async {
    if (_getAppSetting == null) return null;
    final v = (await _getAppSetting!(_keyLansweeperHelpdeskLoginUrl))?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  Future<void> setLansweeperHelpdeskLoginUrl(String value) async {
    if (_setAppSetting == null) return;
    await _setAppSetting!(_keyLansweeperHelpdeskLoginUrl, value.trim());
  }

  Future<String?> getLansweeperHelpdeskWebUsername() async {
    if (_getAppSetting == null) return null;
    final v =
        (await _getAppSetting!(_keyLansweeperHelpdeskWebUsername))?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  Future<void> setLansweeperHelpdeskWebUsername(String value) async {
    if (_setAppSetting == null) return;
    await _setAppSetting!(_keyLansweeperHelpdeskWebUsername, value.trim());
  }

  Future<String?> getLansweeperHelpdeskWebPassword() async {
    if (_getAppSetting == null) return null;
    final v =
        (await _getAppSetting!(_keyLansweeperHelpdeskWebPassword))?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  Future<void> setLansweeperHelpdeskWebPassword(String value) async {
    if (_setAppSetting == null) return;
    await _setAppSetting!(_keyLansweeperHelpdeskWebPassword, value);
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
