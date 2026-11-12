import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_config.dart';
import '../../services/profile_settings.dart';
import '../../services/scoped_settings.dart';

/// Τοπικές ρυθμίσεις μόνο για τη «Λάμπα».
///
/// Δεν χρησιμοποιεί την κεντρική οθόνη ρυθμίσεων της εφαρμογής.
class LampSettingsStore {
  static const String _readPathKey = 'lamp_old_db_read_path';

  /// Κλειδιά της καταργημένης «Δημιουργίας βάσης από Excel» (12/11/2026):
  /// διαβάζονται μόνο μία φορά, από τη μετάβαση, και μετά σβήνονται.
  static const String _retiredExcelPathKey = 'lamp_excel_path';
  static const String _retiredOutputPathKey = 'lamp_old_db_output_path';
  static const String _excelImportRetiredKey = 'lamp_excel_import_retired_v1';
  static const String _integrityStepDurationsMsKey =
      'lamp_integrity_step_durations_ms';

  /// Προεπιλογή: ίδιο με το προηγούμενο hardcoded όριο.
  static const int defaultMaxSearchResults = 100;
  static const int minMaxSearchResults = 1;
  static const int maxMaxSearchResults = 10000;

  static String _prefKey(String baseKey) =>
      AppConfig.prefixedPreferencesKey(baseKey);

  /// **Προσωπικό**: πόσα αποτελέσματα αντέχει κανείς στην οθόνη είναι δικό
  /// του θέμα. Τα όρια ισχύουν στην **εγγραφή** κι όχι μόνο στην ανάγνωση.
  Future<int> getMaxSearchResults() async {
    final v = await ScopedSettings.getInt(
      ProfileSettingKeys.lampMaxSearchResults,
    );
    if (v == null) return defaultMaxSearchResults;
    return v.clamp(minMaxSearchResults, maxMaxSearchResults);
  }

  Future<void> setMaxSearchResults(int value) async {
    final clamped = value.clamp(minMaxSearchResults, maxMaxSearchResults);
    await ScopedSettings.setInt(
      ProfileSettingKeys.lampMaxSearchResults,
      clamped,
    );
  }

  /// Παλιό κλειδί: μονή διαδρομή. Μεταφέρεται αυτόματα στη διαδρομή ανάγνωσης.
  static const String _legacyDatabasePathKey = 'lamp_database_path';

  /// Η βάση που διαβάζει η Λάμπα (αναζήτηση, πίνακες, έλεγχος προβλημάτων).
  Future<String?> getReadPath() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateIfNeeded(prefs);
    final value = prefs.getString(_prefKey(_readPathKey))?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> setReadPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateIfNeeded(prefs);
    await prefs.setString(_prefKey(_readPathKey), path.trim());
  }

  /// Αποθηκευμένο πλάτος λίστας πινάκων (σε px) για την καρτέλα «Πίνακες».
  ///
  /// **Προσωπικό**: ο καθένας στήνει τη διάταξη όπως τον βολεύει.
  Future<double?> getTablesPaneWidthPx() async {
    final value = await ScopedSettings.getDouble(
      ProfileSettingKeys.lampTablesLeftPaneWidth,
    );
    if (value == null || value.isNaN || !value.isFinite) return null;
    if (value < 120 || value > 1200) return null;
    return value;
  }

  Future<void> setTablesPaneWidthPx(double widthPx) async {
    if (widthPx.isNaN || !widthPx.isFinite) return;
    final clamped = widthPx.clamp(120, 1200).toDouble();
    await ScopedSettings.setDouble(
      ProfileSettingKeys.lampTablesLeftPaneWidth,
      clamped,
    );
  }

  Future<Map<String, int>> getIntegrityStepDurationsMs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey(_integrityStepDurationsMsKey));
    if (raw == null || raw.trim().isEmpty) return const <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, int>{};
      return <String, int>{
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is num)
            entry.key as String: (entry.value as num).toInt(),
      };
    } catch (_) {
      return const <String, int>{};
    }
  }

  Future<void> updateIntegrityStepDurationsMs(
    Map<String, int> latestDurationsMs,
  ) async {
    if (latestDurationsMs.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = await getIntegrityStepDurationsMs();
    final merged = <String, int>{...current};
    for (final entry in latestDurationsMs.entries) {
      final latest = entry.value;
      if (latest <= 0) continue;
      final previous = current[entry.key];
      merged[entry.key] = previous == null
          ? latest
          : ((previous * 3 + latest) / 4).round();
    }
    await prefs.setString(
      _prefKey(_integrityStepDurationsMsKey),
      jsonEncode(merged),
    );
  }

  Future<void> _migrateIfNeeded(SharedPreferences prefs) async {
    if (prefs.getBool(_prefKey(_migratedKey)) != true) {
      final read = _nonEmpty(prefs.getString(_prefKey(_readPathKey)));
      final legacy = _nonEmpty(
        prefs.getString(_prefKey(_legacyDatabasePathKey)),
      );
      final resolved = read ?? legacy;
      if (resolved != null) {
        await prefs.setString(_prefKey(_readPathKey), resolved);
      }
      await prefs.setBool(_prefKey(_migratedKey), true);
    }
    await _retireExcelImportSettings(prefs);
  }

  /// Η «Δημιουργία βάσης από Excel» καταργήθηκε. Ως τότε, όταν η βάση της
  /// Λάμπας ήταν κενή, διαβαζόταν σιωπηλά η βάση που δημιουργούσε το Excel —
  /// αυτή περνά τώρα μία φορά στη βάση της Λάμπας, ώστε κανένας σταθμός να
  /// μη χάσει τη Λάμπα του. Μετά σβήνονται οι δύο ρυθμίσεις του Excel.
  Future<void> _retireExcelImportSettings(SharedPreferences prefs) async {
    if (prefs.getBool(_prefKey(_excelImportRetiredKey)) == true) return;
    final read = _nonEmpty(prefs.getString(_prefKey(_readPathKey)));
    final output = _nonEmpty(prefs.getString(_prefKey(_retiredOutputPathKey)));
    if (read == null && output != null) {
      await prefs.setString(_prefKey(_readPathKey), output);
    }
    await prefs.remove(_prefKey(_retiredOutputPathKey));
    await prefs.remove(_prefKey(_retiredExcelPathKey));
    await prefs.setBool(_prefKey(_excelImportRetiredKey), true);
  }

  String? _nonEmpty(String? s) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  static const String _migratedKey = 'lamp_old_db_paths_migrated_v1';
}
