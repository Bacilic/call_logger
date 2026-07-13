import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import 'audit_diff_helper.dart';
import 'database_helper.dart';
import '../utils/search_text_normalizer.dart';

/// Κεντρική εγγραφή στον πίνακα `audit_log` (μόνο από εδώ).
class AuditService {
  AuditService(this._db);

  final Database _db;

  /// Όνομα χρήστη για στήλη `user_performing` (ρύθμιση `app_settings`).
  ///
  /// Χρησιμοποίησε το ίδιο [DatabaseExecutor] με το ενεργό transaction (π.χ. `txn`),
  /// όχι το root [Database] ενώ είναι ανοιχτό transaction — αλλιώς κλείδωμα SQLite.
  static Future<String> performingUser(DatabaseExecutor executor) async {
    final rows = await executor.query(
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

  /// Ανακατασκευή `search_text` από υπάρχουσα γραμμή `audit_log`.
  static String rebuildSearchTextForRow(Map<String, dynamic> row) {
    Map<String, dynamic>? decodeJson(String? raw) {
      if (raw == null || raw.trim().isEmpty) return null;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {}
      return null;
    }

    return _buildSearchText(
      details: row['details'] as String?,
      entityType: row['entity_type'] as String?,
      entityName: row['entity_name'] as String?,
      oldValues: decodeJson(row['old_values_json'] as String?),
      newValues: decodeJson(row['new_values_json'] as String?),
    );
  }

  /// Ενημέρωση `search_text` για μία εγγραφή audit μέσα σε transaction.
  static Future<void> rebuildAndPersistSearchText(
    DatabaseExecutor executor,
    int auditId,
  ) async {
    final rows = await executor.query(
      'audit_log',
      where: 'id = ?',
      whereArgs: [auditId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final searchText = rebuildSearchTextForRow(rows.first);
    await executor.update(
      'audit_log',
      {'search_text': searchText},
      where: 'id = ?',
      whereArgs: [auditId],
    );
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
      if (!AuditDiffHelper.shouldIncludeField(key, oldValue, newValue)) {
        continue;
      }
      final label = AuditDiffHelper.fieldSearchLabel(normalizedEntityType, key);
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
      case AuditEntityTypes.backup:
        return 'αντιγραφο ασφαλειας';
      case AuditEntityTypes.phone:
        return 'τηλεφωνο';
      default:
        return '';
    }
  }

  /// Αναγνώσιμη μορφή κλειδιού πεδίου χωρίς underscores (fallback ετικέτας).
  static String humanizeFieldKey(String field) =>
      AuditDiffHelper.humanizeFieldKey(field);

  /// Πεδία που αποκλείονται από diff UI και από χτίσιμο `search_text`.
  static Set<String> get auditDiffExcludedFields =>
      AuditDiffHelper.excludedFields;

  /// Παράγωγα πεδία που κρύβονται όταν υπάρχει κύριο πεδίο (π.χ. floor_id → map_floor).
  static bool shouldSkipDerivativeAuditField(String field, Set<String> keys) =>
      AuditDiffHelper.shouldSkipDerivativeField(field, keys);

  /// Κοινός κανόνας: εμφάνιση πεδίου στο «Τι άλλαξε» και στο `search_text`.
  static bool shouldIncludeFieldInAuditDiff(
    String field,
    dynamic oldValue,
    dynamic newValue,
  ) =>
      AuditDiffHelper.shouldIncludeField(field, oldValue, newValue);

  static String _searchValueText(String field, dynamic value) {
    if (value == null) return '';
    if (field == 'remote_params') return '';
    return AuditDiffHelper.humanizeFieldValue(
      field,
      value,
      forSearch: true,
    );
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

    if (field == 'remote_params') {
      return AuditDiffHelper.remoteParamsSearchText(
        oldValue: oldValue,
        newValue: newValue,
      );
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
    if (a == null || b == null) return false;
    if (a is List || a is Map || b is List || b is Map) {
      try {
        return jsonEncode(a) == jsonEncode(b);
      } catch (_) {
        return '$a' == '$b';
      }
    }
    final numA = _coerceNumeric(a);
    final numB = _coerceNumeric(b);
    if (numA != null && numB != null) {
      if (numA is int && numB is int) return numA == numB;
      return (numA.toDouble() - numB.toDouble()).abs() < 1e-6;
    }
    return '${a ?? ''}' == '${b ?? ''}';
  }

  /// Δημόσιος wrapper για σύγκριση πεδίων audit (diff repositories).
  static bool valuesEqual(dynamic a, dynamic b) => _valuesEqual(a, b);

  static num? _coerceNumeric(dynamic value) {
    if (value is num) return value;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      return num.tryParse(trimmed);
    }
    return null;
  }


  static String? _formatFloorValue(dynamic value) {
    if (value == null) return 'χωρις οροφο';
    final text = value.toString().trim();
    if (text.isEmpty) return 'χωρις οροφο';
    return text;
  }

  /// Ανακατασκευή `search_text` για όλες τις εγγραφές audit (idempotent).
  static Future<void> rebuildAllSearchTexts(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'audit_log',
      columns: [
        'id',
        'details',
        'entity_type',
        'entity_name',
        'old_values_json',
        'new_values_json',
        'search_text',
      ],
    );
    if (rows.isEmpty) return;

    final batch = executor.batch();
    var pending = 0;
    for (final row in rows) {
      final idRaw = row['id'];
      if (idRaw == null) continue;
      final id = idRaw is int ? idRaw : (idRaw as num).toInt();
      final next = rebuildSearchTextForRow(row);
      final current = (row['search_text'] as String?) ?? '';
      if (current == next) continue;
      batch.update(
        'audit_log',
        {'search_text': next},
        where: 'id = ?',
        whereArgs: [id],
      );
      pending++;
    }
    if (pending > 0) {
      await batch.commit(noResult: true);
    }
  }

  /// Συντήρηση: idempotent ανακατασκευή ευρετηρίου `search_text` (μόνο δεδομένα).
  static Future<void> migrateRebuildAuditSearchTextIndex(Database db) async {
    await rebuildAllSearchTexts(db);
  }

  static List<String> _wordPrefixVariants(String token) {
    final out = <String>{};
    if (token.length >= 5) {
      final trimmed = token.substring(0, token.length - 1);
      if (trimmed.length >= 4) {
        out.add(trimmed);
      }
    }
    final etaToIota = token.replaceAll('η', 'ι');
    if (etaToIota != token) out.add(etaToIota);
    final iotaToEta = token.replaceAll('ι', 'η');
    if (iotaToEta != token) out.add(iotaToEta);
    return out.toList();
  }

  static void _appendExactWordClause(
    List<String> clauses,
    List<Object?> clauseArgs,
    String word,
  ) {
    clauses.add(
      "(COALESCE(search_text, '') LIKE ? OR COALESCE(search_text, '') LIKE ? OR COALESCE(search_text, '') LIKE ? OR COALESCE(search_text, '') = ?)",
    );
    clauseArgs.add('$word %');
    clauseArgs.add('% $word %');
    clauseArgs.add('% $word');
    clauseArgs.add(word);
  }

  static void _appendWordPrefixClause(
    List<String> clauses,
    List<Object?> clauseArgs,
    String variant,
  ) {
    clauses.add(
      "(COALESCE(search_text, '') LIKE ? OR COALESCE(search_text, '') LIKE ?)",
    );
    clauseArgs.add('$variant%');
    clauseArgs.add('% $variant%');
  }

  static void _appendSearchTextKeywordClause(
    List<String> where,
    List<Object?> args,
    String token,
  ) {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) return;

    final clauses = <String>[];
    final clauseArgs = <Object?>[];

    final isGenitiveLikeEnding =
        (normalizedToken.endsWith('ς') || normalizedToken.endsWith('σ')) &&
        normalizedToken.length >= 5;

    if (isGenitiveLikeEnding) {
      final stem = normalizedToken.substring(0, normalizedToken.length - 1);
      // Η πλήρης λέξη του χρήστη ταιριάζει ΠΑΝΤΑ (π.χ. «θεσησ» μέσα στο
      // «αλλαγη θεσησ x») — η ρίζα είναι μόνο επιπλέον ανοχή πτώσης.
      clauses.add("COALESCE(search_text, '') LIKE ?");
      clauseArgs.add('%$normalizedToken%');
      if (stem.length >= 4) {
        _appendExactWordClause(clauses, clauseArgs, stem);
        for (final variant in _wordPrefixVariants(stem)) {
          if (variant == stem) continue;
          _appendExactWordClause(clauses, clauseArgs, variant);
        }
      }
    } else {
      clauses.add("COALESCE(search_text, '') LIKE ?");
      clauseArgs.add('%$normalizedToken%');

      for (final variant in _wordPrefixVariants(normalizedToken)) {
        if (variant == normalizedToken) continue;
        _appendWordPrefixClause(clauses, clauseArgs, variant);
      }
    }

    where.add('(${clauses.join(' OR ')})');
    args.addAll(clauseArgs);
  }

  static void _appendKeywordNormalizedClauses(
    List<String> where,
    List<Object?> args,
    String? keywordNormalized,
  ) {
    if (keywordNormalized == null || keywordNormalized.trim().isEmpty) {
      return;
    }
    final tokens = keywordNormalized
        .trim()
        .split(' ')
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toList();
    for (final token in tokens) {
      _appendSearchTextKeywordClause(where, args, token);
    }
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
    _appendKeywordNormalizedClauses(where, args, keywordNormalized);

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
    _appendKeywordNormalizedClauses(where, args, keywordNormalized);

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

  /// Αντίγραφα ασφαλείας βάσης / φορητών αρχείων.
  static const String backup = 'backup';

  /// Πίνακας `phones` (entity_id = `phones.id`).
  static const String phone = 'phone';
}

/// Σταθερές ενεργειών audit (ΚΕΦΑΛΑΙΑ).
abstract final class AuditActions {
  static const String modifyUser = 'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ';
  static const String modifyDepartment = 'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ';
  static const String modifyEquipment = 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΞΟΠΛΙΣΜΟΥ';
  static const String modifyPhone = 'ΤΡΟΠΟΠΟΙΗΣΗ ΤΗΛΕΦΩΝΟΥ';
  static const String modifyCategory = 'ΤΡΟΠΟΠΟΙΗΣΗ ΚΑΤΗΓΟΡΙΑΣ';
  static const String modifyCall = 'ΤΡΟΠΟΠΟΙΗΣΗ ΚΛΗΣΗΣ';
  static const String modifyTask = 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΚΚΡΕΜΟΤΗΤΑΣ';

  static const Set<String> genericModifyActions = {
    'ΤΡΟΠΟΠΟΙΗΣΗ',
    'Τροποποίηση',
    'τροποποίηση',
  };

  static bool isGenericModifyAction(String? action) {
    return genericModifyActions.contains(action?.trim());
  }

  static String? modifyActionForEntityType(String? entityType) {
    switch ((entityType ?? '').trim()) {
      case AuditEntityTypes.user:
        return modifyUser;
      case AuditEntityTypes.department:
        return modifyDepartment;
      case AuditEntityTypes.equipment:
        return modifyEquipment;
      case AuditEntityTypes.phone:
        return modifyPhone;
      case AuditEntityTypes.category:
        return modifyCategory;
      case AuditEntityTypes.call:
        return modifyCall;
      case AuditEntityTypes.task:
        return modifyTask;
      default:
        return null;
    }
  }
}
