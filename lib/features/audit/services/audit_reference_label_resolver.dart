import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/audit_log_model.dart';
import '../models/audit_reference_labels.dart';

/// Batch επίλυση id τμημάτων σε ονόματα για εμφάνιση audit.
class AuditReferenceLabelResolver {
  AuditReferenceLabelResolver(this._db);

  final Database _db;

  Future<AuditReferenceLabels> resolveForRows(Iterable<AuditLogModel> rows) async {
    final ids = <int>{};
    for (final row in rows) {
      collectDepartmentIds(row, ids);
    }
    if (ids.isEmpty) return AuditReferenceLabels.empty;
    final names = await _loadDepartmentNames(ids);
    return AuditReferenceLabels(departmentNames: names);
  }

  Future<AuditReferenceLabels> resolveForRow(AuditLogModel row) =>
      resolveForRows([row]);

  static void collectDepartmentIds(AuditLogModel row, Set<int> ids) {
    for (final map in [row.oldValuesMap, row.newValuesMap]) {
      if (map == null) continue;
      _collectFromMap(map, ids);
    }
  }

  static void _collectFromMap(Map<String, dynamic> map, Set<int> ids) {
    _maybeAddDepartmentId(map['department_id'], ids);
    final fields = map['fields'];
    if (fields is Map) {
      _maybeAddDepartmentId(fields['department_id'], ids);
    }
  }

  static void _maybeAddDepartmentId(dynamic value, Set<int> ids) {
    if (value == null) return;
    if (value is int) {
      ids.add(value);
      return;
    }
    final parsed = int.tryParse(value.toString().trim());
    if (parsed != null) ids.add(parsed);
  }

  Future<Map<int, String>> _loadDepartmentNames(Set<int> ids) async {
    if (ids.isEmpty) return const {};
    final sorted = ids.toList()..sort();
    final placeholders = List.filled(sorted.length, '?').join(',');
    final rows = await _db.rawQuery(
      'SELECT id, name FROM departments WHERE id IN ($placeholders)',
      sorted,
    );
    final out = <int, String>{};
    for (final row in rows) {
      final id = row['id'] as int?;
      final name = (row['name'] as String?)?.trim();
      if (id != null && name != null && name.isNotEmpty) {
        out[id] = name;
      }
    }
    return out;
  }
}
