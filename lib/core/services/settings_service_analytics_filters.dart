part of 'settings_service.dart';

/// Φίλτρα ημερομηνιών για στατιστικά κλήσεων και εκκρεμοτήτων.
mixin SettingsServiceAnalyticsFiltersMixin {
  static const String _keyDashboardDatePreset = 'dashboard_date_preset';
  static const String _keyDashboardDateFrom = 'dashboard_date_from';
  static const String _keyDashboardDateTo = 'dashboard_date_to';
  static const String _keyDashboardExcludeCallsWithoutCategory =
      'dashboard_exclude_calls_without_category';
  static const String _keyTaskAnalyticsDatePreset =
      'task_analytics_date_preset_v1';
  static const String _keyTaskAnalyticsDateFrom =
      'task_analytics_date_from_v1';
  static const String _keyTaskAnalyticsDateTo = 'task_analytics_date_to_v1';

  /// Τελευταία επιλογή εύρους ημερομηνιών στον πίνακα στατιστικών κλήσεων.
  /// Προεπιλογή: `today`.
  Future<String> getDashboardDatePreset() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(SettingsService._prefKey(_keyDashboardDatePreset)) ?? 'today';
  }

  Future<DateTime?> getDashboardCustomDateFrom() async {
    final prefs = await SharedPreferences.getInstance();
    return _parseStoredDate(prefs.getString(SettingsService._prefKey(_keyDashboardDateFrom)));
  }

  Future<DateTime?> getDashboardCustomDateTo() async {
    final prefs = await SharedPreferences.getInstance();
    return _parseStoredDate(prefs.getString(SettingsService._prefKey(_keyDashboardDateTo)));
  }

  Future<void> setDashboardDateFilter({
    required String preset,
    DateTime? customFrom,
    DateTime? customTo,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsService._prefKey(_keyDashboardDatePreset), preset);
    if (preset == 'custom' && customFrom != null && customTo != null) {
      await prefs.setString(
        SettingsService._prefKey(_keyDashboardDateFrom),
        _formatStoredDate(customFrom),
      );
      await prefs.setString(SettingsService._prefKey(_keyDashboardDateTo), _formatStoredDate(customTo));
    } else {
      await prefs.remove(SettingsService._prefKey(_keyDashboardDateFrom));
      await prefs.remove(SettingsService._prefKey(_keyDashboardDateTo));
    }
  }

  /// Απόκρυψη κλήσεων χωρίς κατηγορία στο γράφημα «Κατανομή Βλαβών». Προεπιλογή: false.
  Future<bool> getDashboardExcludeCallsWithoutCategory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(SettingsService._prefKey(_keyDashboardExcludeCallsWithoutCategory)) ??
        false;
  }

  Future<void> setDashboardExcludeCallsWithoutCategory(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      SettingsService._prefKey(_keyDashboardExcludeCallsWithoutCategory),
      value,
    );
  }

  /// Τελευταία επιλογή εύρους ημερομηνιών στις αναφορές εκκρεμοτήτων.
  /// Προεπιλογή: `all` (πλήρες εύρος δημιουργίας).
  Future<String> getTaskAnalyticsDatePreset() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(SettingsService._prefKey(_keyTaskAnalyticsDatePreset)) ?? 'all';
  }

  Future<DateTime?> getTaskAnalyticsCustomDateFrom() async {
    final prefs = await SharedPreferences.getInstance();
    return _parseStoredDate(prefs.getString(SettingsService._prefKey(_keyTaskAnalyticsDateFrom)));
  }

  Future<DateTime?> getTaskAnalyticsCustomDateTo() async {
    final prefs = await SharedPreferences.getInstance();
    return _parseStoredDate(prefs.getString(SettingsService._prefKey(_keyTaskAnalyticsDateTo)));
  }

  Future<void> setTaskAnalyticsDateFilter({
    required String preset,
    DateTime? customFrom,
    DateTime? customTo,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsService._prefKey(_keyTaskAnalyticsDatePreset), preset);
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
      await prefs.remove(SettingsService._prefKey(_keyTaskAnalyticsDateFrom));
      await prefs.remove(SettingsService._prefKey(_keyTaskAnalyticsDateTo));
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
}
