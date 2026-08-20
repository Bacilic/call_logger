import 'package:sqflite_common/sqlite_api.dart';

/// Persistence των προσωπικών ρυθμίσεων κάθε χρήστη (πίνακας
/// `operator_settings`, key-value ανά προφίλ).
///
/// Αδελφός του `SettingsRepository` (κοινές ρυθμίσεις `app_settings`) — εδώ
/// όμως κάθε τιμή ανήκει σε **έναν** χρήστη και τον ακολουθεί σε όποιον
/// υπολογιστή καθίσει. Ποιο κλειδί ανήκει σε ποια εμβέλεια το αποφασίζει η
/// πύλη προσωπικών ρυθμίσεων, όχι αυτό το αρχείο.
class OperatorSettingsRepository {
  OperatorSettingsRepository(this.db);

  final DatabaseExecutor db;

  static const String tableName = 'operator_settings';

  /// Η τιμή του [key] για τον χρήστη [operatorId]· `null` όταν δεν έχει δική
  /// του τιμή.
  Future<String?> getValue(int operatorId, String key) async {
    final rows = await db.query(
      tableName,
      columns: ['value'],
      where: 'operator_id = ? AND key = ?',
      whereArgs: [operatorId, key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// Γράφει (ή αντικαθιστά) την τιμή του [key] για τον χρήστη [operatorId].
  Future<void> setValue(int operatorId, String key, String value) async {
    await db.insert(tableName, {
      'operator_id': operatorId,
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Σβήνει την τιμή του [key] για τον χρήστη [operatorId] — «δεν έχω δική
  /// μου τιμή», όχι «έχω κενή».
  Future<void> deleteValue(int operatorId, String key) async {
    await db.delete(
      tableName,
      where: 'operator_id = ? AND key = ?',
      whereArgs: [operatorId, key],
    );
  }

  /// Όλες οι προσωπικές ρυθμίσεις του χρήστη — για την εξαγωγή προφίλ.
  Future<Map<String, String?>> getAllForOperator(int operatorId) async {
    final rows = await db.query(
      tableName,
      columns: ['key', 'value'],
      where: 'operator_id = ?',
      whereArgs: [operatorId],
      orderBy: 'key ASC',
    );
    return {
      for (final row in rows) row['key'] as String: row['value'] as String?,
    };
  }
}
