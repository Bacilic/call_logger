import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Κλειδί αποθήκευσης για URL Lansweeper στο `app_settings`.
const String kLansweeperUrlSettingKey = 'lansweeper_url';
const String kLansweeperApiUrlSettingKey = 'lansweeper_api_url';
const String kLansweeperApiKeySettingKey = 'lansweeper_api_key';
const String kLansweeperAgentUsernameSettingKey = 'lansweeper_agent_username';
const String kLansweeperHelpdeskAutoLoginSettingKey =
    'lansweeper_helpdesk_auto_login';
const String kLansweeperHelpdeskLoginUrlSettingKey =
    'lansweeper_helpdesk_login_url';
const String kLansweeperTicketViewUrlSettingKey =
    'lansweeper_ticket_view_url';
const String kLansweeperOpenTicketAfterApiSubmitSettingKey =
    'lansweeper_open_ticket_after_api_submit';
const String kLansweeperHelpdeskWebUsernameSettingKey =
    'lansweeper_helpdesk_web_username';
const String kLansweeperHelpdeskWebPasswordSettingKey =
    'lansweeper_helpdesk_web_password';
const String kGeminiApiKeySettingKey = 'gemini_api_key';
const String kGeminiPromptTemplateSettingKey = 'gemini_prompt_template';
const String kGeminiPromptTemplateUserDefaultSettingKey =
    'gemini_prompt_template_user_default';
const String kGeminiEndpointSettingKey = 'gemini_endpoint';
const String kGeminiPrimaryModelSettingKey = 'gemini_primary_model';
const String kGeminiFallbackEnabledSettingKey = 'gemini_fallback_enabled';
const String kGeminiFallbackModelSettingKey = 'gemini_fallback_model';
const String kGeminiModelsProbeCacheSettingKey = 'gemini_models_probe_cache';

/// Προεπιλεγμένο URL φόρμας νέου αιτήματος Lansweeper (web).
const String kDefaultLansweeperUrl =
    'http://10.10.201.22:81/helpdesk/NewTicket.aspx?tid=-7';

/// Προεπιλεγμένο URL προβολής υπάρχοντος ticket (`{tid}` = αριθμός ticket).
const String kDefaultLansweeperTicketViewUrl =
    'http://10.10.201.22:81/helpdesk/ticket.aspx?tid={tid}';

/// Προεπιλεγμένο URL σελίδας σύνδεσης Help Desk (browser).
const String kDefaultLansweeperLoginUrl = 'http://10.10.201.22:81/login.aspx';

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
