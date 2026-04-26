import 'dart:convert';

import '../../../core/database/database_helper.dart';
import '../models/audit_log_model.dart';

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

  /// Μήνυμα μίας γραμμής για τη λίστα.
  String summaryLine(AuditLogModel row, {bool technical = false}) {
    final bulk = _parseBulk(row.newValuesJson);
    if (bulk != null) {
      return _formatBulk(row, bulk, technical: technical);
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
      final change = primaryChangeLine(row, technical: technical);
      if (change != null && change.isNotEmpty) {
        return '$main - $change';
      }
      if (main.trim().isNotEmpty) return main;
      if (row.details != null && row.details!.trim().isNotEmpty) {
        return row.details!.trim();
      }
      return '—';
    }

    final action = _actionLabel(row.action ?? '', technical);
    final subject = type != null && type.isNotEmpty
        ? _entitySummarySubject(type, eid, effectiveName, technical: technical)
        : (row.details?.trim() ?? '');
    final base = [action, subject].where((e) => e.trim().isNotEmpty).join(' · ');
    final change = primaryChangeLine(row, technical: technical);
    if (change != null && change.isNotEmpty) {
      if (base.isEmpty) return change;
      return '$base - $change';
    }
    if (base.isNotEmpty) return base;
    if (row.details != null) {
      return row.details!.trim();
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

    final keys = _orderedDiffKeys(
      normalizedType,
      oldMap.keys.toSet().union(newMap.keys.toSet()),
    );
    final lines = <String>[];
    for (final key in keys) {
      final hasOld = oldMap.containsKey(key);
      final hasNew = newMap.containsKey(key);
      if (!hasOld && !hasNew) continue;
      final oldValue = oldMap[key];
      final newValue = newMap[key];
      if (_valuesEqual(oldValue, newValue)) continue;
      final line = _diffLineForField(
        entityType: normalizedType,
        field: key,
        oldValue: oldValue,
        hasOld: hasOld,
        newValue: newValue,
        hasNew: hasNew,
        technical: technical,
      );
      if (line != null && line.trim().isNotEmpty) {
        if (skipIfEquals != null && line == skipIfEquals) continue;
        lines.add(line);
      }
    }
    return lines;
  }

  String? primaryChangeLine(AuditLogModel row, {bool technical = false}) {
    final lines = describeChanges(row, technical: technical);
    return lines.isEmpty ? null : lines.first;
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
      case 'phone':
        return 'Τηλέφωνο';
      default:
        return type;
    }
  }

  List<String> _orderedDiffKeys(String entityType, Set<String> keys) {
    final order = switch (entityType) {
      'call' => const [
          'status',
          'category_text',
          'category_id',
          'caller_text',
          'caller_id',
          'phone_text',
          'department_text',
          'equipment_text',
          'equipment_id',
          'issue',
          'solution',
          'duration',
          'is_priority',
        ],
      'task' => const [
          'status',
          'priority',
          'due_date',
          'solution_notes',
          'title',
          'description',
          'department_text',
          'user_text',
          'equipment_text',
          'phone_text',
        ],
      'department' => const [
          'name',
          'color',
          'building',
          'map_floor',
          'floor_id',
          'notes',
          'map_x',
          'map_y',
          'map_width',
          'map_height',
          'map_rotation',
        ],
      'user' => const [
          'department_id',
          'department_text',
          'email',
          'phone',
          'linked_phone_numbers',
          'linked_equipment',
        ],
      'equipment' => const [
          'department_id',
          'type',
          'custom_ip',
          'linked_users',
        ],
      'phone' => const ['linked_user_id', 'department_id'],
      _ => const <String>[],
    };
    final out = <String>[];
    for (final k in order) {
      if (keys.contains(k)) out.add(k);
    }
    final rest = keys.where((k) => !out.contains(k)).toList()..sort();
    out.addAll(rest);
    return out;
  }

  String? _diffLineForField({
    required String entityType,
    required String field,
    required dynamic oldValue,
    required bool hasOld,
    required dynamic newValue,
    required bool hasNew,
    required bool technical,
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
      final o = oldValue == null ? null : '#$oldValue';
      final n = newValue == null ? null : '#$newValue';
      if (o == null && n != null) return 'Σύνδεση σε τμήμα $n';
      if (o != null && n == null) return 'Αποσύνδεση από τμήμα $o';
      if (o != null && n != null) return 'Μεταφορά από τμήμα $o σε $n';
    }

    final label = _fieldLabel(entityType, field);
    final oldFmt = _friendlyValue(entityType, field, oldValue, technical: technical);
    final newFmt = _friendlyValue(entityType, field, newValue, technical: technical);
    final hasOldValue = hasOld && !_isEmptyLike(oldValue);
    final hasNewValue = hasNew && !_isEmptyLike(newValue);

    if (!hasOldValue && hasNewValue) return 'Προσθήκη $label $newFmt';
    if (hasOldValue && !hasNewValue) return 'Αφαίρεση $label $oldFmt';
    return 'Αλλαγή $label από $oldFmt σε $newFmt';
  }

  String _fieldLabel(String entityType, String field) {
    const common = <String, String>{
      'name': 'ονόματος',
      'email': 'email',
      'phone': 'τηλεφώνου',
      'status': 'κατάστασης',
      'priority': 'προτεραιότητας',
      'due_date': 'προθεσμίας',
      'title': 'τίτλου',
      'description': 'περιγραφής',
      'solution_notes': 'λύσης',
      'department_id': 'τμήματος',
      'department_text': 'τμήματος',
      'equipment_id': 'εξοπλισμού',
      'equipment_text': 'εξοπλισμού',
      'caller_id': 'χρήστη',
      'caller_text': 'χρήστη',
      'phone_text': 'τηλεφώνου',
      'category_text': 'κατηγορίας',
      'category_id': 'κατηγορίας',
      'issue': 'θέματος',
      'solution': 'λύσης',
      'type': 'τύπου',
      'custom_ip': 'IP',
      'linked_users': 'συνδεδεμένων χρηστών',
      'linked_equipment': 'συνδεδεμένου εξοπλισμού',
      'linked_phone_numbers': 'τηλεφώνων',
      'linked_user_id': 'χρήστη',
      'color': 'χρώματος',
      'building': 'κτιρίου',
      'map_floor': 'ορόφου',
      'floor_id': 'ορόφου',
      'notes': 'σημειώσεων',
      'map_x': 'θέσης Χ',
      'map_y': 'θέσης Υ',
      'map_width': 'πλάτους',
      'map_height': 'ύψους',
      'map_rotation': 'περιστροφής',
    };
    final label = common[field];
    if (label != null) return label;
    if (entityType.isEmpty) return 'πεδίου $field';
    return 'πεδίου $field';
  }

  String _friendlyValue(
    String entityType,
    String field,
    dynamic value, {
    required bool technical,
  }) {
    if (value == null) return 'κενό';
    if (field == 'status') {
      final s = value.toString().trim().toLowerCase();
      const map = <String, String>{
        'pending': 'Εκκρεμής',
        'completed': 'Ολοκληρωμένη',
        'closed': 'Κλειστή',
        'open': 'Ανοιχτή',
        'in_progress': 'Σε εξέλιξη',
      };
      return map[s] ?? value.toString();
    }
    if (field == 'priority') {
      final s = value.toString().trim().toLowerCase();
      const map = <String, String>{
        'low': 'Χαμηλή',
        'normal': 'Κανονική',
        'medium': 'Μεσαία',
        'high': 'Υψηλή',
        'urgent': 'Επείγουσα',
      };
      return map[s] ?? value.toString();
    }
    if (field == 'color') {
      return _friendlyColor(value.toString());
    }
    if (field == 'map_floor') {
      return _fmtFloorValue(value) ?? 'χωρίς όροφο';
    }
    if (value is List) {
      if (technical) return 'λίστα ${value.length} στοιχείων';
      return '${value.length} στοιχεία';
    }
    if (value is Map) {
      if (technical) return 'δομή';
      return 'δομημένα δεδομένα';
    }
    final t = value.toString().trim();
    return t.isEmpty ? 'κενό' : t;
  }

  bool _valuesEqual(dynamic a, dynamic b) {
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

  bool _isEmptyLike(dynamic value) {
    if (value == null) return true;
    if (value is String) return value.trim().isEmpty;
    if (value is List) return value.isEmpty;
    if (value is Map) return value.isEmpty;
    return false;
  }

  String _friendlyColor(String raw) {
    final r = raw.trim().toUpperCase();
    const known = <String, String>{
      '#1976D2': 'Μπλε',
      '#EF5350': 'Κόκκινο',
      '#4CAF50': 'Πράσινο',
      '#FFC107': 'Κίτρινο',
      '#9C27B0': 'Μωβ',
    };
    return known[r] ?? raw;
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
  }) {
    final ids = bulk['affected_ids'];
    final fields = bulk['fields'];
    final n = ids is List ? ids.length : 0;
    final fieldNames = fields is Map
        ? fields.keys
            .map((k) => _fieldLabel(row.entityType ?? '', '$k'))
            .toSet()
            .toList()
        : const <String>[];
    final fieldStr = fieldNames.join(', ');
    final action = _actionLabel(row.action ?? '', technical);
    final entity = _entityTypeGreekPlural(row.entityType ?? '');
    if (technical) {
      return '$action · $entity · ids=$n${fieldStr.isNotEmpty ? ' · {$fieldStr}' : ''}';
    }
    return '$action · Επηρέασε $n $entity${fieldStr.isNotEmpty ? ' - Πεδία: $fieldStr' : ''}';
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
