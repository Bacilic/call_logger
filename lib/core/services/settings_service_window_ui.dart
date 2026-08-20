import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/calls_screen_cards_visibility.dart';
import '../models/window_placement_mode.dart';
import 'profile_settings.dart';
import 'scoped_settings.dart';

/// Ρυθμίσεις παραθύρου, πλοήγησης και ορατότητας UI.
///
/// Συνεργάτης του `SettingsService` (Σύνθεση) — πρόσβαση μέσω
/// `SettingsService().windowUi`.
///
/// **Οι προτιμήσεις εμφάνισης είναι προσωπικές** (Φάση 2): περνούν από το
/// [ScopedSettings] και ακολουθούν τον χρήστη σε όποιον υπολογιστή καθίσει.
/// **Το μέγεθος και η θέση του παραθύρου ΟΧΙ** — εξαρτώνται από την οθόνη του
/// συγκεκριμένου μηχανήματος, γι' αυτό μένουν στις τοπικές ρυθμίσεις.
class SettingsServiceWindowUi {
  const SettingsServiceWindowUi();

  static const String _keyWindowWidth = 'window_width_v1';
  static const String _keyWindowHeight = 'window_height_v1';
  static const String _keyWindowPositionX = 'window_position_x_v1';
  static const String _keyWindowPositionY = 'window_position_y_v1';
  static const String _keyWindowPlacementMode = 'window_placement_mode_v1';

  /// Κλειδί αποθήκευσης SharedPreferences (με πρόθεμα προφίλ όταν υπάρχει CLI `--profile`).
  static String _prefKey(String baseKey) =>
      AppConfig.prefixedPreferencesKey(baseKey);

  /// Εμφάνιση ενεργού χρονομέτρου στη φόρμα κλήσεων. Προεπιλογή: true.
  Future<bool> getShowActiveTimer() async {
    return await ScopedSettings.getBool(ProfileSettingKeys.showActiveTimer) ??
        true;
  }

  /// Ορίζει αν θα εμφανίζεται το ενεργό χρονόμετρο (MM:SS) στη φόρμα κλήσεων.
  Future<void> setShowActiveTimer(bool value) async {
    await ScopedSettings.setBool(ProfileSettingKeys.showActiveTimer, value);
  }

  /// Εμφάνιση μετρητή (badge) εκκρεμοτήτων στο κεντρικό μενού. Προεπιλογή: true.
  Future<bool> getShowTasksBadge() async {
    return await ScopedSettings.getBool(ProfileSettingKeys.showTasksBadge) ??
        true;
  }

  Future<void> setShowTasksBadge(bool value) async {
    await ScopedSettings.setBool(ProfileSettingKeys.showTasksBadge, value);
  }

  /// Εμφάνιση λεζαντών στην πλευρική μπάρα (NavigationRail extended) όταν το πλάτος επιτρέπει.
  /// Προεπιλογή: true.
  Future<bool> getNavRailShowLabels() async {
    return await ScopedSettings.getBool(ProfileSettingKeys.navRailShowLabels) ??
        true;
  }

  Future<void> setNavRailShowLabels(bool value) async {
    await ScopedSettings.setBool(ProfileSettingKeys.navRailShowLabels, value);
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
    if (x == null || y == null || !x.isFinite || !y.isFinite) {
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
    return await ScopedSettings.getBool(
          ProfileSettingKeys.databaseBrowserStatsCardExpanded,
        ) ??
        false;
  }

  Future<void> setDatabaseBrowserStatsCardExpanded(bool value) async {
    await ScopedSettings.setBool(
      ProfileSettingKeys.databaseBrowserStatsCardExpanded,
      value,
    );
  }

  /// Εμφάνιση κωδικού κτιρίου `[...]` στη στήλη Τοποθεσία (πίνακας εξοπλισμού). Προεπιλογή: true.
  Future<bool> getEquipmentLocationShowBuilding() async {
    return await ScopedSettings.getBool(
          ProfileSettingKeys.equipmentLocationShowBuilding,
        ) ??
        true;
  }

  Future<void> setEquipmentLocationShowBuilding(bool value) async {
    await ScopedSettings.setBool(
      ProfileSettingKeys.equipmentLocationShowBuilding,
      value,
    );
  }

  /// Ενεργοποίηση ενσωματωμένου ορθογραφικού ελέγχου σημειώσεων (Windows). Προεπιλογή: true.
  Future<bool> getEnableSpellCheck() async {
    return await ScopedSettings.getBool(ProfileSettingKeys.enableSpellCheck) ??
        true;
  }

  Future<void> setEnableSpellCheck(bool value) async {
    await ScopedSettings.setBool(ProfileSettingKeys.enableSpellCheck, value);
  }

  /// Εμφάνιση κάρτας «Τελευταίες 7 Κλήσεις» στην οθόνη κλήσεων. Προεπιλογή: true.
  Future<bool> getShowGlobalCalls() async {
    return await ScopedSettings.getBool(
          ProfileSettingKeys.showGlobalCallsDashboard,
        ) ??
        true;
  }

  Future<void> setShowGlobalCalls(bool value) async {
    await ScopedSettings.setBool(
      ProfileSettingKeys.showGlobalCallsDashboard,
      value,
    );
  }

  /// Εμφάνιση στοιχείου πλοήγησης «Βάση Δεδομένων». Προεπιλογή: true.
  Future<bool> getShowDatabaseNav() async {
    return await ScopedSettings.getBool(ProfileSettingKeys.showDatabaseNav) ??
        true;
  }

  Future<void> setShowDatabaseNav(bool value) async {
    await ScopedSettings.setBool(ProfileSettingKeys.showDatabaseNav, value);
  }

  /// Εμφάνιση στοιχείου πλοήγησης «Λάμπα» (παλιά βάση). Προεπιλογή: true.
  Future<bool> getShowLampNav() async {
    return await ScopedSettings.getBool(ProfileSettingKeys.showLampNav) ?? true;
  }

  Future<void> setShowLampNav(bool value) async {
    await ScopedSettings.setBool(ProfileSettingKeys.showLampNav, value);
  }

  /// Εμφάνιση στοιχείου πλοήγησης «Λεξικό». Προεπιλογή: true.
  Future<bool> getShowDictionaryNav() async {
    return await ScopedSettings.getBool(ProfileSettingKeys.showDictionaryNav) ??
        true;
  }

  Future<void> setShowDictionaryNav(bool value) async {
    await ScopedSettings.setBool(ProfileSettingKeys.showDictionaryNav, value);
  }

  /// Ποια κάρτες εμφανίζονται στην οθόνη κλήσεων. Προεπιλογή: όλες ορατές.
  Future<CallsScreenCardsVisibility> getCallsScreenCardsVisibility() async {
    final raw = await ScopedSettings.getString(
      ProfileSettingKeys.callsScreenCardsVisibility,
    );
    return CallsScreenCardsVisibility.fromJsonString(raw);
  }

  Future<void> setCallsScreenCardsVisibility(
    CallsScreenCardsVisibility value,
  ) async {
    await ScopedSettings.setString(
      ProfileSettingKeys.callsScreenCardsVisibility,
      value.toJsonString(),
    );
  }

  /// Εμφάνιση ιπτάμενου κουμπιού γρήγορης καταγραφής κλήσης. Προεπιλογή: true.
  Future<bool> getShowQuickCallFab() async {
    return await ScopedSettings.getBool(ProfileSettingKeys.showQuickCallFab) ??
        true;
  }

  Future<void> setShowQuickCallFab(bool value) async {
    await ScopedSettings.setBool(ProfileSettingKeys.showQuickCallFab, value);
  }
}
