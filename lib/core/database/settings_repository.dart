import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Κλειδί αποθήκευσης για URL Lansweeper στο `app_settings`.
const String kLansweeperUrlSettingKey = 'lansweeper_url';

/// Προεπιλεγμένο URL Lansweeper.
const String kDefaultLansweeperUrl =
    'http://10.10.201.22:81/helpdesk/NewTicket.aspx?tid=-7';

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
