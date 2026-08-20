import 'profile_settings.dart';
import 'scoped_settings.dart';
import 'settings_service.dart';

/// Ρυθμίσεις απομακρυσμένης σύνδεσης, Lansweeper και προτεραιότητας εργαλείων.
///
/// Συνεργάτης του `SettingsService` (Σύνθεση) — πρόσβαση μέσω
/// `SettingsService().remoteLansweeper`. Οι ρυθμίσεις app_settings διαβάζονται
/// μέσω του καταχωρημένου παρόχου του [SettingsService] (μετά το άνοιγμα βάσης).
class SettingsServiceRemoteLansweeper {
  const SettingsServiceRemoteLansweeper();

  /// Κλειδιά για ρυθμίσεις απομακρυσμένης σύνδεσης (πίνακας app_settings).
  static const String _keyLansweeperApiUrl = 'lansweeper_api_url';
  static const String _keyLansweeperApiKey = 'lansweeper_api_key';
  static const String _legacyKeyLansweeperUrl = 'lansweeper_url';

  /// Μία φορά: migration legacy remote_tools → arguments_json (placeholders v2).
  static const String _keyRemoteToolsV2Migrated = 'remote_tools_v2_migrated';

  static Future<String?> Function(String key)? get _getAppSetting =>
      SettingsService.appSettingReader;
  static Future<void> Function(String key, String value)? get _setAppSetting =>
      SettingsService.appSettingWriter;

  /// Καθολική λειτουργία πεδίου «Προτεραιότητα» στη φόρμα εργαλείου:
  /// `false` = ταξινόμιση (ολίσθηση), `true` = αντιμετάθεση θέσεων.
  /// Δεν αποθηκεύεται ανά εργαλείο· κοινή για όλα τα διαλόγους.
  Future<bool> getRemoteToolPrioritySwapMode() async {
    return await ScopedSettings.getBool(
          ProfileSettingKeys.remoteToolPrioritySwapMode,
        ) ??
        false;
  }

  Future<void> setRemoteToolPrioritySwapMode(bool value) async {
    await ScopedSettings.setBool(
      ProfileSettingKeys.remoteToolPrioritySwapMode,
      value,
    );
  }

  // --- Ρυθμίσεις απομακρυσμένης σύνδεσης (app_settings) ---

  /// Προεπιλεγμένο κύριο εργαλείο στην οθόνη κλήσεων (`remote_tools.id`)· null = πρώτο ενεργό.
  Future<int?> getCallsPrimaryToolId() async {
    final value = await ScopedSettings.getString(
      ProfileSettingKeys.callsPrimaryToolId,
    );
    if (value == null || value.trim().isEmpty) return null;
    return int.tryParse(value.trim());
  }

  Future<void> setCallsPrimaryToolId(int? id) async {
    await ScopedSettings.setString(
      ProfileSettingKeys.callsPrimaryToolId,
      id?.toString() ?? '',
    );
  }

  /// Αν false, τα δευτερεύοντα εργαλεία μπαίνουν σε overflow menu.
  Future<bool> getCallsShowSecondaryRemoteActions() async {
    return await ScopedSettings.getBool(
          ProfileSettingKeys.callsShowSecondaryRemoteActions,
        ) ??
        true;
  }

  Future<void> setCallsShowSecondaryRemoteActions(bool value) async {
    await ScopedSettings.setBool(
      ProfileSettingKeys.callsShowSecondaryRemoteActions,
      value,
    );
  }

  /// Εμφάνιση κουμπιών «εκκίνηση χωρίς παραμέτρους» δίπλα στα εργαλεία κλήσεων.
  /// Προεπιλογή: true.
  Future<bool> getCallsShowEmptyRemoteLaunchers() async {
    return await ScopedSettings.getBool(
          ProfileSettingKeys.callsShowEmptyRemoteLaunchers,
        ) ??
        true;
  }

  Future<void> setCallsShowEmptyRemoteLaunchers(bool value) async {
    await ScopedSettings.setBool(
      ProfileSettingKeys.callsShowEmptyRemoteLaunchers,
      value,
    );
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

  /// Όνομα χρήστη πράκτορα Lansweeper — **προσωπικό** (Φάση 2): καθορίζει σε
  /// ποιον χρεώνεται το αίτημα, οπότε κοινή τιμή σημαίνει λάθος χρέωση.
  Future<String?> getLansweeperAgentUsername() async {
    final value = await ScopedSettings.getString(
      ProfileSettingKeys.lansweeperAgentUsername,
    );
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> setLansweeperAgentUsername(String value) async {
    await ScopedSettings.setString(
      ProfileSettingKeys.lansweeperAgentUsername,
      value.trim(),
    );
  }
}
