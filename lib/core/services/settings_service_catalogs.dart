import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'shared_settings.dart';
import '../config/audit_retention_config.dart';
import '../../features/database/debug/publish_cli.dart';
import 'settings_list_conflict.dart';
import 'settings_service.dart';

/// Κατάλογοι, λεξικό, audit retention και timeout ανοίγματος βάσης.
///
/// Συνεργάτης του `SettingsService` (Σύνθεση) — πρόσβαση μέσω
/// `SettingsService().catalogs`. Οι ρυθμίσεις app_settings διαβάζονται
/// μέσω του καταχωρημένου παρόχου του [SettingsService] (μετά το άνοιγμα βάσης).
class SettingsServiceCatalogs {
  const SettingsServiceCatalogs();

  static const String _keyDatabaseOpenTimeoutSeconds =
      'database_open_timeout_seconds';
  static const String _keyDatabaseOpenMaxAttempts =
      'database_open_max_attempts';
  static const String _keyDictionarySourcePath = 'dictionary_source_path';
  static const String _keyDictionaryExportPath = 'dictionary_export_path';
  static const String _keyEquipmentTypes = 'equipment_types';
  static const String _keyLexiconCategories = 'lexicon_categories';
  static const String _keyCrashLogRetentionCount =
      'crash_log_retention_count_v1';
  static const String _keyCatalogValidationRules =
      'catalog_validation_rules_v1';
  static const String _keyPublishCliCommandTemplate =
      'publish_cli_command_template';
  static const String _keyShowUpdateOnStartup = 'show_update_on_startup';

  static const int defaultCrashLogRetentionCount = 14;
  static const int minCrashLogRetentionCount = 3;
  static const int maxCrashLogRetentionCount = 90;

  /// Προεπιλεγμένες κατηγορίες λεξικού (CSV για ρυθμίσεις / dropdown).
  static const String defaultLexiconCategoriesCsv =
      'Γενική, Τεχνικός Όρος, Όνομα';

  static List<String> get defaultLexiconCategoriesList {
    return defaultLexiconCategoriesCsv
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Κλειδί αποθήκευσης SharedPreferences (με πρόθεμα προφίλ όταν υπάρχει CLI `--profile`).
  static String _prefKey(String baseKey) =>
      AppConfig.prefixedPreferencesKey(baseKey);

  static Future<String?> Function(String key)? get _getAppSetting =>
      SettingsService.appSettingReader;

  /// Timeout ανοίγματος βάσης σε δευτερόλεπτα. Προεπιλογή: [AppConfig.databaseOpenTimeoutSeconds].
  Future<int> getDatabaseOpenTimeoutSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_prefKey(_keyDatabaseOpenTimeoutSeconds));
    if (value == null || value <= 0) {
      return AppConfig.databaseOpenTimeoutSeconds;
    }
    return value;
  }

  Future<void> setDatabaseOpenTimeoutSeconds(int value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value <= 0
        ? AppConfig.databaseOpenTimeoutSeconds
        : value;
    await prefs.setInt(_prefKey(_keyDatabaseOpenTimeoutSeconds), normalized);
  }

  /// Μέγιστες προσπάθειες ανοίγματος βάσης. Προεπιλογή: [AppConfig.databaseOpenMaxAttempts].
  Future<int> getDatabaseOpenMaxAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_prefKey(_keyDatabaseOpenMaxAttempts));
    if (value == null || value <= 0) {
      return AppConfig.databaseOpenMaxAttempts;
    }
    return value.clamp(1, 5);
  }

  Future<void> setDatabaseOpenMaxAttempts(int value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value <= 0
        ? AppConfig.databaseOpenMaxAttempts
        : value.clamp(1, 5);
    await prefs.setInt(_prefKey(_keyDatabaseOpenMaxAttempts), normalized);
  }

  /// Διαδρομή αρχείου TXT λεξικού-πυρήνα (ορθογραφία). Κενό/null = δεν έχει φορτωθεί πυρήνας.
  Future<String?> getDictionarySourcePath() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_prefKey(_keyDictionarySourcePath));
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> setDictionarySourcePath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.trim().isEmpty) {
      await prefs.remove(_prefKey(_keyDictionarySourcePath));
    } else {
      await prefs.setString(_prefKey(_keyDictionarySourcePath), path.trim());
    }
  }

  /// Διαδρομή εξόδου για Compile (`exportToTxt`).
  Future<String?> getDictionaryExportPath() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_prefKey(_keyDictionaryExportPath));
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> setDictionaryExportPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.trim().isEmpty) {
      await prefs.remove(_prefKey(_keyDictionaryExportPath));
    } else {
      await prefs.setString(_prefKey(_keyDictionaryExportPath), path.trim());
    }
  }

  /// Πολιτική εκκαθάρισης Ιστορικού — **κοινή** (Φάση 2): καθαρίζει το κοινό
  /// Ιστορικό, οπότε δεν επιτρέπεται να διαφέρει ανά μηχάνημα.
  Future<AuditRetentionConfig> getAuditRetentionConfig() async {
    final raw = await SharedSettings.read(
      SharedSettingKeys.auditRetentionConfig,
    );
    return AuditRetentionConfig.fromJsonString(raw);
  }

  Future<void> setAuditRetentionConfig(AuditRetentionConfig config) async {
    await SharedSettings.write(
      SharedSettingKeys.auditRetentionConfig,
      jsonEncode(config.toJson()),
    );
  }

  /// Πόσα πρόσφατα ημερήσια αρχεία errors_*.log διατηρούνται στον φάκελο logs.
  Future<int> getCrashLogRetentionCount() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_prefKey(_keyCrashLogRetentionCount));
    if (value == null) return defaultCrashLogRetentionCount;
    return value.clamp(minCrashLogRetentionCount, maxCrashLogRetentionCount);
  }

  Future<void> setCrashLogRetentionCount(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _prefKey(_keyCrashLogRetentionCount),
      value.clamp(minCrashLogRetentionCount, maxCrashLogRetentionCount),
    );
  }

  /// Φάκελος ενημερώσεων — **κοινός** (Φάση 2): τον ορίζει ο διαχειριστής και
  /// από εκεί παίρνουν όλοι τις εκδόσεις.
  Future<String?> getUpdateFolderPath() async {
    final s = await SharedSettings.read(SharedSettingKeys.updateFolderPath);
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> setUpdateFolderPath(String? path) async {
    await SharedSettings.write(
      SharedSettingKeys.updateFolderPath,
      path?.trim() ?? '',
    );
  }

  /// Πρότυπο εντολής δημοσίευσης μέσω τερματικού.
  /// Κενό/null = [kDefaultPublishCliCommandTemplate].
  Future<String> getPublishCliCommandTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_prefKey(_keyPublishCliCommandTemplate));
    if (s == null) return kDefaultPublishCliCommandTemplate;
    final t = s.trim();
    return t.isEmpty ? kDefaultPublishCliCommandTemplate : t;
  }

  Future<void> setPublishCliCommandTemplate(String? template) async {
    final prefs = await SharedPreferences.getInstance();
    if (template == null || template.trim().isEmpty) {
      await prefs.remove(_prefKey(_keyPublishCliCommandTemplate));
    } else {
      await prefs.setString(
        _prefKey(_keyPublishCliCommandTemplate),
        template.trim(),
      );
    }
  }

  /// Εμφάνιση αυτόματου μηνύματος διαθέσιμης ενημέρωσης στην εκκίνηση.
  /// Προεπιλογή: true. Δεν επηρεάζει την κόκκινη κουκίδα ούτε τον έλεγχο.
  Future<bool> getShowUpdateOnStartup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(_keyShowUpdateOnStartup)) ?? true;
  }

  Future<void> setShowUpdateOnStartup(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(_keyShowUpdateOnStartup), value);
  }

  // --- Τύποι εξοπλισμού (app_settings, comma-separated) ---

  /// Τι δείχνει η οθόνη για μια αποθηκευμένη τιμή τύπων εξοπλισμού.
  ///
  /// Καθαρή συνάρτηση επίτηδες: ο φρουρός της [setEquipmentTypes] συγκρίνει
  /// την αφετηρία της οθόνης με το **ίδιο** αποτέλεσμα που θα έδειχνε η οθόνη —
  /// αλλιώς μια κενή αποθηκευμένη τιμή θα φαινόταν ξένη αλλαγή σε κάθε νέα βάση.
  static String effectiveEquipmentTypes(String? stored) {
    final trimmed = stored?.trim() ?? '';
    return trimmed.isEmpty ? 'Υπολογιστής, Εκτυπωτής' : trimmed;
  }

  /// Επιστρέφει το ακατέργαστο string τύπων εξοπλισμού (διαχωρισμένα με κόμμα).
  /// Χρήση στο UI ρυθμίσεων. Προεπιλογή: "Υπολογιστής, Εκτυπωτής".
  Future<String> getEquipmentTypesRaw() async {
    final value = _getAppSetting != null
        ? await _getAppSetting!(_keyEquipmentTypes)
        : null;
    return effectiveEquipmentTypes(value);
  }

  /// Αποθηκεύει τους τύπους εξοπλισμού (comma-separated).
  ///
  /// Το [expected] είναι η λίστα **όπως τη φόρτωσε ο διάλογος**. Ο χρήστης
  /// επεξεργάζεται ελεύθερο κείμενο, οπότε δεν υπάρχει σιωπηλή συγχώνευση που
  /// να ξέρει αν ένα στοιχείο λείπει επίτηδες: αν κάποιος πρόλαβε, πετιέται
  /// [SettingsListStaleException] και αποφασίζει ο άνθρωπος. `null` = χωρίς
  /// αφετηρία, η εγγραφή περνά (και είναι ο τρόπος να γραφτεί «από πάνω»).
  Future<void> setEquipmentTypes(
    String value, {
    required String? expected,
  }) async {
    await _writeGuardedList(
      key: _keyEquipmentTypes,
      next: value.trim(),
      expected: expected,
      effective: effectiveEquipmentTypes,
    );
  }

  /// Η κοινή εγγραφή ρυθμιζόμενης λίστας, με τον φρουρό μέσα στην ατομική
  /// δέσμευση: ο έλεγχος γίνεται πάνω στην τιμή που μόλις διαβάστηκε, άρα δεν
  /// υπάρχει παράθυρο ανάμεσα στην ανάγνωση και στην εγγραφή.
  Future<void> _writeGuardedList({
    required String key,
    required String next,
    required String? expected,
    required String Function(String? stored) effective,
  }) async {
    final update = SettingsService.appSettingUpdater;
    if (update == null) return;
    final baseline = expected?.trim();
    await update(key, (current) {
      if (baseline != null && effective(current) != baseline) {
        throw SettingsListStaleException(
          SettingsListConflict(
            expected: baseline,
            fresh: effective(current),
            attempted: next,
          ),
        );
      }
      return next;
    });
  }

  /// Ακατέργαστο JSON των κανόνων επικύρωσης Καταλόγου (app_settings).
  ///
  /// Το core δεν γνωρίζει το σχήμα — η αποκωδικοποίηση γίνεται στο feature
  /// (`CatalogValidationRules.fromRawJson`), που δίνει προεπιλογές σε null.
  Future<String?> getCatalogValidationRulesRaw() async {
    if (_getAppSetting == null) return null;
    return _getAppSetting!(_keyCatalogValidationRules);
  }

  /// **Στοχευμένη αλλαγή** των κανόνων επικύρωσης.
  ///
  /// Οι είκοσι δύο κανόνες ζουν σε ΕΝΑ κλειδί, οπότε γράφοντας ολόκληρο το
  /// JSON από την εικόνα της οθόνης σβήναμε τον διακόπτη που μόλις άλλαξε ο
  /// άλλος διαχειριστής. Η [change] παίρνει το **τρέχον αποθηκευμένο** κείμενο
  /// (`null` = καμία αποθηκευμένη τιμή) και επιστρέφει το νέο· η εγγραφή είναι
  /// ατομική και η [change] μπορεί να ξανατρέξει, άρα οφείλει να είναι καθαρή.
  ///
  /// Επιστρέφει ό,τι αποθηκεύτηκε — `null` όταν δεν υπάρχει ακόμη ενεργή βάση.
  Future<String?> updateCatalogValidationRulesRaw(
    String Function(String? current) change,
  ) async {
    final update = SettingsService.appSettingUpdater;
    if (update == null) return null;
    return update(_keyCatalogValidationRules, change);
  }

  /// Επιστρέφει λίστα τύπων για dropdown. Αν η ρύθμιση είναι κενή, επιστρέφει ["Υπολογιστής", "Εκτυπωτής"].
  Future<List<String>> getEquipmentTypesList() async {
    final raw = await getEquipmentTypesRaw();
    final list = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (list.isEmpty) return ['Υπολογιστής', 'Εκτυπωτής'];
    return list;
  }

  // --- Κατηγορίες λεξικού (app_settings, comma-separated) ---

  /// Ακατέργαστο string κατηγοριών λεξικού (διαχωρισμένα με κόμμα).
  /// Αφαιρεί [AppConfig.lexiconCategoryUnspecified] από την εμφάνιση/αποθήκευση λίστας.
  Future<String> getLexiconCategoriesRaw() async {
    final value = _getAppSetting != null
        ? await _getAppSetting!(_keyLexiconCategories)
        : null;
    return effectiveLexiconCategories(value);
  }

  /// Τι δείχνει η οθόνη για μια αποθηκευμένη τιμή κατηγοριών λεξικού.
  ///
  /// Ίδιος ρόλος με την [effectiveEquipmentTypes]: ο φρουρός συγκρίνει με ό,τι
  /// βλέπει ο άνθρωπος, όχι με το ωμό αποθηκευμένο κείμενο.
  static String effectiveLexiconCategories(String? stored) {
    if (stored == null || stored.trim().isEmpty) {
      return defaultLexiconCategoriesCsv;
    }
    final filtered = _withoutInternalCategory(stored);
    return filtered.isEmpty ? defaultLexiconCategoriesCsv : filtered;
  }

  /// Η εσωτερική τιμή «χωρίς κατηγορία» δεν ορίζεται από τον χρήστη και δεν
  /// αποθηκεύεται ποτέ — φιλτράρεται και στην ανάγνωση και στην εγγραφή, ώστε
  /// οι δύο πλευρές να μη διαφωνήσουν ποτέ για το τι είναι «η ίδια λίστα».
  static String _withoutInternalCategory(String csv) => csv
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && s != AppConfig.lexiconCategoryUnspecified)
      .join(', ');

  /// Αποθήκευση κατηγοριών λεξικού (comma-separated).
  ///
  /// Το [expected] παίζει τον ίδιο ρόλο με της [setEquipmentTypes].
  Future<void> setLexiconCategories(
    String value, {
    required String? expected,
  }) async {
    await _writeGuardedList(
      key: _keyLexiconCategories,
      next: _withoutInternalCategory(value),
      expected: expected,
      effective: effectiveLexiconCategories,
    );
  }

  /// Λίστα κατηγοριών για dropdown. Κενό μετά το split → [defaultLexiconCategoriesList].
  /// Εξαιρεί [AppConfig.lexiconCategoryUnspecified].
  Future<List<String>> getLexiconCategoriesList() async {
    final raw = await getLexiconCategoriesRaw();
    final list = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s != AppConfig.lexiconCategoryUnspecified)
        .toList();
    if (list.isEmpty) return defaultLexiconCategoriesList;
    return list;
  }
}
