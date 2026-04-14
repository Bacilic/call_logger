import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../database/database_helper.dart';

/// Κεντρική εγγραφή στον πίνακα `audit_log` (μόνο από εδώ).
class AuditService {
  AuditService(this._db);

  final Database _db;

  /// Όνομα χρήστη για στήλη `user_performing` (ρύθμιση `app_settings`).
  static Future<String> performingUser(Database db) async {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [DatabaseHelper.auditUserPerformingSettingsKey],
      limit: 1,
    );
    if (rows.isEmpty) return '—';
    final v = rows.first['value'] as String?;
    final t = v?.trim();
    if (t != null && t.isNotEmpty) return t;
    return '—';
  }

  /// Εισαγωγή μίας γραμμής audit μέσα σε transaction ή απευθείας.
  static Future<void> log(
    DatabaseExecutor executor, {
    required String action,
    required String userPerforming,
    String? details,
    String? entityType,
    int? entityId,
    String? entityName,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) async {
    await executor.insert('audit_log', {
      'action': action,
      'timestamp': DateTime.now().toIso8601String(),
      'user_performing': userPerforming,
      'details': details,
      'entity_type': entityType,
      'entity_id': entityId,
      'entity_name': entityName,
      'old_values_json': _encodeOrNull(oldValues),
      'new_values_json': _encodeOrNull(newValues),
    });
  }

  /// Μαζική ενημέρωση: κοινά `fields` + λίστα επηρεασμένων ids.
  static Future<void> logBulk(
    DatabaseExecutor executor, {
    required String action,
    required String userPerforming,
    required String entityType,
    required List<int> affectedIds,
    required Map<String, dynamic> appliedFields,
    String? details,
    Map<String, dynamic>? oldValuesSummary,
  }) async {
    final payload = <String, dynamic>{
      'fields': appliedFields,
      'affected_ids': affectedIds,
    };
    await executor.insert('audit_log', {
      'action': action,
      'timestamp': DateTime.now().toIso8601String(),
      'user_performing': userPerforming,
      'details': details,
      'entity_type': entityType,
      'entity_id': null,
      'entity_name': null,
      'old_values_json': _encodeOrNull(oldValuesSummary),
      'new_values_json': jsonEncode(payload),
    });
  }

  static String? _encodeOrNull(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return null;
    return jsonEncode(m);
  }

  /// Σελιδοποιημένη λίστα + συνολικό πλήθος (για φίλτρα UI).
  Future<({List<Map<String, Object?>> rows, int total})> queryPage({
    required int offset,
    required int limit,
    String? keywordNormalized,
    String? action,
    String? entityType,
    String? dateFromInclusiveIso,
    String? dateToExclusiveIso,
  }) async {
    final where = <String>[];
    final args = <Object?>[];

    if (action != null && action.trim().isNotEmpty) {
      where.add('action = ?');
      args.add(action.trim());
    }
    if (entityType != null && entityType.trim().isNotEmpty) {
      where.add('entity_type = ?');
      args.add(entityType.trim());
    }
    if (dateFromInclusiveIso != null &&
        dateFromInclusiveIso.trim().isNotEmpty) {
      where.add('timestamp >= ?');
      args.add(dateFromInclusiveIso.trim());
    }
    if (dateToExclusiveIso != null && dateToExclusiveIso.trim().isNotEmpty) {
      where.add('timestamp < ?');
      args.add(dateToExclusiveIso.trim());
    }
    if (keywordNormalized != null && keywordNormalized.trim().isNotEmpty) {
      final k = '%${keywordNormalized.trim()}%';
      where.add(
        '('
        'COALESCE(details, \'\') LIKE ? OR '
        'COALESCE(entity_name, \'\') LIKE ? OR '
        'COALESCE(entity_type, \'\') LIKE ? OR '
        'COALESCE(action, \'\') LIKE ? OR '
        'COALESCE(user_performing, \'\') LIKE ?'
        ')',
      );
      args.addAll([k, k, k, k, k]);
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final countRows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM audit_log $whereSql',
      args,
    );
    final totalRaw = countRows.isEmpty ? 0 : countRows.first['c'];
    final total = totalRaw is int
        ? totalRaw
        : (totalRaw is num ? totalRaw.toInt() : int.tryParse('$totalRaw') ?? 0);

    final rows = await _db.rawQuery(
      'SELECT * FROM audit_log $whereSql '
      'ORDER BY timestamp DESC, id DESC LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );

    return (rows: rows, total: total);
  }

  /// Διαγραφή παλαιότερων από [cutoff] (ISO timestamp σύγκριση).
  Future<int> deleteOlderThan(DateTime cutoff) async {
    return _db.delete(
      'audit_log',
      where: 'timestamp < ?',
      whereArgs: [cutoff.toIso8601String()],
    );
  }

  /// Διαγραφή των παλαιότερων γραμμών ώστε να μείνουν το πολύ [keep] (νεότερες πρώτες).
  Future<int> trimToMaxRows(int keep) async {
    if (keep <= 0) return 0;
    final c = await _db.rawQuery('SELECT COUNT(*) AS c FROM audit_log');
    final nRaw = c.isEmpty ? 0 : c.first['c'];
    final n = nRaw is int ? nRaw : (nRaw is num ? nRaw.toInt() : 0);
    if (n <= keep) return 0;
    final toRemove = n - keep;
    return _db.rawDelete(
      'DELETE FROM audit_log WHERE id IN (SELECT id FROM audit_log ORDER BY timestamp ASC, id ASC LIMIT ?)',
      [toRemove],
    );
  }
}

/// Σταθερές τύπου οντότητας για `entity_type` (κείμενο στη βάση).
abstract final class AuditEntityTypes {
  static const String user = 'user';
  static const String department = 'department';
  static const String equipment = 'equipment';
  static const String category = 'category';
  static const String task = 'task';
  static const String call = 'call';
  static const String bulkUsers = 'bulk_users';
  static const String bulkDepartments = 'bulk_departments';
  static const String bulkEquipment = 'bulk_equipment';
  static const String importData = 'import_data';
  static const String maintenance = 'maintenance';
  /// Πίνακας `phones` (entity_id = `phones.id`).
  static const String phone = 'phone';
}
