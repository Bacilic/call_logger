import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../database/database_helper.dart';
import '../utils/search_text_normalizer.dart';

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
    final searchText = _buildSearchText(
      details: details,
      entityType: entityType,
      entityName: entityName,
      oldValues: oldValues,
      newValues: newValues,
    );
    await executor.insert('audit_log', {
      'action': action,
      'timestamp': DateTime.now().toIso8601String(),
      'user_performing': userPerforming,
      'details': details,
      'entity_type': entityType,
      'entity_id': entityId,
      'entity_name': entityName,
      'search_text': searchText,
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
    final searchText = _buildSearchText(
      details: details,
      entityType: entityType,
      entityName: null,
      oldValues: oldValuesSummary,
      newValues: payload,
    );
    await executor.insert('audit_log', {
      'action': action,
      'timestamp': DateTime.now().toIso8601String(),
      'user_performing': userPerforming,
      'details': details,
      'entity_type': entityType,
      'entity_id': null,
      'entity_name': null,
      'search_text': searchText,
      'old_values_json': _encodeOrNull(oldValuesSummary),
      'new_values_json': jsonEncode(payload),
    });
  }

  static String? _encodeOrNull(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return null;
    return jsonEncode(m);
  }

  static String _buildSearchText({
    String? details,
    String? entityType,
    String? entityName,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
  }) {
    final parts = <String>[];
    final normalizedEntityType = (entityType ?? '').trim();
    void add(String? raw) {
      final t = raw?.trim() ?? '';
      if (t.isNotEmpty) parts.add(t);
    }

    add(entityName);
    add(_entityTypeSearchLabel(entityType));
    add(details);

    final oldMap = oldValues ?? const <String, dynamic>{};
    final newMap = newValues ?? const <String, dynamic>{};
    final keys = oldMap.keys.toSet().union(newMap.keys.toSet()).toList()
      ..sort();
    for (final key in keys) {
      final oldValue = oldMap[key];
      final newValue = newMap[key];
      if (_valuesEqual(oldValue, newValue)) continue;
      final label = _fieldSearchLabel(normalizedEntityType, key);
      final oldText = _searchValueText(key, oldValue);
      final newText = _searchValueText(key, newValue);
      final subaction = _subactionSearchText(
        entityType: normalizedEntityType,
        field: key,
        label: label,
        oldValue: oldValue,
        oldText: oldText,
        newValue: newValue,
        newText: newText,
      );
      add(label);
      add(oldText);
      add(newText);
      add(subaction);
    }

    final normalized = SearchTextNormalizer.normalizeForSearch(parts.join(' '));
    return normalized;
  }

  static String _entityTypeSearchLabel(String? entityType) {
    switch ((entityType ?? '').trim()) {
      case AuditEntityTypes.user:
        return 'χρηστης';
      case AuditEntityTypes.department:
        return 'τμημα';
      case AuditEntityTypes.equipment:
        return 'εξοπλισμος';
      case AuditEntityTypes.category:
        return 'κατηγορια';
      case AuditEntityTypes.task:
        return 'εκκρεμοτητα';
      case AuditEntityTypes.call:
        return 'κληση';
      case AuditEntityTypes.bulkUsers:
        return 'μαζικη ενημερωση χρηστων';
      case AuditEntityTypes.bulkDepartments:
        return 'μαζικη ενημερωση τμηματων';
      case AuditEntityTypes.bulkEquipment:
        return 'μαζικη ενημερωση εξοπλισμου';
      case AuditEntityTypes.importData:
        return 'εισαγωγη δεδομενων';
      case AuditEntityTypes.maintenance:
        return 'συντηρηση βασης';
      case AuditEntityTypes.phone:
        return 'τηλεφωνο';
      default:
        return '';
    }
  }

  static String _fieldSearchLabel(String entityType, String field) {
    const labels = <String, String>{
      'name': 'ονομα',
      'email': 'email',
      'phone': 'τηλεφωνο',
      'status': 'κατασταση',
      'priority': 'προτεραιοτητα',
      'due_date': 'προθεσμια',
      'title': 'τιτλος',
      'description': 'περιγραφη',
      'solution_notes': 'λυση',
      'department_id': 'τμημα',
      'department_text': 'τμημα',
      'equipment_id': 'εξοπλισμος',
      'equipment_text': 'εξοπλισμος',
      'caller_id': 'χρηστης',
      'caller_text': 'χρηστης',
      'phone_text': 'τηλεφωνο',
      'category_text': 'κατηγορια',
      'category_id': 'κατηγορια',
      'issue': 'θεμα',
      'solution': 'λυση',
      'type': 'τυπος',
      'custom_ip': 'ip',
      'linked_users': 'συνδεδεμενοι χρηστες',
      'linked_equipment': 'συνδεδεμενος εξοπλισμος',
      'linked_phone_numbers': 'τηλεφωνα',
      'linked_user_id': 'χρηστης',
      'color': 'χρωμα',
      'building': 'κτηριο',
      'map_floor': 'οροφος',
      'floor_id': 'οροφος',
      'notes': 'σημειωσεις',
      'map_x': 'θεσης χ',
      'map_y': 'θεσης υ',
      'map_width': 'πλατους',
      'map_height': 'υψους',
      'map_rotation': 'περιστροφης',
      'map_label_offset_x': 'μετατοπισης ετικετας χ',
      'map_label_offset_y': 'μετατοπισης ετικετας υ',
      'map_anchor_offset_x': 'μετατοπισης αγκυρας χ',
      'map_anchor_offset_y': 'μετατοπισης αγκυρας υ',
      'map_custom_name': 'προσαρμοσμενου ονοματος',
      'map_hidden': 'ορατοτητας',
    };
    final label = labels[field];
    if (label != null) return label;
    if (entityType.trim().isEmpty) return 'πεδιου $field';
    return 'πεδιου $field';
  }

  static String _searchValueText(String field, dynamic value) {
    if (value == null) return '';
    if (field == 'status') {
      final raw = value.toString().trim().toLowerCase();
      const map = <String, String>{
        'pending': 'εκκρεμης',
        'completed': 'ολοκληρωμενη',
        'closed': 'κλειστη',
        'open': 'ανοιχτη',
        'in_progress': 'σε εξελιξη',
      };
      return map[raw] ?? raw;
    }
    if (field == 'priority') {
      final raw = value.toString().trim().toLowerCase();
      const map = <String, String>{
        'low': 'χαμηλη',
        'normal': 'κανονικη',
        'medium': 'μεσαια',
        'high': 'υψηλη',
        'urgent': 'επειγουσα',
      };
      return map[raw] ?? raw;
    }
    if (field == 'color') {
      return _friendlyColor(value.toString());
    }
    if (field == 'map_floor') {
      return _formatFloorValue(value) ?? 'χωρις οροφο';
    }
    if (value is List) {
      return '${value.length} στοιχεια';
    }
    if (value is Map) {
      return 'δομημενα δεδομενα';
    }
    return '$value'.trim();
  }

  static String _subactionSearchText({
    required String entityType,
    required String field,
    required String label,
    required dynamic oldValue,
    required String oldText,
    required dynamic newValue,
    required String newText,
  }) {
    if (entityType == AuditEntityTypes.department && field == 'map_floor') {
      final oldFloor = _formatFloorValue(oldValue);
      final newFloor = _formatFloorValue(newValue);
      if ((oldFloor == null || oldFloor == 'χωρις οροφο') &&
          newFloor != null &&
          newFloor != 'χωρις οροφο') {
        return 'προσθηκη στον οροφο $newFloor';
      }
      if (oldFloor != null &&
          oldFloor != 'χωρις οροφο' &&
          (newFloor == null || newFloor == 'χωρις οροφο')) {
        return 'αφαιρεση απο οροφο $oldFloor';
      }
      if (oldFloor != null && newFloor != null) {
        return 'αλλαγη οροφου απο $oldFloor σε $newFloor';
      }
    }

    if (entityType == AuditEntityTypes.phone && field == 'linked_user_id') {
      final oldUser = _hasMeaningfulValue(oldValue) ? '#$oldValue' : null;
      final newUser = _hasMeaningfulValue(newValue) ? '#$newValue' : null;
      if (oldUser == null && newUser != null) {
        return 'συνδεση σε χρηστη $newUser';
      }
      if (oldUser != null && newUser == null) {
        return 'αποσυνδεση απο χρηστη $oldUser';
      }
      if (oldUser != null && newUser != null) {
        return 'μεταφορα απο χρηστη $oldUser σε $newUser';
      }
    }
    if (entityType == AuditEntityTypes.phone && field == 'department_id') {
      final oldDepartment = _hasMeaningfulValue(oldValue) ? '#$oldValue' : null;
      final newDepartment = _hasMeaningfulValue(newValue) ? '#$newValue' : null;
      if (oldDepartment == null && newDepartment != null) {
        return 'συνδεση σε τμημα $newDepartment';
      }
      if (oldDepartment != null && newDepartment == null) {
        return 'αποσυνδεση απο τμημα $oldDepartment';
      }
      if (oldDepartment != null && newDepartment != null) {
        return 'μεταφορα απο τμημα $oldDepartment σε $newDepartment';
      }
    }

    final hasOld = _hasMeaningfulValue(oldValue);
    final hasNew = _hasMeaningfulValue(newValue);
    if (!hasOld && hasNew) {
      return 'προσθηκη $label $newText';
    }
    if (hasOld && !hasNew) {
      return 'αφαιρεση $label $oldText';
    }
    if (hasOld && hasNew) {
      return 'αλλαγη $label απο $oldText σε $newText';
    }
    return '';
  }

  static bool _hasMeaningfulValue(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return '$value'.trim().isNotEmpty;
  }

  static bool _valuesEqual(dynamic a, dynamic b) {
    if (a == null && b == null) return true;
    if (a is List || a is Map || b is List || b is Map) {
      try {
        return jsonEncode(a) == jsonEncode(b);
      } catch (_) {
        return '$a' == '$b';
      }
    }
    return '${a ?? ''}' == '${b ?? ''}';
  }

  static String _friendlyColor(String raw) {
    final normalized = raw.trim().toUpperCase();
    const known = <String, String>{
      '#1976D2': 'μπλε',
      '#EF5350': 'κοκκινο',
      '#4CAF50': 'πρασινο',
      '#FFC107': 'κιτρινο',
      '#9C27B0': 'μωβ',
    };
    return known[normalized] ?? raw.trim();
  }

  static String? _formatFloorValue(dynamic value) {
    if (value == null) return 'χωρις οροφο';
    final text = value.toString().trim();
    if (text.isEmpty) return 'χωρις οροφο';
    return text;
  }

  static List<String> _tokenVariants(String token) {
    final out = <String>{token};
    if (token.length > 3) {
      out.add(token.substring(0, token.length - 1));
    }
    if (token.length > 4) {
      out.add(token.substring(0, token.length - 2));
    }
    final etaToIota = token.replaceAll('η', 'ι');
    if (etaToIota != token) out.add(etaToIota);
    final iotaToEta = token.replaceAll('ι', 'η');
    if (iotaToEta != token) out.add(iotaToEta);
    return out.where((v) => v.trim().length >= 2).toList();
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
      final tokens = keywordNormalized
          .trim()
          .split(' ')
          .map((token) => token.trim())
          .where((token) => token.isNotEmpty)
          .toList();
      for (final token in tokens) {
        final variants = _tokenVariants(token);
        if (variants.isEmpty) continue;
        where.add(
          '(${variants.map((_) => "COALESCE(search_text, '') LIKE ?").join(' OR ')})',
        );
        args.addAll(variants.map((variant) => '%$variant%'));
      }
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

  /// Όλα τα ids που ταιριάζουν στα φίλτρα (χωρίς σελιδοποίηση), νεότερα πρώτα.
  Future<List<int>> queryMatchingIds({
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
      final tokens = keywordNormalized
          .trim()
          .split(' ')
          .map((token) => token.trim())
          .where((token) => token.isNotEmpty)
          .toList();
      for (final token in tokens) {
        final variants = _tokenVariants(token);
        if (variants.isEmpty) continue;
        where.add(
          '(${variants.map((_) => "COALESCE(search_text, '') LIKE ?").join(' OR ')})',
        );
        args.addAll(variants.map((variant) => '%$variant%'));
      }
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = await _db.rawQuery(
      'SELECT id FROM audit_log $whereSql ORDER BY timestamp DESC, id DESC',
      args,
    );
    return rows
        .map((row) => row['id'])
        .whereType<num>()
        .map((id) => id.toInt())
        .toList();
  }

  /// Οριστική διαγραφή συγκεκριμένων εγγραφών audit.
  /// Επιστρέφει το πλήθος που αφαιρέθηκε και γράφει εγγραφή συντήρησης βάσης.
  Future<int> deleteByIds(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final uniqueIds = ids.toSet().toList()..sort();
    final placeholders = List.filled(uniqueIds.length, '?').join(',');
    final user = await performingUser(_db);
    return _db.transaction((txn) async {
      final removed = await txn.rawDelete(
        'DELETE FROM audit_log WHERE id IN ($placeholders)',
        uniqueIds,
      );
      if (removed > 0) {
        await log(
          txn,
          action: 'ΔΙΑΓΡΑΦΗ ΕΓΓΡΑΦΩΝ AUDIT',
          userPerforming: user,
          entityType: AuditEntityTypes.maintenance,
          details: 'deleteAuditLogBySelection',
          newValues: {
            'rows_deleted': removed,
            'selected_ids_count': uniqueIds.length,
          },
        );
      }
      return removed;
    });
  }

  /// Διαθέσιμες ενέργειες (μοναδικές τιμές `action`) για το τρέχον φίλτρο.
  Future<List<String>> queryDistinctActions({
    String? entityType,
    String? dateFromInclusiveIso,
    String? dateToExclusiveIso,
  }) async {
    final where = <String>[];
    final args = <Object?>[];

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

    where.add('action IS NOT NULL');
    where.add('TRIM(action) <> \'\'');
    final whereSql = 'WHERE ${where.join(' AND ')}';
    final rows = await _db.rawQuery(
      'SELECT DISTINCT action FROM audit_log $whereSql '
      'ORDER BY action COLLATE NOCASE ASC',
      args,
    );

    return rows
        .map((row) => (row['action'] as String?)?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList();
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
