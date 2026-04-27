import 'package:shared_preferences/shared_preferences.dart';

/// Τοπικές ρυθμίσεις μόνο για τη «Λάμπα».
///
/// Δεν χρησιμοποιεί την κεντρική οθόνη ρυθμίσεων της εφαρμογής.
class LampSettingsStore {
  static const String _excelPathKey = 'lamp_excel_path';
  static const String _readPathKey = 'lamp_old_db_read_path';
  static const String _outputPathKey = 'lamp_old_db_output_path';
  static const String _tablesPaneWidthKey = 'lamp_tables_left_pane_width_px';
  static const String _maxSearchResultsKey = 'lamp_max_search_results';

  /// Προεπιλογή: ίδιο με το προηγούμενο hardcoded όριο.
  static const int defaultMaxSearchResults = 100;
  static const int minMaxSearchResults = 1;
  static const int maxMaxSearchResults = 10000;

  Future<int> getMaxSearchResults() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_maxSearchResultsKey);
    if (v == null) return defaultMaxSearchResults;
    return v.clamp(minMaxSearchResults, maxMaxSearchResults);
  }

  Future<void> setMaxSearchResults(int value) async {
    final prefs = await SharedPreferences.getInstance();
    final clamped = value.clamp(minMaxSearchResults, maxMaxSearchResults);
    await prefs.setInt(_maxSearchResultsKey, clamped);
  }

  /// Παλιό κλειδί: μονή διαδρομή. Μεταφέρεται αυτόματα σε [read] και [output].
  static const String _legacyDatabasePathKey = 'lamp_database_path';

  Future<String?> getExcelPath() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_excelPathKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> setExcelPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_excelPathKey, path.trim());
  }

  /// Διαδρομή .db **για αναζήτηση, ETL issues** κ.λπ.
  Future<String?> getReadPath() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateIfNeeded(prefs);
    var value = prefs.getString(_readPathKey)?.trim();
    if (value == null || value.isEmpty) {
      value = prefs.getString(_outputPathKey)?.trim();
    }
    return value == null || value.isEmpty ? null : value;
  }

  /// Αποθηκευμένη διαδρομή ανάγνωσης (χωρίς fallback) — χρήση μόνο για UI.
  Future<String?> getReadPathRaw() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateIfNeeded(prefs);
    final value = prefs.getString(_readPathKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> setReadPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateIfNeeded(prefs);
    await prefs.setString(_readPathKey, path.trim());
  }

  /// Διαδρομή .db **όπου γράφει το import/ενημέρωση από Excel**.
  Future<String?> getOutputPath() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateIfNeeded(prefs);
    var value = prefs.getString(_outputPathKey)?.trim();
    if (value == null || value.isEmpty) {
      value = prefs.getString(_readPathKey)?.trim();
    }
    return value == null || value.isEmpty ? null : value;
  }

  Future<String?> getOutputPathRaw() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateIfNeeded(prefs);
    final value = prefs.getString(_outputPathKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> setOutputPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateIfNeeded(prefs);
    await prefs.setString(_outputPathKey, path.trim());
  }

  /// Μετά από επιτυχημένη δημιουργία: και τα δύο ίδια. Ο τεχνικός αλλάζει
  /// ξεχωριστά το [read] για δοκιμές.
  Future<void> setOutputAndReadFromImportResult(String newOutputPath) async {
    final p = newOutputPath.trim();
    final prefs = await SharedPreferences.getInstance();
    await _migrateIfNeeded(prefs);
    await prefs.setString(_outputPathKey, p);
    await prefs.setString(_readPathKey, p);
  }

  /// Αποθηκευμένο πλάτος λίστας πινάκων (σε px) για την καρτέλα «Πίνακες».
  Future<double?> getTablesPaneWidthPx() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getDouble(_tablesPaneWidthKey);
    if (value == null || value.isNaN || !value.isFinite) return null;
    if (value < 120 || value > 1200) return null;
    return value;
  }

  Future<void> setTablesPaneWidthPx(double widthPx) async {
    if (widthPx.isNaN || !widthPx.isFinite) return;
    final prefs = await SharedPreferences.getInstance();
    final clamped = widthPx.clamp(120, 1200).toDouble();
    await prefs.setDouble(_tablesPaneWidthKey, clamped);
  }

  /// [Deprecated] Χρήση μόνο εσωτερική για migration.
  Future<String?> getDatabasePath() async {
    return getReadPath();
  }

  /// [Deprecated] Χρήση [setReadPath] / [setOutputPath].
  Future<void> setDatabasePath(String path) async {
    await setOutputPath(path);
    final read = await getReadPathRaw();
    if (read == null || read.isEmpty) {
      await setReadPath(path);
    }
  }

  Future<void> _migrateIfNeeded(SharedPreferences prefs) async {
    if (prefs.getBool(_migratedKey) == true) return;

    String? r = _nonEmpty(prefs.getString(_readPathKey));
    String? o = _nonEmpty(prefs.getString(_outputPathKey));
    final String? legacy = _nonEmpty(prefs.getString(_legacyDatabasePathKey));

    if (legacy != null) {
      r ??= legacy;
      o ??= legacy;
    }
    if (r == null && o != null) r = o;
    if (o == null && r != null) o = r;
    if (r != null) await prefs.setString(_readPathKey, r);
    if (o != null) await prefs.setString(_outputPathKey, o);
    await prefs.setBool(_migratedKey, true);
  }

  String? _nonEmpty(String? s) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  static const String _migratedKey = 'lamp_old_db_paths_migrated_v1';
}
