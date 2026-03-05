import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Υπηρεσία αποθήκευσης και ανάκτησης ρυθμίσεων (key-value) τοπικά.
class SettingsService {
  static const String _keyDatabasePath = 'database_path';

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

  /// Αποθηκεύει τη νέα διαδρομή βάσης δεδομένων.
  Future<void> setDatabasePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDatabasePath, path.trim());
  }
}
