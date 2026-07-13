import 'dart:convert';

import '../../../core/database/audit_diff_helper.dart';
import '../../../core/database/audit_service.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_support.dart';
import '../models/audit_log_model.dart';
import '../models/audit_reference_labels.dart';

/// Μορφοποίηση εγγραφών audit σε φυσικά ελληνικά (απλός/τεχνικός τόνος).
class AuditFormatterService {
  const AuditFormatterService();

  /// Ημέρα (3 γράμματα) · ημερομηνία · 24ωρη ώρα, σε τοπική ζώνη.
  /// Π.χ. `Πεμ 13-04-2026 19:23`
  String formatAuditTimestamp(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '—';
    final d = DateTime.tryParse(iso.trim());
    if (d == null) return iso.trim();
    final l = d.toLocal();
    const wd = ['Δευ', 'Τρι', 'Τετ', 'Πεμ', 'Παρ', 'Σαβ', 'Κυρ'];
    final w = wd[l.weekday - 1];
    final dd = l.day.toString().padLeft(2, '0');
    final mm = l.month.toString().padLeft(2, '0');
    final yyyy = l.year.toString();
    final hh = l.hour.toString().padLeft(2, '0');
    final min = l.minute.toString().padLeft(2, '0');
    return '$w $dd-$mm-$yyyy $hh:$min';
  }

  /// Διακριτή γραμμή προέλευσης παράγωγης εγγραφής (κάτω από τίτλο λεπτομερειών).
  String? originDisplayLine(AuditLogModel row) =>
      DirectorySupport.auditOriginDisplayLine(row.details);

  /// Λεπτομέρειες χωρίς suffix προέλευσης (για εμφάνιση κειμένου).
  String? detailsWithoutOrigin(AuditLogModel row) {
    final stripped = DirectorySupport.stripAuditOriginSuffix(row.details);
    return stripped.isEmpty ? null : stripped;
  }

  /// Μήνυμα μίας γραμμής για τη λίστα.
  String summaryLine(
    AuditLogModel row, {
    bool technical = false,
    AuditReferenceLabels labels = AuditReferenceLabels.empty,
  }) {
    final bulk = _parseBulk(row.newValuesJson);
    if (bulk != null) {
      return _formatBulk(
        row,
        bulk,
        technical: technical,
        labels: labels,
      );
    }

    var type = row.entityType?.trim();
    int? eid = row.entityId;

    if (type == null || type.isEmpty) {
      final parsed = _parseDetailsTableId(row.details);
      if (parsed != null) {
        type = parsed.$1;
        eid = parsed.$2;
      }
    } else {
      type = _normalizeEntityType(type);
    }

    final inferredName = _titleFromJson(row);
    final effectiveName =
        (row.entityName?.trim().isNotEmpty == true)
            ? row.entityName!.trim()
            : inferredName;

    if (type == 'call' && !technical) {
      final action = _actionLabel(row.action ?? '', technical);
      final dash = _callAuditDashContext(row);
      final subject = dash != null && dash.isNotEmpty ? dash : 'Κλήση';
      final main = action.isEmpty ? subject : '$action · $subject';
      final change = primaryChangeLine(
        row,
        technical: technical,
        labels: labels,
      );
      if (change != null && change.isNotEmpty) {
        return '$main - $change';
      }
      if (main.trim().isNotEmpty) return main;
      final detailsOnly = detailsWithoutOrigin(row);
      if (detailsOnly != null && detailsOnly.isNotEmpty) {
        return detailsOnly;
      }
      return '—';
    }

    final action = _actionLabel(row.action ?? '', technical);
    final subject = type != null && type.isNotEmpty
        ? _entitySummarySubject(type, eid, effectiveName, technical: technical)
        : (detailsWithoutOrigin(row) ?? '');
    final base = [action, subject].where((e) => e.trim().isNotEmpty).join(' · ');
    final change = primaryChangeLine(
      row,
      technical: technical,
      labels: labels,
    );
    if (change != null && change.isNotEmpty) {
      if (base.isEmpty) return change;
      return '$base - $change';
    }
    if (base.isNotEmpty) return base;
    final detailsOnly = detailsWithoutOrigin(row);
    if (detailsOnly != null) {
      return detailsOnly;
    }
    return '—';
  }

  /// `entity_name` (νέες εγγραφές) ή συγχώνευση `old/new_values_json` (παλιές).
  String? _callAuditDashContext(AuditLogModel row) {
    final stored = row.entityName?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    return _callDashFromMergedJson(row);
  }

  static const List<String> _kCallAuditDashJsonKeys = [
    'phone_text',
    'caller_text',
    'department_text',
    'equipment_text',
  ];

  String? _callDashFromMergedJson(AuditLogModel row) {
    final parts = <String>[];
    for (final key in _kCallAuditDashJsonKeys) {
      final s = _mergedJsonField(row, key);
      if (s != null && s.isNotEmpty) parts.add(s);
    }
    if (parts.isEmpty) return null;
    return parts.join(' - ');
  }

  String? _mergedJsonField(AuditLogModel row, String key) {
    final neu = row.newValuesMap;
    final old = row.oldValuesMap;
    if (neu != null && neu.containsKey(key)) {
      final t = neu[key]?.toString().trim() ?? '';
      if (t.isNotEmpty) return t;
      return null;
    }
    if (old != null && old.containsKey(key)) {
      final t = old[key]?.toString().trim() ?? '';
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  /// `title` / `name` από old/new JSON όταν λείπει `entity_name` (π.χ. παλιές εγγραφές).
  String? _titleFromJson(AuditLogModel row) {
    for (final raw in [row.newValuesJson, row.oldValuesJson]) {
      if (raw == null || raw.trim().isEmpty) continue;
      try {
        final d = jsonDecode(raw);
        if (d is! Map) continue;
        final m = Map<String, dynamic>.from(d);
        final t = m['title']?.toString().trim();
        if (t != null && t.isNotEmpty) return t;
        final n = m['name']?.toString().trim();
        if (n != null && n.isNotEmpty) return n;
      } catch (_) {}
    }
    return null;
  }

  static final RegExp _detailsTableId = RegExp(
    r'^([a-zA-Z_]+)\s+id=(\d+)',
  );

  /// Επιστρέφει canonical `entity_type` και id από `details` π.χ. `tasks id=48`.
  (String, int)? _parseDetailsTableId(String? details) {
    if (details == null) return null;
    final m = _detailsTableId.firstMatch(details.trim());
    if (m == null) return null;
    final table = m.group(1);
    final idStr = m.group(2);
    if (table == null || idStr == null) return null;
    final id = int.tryParse(idStr);
    if (id == null) return null;
    return (_normalizeEntityType(table.toLowerCase()), id);
  }

  String _normalizeEntityType(String raw) {
    switch (raw) {
      case 'tasks':
        return 'task';
      case 'users':
        return 'user';
      case 'departments':
        return 'department';
      case 'equipment':
        return 'equipment';
      case 'categories':
        return 'category';
      case 'calls':
        return 'call';
      default:
        return raw;
    }
  }

  String _actionLabel(String action, bool technical) {
    if (technical) return action;
    final a = action.trim();
    if (a.isEmpty) return '';
    if (a == DatabaseHelper.auditActionDelete) return 'Διαγραφή';
    if (a == DatabaseHelper.auditActionRestore) return 'Επαναφορά';
    if (a == DatabaseHelper.auditActionBulkDelete) return 'Μαζική διαγραφή';
    if (a == 'ΤΡΟΠΟΠΟΙΗΣΗ') return 'Τροποποίηση';
    return a;
  }

  /// Συντομευμένο subject για μία γραμμή σύνοψης.
  String _entitySummarySubject(
    String type,
    int? id,
    String? name, {
    required bool technical,
  }) {
    final t = type.trim();
    if (technical) {
      if (id != null && name != null && name.isNotEmpty) {
        return '$name (id $id)';
      }
      return name?.trim().isNotEmpty == true ? name!.trim() : _entityTypeGreek(t);
    }
    final displayName = name?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    if (id != null) return '${_entityTypeGreek(t)} #$id';
    return _entityTypeGreek(t);
  }

  List<String> describeChanges(
    AuditLogModel row, {
    bool technical = false,
    String? skipIfEquals,
    AuditReferenceLabels labels = AuditReferenceLabels.empty,
  }) {
    final oldMap = row.oldValuesMap ?? const <String, dynamic>{};
    final newMap = row.newValuesMap ?? const <String, dynamic>{};
    if (oldMap.isEmpty && newMap.isEmpty) return const <String>[];

    var type = row.entityType?.trim();
    if (type == null || type.isEmpty) {
      final parsed = _parseDetailsTableId(row.details);
      if (parsed != null) type = parsed.$1;
    }
    final normalizedType = type == null ? '' : _normalizeEntityType(type);

    final allKeys = oldMap.keys.toSet().union(newMap.keys.toSet());
    final keys = AuditDiffHelper.orderedDiffKeys(normalizedType, allKeys);
    final lines = <String>[];
    for (final key in keys) {
      if (AuditDiffHelper.shouldSkipDerivativeField(key, allKeys)) continue;
      final hasOld = oldMap.containsKey(key);
      final hasNew = newMap.containsKey(key);
      if (!hasOld && !hasNew) continue;
      final oldValue = oldMap[key];
      final newValue = newMap[key];
      if (!AuditService.shouldIncludeFieldInAuditDiff(key, oldValue, newValue)) {
        continue;
      }
      if (normalizedType == 'equipment' && key == 'remote_params') {
        final toolLines = AuditDiffHelper.describeRemoteParamsDiffLines(
          oldValue: oldValue,
          newValue: newValue,
          toolNames: labels.remoteToolNames,
        );
        if (toolLines.length == 1) {
          final line =
              'Αλλαγή παραμέτρων απομακρυσμένης · ${toolLines.first}';
          if (skipIfEquals == null || line != skipIfEquals) {
            lines.add(line);
          }
        } else {
          for (final line in toolLines) {
            if (line.trim().isEmpty) continue;
            if (skipIfEquals != null && line == skipIfEquals) continue;
            lines.add(line);
          }
        }
        continue;
      }
      final line = _diffLineForField(
        entityType: normalizedType,
        field: key,
        oldValue: oldValue,
        hasOld: hasOld,
        newValue: newValue,
        hasNew: hasNew,
        technical: technical,
        oldMap: oldMap,
        newMap: newMap,
        labels: labels,
      );
      if (line != null && line.trim().isNotEmpty) {
        if (skipIfEquals != null && line == skipIfEquals) continue;
        lines.add(line);
      }
    }
    return lines;
  }

  String? primaryChangeLine(
    AuditLogModel row, {
    bool technical = false,
    AuditReferenceLabels labels = AuditReferenceLabels.empty,
  }) {
    final lines = describeChanges(
      row,
      technical: technical,
      labels: labels,
    );
    if (lines.isEmpty) return null;
    if (lines.length == 1) return lines.first;
    final fieldLabels = _changedFieldTitleLabels(
      row,
      technical: technical,
      labels: labels,
    );
    if (fieldLabels.isEmpty) {
      return '${lines.length} αλλαγές';
    }
    return '${lines.length} αλλαγές: ${fieldLabels.join(', ')}';
  }

  List<String> _changedFieldTitleLabels(
    AuditLogModel row, {
    required bool technical,
    required AuditReferenceLabels labels,
  }) {
    final oldMap = row.oldValuesMap ?? const <String, dynamic>{};
    final newMap = row.newValuesMap ?? const <String, dynamic>{};
    if (oldMap.isEmpty && newMap.isEmpty) return const <String>[];

    var type = row.entityType?.trim();
    if (type == null || type.isEmpty) {
      final parsed = _parseDetailsTableId(row.details);
      if (parsed != null) type = parsed.$1;
    }
    final normalizedType = type == null ? '' : _normalizeEntityType(type);

    return AuditDiffHelper.changedFieldTitleLabels(
      entityType: normalizedType,
      oldMap: oldMap,
      newMap: newMap,
    );
  }

  String _entityTypeGreek(String type) {
    switch (type) {
      case 'user':
        return 'Χρήστης';
      case 'department':
        return 'Τμήμα';
      case 'equipment':
        return 'Εξοπλισμός';
      case 'category':
        return 'Κατηγορία';
      case 'task':
        return 'Εκκρεμότητα';
      case 'call':
        return 'Κλήση';
      case 'bulk_users':
        return 'Μαζική ενημέρωση χρηστών';
      case 'bulk_departments':
        return 'Μαζική ενημέρωση τμημάτων';
      case 'bulk_equipment':
        return 'Μαζική ενημέρωση εξοπλισμού';
      case 'import_data':
        return 'Δεδομένα εισαγωγής';
      case 'maintenance':
        return 'Συντήρηση βάσης';
      case 'backup':
        return 'Αντίγραφο ασφαλείας';
      case 'phone':
        return 'Τηλέφωνο';
      default:
        return type;
    }
  }

  String? _diffLineForField({
    required String entityType,
    required String field,
    required dynamic oldValue,
    required bool hasOld,
    required dynamic newValue,
    required bool hasNew,
    required bool technical,
    required Map<String, dynamic> oldMap,
    required Map<String, dynamic> newMap,
    required AuditReferenceLabels labels,
  }) {
    if (entityType == 'department' && field == 'map_floor') {
      final oldFloor = _fmtFloorValue(oldValue);
      final newFloor = _fmtFloorValue(newValue);
      if ((oldFloor == null || oldFloor == 'χωρίς όροφο') &&
          newFloor != null &&
          newFloor != 'χωρίς όροφο') {
        return 'Προσθήκη στον όροφο $newFloor';
      }
      if (oldFloor != null &&
          oldFloor != 'χωρίς όροφο' &&
          (newFloor == null || newFloor == 'χωρίς όροφο')) {
        return 'Αφαίρεση από όροφο $oldFloor';
      }
      if (oldFloor != null && newFloor != null) {
        return 'Αλλαγή ορόφου από $oldFloor σε $newFloor';
      }
    }

    if (entityType == 'phone' && field == 'linked_user_id') {
      final o = oldValue == null ? null : '#$oldValue';
      final n = newValue == null ? null : '#$newValue';
      if (o == null && n != null) return 'Σύνδεση σε χρήστη $n';
      if (o != null && n == null) return 'Αποσύνδεση από χρήστη $o';
      if (o != null && n != null) return 'Μεταφορά από χρήστη $o σε $n';
    }
    if (entityType == 'phone' && field == 'department_id') {
      final o = _formatDepartmentReference(
        oldValue,
        oldMap,
        technical: technical,
        labels: labels,
      );
      final n = _formatDepartmentReference(
        newValue,
        newMap,
        technical: technical,
        labels: labels,
      );
      if (o == null && n != null) return 'Σύνδεση σε τμήμα $n';
      if (o != null && n == null) return 'Αποσύνδεση από τμήμα $o';
      if (o != null && n != null) return 'Μεταφορά από τμήμα $o σε $n';
    }

    if (entityType == 'equipment' && field == 'remote_params') {
      final toolLines = AuditDiffHelper.describeRemoteParamsDiffLines(
        oldValue: oldValue,
        newValue: newValue,
        toolNames: labels.remoteToolNames,
      );
      if (toolLines.isEmpty) return null;
      return toolLines.join(' · ');
    }

    final label = AuditDiffHelper.fieldDetailLabel(entityType, field);
    final oldFmt = _friendlyValue(
      entityType,
      field,
      oldValue,
      technical: technical,
      sideMap: oldMap,
      labels: labels,
    );
    final newFmt = _friendlyValue(
      entityType,
      field,
      newValue,
      technical: technical,
      sideMap: newMap,
      labels: labels,
    );
    final hasOldValue = hasOld && !_isEmptyLike(oldValue);
    final hasNewValue = hasNew && !_isEmptyLike(newValue);

    if (!hasOldValue && hasNewValue) return 'Προσθήκη $label $newFmt';
    if (hasOldValue && !hasNewValue) return 'Αφαίρεση $label $oldFmt';
    return 'Αλλαγή $label από $oldFmt σε $newFmt';
  }

  String _friendlyValue(
    String entityType,
    String field,
    dynamic value, {
    required bool technical,
    Map<String, dynamic> sideMap = const {},
    AuditReferenceLabels labels = AuditReferenceLabels.empty,
  }) {
    if (value == null) return 'κενό';
    if (field == 'department_id') {
      final formatted = _formatDepartmentReference(
        value,
        sideMap,
        technical: technical,
        labels: labels,
      );
      return formatted ?? 'κενό';
    }
    if (technical && field == 'remote_params') {
      return 'δομή';
    }
    return AuditDiffHelper.humanizeFieldValue(
      field,
      value,
      sideMap: sideMap,
      forSearch: false,
    );
  }

  String? _formatDepartmentReference(
    dynamic value,
    Map<String, dynamic> sideMap, {
    required bool technical,
    required AuditReferenceLabels labels,
  }) {
    if (value == null || _isEmptyLike(value)) return null;
    if (technical) return '#$value';
    final text = sideMap['department_text']?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
    final id = _parseIntId(value);
    final resolved = labels.departmentName(id);
    if (resolved != null) return resolved;
    return '#$value';
  }

  int? _parseIntId(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value.toString().trim());
  }

  bool _isEmptyLike(dynamic value) {
    if (value == null) return true;
    if (value is String) return value.trim().isEmpty;
    if (value is List) return value.isEmpty;
    if (value is Map) return value.isEmpty;
    return false;
  }

  String? _fmtFloorValue(dynamic v) {
    if (v == null) return 'χωρίς όροφο';
    final t = v.toString().trim();
    if (t.isEmpty) return 'χωρίς όροφο';
    return t;
  }

  Map<String, dynamic>? _parseBulk(String? json) {
    if (json == null || json.trim().isEmpty) return null;
    try {
      final d = jsonDecode(json) as Map<String, dynamic>?;
      if (d == null) return null;
      if (d.containsKey('affected_ids') && d.containsKey('fields')) {
        return d;
      }
    } catch (_) {}
    return null;
  }

  String _formatBulk(
    AuditLogModel row,
    Map<String, dynamic> bulk, {
    required bool technical,
    AuditReferenceLabels labels = AuditReferenceLabels.empty,
  }) {
    final ids = bulk['affected_ids'];
    final fields = bulk['fields'];
    final n = ids is List ? ids.length : 0;
    final fieldNames = fields is Map
        ? _bulkFieldLabels(
            entityType: row.entityType ?? '',
            fields: Map<String, dynamic>.from(fields),
            technical: technical,
            labels: labels,
          )
        : const <String>[];
    final fieldStr = fieldNames.join(', ');
    final action = _actionLabel(row.action ?? '', technical);
    final entity = _entityTypeGreekPlural(row.entityType ?? '');
    if (technical) {
      return '$action · $entity · ids=$n${fieldStr.isNotEmpty ? ' · {$fieldStr}' : ''}';
    }
    return '$action · Επηρέασε $n $entity${fieldStr.isNotEmpty ? ' - Πεδία: $fieldStr' : ''}';
  }

  List<String> _bulkFieldLabels({
    required String entityType,
    required Map<String, dynamic> fields,
    required bool technical,
    required AuditReferenceLabels labels,
  }) {
    final out = <String>[];
    for (final key in fields.keys) {
      if (key == 'department_text' && fields.containsKey('department_id')) {
        continue;
      }
      final label = AuditDiffHelper.fieldDetailLabel(entityType, key);
      if (key == 'department_id' && !technical) {
        final name = _formatDepartmentReference(
          fields['department_id'],
          fields,
          technical: false,
          labels: labels,
        );
        if (name != null) {
          out.add('$label ($name)');
          continue;
        }
      }
      out.add(label);
    }
    return out.toSet().toList();
  }

  String _entityTypeGreekPlural(String type) {
    switch (type) {
      case 'call':
        return 'κλήσεις';
      case 'task':
        return 'εκκρεμότητες';
      case 'user':
      case 'bulk_users':
        return 'χρήστες';
      case 'department':
      case 'bulk_departments':
        return 'τμήματα';
      case 'equipment':
      case 'bulk_equipment':
        return 'εξοπλισμοί';
      case 'phone':
        return 'τηλέφωνα';
      case 'category':
        return 'κατηγορίες';
      default:
        return 'εγγραφές';
    }
  }

  /// Ανάγνωση πεδίων για εμφάνιση «Πριν/Μετά».
  String prettyJsonBlock(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '—';
    try {
      final d = jsonDecode(raw);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(d);
    } catch (_) {
      return raw;
    }
  }
}
