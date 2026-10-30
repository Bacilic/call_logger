import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import 'audit_action_labels.dart';
import 'audit_diff_helper.dart';
import 'database_table_labels.dart';
import '../services/current_operator.dart';
import '../config/audit_retention_class.dart';
import '../utils/search_text_normalizer.dart';
import 'sql_like.dart';
import '../utils/display_text_sort.dart';

/// Κεντρική εγγραφή στον πίνακα `audit_log` (μόνο από εδώ).
class AuditService {
  AuditService(this._db);

  final Database _db;

  /// Όνομα χρήστη για τη στήλη `user_performing` — ο ενεργός χρήστης.
  ///
  /// Η ταυτότητα έρχεται από τον [CurrentOperator], που την ορίζει μία φορά
  /// στην εκκίνηση. Όσο δεν έχει αναγνωριστεί κανείς, η στήλη γράφει παύλα.
  ///
  /// **Δεν αγγίζει τη βάση** — γι' αυτό δεν δέχεται σύνδεση και δεν επιστρέφει
  /// υπόσχεση. Και τα δύο τα δεχόταν κάποτε, και όσο έμεναν στην υπογραφή
  /// έλεγαν στον αναγνώστη το αντίθετο από ό,τι συμβαίνει: ότι η απάντηση
  /// κρίνεται από τη συγκεκριμένη συναλλαγή. Επειδή δεν ρωτά τη βάση, δεν
  /// υπάρχει ούτε κίνδυνος κλειδώματος μέσα σε ανοιχτό transaction.
  static String performingUser() => CurrentOperator.auditName;

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

  /// Η λέξη του τύπου μέσα στο ευρετήριο — πάντα ίδια με αυτήν της οθόνης.
  ///
  /// Δεύτερος κατάλογος εδώ σήμαινε δεύτερη αλήθεια: όταν η οθόνη μετονομάστηκε
  /// σε «Υπάλληλος», το ευρετήριο έμεινε στο «χρήστης» και η αναζήτηση έψαχνε
  /// λέξη που δεν έγραφε πουθενά η εφαρμογή.
  static String _entityTypeSearchLabel(String? entityType) =>
      databaseEntityTypeSearchLabelEl(entityType);

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
  ) => AuditDiffHelper.shouldIncludeField(field, oldValue, newValue);

  static String _searchValueText(String field, dynamic value) {
    if (value == null) return '';
    if (field == 'remote_params') return '';
    return AuditDiffHelper.humanizeFieldValue(field, value, forSearch: true);
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
        return 'συνδεση σε υπαλληλο $newUser';
      }
      if (oldUser != null && newUser == null) {
        return 'αποσυνδεση απο υπαλληλο $oldUser';
      }
      if (oldUser != null && newUser != null) {
        return 'μεταφορα απο υπαλληλο $oldUser σε $newUser';
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
      "(COALESCE(search_text, '') ${SqlLike.op} OR COALESCE(search_text, '') ${SqlLike.op} OR COALESCE(search_text, '') ${SqlLike.op} OR COALESCE(search_text, '') = ?)",
    );
    clauseArgs.add(SqlLike.startsWith('$word '));
    clauseArgs.add(SqlLike.contains(' $word '));
    clauseArgs.add(SqlLike.endsWith(' $word'));
    clauseArgs.add(word);
  }

  static void _appendWordPrefixClause(
    List<String> clauses,
    List<Object?> clauseArgs,
    String variant,
  ) {
    clauses.add(
      "(COALESCE(search_text, '') ${SqlLike.op} OR COALESCE(search_text, '') ${SqlLike.op})",
    );
    clauseArgs.add(SqlLike.startsWith(variant));
    clauseArgs.add(SqlLike.contains(' $variant'));
  }

  static void _appendSearchTextKeywordClause(
    List<String> where,
    List<Object?> args,
    String token,
    List<_AuditActionPair> actionPairs,
  ) {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) return;

    final clauses = <String>[];
    final clauseArgs = <Object?>[];

    final isGenitiveLikeEnding =
        (normalizedToken.endsWith('ς') || normalizedToken.endsWith('σ')) &&
        normalizedToken.length >= 5;
    final stem = isGenitiveLikeEnding
        ? normalizedToken.substring(0, normalizedToken.length - 1)
        : normalizedToken;

    if (isGenitiveLikeEnding) {
      // Η πλήρης λέξη του χρήστη ταιριάζει ΠΑΝΤΑ (π.χ. «θεσησ» μέσα στο
      // «αλλαγη θεσησ x») — η ρίζα είναι μόνο επιπλέον ανοχή πτώσης.
      clauses.add("COALESCE(search_text, '') ${SqlLike.op}");
      clauseArgs.add(SqlLike.contains(normalizedToken));
      if (stem.length >= 4) {
        _appendExactWordClause(clauses, clauseArgs, stem);
        for (final variant in _wordPrefixVariants(stem)) {
          if (variant == stem) continue;
          _appendExactWordClause(clauses, clauseArgs, variant);
        }
      }
    } else {
      clauses.add("COALESCE(search_text, '') ${SqlLike.op}");
      clauseArgs.add(SqlLike.contains(normalizedToken));

      for (final variant in _wordPrefixVariants(normalizedToken)) {
        if (variant == normalizedToken) continue;
        _appendWordPrefixClause(clauses, clauseArgs, variant);
      }
    }

    // Η ενέργεια δεν γράφεται στο ευρετήριο: η ετικέτα της βγαίνει την ώρα
    // της ανάγνωσης, ώστε παλιές και νέες εγγραφές να βρίσκονται με την ίδια
    // λέξη που δείχνει η οθόνη, χωρίς αναβάθμιση της βάσης.
    for (final pair in actionPairs) {
      final label = pair.searchLabel;
      if (!label.contains(normalizedToken) &&
          !(stem.length >= 4 && label.contains(stem))) {
        continue;
      }
      clauses.add(_AuditActionPair.sqlMatch);
      clauseArgs.addAll(pair.sqlArgs);
    }

    where.add('(${clauses.join(' OR ')})');
    args.addAll(clauseArgs);
  }

  static void _appendKeywordNormalizedClauses(
    List<String> where,
    List<Object?> args,
    String? keywordNormalized,
    List<_AuditActionPair> actionPairs,
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
      _appendSearchTextKeywordClause(where, args, token, actionPairs);
    }
  }

  /// Κάθε συνδυασμός τύπου και ενέργειας που υπάρχει στο ιστορικό.
  ///
  /// Λίγες δεκάδες γραμμές: η ετικέτα «Οντότητα - Ενέργεια» βγαίνει από αυτές
  /// στη Dart, γιατί η SQL δεν την ξέρει.
  Future<List<_AuditActionPair>> _distinctActionPairs({
    String whereSql = '',
    List<Object?> args = const [],
  }) async {
    final rows = await _db.rawQuery(
      'SELECT DISTINCT entity_type, action FROM audit_log $whereSql',
      args,
    );
    return [
      for (final row in rows)
        if (row['action'] case final String action
            when action.trim().isNotEmpty)
          _AuditActionPair((row['entity_type'] as String?) ?? '', action),
    ];
  }

  /// Ό,τι χρειάζονται από τις ενέργειες τα φίλτρα και η λέξη-κλειδί.
  ///
  /// [actionFilter]: τα ζεύγη που δείχνει η οθόνη με την επιλεγμένη ετικέτα —
  /// null όταν δεν έχει επιλεγεί ενέργεια. Μία ετικέτα μπορεί να καλύπτει
  /// πολλά ζεύγη («ΤΡΟΠΟΠΟΙΗΣΗ» και «ΤΡΟΠΟΠΟΙΗΣΗ ΥΠΑΛΛΗΛΟΥ» λένε και τα δύο
  /// «Υπάλληλος - Τροποποίηση»). Η βάση ρωτιέται μόνο όταν χρειάζεται.
  Future<
    ({List<_AuditActionPair>? actionFilter, List<_AuditActionPair> forKeyword})
  >
  _resolveActionTerms({String? actionLabel, String? keywordNormalized}) async {
    final label = actionLabel?.trim() ?? '';
    final hasKeyword = keywordNormalized?.trim().isNotEmpty ?? false;
    if (label.isEmpty && !hasKeyword) {
      return (actionFilter: null, forKeyword: const <_AuditActionPair>[]);
    }
    final pairs = await _distinctActionPairs();
    return (
      actionFilter: label.isEmpty
          ? null
          : [
              for (final pair in pairs)
                if (pair.label == label) pair,
            ],
      forKeyword: hasKeyword ? pairs : const <_AuditActionPair>[],
    );
  }

  /// Οι όροι που στενεύουν τη λίστα, γραμμένοι ΜΙΑ φορά.
  ///
  /// Τέσσερα ερωτήματα ρωτούν το ίδιο πράγμα με διαφορετική αφορμή: η σελίδα,
  /// τα ids της «επιλογής όλων», οι διαθέσιμες ενέργειες και οι διαθέσιμοι
  /// χειριστές του φίλτρου. Όσο το καθένα έχτιζε τους δικούς του όρους, μια
  /// νέα στήλη φίλτρου έμπαινε στα δύο και το τρίτο συνέχιζε σιωπηλά να μετρά
  /// με τα παλιά κριτήρια.
  ///
  /// Το [action] είναι η ετικέτα της οθόνης («Υπάλληλος - Διαγραφή»), όχι η
  /// ωμή ενέργεια της βάσης· ο [entityType] πιάνει και τις μαζικές
  /// ενημερώσεις της ίδιας οντότητας ([auditEntityTypeFamily]).
  Future<({String whereSql, List<Object?> args})> _scopeWhere({
    String? keywordNormalized,
    String? action,
    String? entityType,
    String? userPerforming,
    String? dateFromInclusiveIso,
    String? dateToExclusiveIso,
    List<String> extraConditions = const [],
  }) async {
    final terms = await _resolveActionTerms(
      actionLabel: action,
      keywordNormalized: keywordNormalized,
    );
    final where = <String>[];
    final args = <Object?>[];

    final actionPairs = terms.actionFilter;
    if (actionPairs != null) {
      if (actionPairs.isEmpty) {
        // Ετικέτα που δεν αντιστοιχεί πια σε καμία εγγραφή: καμία γραμμή,
        // όχι όλες.
        where.add('0');
      } else {
        where.add(
          '(${List.filled(actionPairs.length, _AuditActionPair.sqlMatch).join(' OR ')})',
        );
        for (final pair in actionPairs) {
          args.addAll(pair.sqlArgs);
        }
      }
    }

    final type = entityType?.trim() ?? '';
    if (type.isNotEmpty) {
      final family = auditEntityTypeFamily(type);
      where.add(
        'entity_type IN (${List.filled(family.length, '?').join(', ')})',
      );
      args.addAll(family);
    }

    final performing = userPerforming?.trim() ?? '';
    if (performing.isNotEmpty) {
      where.add('user_performing = ?');
      args.add(performing);
    }

    final from = dateFromInclusiveIso?.trim() ?? '';
    if (from.isNotEmpty) {
      where.add('timestamp >= ?');
      args.add(from);
    }
    final to = dateToExclusiveIso?.trim() ?? '';
    if (to.isNotEmpty) {
      where.add('timestamp < ?');
      args.add(to);
    }

    _appendKeywordNormalizedClauses(
      where,
      args,
      keywordNormalized,
      terms.forKeyword,
    );
    where.addAll(extraConditions);

    return (
      whereSql: where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}',
      args: args,
    );
  }

  /// Σελιδοποιημένη λίστα + συνολικό πλήθος (για φίλτρα UI).
  Future<({List<Map<String, Object?>> rows, int total})> queryPage({
    required int offset,
    required int limit,
    String? keywordNormalized,
    String? action,
    String? entityType,
    String? userPerforming,
    String? dateFromInclusiveIso,
    String? dateToExclusiveIso,
  }) async {
    final (:whereSql, :args) = await _scopeWhere(
      keywordNormalized: keywordNormalized,
      action: action,
      entityType: entityType,
      userPerforming: userPerforming,
      dateFromInclusiveIso: dateFromInclusiveIso,
      dateToExclusiveIso: dateToExclusiveIso,
    );

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
    String? userPerforming,
    String? dateFromInclusiveIso,
    String? dateToExclusiveIso,
  }) async {
    final (:whereSql, :args) = await _scopeWhere(
      keywordNormalized: keywordNormalized,
      action: action,
      entityType: entityType,
      userPerforming: userPerforming,
      dateFromInclusiveIso: dateFromInclusiveIso,
      dateToExclusiveIso: dateToExclusiveIso,
    );
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
    final user = performingUser();
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

  /// Οι ετικέτες «Οντότητα - Ενέργεια» του φίλτρου «Ενέργεια», για το τρέχον
  /// φίλτρο — μία φορά η καθεμιά, ταξινομημένες ώστε να μαζεύονται ανά
  /// οντότητα.
  Future<List<String>> queryDistinctActions({
    String? entityType,
    String? userPerforming,
    String? dateFromInclusiveIso,
    String? dateToExclusiveIso,
  }) async {
    final (:whereSql, :args) = await _scopeWhere(
      entityType: entityType,
      userPerforming: userPerforming,
      dateFromInclusiveIso: dateFromInclusiveIso,
      dateToExclusiveIso: dateToExclusiveIso,
    );
    final pairs = await _distinctActionPairs(whereSql: whereSql, args: args);

    final labels = {
      for (final pair in pairs)
        if (pair.label.trim().isNotEmpty) pair.label,
    }.toList();
    labels.sort((a, b) {
      final byText = SearchTextNormalizer.normalizeForSearch(a)
          .compareTo(SearchTextNormalizer.normalizeForSearch(b));
      return byText != 0 ? byText : a.compareTo(b);
    });
    return labels;
  }

  /// Τα ονόματα που έχουν σφραγίσει εγγραφές — για το φίλτρο «Χειριστής».
  ///
  /// Επιστρέφεται και η παύλα του [CurrentOperator.unknownAuditName]. Οι
  /// εγγραφές που γράφτηκαν πριν αποκτήσει η εφαρμογή ταυτότητα χειριστή είναι
  /// η συντριπτική πλειοψηφία· το να λείπουν από τη λίστα δεν θα τις έκρυβε,
  /// θα έκανε μόνο αδύνατο να απομονωθούν.
  Future<List<String>> queryDistinctPerformingUsers({
    String? action,
    String? entityType,
    String? dateFromInclusiveIso,
    String? dateToExclusiveIso,
  }) async {
    final (:whereSql, :args) = await _scopeWhere(
      action: action,
      entityType: entityType,
      dateFromInclusiveIso: dateFromInclusiveIso,
      dateToExclusiveIso: dateToExclusiveIso,
      extraConditions: const [
        'user_performing IS NOT NULL',
        "TRIM(user_performing) <> ''",
      ],
    );
    final rows = await _db.rawQuery(
      'SELECT DISTINCT user_performing FROM audit_log $whereSql '
      'ORDER BY user_performing COLLATE NOCASE ASC',
      args,
    );

    return sortedForDisplay(
      rows
          .map((row) => (row['user_performing'] as String?)?.trim())
          .whereType<String>()
          .where((value) => value.isNotEmpty),
      (name) => [name],
    );
  }

  /// Διαγραφή παλαιότερων από [cutoff] (ISO timestamp σύγκριση).
  Future<int> deleteOlderThan(DateTime cutoff) async {
    return _db.delete(
      'audit_log',
      where: 'timestamp < ?',
      whereArgs: [cutoff.toIso8601String()],
    );
  }

  /// Πόσες γραμμές **μιας κλάσης** είναι παλαιότερες από [cutoff].
  ///
  /// Η προεπισκόπηση και η διαγραφή ρωτούν από το ίδιο σημείο: δύο χωριστά
  /// ερωτήματα θα απέκλιναν και ο χειριστής θα ενέκρινε ένα νούμερο ενώ θα
  /// εκτελούνταν άλλο.
  Future<int> countOlderThanInClass(
    AuditRetentionClass retentionClass,
    DateTime cutoff,
  ) async {
    final clause = auditRetentionClassClause(retentionClass);
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM audit_log '
      'WHERE timestamp < ? AND (${clause.sql})',
      [cutoff.toIso8601String(), ...clause.args],
    );
    return _firstCount(rows);
  }

  /// Διαγραφή των παλαιότερων γραμμών **μιας κλάσης**.
  Future<int> deleteOlderThanInClass(
    AuditRetentionClass retentionClass,
    DateTime cutoff,
  ) async {
    final clause = auditRetentionClassClause(retentionClass);
    return _db.rawDelete(
      'DELETE FROM audit_log WHERE timestamp < ? AND (${clause.sql})',
      [cutoff.toIso8601String(), ...clause.args],
    );
  }

  /// Επιστρέφει ολόκληρες τις γραμμές που θα σβηστούν — για την εξαγωγή.
  Future<List<Map<String, Object?>>> rowsOlderThanInClass(
    AuditRetentionClass retentionClass,
    DateTime cutoff,
  ) async {
    final clause = auditRetentionClassClause(retentionClass);
    return _db.rawQuery(
      'SELECT * FROM audit_log WHERE timestamp < ? AND (${clause.sql}) '
      'ORDER BY timestamp ASC, id ASC',
      [cutoff.toIso8601String(), ...clause.args],
    );
  }

  /// Πλήθος γραμμών ανά κλάση — η εικόνα που δείχνει η οθόνη συντήρησης.
  Future<Map<AuditRetentionClass, int>> countByRetentionClass() async {
    final out = <AuditRetentionClass, int>{};
    for (final value in AuditRetentionClass.values) {
      final clause = auditRetentionClassClause(value);
      final rows = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM audit_log WHERE ${clause.sql}',
        clause.args,
      );
      out[value] = _firstCount(rows);
    }
    return out;
  }

  /// **Επίπεδο 1 — συμπίεση χωρίς απώλεια.**
  ///
  /// Πετά το παραγόμενο κείμενο αναζήτησης από εγγραφές παλαιότερες του
  /// [cutoff]. Καμία γραμμή δεν χάνεται και **καμία πληροφορία**: το κείμενο
  /// είναι κανονικοποιημένο αντίγραφο των υπόλοιπων πεδίων και ξαναχτίζεται
  /// με το [rebuildAllSearchTexts].
  ///
  /// Μετρημένο σε βάση 200.000 γραμμών: 312 MB → 121 MB.
  ///
  /// Το τίμημα είναι μόνο ταχύτητα: η αναζήτηση δεν βρίσκει πια τις παλιές
  /// εγγραφές από το ευρετήριο κειμένου.
  Future<int> compactSearchTextOlderThan(DateTime cutoff) async {
    return _db.rawUpdate(
      "UPDATE audit_log SET search_text = NULL "
      "WHERE timestamp < ? AND search_text IS NOT NULL",
      [cutoff.toIso8601String()],
    );
  }

  /// Πόσες γραμμές θα πετούσαν το κείμενό τους με αυτό το όριο.
  Future<int> countCompactableOlderThan(DateTime cutoff) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM audit_log '
      'WHERE timestamp < ? AND search_text IS NOT NULL',
      [cutoff.toIso8601String()],
    );
    return _firstCount(rows);
  }

  static int _firstCount(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return 0;
    final raw = rows.first['c'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw') ?? 0;
  }

  /// Διαγραφή των παλαιότερων γραμμών ώστε να μείνουν το πολύ [keep].
  ///
  /// **Οι μόνιμες εγγραφές δεν μετρούν και δεν σβήνονται.** Το όριο πλήθους
  /// κόβει οριζόντια και αγνοεί το τι είναι η κάθε γραμμή· αν του επιτρεπόταν
  /// να αγγίξει τις δημιουργίες Καταλόγου, θα παρέκαμπτε σιωπηλά ολόκληρη τη
  /// διαβάθμιση — ένα «κράτα 1.000 γραμμές» θα έσβηνε το «ποιος έφτιαξε αυτό
  /// το τμήμα» επειδή έτυχε να είναι παλιό.
  Future<int> trimToMaxRows(int keep) async {
    if (keep <= 0) return 0;
    final permanent = auditRetentionClassClause(AuditRetentionClass.permanent);
    final erasable = 'NOT (${permanent.sql})';

    final c = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM audit_log WHERE $erasable',
      permanent.args,
    );
    final n = _firstCount(c);
    if (n <= keep) return 0;

    final toRemove = n - keep;
    return _db.rawDelete(
      'DELETE FROM audit_log WHERE id IN ('
      '  SELECT id FROM audit_log WHERE $erasable '
      '  ORDER BY timestamp ASC, id ASC LIMIT ?'
      ')',
      [...permanent.args, toRemove],
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

  /// Άρθρο Βάσης Γνώσης (entity_id = `knowledge_base.id`).
  static const String knowledge = 'knowledge';

  /// Διακομιστής της «Αποσύνδεσης χρήστη» (πίνακας `servers`). Δεν γράφει
  /// Ιστορικό· χρειάζεται μόνο για τον φύλακα «κάποιος πρόλαβε».
  static const String server = 'server';

  /// Εργαλείο απομακρυσμένης σύνδεσης (πίνακας `remote_tools`). Όπως ο
  /// [server]: μόνο για τον φύλακα «κάποιος πρόλαβε».
  static const String remoteTool = 'remote_tool';

  /// Προφίλ χειριστή της εφαρμογής — πίνακας `operators`, όχι `users`.
  ///
  /// Η σταθερά λέγεται `operatorProfile` επειδή το `operator` είναι δεσμευμένη
  /// λέξη της Dart· η τιμή που φτάνει στη βάση μένει «operator». Στην οθόνη
  /// διαβάζεται «Χρήστης» — ρητά αντιδιαστολή προς τον «Υπάλληλο» του [user],
  /// που είναι άνθρωπος του νοσοκομείου και όχι κάποιος που χειρίζεται την
  /// εφαρμογή.
  static const String operatorProfile = 'operator';
}

/// Σταθερές ενεργειών audit (ΚΕΦΑΛΑΙΑ).
abstract final class AuditActions {
  /// «ΥΠΑΛΛΗΛΟΥ» και όχι «ΧΡΗΣΤΗ»: εμφανίζεται αυτούσια στη γραμμή του
  /// ιστορικού, δίπλα στον τύπο «Υπάλληλος». Οι παλιές εγγραφές μεταφράστηκαν
  /// από την αναβάθμιση v51.
  static const String modifyUser = 'ΤΡΟΠΟΠΟΙΗΣΗ ΥΠΑΛΛΗΛΟΥ';

  /// Δημιουργία υπαλλήλου του καταλόγου — βλ. [modifyUser] για τη λέξη.
  static const String createUser = 'ΔΗΜΙΟΥΡΓΙΑ ΥΠΑΛΛΗΛΟΥ';
  static const String modifyDepartment = 'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ';
  static const String modifyEquipment = 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΞΟΠΛΙΣΜΟΥ';
  static const String modifyPhone = 'ΤΡΟΠΟΠΟΙΗΣΗ ΤΗΛΕΦΩΝΟΥ';
  static const String modifyCategory = 'ΤΡΟΠΟΠΟΙΗΣΗ ΚΑΤΗΓΟΡΙΑΣ';
  static const String modifyCall = 'ΤΡΟΠΟΠΟΙΗΣΗ ΚΛΗΣΗΣ';
  static const String modifyTask = 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΚΚΡΕΜΟΤΗΤΑΣ';

  /// Αλλαγή προφίλ χειριστή. Η λέξη «ΧΡΗΣΤΗ» είναι πλέον ελεύθερη: την άφησε
  /// ο υπάλληλος του καταλόγου όταν μετονομάστηκε σε «ΥΠΑΛΛΗΛΟΥ» (v51).
  static const String modifyOperator = 'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ';

  /// Δημιουργία προφίλ χειριστή — βλ. [modifyOperator] για τη λέξη.
  static const String createOperator = 'ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ';

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
      case AuditEntityTypes.operatorProfile:
        return modifyOperator;
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

/// Ένας συνδυασμός τύπου οντότητας και ωμής ενέργειας, όπως είναι στη βάση,
/// μαζί με την ετικέτα που βλέπει γι' αυτόν ο χρήστης.
class _AuditActionPair {
  _AuditActionPair(this.entityType, this.action)
    : label = auditActionLabelEl(entityType: entityType, action: action);

  /// Κενό όταν η εγγραφή δεν έχει τύπο.
  final String entityType;
  final String action;
  final String label;

  late final String searchLabel = SearchTextNormalizer.normalizeForSearch(
    label,
  );

  /// Ο όρος που ξεχωρίζει τις εγγραφές του ζεύγους — με τα [sqlArgs].
  static const String sqlMatch =
      "(COALESCE(entity_type, '') = ? AND action = ?)";

  List<Object?> get sqlArgs => [entityType, action];
}
