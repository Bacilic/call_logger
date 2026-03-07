import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Υπηρεσία αποθήκευσης και ανάκτησης ρυθμίσεων (key-value) τοπικά.
class SettingsService {
  static const String _keyDatabasePath = 'database_path';
  static const String _keyRecentPaths = 'recent_database_paths';
  static const String _keyShowImportExcelButton = 'show_import_excel_button';
  static const int _maxRecentPaths = 3;

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
}
