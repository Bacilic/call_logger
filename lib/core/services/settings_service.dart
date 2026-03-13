import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Υπηρεσία αποθήκευσης και ανάκτησης ρυθμίσεων (key-value) τοπικά.
class SettingsService {
  static const String _keyDatabasePath = 'database_path';
  static const String _keyRecentPaths = 'recent_database_paths';
  static const String _keyShowImportExcelButton = 'show_import_excel_button';
  static const int _maxRecentPaths = 3;

  /// Κλειδιά για ρυθμίσεις απομακρυσμένης σύνδεσης (πίνακας app_settings).
  static const String _keyVncPaths = 'vnc_paths';
  static const String _keyVncPassword = 'vnc_password';
  static const String _keyAnydeskPath = 'anydesk_path';

  /// Προεπιλεγμένες διαδρομές αναζήτησης TightVNC Viewer.
  static const List<String> _defaultVncPaths = [
    r'C:\Program Files\TightVNC\tvnviewer.exe',
    r'C:\Program Files (x86)\TightVNC\tvnviewer.exe',
  ];

  /// Προεπιλεγμένη διαδρομή AnyDesk.
  static const String _defaultAnydeskPath = r'C:\Program Files (x86)\AnyDesk\AnyDesk.exe';

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
  /// Αν δεν υπάρχει ή είναι κενή, επιστρέφει την [AppConfig.defaultDbPath].
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
    final updated = [path, ...list.where((p) => p != path)].take(_maxRecentPaths).toList();
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

  // --- Ρυθμίσεις απομακρυσμένης σύνδεσης (app_settings) ---

  /// Επιστρέφει τη λίστα διαδρομών για TightVNC Viewer.
  /// Αν δεν υπάρχει τιμή στη βάση, επιστρέφει τις προεπιλεγμένες διαδρομές.
  /// Η τιμή αποθηκεύεται ως JSON (λίστα strings).
  Future<List<String>> getVncPaths() async {
    final raw = _getAppSetting != null ? await _getAppSetting!(_keyVncPaths) : null;
    if (raw == null || raw.trim().isEmpty) return List.from(_defaultVncPaths);
    try {
      final decoded = jsonDecode(raw) as List<dynamic>?;
      if (decoded == null) return List.from(_defaultVncPaths);
      return decoded.map((e) => e.toString()).toList();
    } catch (_) {
      return List.from(_defaultVncPaths);
    }
  }

  /// Αποθηκεύει τη λίστα διαδρομών VNC στη βάση (JSON).
  Future<void> setVncPaths(List<String> paths) async {
    if (_setAppSetting != null) await _setAppSetting!(_keyVncPaths, jsonEncode(paths));
  }

  /// Επιστρέφει τον αποθηκευμένο κωδικό VNC. Προεπιλογή: κενό string.
  Future<String> getVncPassword() async {
    final value = _getAppSetting != null ? await _getAppSetting!(_keyVncPassword) : null;
    return value ?? '';
  }

  /// Αποθηκεύει τον κωδικό VNC στη βάση.
  Future<void> setVncPassword(String password) async {
    if (_setAppSetting != null) await _setAppSetting!(_keyVncPassword, password);
  }

  /// Επιστρέφει την αποθηκευμένη διαδρομή AnyDesk. Αν δεν υπάρχει ή είναι κενή, η προεπιλογή.
  Future<String> getAnydeskPath() async {
    final value = _getAppSetting != null ? await _getAppSetting!(_keyAnydeskPath) : null;
    if (value == null || value.trim().isEmpty) return _defaultAnydeskPath;
    return value.trim();
  }

  /// Αποθηκεύει τη διαδρομή AnyDesk στη βάση.
  Future<void> setAnydeskPath(String path) async {
    if (_setAppSetting != null) await _setAppSetting!(_keyAnydeskPath, path.trim());
  }
}
