part of 'settings_service.dart';

/// Ρυθμίσεις απομακρυσμένης σύνδεσης, Lansweeper και προτεραιότητας εργαλείων.
mixin SettingsServiceRemoteLansweeperMixin {
  /// Κλειδιά για ρυθμίσεις απομακρυσμένης σύνδεσης (πίνακας app_settings).
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
  static const String _keyRemoteToolPrioritySwapMode =
      'remote_tool_priority_swap_mode';

  /// Καθολική λειτουργία πεδίου «Προτεραιότητα» στη φόρμα εργαλείου:
  /// `false` = ταξινόμιση (ολίσθηση), `true` = αντιμετάθεση θέσεων.
  /// Δεν αποθηκεύεται ανά εργαλείο· κοινή για όλα τα διαλόγους.
  Future<bool> getRemoteToolPrioritySwapMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(SettingsService._prefKey(_keyRemoteToolPrioritySwapMode)) ?? false;
  }

  Future<void> setRemoteToolPrioritySwapMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsService._prefKey(_keyRemoteToolPrioritySwapMode), value);
  }

  // --- Ρυθμίσεις απομακρυσμένης σύνδεσης (app_settings) ---

  /// Προεπιλεγμένο κύριο εργαλείο στην οθόνη κλήσεων (`remote_tools.id`)· null = πρώτο ενεργό.
  Future<int?> getCallsPrimaryToolId() async {
    final value = SettingsService._getAppSetting != null
        ? await SettingsService._getAppSetting!(_keyCallsPrimaryToolId)
        : null;
    if (value == null || value.trim().isEmpty) return null;
    return int.tryParse(value.trim());
  }

  Future<void> setCallsPrimaryToolId(int? id) async {
    if (SettingsService._setAppSetting == null) return;
    if (id == null) {
      await SettingsService._setAppSetting!(_keyCallsPrimaryToolId, '');
    } else {
      await SettingsService._setAppSetting!(_keyCallsPrimaryToolId, id.toString());
    }
  }

  /// Αν false, τα δευτερεύοντα εργαλεία μπαίνουν σε overflow menu.
  Future<bool> getCallsShowSecondaryRemoteActions() async {
    final value = SettingsService._getAppSetting != null
        ? await SettingsService._getAppSetting!(_keyCallsShowSecondaryRemoteActions)
        : null;
    if (value == null || value.trim().isEmpty) return true;
    final lower = value.trim().toLowerCase();
    return lower != '0' && lower != 'false' && lower != 'no';
  }

  Future<void> setCallsShowSecondaryRemoteActions(bool value) async {
    if (SettingsService._setAppSetting == null) return;
    await SettingsService._setAppSetting!(
      _keyCallsShowSecondaryRemoteActions,
      value ? '1' : '0',
    );
  }

  /// Εμφάνιση κουμπιών «εκκίνηση χωρίς παραμέτρους» δίπλα στα εργαλεία κλήσεων.
  /// Προεπιλογή: true.
  Future<bool> getCallsShowEmptyRemoteLaunchers() async {
    final value = SettingsService._getAppSetting != null
        ? await SettingsService._getAppSetting!(_keyCallsShowEmptyRemoteLaunchers)
        : null;
    if (value == null || value.trim().isEmpty) return true;
    final lower = value.trim().toLowerCase();
    return lower != '0' && lower != 'false' && lower != 'no';
  }

  Future<void> setCallsShowEmptyRemoteLaunchers(bool value) async {
    if (SettingsService._setAppSetting == null) return;
    await SettingsService._setAppSetting!(_keyCallsShowEmptyRemoteLaunchers, value ? '1' : '0');
  }

  /// Έχει ολοκληρωθεί το one-shot migration legacy remote_tools → arguments_json.
  Future<bool> getRemoteToolsV2Migrated() async {
    final value = SettingsService._getAppSetting != null
        ? await SettingsService._getAppSetting!(_keyRemoteToolsV2Migrated)
        : null;
    if (value == null || value.trim().isEmpty) return false;
    final lower = value.trim().toLowerCase();
    return lower == '1' || lower == 'true';
  }

  Future<void> setRemoteToolsV2Migrated(bool value) async {
    if (SettingsService._setAppSetting == null) return;
    await SettingsService._setAppSetting!(_keyRemoteToolsV2Migrated, value ? '1' : '0');
  }

  /// URL API Lansweeper (`lansweeper_api_url`). Legacy `lansweeper_url` μόνο αν περιέχει `api.aspx`.
  Future<String?> getLansweeperApiUrl() async {
    if (SettingsService._getAppSetting == null) return null;
    final direct = await SettingsService._getAppSetting!(_keyLansweeperApiUrl);
    final normalizedDirect = direct?.trim() ?? '';
    if (_looksLikeLansweeperApiUrl(normalizedDirect)) {
      return normalizedDirect;
    }
    final legacy = await SettingsService._getAppSetting!(_legacyKeyLansweeperUrl);
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
    if (SettingsService._setAppSetting == null) return;
    await SettingsService._setAppSetting!(_keyLansweeperApiUrl, value.trim());
  }

  /// Κοινό API key Lansweeper στο app_settings.
  Future<String?> getLansweeperApiKey() async {
    if (SettingsService._getAppSetting == null) return null;
    final value = await SettingsService._getAppSetting!(_keyLansweeperApiKey);
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> setLansweeperApiKey(String value) async {
    if (SettingsService._setAppSetting == null) return;
    await SettingsService._setAppSetting!(_keyLansweeperApiKey, value.trim());
  }

  /// Όνομα χρήστη πράκτορα Lansweeper (μόνιμη ρύθμιση, κοινό σε υποβολές).
  Future<String?> getLansweeperAgentUsername() async {
    if (SettingsService._getAppSetting == null) return null;
    final value = await SettingsService._getAppSetting!(_keyLansweeperAgentUsername);
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> setLansweeperAgentUsername(String value) async {
    if (SettingsService._setAppSetting == null) return;
    await SettingsService._setAppSetting!(_keyLansweeperAgentUsername, value.trim());
  }

  /// Αυτόματο άνοιγμα σελίδας σύνδεσης πριν τη φόρμα αιτήματος (browser).
  Future<bool> getLansweeperHelpdeskAutoLogin() async {
    if (SettingsService._getAppSetting == null) return false;
    final raw = await SettingsService._getAppSetting!(_keyLansweeperHelpdeskAutoLogin);
    final t = (raw ?? '').trim().toLowerCase();
    return t == '1' || t == 'true' || t == 'yes';
  }

  Future<void> setLansweeperHelpdeskAutoLogin(bool value) async {
    if (SettingsService._setAppSetting == null) return;
    await SettingsService._setAppSetting!(_keyLansweeperHelpdeskAutoLogin, value ? '1' : '0');
  }

  Future<String?> getLansweeperHelpdeskLoginUrl() async {
    if (SettingsService._getAppSetting == null) return null;
    final v = (await SettingsService._getAppSetting!(_keyLansweeperHelpdeskLoginUrl))?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  Future<void> setLansweeperHelpdeskLoginUrl(String value) async {
    if (SettingsService._setAppSetting == null) return;
    await SettingsService._setAppSetting!(_keyLansweeperHelpdeskLoginUrl, value.trim());
  }

  Future<String?> getLansweeperHelpdeskWebUsername() async {
    if (SettingsService._getAppSetting == null) return null;
    final v =
        (await SettingsService._getAppSetting!(_keyLansweeperHelpdeskWebUsername))?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  Future<void> setLansweeperHelpdeskWebUsername(String value) async {
    if (SettingsService._setAppSetting == null) return;
    await SettingsService._setAppSetting!(_keyLansweeperHelpdeskWebUsername, value.trim());
  }

  Future<String?> getLansweeperHelpdeskWebPassword() async {
    if (SettingsService._getAppSetting == null) return null;
    final v =
        (await SettingsService._getAppSetting!(_keyLansweeperHelpdeskWebPassword))?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  Future<void> setLansweeperHelpdeskWebPassword(String value) async {
    if (SettingsService._setAppSetting == null) return;
    await SettingsService._setAppSetting!(_keyLansweeperHelpdeskWebPassword, value);
  }
}
