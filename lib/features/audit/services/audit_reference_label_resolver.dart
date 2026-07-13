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
    final deptIds = <int>{};
    for (final row in rows) {
      collectDepartmentIds(row, deptIds);
    }
    final departmentNames = deptIds.isEmpty
        ? const <int, String>{}
        : await _departments.getDepartmentNamesByIds(deptIds);
    final remoteToolNames = await _loadRemoteToolNames();
    if (departmentNames.isEmpty && remoteToolNames.isEmpty) {
      return AuditReferenceLabels.empty;
    }
    return AuditReferenceLabels(
      departmentNames: departmentNames,
      remoteToolNames: remoteToolNames,
    );
  }

  Future<Map<int, String>> _loadRemoteToolNames() async {
    final rows = await _departments.db.query(
      'remote_tools',
      columns: ['id', 'name'],
    );
    final out = <int, String>{};
    for (final row in rows) {
      final idRaw = row['id'];
      final id = idRaw is int ? idRaw : int.tryParse('$idRaw');
      if (id == null) continue;
      final name = (row['name'] as String?)?.trim() ?? '';
      if (name.isNotEmpty) out[id] = name;
    }
    return out;
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
