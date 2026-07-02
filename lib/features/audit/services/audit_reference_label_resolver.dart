import '../../../core/database/department_repository.dart';
import '../../../core/database/sqlite_types.dart';

import '../models/audit_log_model.dart';
import '../models/audit_reference_labels.dart';

/// Batch επίλυση id τμημάτων σε ονόματα για εμφάνιση audit.
class AuditReferenceLabelResolver {
  AuditReferenceLabelResolver(this._departments);

  final DepartmentRepository _departments;

  factory AuditReferenceLabelResolver.fromDatabase(Database db) {
    return AuditReferenceLabelResolver(DepartmentRepository(db));
  }

  Future<AuditReferenceLabels> resolveForRows(Iterable<AuditLogModel> rows) async {
    final ids = <int>{};
    for (final row in rows) {
      collectDepartmentIds(row, ids);
    }
    if (ids.isEmpty) return AuditReferenceLabels.empty;
    final names = await _departments.getDepartmentNamesByIds(ids);
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
}
