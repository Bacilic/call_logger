part of 'settings_service.dart';

/// Ρυθμίσεις παραθύρου, πλοήγησης και ορατότητας UI.
mixin SettingsServiceWindowUiMixin {
  static const String _keyShowActiveTimer = 'show_active_timer';
  static const String _keyShowTasksBadge = 'show_tasks_badge';
  static const String _keyNavRailShowLabels = 'nav_rail_show_labels';
  static const String _keyWindowWidth = 'window_width_v1';
  static const String _keyWindowHeight = 'window_height_v1';
  static const String _keyWindowPositionX = 'window_position_x_v1';
  static const String _keyWindowPositionY = 'window_position_y_v1';
  static const String _keyWindowPlacementMode = 'window_placement_mode_v1';
  static const String _keyDatabaseBrowserStatsCardExpanded =
      'database_browser_stats_card_expanded';
  static const String _keyEquipmentLocationShowBuilding =
      'equipment_location_show_building';
  static const String _keyEnableSpellCheck = 'enable_spell_check';
  static const String _keyShowGlobalCallsDashboard =
      'show_global_calls_dashboard';
  static const String _keyShowDatabaseNav = 'show_database_nav';
  static const String _keyShowLampNav = 'show_lamp_nav';
  static const String _keyShowDictionaryNav = 'show_dictionary_nav';
  static const String _keyCallsScreenCardsVisibility =
      'calls_screen_cards_visibility_v1';
  static const String _keyShowQuickCallFab = 'show_quick_call_fab';

  /// Εμφάνιση ενεργού χρονομέτρου στη φόρμα κλήσεων. Προεπιλογή: true.
  Future<bool> getShowActiveTimer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(SettingsService._prefKey(_keyShowActiveTimer)) ?? true;
  }

  /// Ορίζει αν θα εμφανίζεται το ενεργό χρονόμετρο (MM:SS) στη φόρμα κλήσεων.
  Future<void> setShowActiveTimer(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsService._prefKey(_keyShowActiveTimer), value);
  }

  /// Εμφάνιση μετρητή (badge) εκκρεμοτήτων στο κεντρικό μενού. Προεπιλογή: true.
  Future<bool> getShowTasksBadge() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(SettingsService._prefKey(_keyShowTasksBadge)) ?? true;
  }

  Future<void> setShowTasksBadge(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsService._prefKey(_keyShowTasksBadge), value);
  }

  /// Εμφάνιση λεζαντών στην πλευρική μπάρα (NavigationRail extended) όταν το πλάτος επιτρέπει.
  /// Προεπιλογή: true.
  Future<bool> getNavRailShowLabels() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(SettingsService._prefKey(_keyNavRailShowLabels)) ?? true;
  }

  Future<void> setNavRailShowLabels(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsService._prefKey(_keyNavRailShowLabels), value);
  }

  /// Τελευταίο πλάτος/ύψος κύριου παραθύρου (Windows desktop)· null αν δεν έχει αποθηκευτεί.
  Future<({double width, double height})?> getSavedWindowSize() async {
    final prefs = await SharedPreferences.getInstance();
    final width = prefs.getDouble(SettingsService._prefKey(_keyWindowWidth));
    final height = prefs.getDouble(SettingsService._prefKey(_keyWindowHeight));
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
    await prefs.setDouble(SettingsService._prefKey(_keyWindowWidth), width);
    await prefs.setDouble(SettingsService._prefKey(_keyWindowHeight), height);
  }

  /// Τελευταία θέση κύριου παραθύρου (πάνω-αριστερή γωνία)· null αν δεν έχει αποθηκευτεί.
  Future<({double x, double y})?> getSavedWindowPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble(SettingsService._prefKey(_keyWindowPositionX));
    final y = prefs.getDouble(SettingsService._prefKey(_keyWindowPositionY));
    if (x == null ||
        y == null ||
        !x.isFinite ||
        !y.isFinite) {
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
    await prefs.setDouble(SettingsService._prefKey(_keyWindowPositionX), x);
    await prefs.setDouble(SettingsService._prefKey(_keyWindowPositionY), y);
  }

  /// Πού εμφανίζεται το παράθυρο στην επόμενη εκκίνηση. Προεπιλογή: κέντρο οθόνης.
  Future<WindowPlacementMode> getWindowPlacementMode() async {
    final prefs = await SharedPreferences.getInstance();
    return WindowPlacementModeStorage.fromStorage(
          prefs.getString(SettingsService._prefKey(_keyWindowPlacementMode)),
        ) ??
        WindowPlacementMode.alwaysCenter;
  }

  Future<void> setWindowPlacementMode(WindowPlacementMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsService._prefKey(_keyWindowPlacementMode), mode.storageValue);
  }

  /// Κάρτα «Στατιστικά Βάσης Δεδομένων» στην οθόνη περιήγησης βάσης — ανοιχτή/κλειστή.
  /// Προεπιλογή: false (συμπτυγμένη).
  Future<bool> getDatabaseBrowserStatsCardExpanded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(SettingsService._prefKey(_keyDatabaseBrowserStatsCardExpanded)) ?? false;
  }

  Future<void> setDatabaseBrowserStatsCardExpanded(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsService._prefKey(_keyDatabaseBrowserStatsCardExpanded), value);
  }

  /// Εμφάνιση κωδικού κτιρίου `[...]` στη στήλη Τοποθεσία (πίνακας εξοπλισμού). Προεπιλογή: true.
  Future<bool> getEquipmentLocationShowBuilding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(SettingsService._prefKey(_keyEquipmentLocationShowBuilding)) ?? true;
  }

  Future<void> setEquipmentLocationShowBuilding(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsService._prefKey(_keyEquipmentLocationShowBuilding), value);
  }

  /// Ενεργοποίηση ενσωματωμένου ορθογραφικού ελέγχου σημειώσεων (Windows). Προεπιλογή: true.
  Future<bool> getEnableSpellCheck() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(SettingsService._prefKey(_keyEnableSpellCheck)) ?? true;
  }

  Future<void> setEnableSpellCheck(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsService._prefKey(_keyEnableSpellCheck), value);
  }

  /// Εμφάνιση κάρτας «Τελευταίες 7 Κλήσεις» στην οθόνη κλήσεων. Προεπιλογή: true.
  Future<bool> getShowGlobalCalls() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(SettingsService._prefKey(_keyShowGlobalCallsDashboard)) ?? true;
  }

  Future<void> setShowGlobalCalls(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsService._prefKey(_keyShowGlobalCallsDashboard), value);
  }

  /// Εμφάνιση στοιχείου πλοήγησης «Βάση Δεδομένων». Προεπιλογή: true.
  Future<bool> getShowDatabaseNav() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(SettingsService._prefKey(_keyShowDatabaseNav)) ?? true;
  }

  Future<void> setShowDatabaseNav(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsService._prefKey(_keyShowDatabaseNav), value);
  }

  /// Εμφάνιση στοιχείου πλοήγησης «Λάμπα» (παλιά βάση). Προεπιλογή: true.
  Future<bool> getShowLampNav() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(SettingsService._prefKey(_keyShowLampNav)) ?? true;
  }

  Future<void> setShowLampNav(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsService._prefKey(_keyShowLampNav), value);
  }

  /// Εμφάνιση στοιχείου πλοήγησης «Λεξικό». Προεπιλογή: true.
  Future<bool> getShowDictionaryNav() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(SettingsService._prefKey(_keyShowDictionaryNav)) ?? true;
  }

  Future<void> setShowDictionaryNav(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsService._prefKey(_keyShowDictionaryNav), value);
  }

  /// Ποια κάρτες εμφανίζονται στην οθόνη κλήσεων. Προεπιλογή: όλες ορατές.
  Future<CallsScreenCardsVisibility> getCallsScreenCardsVisibility() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(SettingsService._prefKey(_keyCallsScreenCardsVisibility));
    return CallsScreenCardsVisibility.fromJsonString(raw);
  }

  Future<void> setCallsScreenCardsVisibility(
    CallsScreenCardsVisibility value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsService._prefKey(_keyCallsScreenCardsVisibility), value.toJsonString());
  }

  /// Εμφάνιση ιπτάμενου κουμπιού γρήγορης καταγραφής κλήσης. Προεπιλογή: true.
  Future<bool> getShowQuickCallFab() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(SettingsService._prefKey(_keyShowQuickCallFab)) ?? true;
  }

  Future<void> setShowQuickCallFab(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsService._prefKey(_keyShowQuickCallFab), value);
  }
}
