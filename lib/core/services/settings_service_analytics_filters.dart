import 'profile_settings.dart';
import 'scoped_settings.dart';

/// Φίλτρα ημερομηνιών για στατιστικά κλήσεων και εκκρεμοτήτων.
///
/// Συνεργάτης του `SettingsService` (Σύνθεση) — πρόσβαση μέσω
/// `SettingsService().analyticsFilters`.
class SettingsServiceAnalyticsFilters {
  const SettingsServiceAnalyticsFilters();

  /// Τελευταία επιλογή εύρους ημερομηνιών στον πίνακα στατιστικών κλήσεων.
  /// Προεπιλογή: `today`.
  Future<String> getDashboardDatePreset() async {
    return await ScopedSettings.getString(
          ProfileSettingKeys.dashboardDatePreset,
        ) ??
        'today';
  }

  Future<DateTime?> getDashboardCustomDateFrom() async {
    return _parseStoredDate(
      await ScopedSettings.getString(ProfileSettingKeys.dashboardDateFrom),
    );
  }

  Future<DateTime?> getDashboardCustomDateTo() async {
    return _parseStoredDate(
      await ScopedSettings.getString(ProfileSettingKeys.dashboardDateTo),
    );
  }

  Future<void> setDashboardDateFilter({
    required String preset,
    DateTime? customFrom,
    DateTime? customTo,
  }) async {
    await ScopedSettings.setString(
      ProfileSettingKeys.dashboardDatePreset,
      preset,
    );
    if (preset == 'custom' && customFrom != null && customTo != null) {
      await ScopedSettings.setString(
        ProfileSettingKeys.dashboardDateFrom,
        _formatStoredDate(customFrom),
      );
      await ScopedSettings.setString(
        ProfileSettingKeys.dashboardDateTo,
        _formatStoredDate(customTo),
      );
    } else {
      await ScopedSettings.remove(ProfileSettingKeys.dashboardDateFrom);
      await ScopedSettings.remove(ProfileSettingKeys.dashboardDateTo);
    }
  }

  /// Απόκρυψη κλήσεων χωρίς κατηγορία στο γράφημα «Κατανομή Βλαβών». Προεπιλογή: false.
  Future<bool> getDashboardExcludeCallsWithoutCategory() async {
    return await ScopedSettings.getBool(
          ProfileSettingKeys.dashboardExcludeCallsWithoutCategory,
        ) ??
        false;
  }

  Future<void> setDashboardExcludeCallsWithoutCategory(bool value) async {
    await ScopedSettings.setBool(
      ProfileSettingKeys.dashboardExcludeCallsWithoutCategory,
      value,
    );
  }

  /// Απόκρυψη του συγκεντρωτικού «Άγνωστου» στην όψη «χρόνος ανά άτομο».
  /// Προεπιλογή: false.
  Future<bool> getDashboardHideUnknownCaller() async {
    return await ScopedSettings.getBool(
          ProfileSettingKeys.dashboardHideUnknownCaller,
        ) ??
        false;
  }

  Future<void> setDashboardHideUnknownCaller(bool value) async {
    await ScopedSettings.setBool(
      ProfileSettingKeys.dashboardHideUnknownCaller,
      value,
    );
  }

  /// Απόκρυψη του συγκεντρωτικού «Άγνωστου» στην κατάταξη «Κορυφαίοι Καλούντες».
  /// Χωριστή από την όψη «χρόνος ανά άτομο»: οι δύο κάρτες απαντούν σε
  /// διαφορετικό ερώτημα και ο χρήστης μπορεί να θέλει τον «Άγνωστο» στη μία και
  /// όχι στην άλλη. Προεπιλογή: false.
  Future<bool> getDashboardHideUnknownTopCaller() async {
    return await ScopedSettings.getBool(
          ProfileSettingKeys.dashboardHideUnknownTopCaller,
        ) ??
        false;
  }

  Future<void> setDashboardHideUnknownTopCaller(bool value) async {
    await ScopedSettings.setBool(
      ProfileSettingKeys.dashboardHideUnknownTopCaller,
      value,
    );
  }

  /// Τελευταία επιλογή εύρους ημερομηνιών στις αναφορές εκκρεμοτήτων.
  /// Προεπιλογή: `all` (πλήρες εύρος δημιουργίας).
  Future<String> getTaskAnalyticsDatePreset() async {
    return await ScopedSettings.getString(
          ProfileSettingKeys.taskAnalyticsDatePreset,
        ) ??
        'all';
  }

  Future<DateTime?> getTaskAnalyticsCustomDateFrom() async {
    return _parseStoredDate(
      await ScopedSettings.getString(ProfileSettingKeys.taskAnalyticsDateFrom),
    );
  }

  Future<DateTime?> getTaskAnalyticsCustomDateTo() async {
    return _parseStoredDate(
      await ScopedSettings.getString(ProfileSettingKeys.taskAnalyticsDateTo),
    );
  }

  Future<void> setTaskAnalyticsDateFilter({
    required String preset,
    DateTime? customFrom,
    DateTime? customTo,
  }) async {
    await ScopedSettings.setString(
      ProfileSettingKeys.taskAnalyticsDatePreset,
      preset,
    );
    if (preset == 'custom' && customFrom != null && customTo != null) {
      await ScopedSettings.setString(
        ProfileSettingKeys.taskAnalyticsDateFrom,
        _formatStoredDate(customFrom),
      );
      await ScopedSettings.setString(
        ProfileSettingKeys.taskAnalyticsDateTo,
        _formatStoredDate(customTo),
      );
    } else {
      await ScopedSettings.remove(ProfileSettingKeys.taskAnalyticsDateFrom);
      await ScopedSettings.remove(ProfileSettingKeys.taskAnalyticsDateTo);
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
