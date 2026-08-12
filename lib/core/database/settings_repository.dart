import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Κλειδί αποθήκευσης για URL Lansweeper στο `app_settings`.
const String kLansweeperUrlSettingKey = 'lansweeper_url';
const String kLansweeperApiUrlSettingKey = 'lansweeper_api_url';
const String kLansweeperApiKeySettingKey = 'lansweeper_api_key';
const String kLansweeperAgentUsernameSettingKey = 'lansweeper_agent_username';
const String kLansweeperTicketViewUrlSettingKey = 'lansweeper_ticket_view_url';
const String kLansweeperOpenTicketAfterApiSubmitSettingKey =
    'lansweeper_open_ticket_after_api_submit';
const String kLansweeperTicketSubmitConfigSettingKey =
    'lansweeper_ticket_submit_config';
const String kLansweeperTicketSubmitFormPrefsSettingKey =
    'lansweeper_ticket_submit_form_prefs';

/// Το διάστημα που είχε επιλεγμένο τελευταία η Αναφορά Lansweeper.
///
/// Μετά την αφαίρεση της μπάρας καταστάσεων το διάστημα είναι η μοναδική
/// ρύθμιση της αναφοράς, οπότε αξίζει να επιβιώνει μεταξύ ανοιγμάτων.
const String kLansweeperReportRangeSettingKey = 'lansweeper_report_range';
const String kGeminiApiKeySettingKey = 'gemini_api_key';
const String kGeminiPromptTemplateSettingKey = 'gemini_prompt_template';
const String kGeminiPromptTemplateUserDefaultSettingKey =
    'gemini_prompt_template_user_default';
const String kGeminiEndpointSettingKey = 'gemini_endpoint';
const String kGeminiPrimaryModelSettingKey = 'gemini_primary_model';
const String kGeminiFallbackEnabledSettingKey = 'gemini_fallback_enabled';
const String kGeminiFallbackModelSettingKey = 'gemini_fallback_model';
const String kGeminiAutoResubmitSettingKey = 'gemini_auto_resubmit';
const String kGeminiModelsProbeCacheSettingKey = 'gemini_models_probe_cache';

/// Υπογραφή του σπορέα «Σενάρια σφαλμάτων» ΜΕΣΑ στη δοκιμαστική βάση.
///
/// Το είδος μιας βάσης το λέει το περιεχόμενό της, ποτέ το όνομα του αρχείου:
/// η μετονομασία δεν κρύβει τη δοκιμαστική, και η επαναφορά αληθινών δεδομένων
/// πάνω στο ίδιο αρχείο σβήνει την υπογραφή μαζί με το παλιό περιεχόμενο.
const String kDebugScenarioSignatureSettingKey = 'debug_scenario_signature';

/// Προεπιλεγμένο URL φόρμας νέου αιτήματος Lansweeper (web).
const String kDefaultLansweeperUrl =
    'http://10.10.201.22:81/helpdesk/NewTicket.aspx?tid=-7';

/// Προεπιλεγμένο URL προβολής υπάρχοντος ticket (`{tid}` = αριθμός ticket).
const String kDefaultLansweeperTicketViewUrl =
    'http://10.10.201.22:81/helpdesk/ticket.aspx?tid={tid}';

/// Δείγμα αριθμού αιτήματος για τον «Έλεγχο συνδέσμου» προβολής ticket, όταν
/// καμία κλήση δεν έχει ακόμη καταχωρημένο αίτημα.
const String kSampleLansweeperTicketId = '17132';

/// Παράδειγμα URL τελικού σημείου API (`api.aspx`) για υποδείξεις.
const String kExampleLansweeperApiUrl = 'http://10.10.201.22:81/api.aspx';

/// Ελαφρύ repository για ρυθμίσεις `app_settings` (key-value).
class SettingsRepository {
  SettingsRepository(this.db);

  final Database db;

  Future<void> _ensureTable({DatabaseExecutor? executor}) async {
    final e = executor ?? db;
    await e.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  Future<String?> getSetting(String key, {DatabaseExecutor? executor}) async {
    final e = executor ?? db;
    await _ensureTable(executor: e);
    final rows = await e.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> saveSetting(
    String key,
    String value, {
    DatabaseExecutor? executor,
  }) async {
    final e = executor ?? db;
    await _ensureTable(executor: e);
    await e.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
