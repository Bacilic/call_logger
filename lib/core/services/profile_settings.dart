import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../config/app_config.dart';
import '../database/operator_settings_repository.dart';
import '../database/settings_repository.dart';
import '../models/operator.dart';
import 'current_operator.dart';
import 'settings_service.dart';

/// Από πού κληρονομεί ένα προσωπικό κλειδί την πρώτη του τιμή — η μετάβαση
/// από τον παλιό κόσμο (κοινά ή ανά μηχάνημα) στον νέο (ανά χρήστη).
enum ProfileSettingLegacySource {
  /// Χωρίς κληρονομιά: ξεκινά από τις προεπιλογές του καλούντα.
  none,

  /// Η παλιά τιμή ζούσε στα ΚΟΙΝΑ (`app_settings`). Την κληρονομεί **μόνο ο
  /// διαχειριστής** — αυτός την όρισε· οι υπόλοιποι ξεκινούν καθαροί.
  sharedForAdmin,

  /// Η παλιά τιμή ζούσε στον ΥΠΟΛΟΓΙΣΤΗ. Την κληρονομεί όποιος καθίσει εκεί
  /// πρώτη φορά χωρίς δική του τιμή — κανείς δεν χάνει τη σημερινή του
  /// εμπειρία, και από εκεί και πέρα η ρύθμιση τον ακολουθεί.
  machine,
}

/// Δήλωση προσωπικού κλειδιού: το όνομά του και η πηγή κληρονομιάς του.
class ProfileSettingKey {
  const ProfileSettingKey(
    this.key, {
    this.legacySource = ProfileSettingLegacySource.none,
  });

  final String key;
  final ProfileSettingLegacySource legacySource;
}

/// **Η μία θέση** όπου δηλώνεται ποια κλειδιά είναι προσωπικά (εμβέλεια
/// ΠΡΟΦΙΛ). Δύο σημεία που απαντούν στο ίδιο ερώτημα κάποια μέρα θα
/// διαφωνήσουν σιωπηλά — γι' αυτό ο κατάλογος ζει μόνο εδώ.
///
/// Η μετακόμιση της Φάσης 2 γίνεται τμηματικά: κάθε κλειδί που γίνεται
/// προσωπικό προστίθεται εδώ και οι αναγνώστες/εγγραφείς του περνούν από το
/// [ProfileSettings]. Ό,τι δεν είναι εδώ, ζει ακόμη στην παλιά του θέση.
abstract final class ProfileSettingKeys {
  /// Το «δέμα» των αντιγράφων ασφαλείας: πρόγραμμα, φάκελος, διατήρηση,
  /// ιστορικό, τελευταία κατάσταση — ενιαίο JSON, όπως ήταν και στα κοινά.
  static const ProfileSettingKey databaseBackupSettings = ProfileSettingKey(
    'database_backup_settings_v1',
    legacySource: ProfileSettingLegacySource.sharedForAdmin,
  );

  // ── Προτιμήσεις εμφάνισης ────────────────────────────────────────────────
  // Σήμερα ζουν στον υπολογιστή: όποιος πρωτοκαθίσει κληρονομεί ό,τι ίσχυε
  // εκεί, και από εκεί και πέρα οι προτιμήσεις τον ακολουθούν.
  // ΔΕΝ περιλαμβάνονται το μέγεθος και η θέση του παραθύρου: εξαρτώνται από
  // την οθόνη του συγκεκριμένου μηχανήματος.

  static const ProfileSettingKey showActiveTimer = ProfileSettingKey(
    'show_active_timer',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey showTasksBadge = ProfileSettingKey(
    'show_tasks_badge',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey navRailShowLabels = ProfileSettingKey(
    'nav_rail_show_labels',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey showGlobalCallsDashboard = ProfileSettingKey(
    'show_global_calls_dashboard',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey showDatabaseNav = ProfileSettingKey(
    'show_database_nav',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey showLampNav = ProfileSettingKey(
    'show_lamp_nav',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey showDictionaryNav = ProfileSettingKey(
    'show_dictionary_nav',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey showQuickCallFab = ProfileSettingKey(
    'show_quick_call_fab',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey callsScreenCardsVisibility = ProfileSettingKey(
    'calls_screen_cards_visibility_v1',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey databaseBrowserStatsCardExpanded =
      ProfileSettingKey(
        'database_browser_stats_card_expanded',
        legacySource: ProfileSettingLegacySource.machine,
      );
  static const ProfileSettingKey equipmentLocationShowBuilding =
      ProfileSettingKey(
        'equipment_location_show_building',
        legacySource: ProfileSettingLegacySource.machine,
      );
  static const ProfileSettingKey enableSpellCheck = ProfileSettingKey(
    'enable_spell_check',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey showUpdateOnStartup = ProfileSettingKey(
    'show_update_on_startup',
    legacySource: ProfileSettingLegacySource.machine,
  );

  // ── Φίλτρα στατιστικών ───────────────────────────────────────────────────

  static const ProfileSettingKey dashboardDatePreset = ProfileSettingKey(
    'dashboard_date_preset',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey dashboardDateFrom = ProfileSettingKey(
    'dashboard_date_from',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey dashboardDateTo = ProfileSettingKey(
    'dashboard_date_to',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey dashboardExcludeCallsWithoutCategory =
      ProfileSettingKey(
        'dashboard_exclude_calls_without_category',
        legacySource: ProfileSettingLegacySource.machine,
      );
  static const ProfileSettingKey dashboardHideUnknownCaller = ProfileSettingKey(
    'dashboard_hide_unknown_caller',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey dashboardHideUnknownTopCaller =
      ProfileSettingKey(
        'dashboard_hide_unknown_top_caller',
        legacySource: ProfileSettingLegacySource.machine,
      );
  static const ProfileSettingKey taskAnalyticsDatePreset = ProfileSettingKey(
    'task_analytics_date_preset_v1',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey taskAnalyticsDateFrom = ProfileSettingKey(
    'task_analytics_date_from_v1',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey taskAnalyticsDateTo = ProfileSettingKey(
    'task_analytics_date_to_v1',
    legacySource: ProfileSettingLegacySource.machine,
  );

  // ── Εργαλεία απομακρυσμένης στις Κλήσεις ─────────────────────────────────
  // Σήμερα κοινά: τα κληρονομεί ο διαχειριστής (αυτός τα όρισε).

  static const ProfileSettingKey callsPrimaryToolId = ProfileSettingKey(
    'calls_primary_tool_id',
    legacySource: ProfileSettingLegacySource.sharedForAdmin,
  );
  static const ProfileSettingKey callsShowSecondaryRemoteActions =
      ProfileSettingKey(
        'calls_show_secondary_remote_actions',
        legacySource: ProfileSettingLegacySource.sharedForAdmin,
      );
  static const ProfileSettingKey callsShowEmptyRemoteLaunchers =
      ProfileSettingKey(
        'calls_show_empty_remote_launchers',
        legacySource: ProfileSettingLegacySource.sharedForAdmin,
      );
  static const ProfileSettingKey remoteToolPrioritySwapMode = ProfileSettingKey(
    'remote_tool_priority_swap_mode',
    legacySource: ProfileSettingLegacySource.machine,
  );

  // ── Lansweeper: προσωπική ταυτότητα και προτιμήσεις ──────────────────────

  /// **Καθορίζει σε ποιον χρεώνεται το αίτημα** — κοινό σημαίνει λάθος χρέωση.
  static const ProfileSettingKey lansweeperAgentUsername = ProfileSettingKey(
    'lansweeper_agent_username',
    legacySource: ProfileSettingLegacySource.sharedForAdmin,
  );
  static const ProfileSettingKey lansweeperReportRange = ProfileSettingKey(
    'lansweeper_report_range',
    legacySource: ProfileSettingLegacySource.sharedForAdmin,
  );
  static const ProfileSettingKey lansweeperTicketSubmitFormPrefs =
      ProfileSettingKey(
        'lansweeper_ticket_submit_form_prefs',
        legacySource: ProfileSettingLegacySource.sharedForAdmin,
      );

  // ── Τεχνητή νοημοσύνη: το πρότυπο προτροπής είναι προσωπικό ──────────────

  static const ProfileSettingKey geminiPromptTemplate = ProfileSettingKey(
    'gemini_prompt_template',
    legacySource: ProfileSettingLegacySource.sharedForAdmin,
  );
  static const ProfileSettingKey geminiPromptTemplateUserDefault =
      ProfileSettingKey(
        'gemini_prompt_template_user_default',
        legacySource: ProfileSettingLegacySource.sharedForAdmin,
      );
  static const ProfileSettingKey geminiAutoResubmit = ProfileSettingKey(
    'gemini_auto_resubmit',
    legacySource: ProfileSettingLegacySource.sharedForAdmin,
  );

  // ── Κατάλογοι: στήλες, διατάξεις, κύλιση ─────────────────────────────────

  static const ProfileSettingKey catalogUsersVisibleColumns = ProfileSettingKey(
    'catalog_users_visible_columns',
    legacySource: ProfileSettingLegacySource.sharedForAdmin,
  );
  static const ProfileSettingKey catalogDepartmentsVisibleColumns =
      ProfileSettingKey(
        'catalog_departments_visible_columns',
        legacySource: ProfileSettingLegacySource.sharedForAdmin,
      );
  static const ProfileSettingKey catalogEquipmentColumns = ProfileSettingKey(
    'catalog_equipment_columns',
    legacySource: ProfileSettingLegacySource.sharedForAdmin,
  );
  static const ProfileSettingKey catalogCategoriesVisibleColumns =
      ProfileSettingKey(
        'catalog_categories_visible_columns',
        legacySource: ProfileSettingLegacySource.sharedForAdmin,
      );
  static const ProfileSettingKey catalogContinuousScroll = ProfileSettingKey(
    'catalog_continuous_scroll',
    legacySource: ProfileSettingLegacySource.sharedForAdmin,
  );
  static const ProfileSettingKey catalogContinuousScrollUsers =
      ProfileSettingKey(
        'catalog_continuous_scroll_users',
        legacySource: ProfileSettingLegacySource.sharedForAdmin,
      );
  static const ProfileSettingKey catalogContinuousScrollDepartments =
      ProfileSettingKey(
        'catalog_continuous_scroll_departments',
        legacySource: ProfileSettingLegacySource.sharedForAdmin,
      );
  static const ProfileSettingKey catalogContinuousScrollEquipment =
      ProfileSettingKey(
        'catalog_continuous_scroll_equipment',
        legacySource: ProfileSettingLegacySource.sharedForAdmin,
      );
  static const ProfileSettingKey lexiconContinuousScroll = ProfileSettingKey(
    'lexicon_continuous_scroll',
    legacySource: ProfileSettingLegacySource.sharedForAdmin,
  );
  static const ProfileSettingKey lexiconPageSize = ProfileSettingKey(
    'lexicon_page_size',
    legacySource: ProfileSettingLegacySource.sharedForAdmin,
  );
  static const ProfileSettingKey lexiconListFilters = ProfileSettingKey(
    'lexicon_list_filters',
    legacySource: ProfileSettingLegacySource.sharedForAdmin,
  );
  static const ProfileSettingKey databaseBrowserPreviewZoomByTable =
      ProfileSettingKey(
        'database_browser_preview_zoom_by_table',
        legacySource: ProfileSettingLegacySource.sharedForAdmin,
      );

  // ── Λάμπα & Εκκρεμότητες ─────────────────────────────────────────────────

  static const ProfileSettingKey lampTablesLeftPaneWidth = ProfileSettingKey(
    'lamp_tables_left_pane_width_px',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey lampMaxSearchResults = ProfileSettingKey(
    'lamp_max_search_results',
    legacySource: ProfileSettingLegacySource.machine,
  );
  static const ProfileSettingKey taskSettingsConfig = ProfileSettingKey(
    'task_settings_config',
    legacySource: ProfileSettingLegacySource.sharedForAdmin,
  );

  static const List<ProfileSettingKey> all = [
    databaseBackupSettings,
    showActiveTimer,
    showTasksBadge,
    navRailShowLabels,
    showGlobalCallsDashboard,
    showDatabaseNav,
    showLampNav,
    showDictionaryNav,
    showQuickCallFab,
    callsScreenCardsVisibility,
    databaseBrowserStatsCardExpanded,
    equipmentLocationShowBuilding,
    enableSpellCheck,
    showUpdateOnStartup,
    dashboardDatePreset,
    dashboardDateFrom,
    dashboardDateTo,
    dashboardExcludeCallsWithoutCategory,
    dashboardHideUnknownCaller,
    dashboardHideUnknownTopCaller,
    taskAnalyticsDatePreset,
    taskAnalyticsDateFrom,
    taskAnalyticsDateTo,
    callsPrimaryToolId,
    callsShowSecondaryRemoteActions,
    callsShowEmptyRemoteLaunchers,
    remoteToolPrioritySwapMode,
    lansweeperAgentUsername,
    lansweeperReportRange,
    lansweeperTicketSubmitFormPrefs,
    geminiPromptTemplate,
    geminiPromptTemplateUserDefault,
    geminiAutoResubmit,
    catalogUsersVisibleColumns,
    catalogDepartmentsVisibleColumns,
    catalogEquipmentColumns,
    catalogCategoriesVisibleColumns,
    catalogContinuousScroll,
    catalogContinuousScrollUsers,
    catalogContinuousScrollDepartments,
    catalogContinuousScrollEquipment,
    lexiconContinuousScroll,
    lexiconPageSize,
    lexiconListFilters,
    databaseBrowserPreviewZoomByTable,
    lampTablesLeftPaneWidth,
    lampMaxSearchResults,
    taskSettingsConfig,
  ];
}

/// Η πύλη των προσωπικών ρυθμίσεων — διαβάζει και γράφει **για τον ενεργό
/// χρήστη**.
///
/// Κανόνες, με τη σειρά:
/// 1. **Χωρίς συνδεδεμένο χρήστη, όλα δουλεύουν όπως χθες**: ανάγνωση και
///    εγγραφή πάνε στην παλιά θέση του κλειδιού (κοινά ή τοπικά). Έτσι οι
///    έλεγχοι και κάθε ροή χωρίς προφίλ δεν αλλάζουν συμπεριφορά.
/// 2. Με χρήστη: διαβάζεται η δική του τιμή από τον πίνακα
///    `operator_settings`.
/// 3. Πρώτη ανάγνωση χωρίς δική του τιμή → **κληρονομιά μίας φοράς** από την
///    παλιά θέση, κατά τη δήλωση του κλειδιού ([ProfileSettingLegacySource]).
///    Η παλιά τιμή ΔΕΝ σβήνεται: παλαιότερες εκδόσεις της εφαρμογής τη
///    διαβάζουν ακόμη.
class ProfileSettings {
  ProfileSettings(this.db, {Operator? operator, ProfileSettingKey? setting})
    : operator = operator ?? CurrentOperator.active,
      // Το [setting] δεν χρησιμοποιείται εδώ· υπάρχει ώστε ο καλών να δηλώνει
      // ρητά για ποιο κλειδί φτιάχτηκε η πύλη — βοηθά τη διάγνωση και κρατά
      // την κλήση αυτοτελή.
      declaredSetting = setting;

  final Database db;

  /// Το κλειδί για το οποίο φτιάχτηκε αυτή η πύλη, όταν δηλώθηκε.
  final ProfileSettingKey? declaredSetting;

  /// Ο χρήστης της στιγμής που φτιάχτηκε η πύλη — οι καλούντες δημιουργούν
  /// φρέσκο αντίτυπο ανά λειτουργία, όπως με τα repositories.
  final Operator? operator;

  /// Η τιμή του [setting] για τον ενεργό χρήστη· `null` σημαίνει «καμία τιμή
  /// πουθενά — χρησιμοποίησε τις προεπιλογές σου».
  Future<String?> read(ProfileSettingKey setting) async {
    final op = operator;
    if (op?.id == null) {
      return _readLegacy(setting);
    }

    final own = await OperatorSettingsRepository(
      db,
    ).getValue(op!.id!, setting.key);
    if (own != null) return own;

    return _seedFromLegacy(op, setting);
  }

  /// Γράφει την τιμή του [setting] για τον ενεργό χρήστη — ή, χωρίς χρήστη,
  /// στην παλιά θέση του κλειδιού (κανόνας 1).
  Future<void> write(ProfileSettingKey setting, String value) async {
    final op = operator;
    if (op?.id == null) {
      await _writeLegacy(setting, value);
      return;
    }
    await OperatorSettingsRepository(db).setValue(op!.id!, setting.key, value);
  }

  /// Σβήνει τη δική του τιμή — «δεν έχω δική μου», όχι «έχω κενή».
  Future<void> clear(ProfileSettingKey setting) async {
    final op = operator;
    if (op?.id == null) return;
    await OperatorSettingsRepository(db).deleteValue(op!.id!, setting.key);
  }

  /// Κληρονομιά πρώτης φοράς: αντιγράφει την παλιά τιμή στο προφίλ ώστε από
  /// εδώ και πέρα να ταξιδεύει με τον χρήστη.
  Future<String?> _seedFromLegacy(
    Operator op,
    ProfileSettingKey setting,
  ) async {
    final legacy = switch (setting.legacySource) {
      ProfileSettingLegacySource.none => null,
      ProfileSettingLegacySource.sharedForAdmin =>
        op.isAdmin ? await _readShared(setting.key) : null,
      ProfileSettingLegacySource.machine => await _readMachine(setting.key),
    };
    if (legacy == null) return null;

    await OperatorSettingsRepository(db).setValue(op.id!, setting.key, legacy);
    return legacy;
  }

  Future<String?> _readLegacy(ProfileSettingKey setting) =>
      switch (setting.legacySource) {
        ProfileSettingLegacySource.none => Future<String?>.value(),
        ProfileSettingLegacySource.sharedForAdmin => _readShared(setting.key),
        ProfileSettingLegacySource.machine => _readMachine(setting.key),
      };

  Future<void> _writeLegacy(ProfileSettingKey setting, String value) async {
    switch (setting.legacySource) {
      case ProfileSettingLegacySource.none:
        return;
      case ProfileSettingLegacySource.sharedForAdmin:
        final writer = SettingsService.appSettingWriter;
        if (writer != null) {
          await writer(setting.key, value);
        } else {
          await SettingsRepository(db).saveSetting(setting.key, value);
        }
      case ProfileSettingLegacySource.machine:
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          AppConfig.prefixedPreferencesKey(setting.key),
          value,
        );
    }
  }

  /// Η κοινή τιμή διαβάζεται από τον **καθιερωμένο πάροχο** όταν υπάρχει —
  /// το ίδιο σημείο που χρησιμοποιούν οι συνεργάτες του [SettingsService] και
  /// το μόνο που αντικαθίσταται σε ελέγχους. Χωρίς πάροχο, απευθείας από τη
  /// βάση που ήδη κρατά αυτή η πύλη.
  Future<String?> _readShared(String key) {
    final reader = SettingsService.appSettingReader;
    if (reader != null) return reader(key);
    return SettingsRepository(db).getSetting(key);
  }

  /// Οι τοπικές τιμές είναι αποθηκευμένες **τυπωμένες** (λογικές, ακέραιες,
  /// δεκαδικές, κείμενο). Η ανάγνωση γίνεται γενικά και μετατρέπεται σε
  /// κείμενο: ένα `getString` πάνω σε αποθηκευμένη λογική τιμή θα έσκαγε.
  Future<String?> _readMachine(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.get(AppConfig.prefixedPreferencesKey(key))?.toString();
  }
}
