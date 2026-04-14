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
      final parts = <String>[];
      if (row.action != null && row.action!.trim().isNotEmpty) {
        parts.add(_actionLabel(row.action!, technical));
      }
      final dash = _callAuditDashContext(row);
      if (dash != null && dash.isNotEmpty) {
        parts.add(dash);
      }
      if (parts.isEmpty && row.details != null && row.details!.trim().isNotEmpty) {
        return row.details!.trim();
      }
      if (parts.isEmpty) {
        return row.details?.trim().isNotEmpty == true
            ? row.details!.trim()
            : '—';
      }
      return parts.join(' · ');
    }

    final parts = <String>[];
    if (row.action != null && row.action!.trim().isNotEmpty) {
      parts.add(_actionLabel(row.action!, technical));
    }

    if (type != null && type.isNotEmpty) {
      parts.add(
        _entityLabel(
          type,
          eid,
          effectiveName,
          technical: technical,
        ),
      );
    } else if (row.details != null && row.details!.trim().isNotEmpty) {
      parts.add(row.details!.trim());
    }
    if (parts.isEmpty && row.details != null) {
      return row.details!.trim();
    }
    return parts.join(' · ');
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
    if (a == DatabaseHelper.auditActionDelete) return 'Διαγραφή';
    if (a == DatabaseHelper.auditActionRestore) return 'Επαναφορά';
    if (a == DatabaseHelper.auditActionBulkDelete) return 'Μαζική διαγραφή';
    if (a == 'ΤΡΟΠΟΠΟΙΗΣΗ') return 'Τροποποίηση';
    return a;
  }

  /// Ετικέτα οντότητας: τεχνικό `table id=` · φιλικό `Γενική πτώση: όνομα`.
  String _entityLabel(
    String type,
    int? id,
    String? name, {
    required bool technical,
  }) {
    final t = type.trim();
    if (technical) {
      if (id != null && name != null && name.isNotEmpty) {
        return '$t · $name (id $id)';
      }
      if (id != null) return '$t id=$id';
      return t;
    }

    final gen = _entityGenitiveHeading(t);
    final displayName = name?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return '$gen: $displayName';
    }
    if (id != null) {
      return '$gen #$id';
    }
    return gen;
  }

  /// Κεφαλίδα σε γενική (για προτάσεις τύπου «Εκκρεμότητας: …»).
  String _entityGenitiveHeading(String type) {
    switch (type) {
      case 'user':
        return 'Χρήστη';
      case 'department':
        return 'Τμήματος';
      case 'equipment':
        return 'Εξοπλισμού';
      case 'category':
        return 'Κατηγορίας';
      case 'task':
        return 'Εκκρεμότητας';
      case 'call':
        return 'Κλήσης';
      case 'bulk_users':
        return 'Μαζικής ενημέρωσης χρηστών';
      case 'bulk_departments':
        return 'Μαζικής ενημέρωσης τμημάτων';
      case 'bulk_equipment':
        return 'Μαζικής ενημέρωσης εξοπλισμού';
      case 'import_data':
        return 'Δεδομένων εισαγωγής';
      case 'maintenance':
        return 'Συντήρησης βάσης';
      case 'phone':
        return 'Τηλεφώνου';
      default:
        return _entityTypeGreek(type);
    }
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
    final fieldStr = fields is Map
        ? fields.entries.map((e) => '${e.key}=${e.value}').join(', ')
        : '';
    final action = _actionLabel(row.action ?? '', technical);
    final entity = _entityTypeGreek(row.entityType ?? '');
    if (technical) {
      return '$action · $entity · ids=$n · {$fieldStr}';
    }
    return '$action: $n επηρεασμένες εγγραφές${fieldStr.isNotEmpty ? ' ($fieldStr)' : ''}.';
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
