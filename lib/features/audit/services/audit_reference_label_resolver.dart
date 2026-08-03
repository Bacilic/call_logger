import '../../../core/database/department_repository.dart';
import '../../../core/database/remote_tools_repository.dart';
import '../../../core/database/sqlite_types.dart';
import '../../../core/database/user_repository.dart';
import '../models/audit_log_model.dart';
import '../models/audit_reference_labels.dart';

/// Batch επίλυση id αναφορών (τμήματα, χρήστες, εργαλεία) σε ονόματα για εμφάνιση audit.
class AuditReferenceLabelResolver {
  AuditReferenceLabelResolver(this._departments);

  final DepartmentRepository _departments;

  factory AuditReferenceLabelResolver.fromDatabase(Database db) {
    return AuditReferenceLabelResolver(DepartmentRepository(db));
  }

  Future<AuditReferenceLabels> resolveForRows(
    Iterable<AuditLogModel> rows,
  ) async {
    final deptIds = <int>{};
    final userIds = <int>{};
    for (final row in rows) {
      collectDepartmentIds(row, deptIds);
      collectUserIds(row, userIds);
    }
    final departmentNames = deptIds.isEmpty
        ? const <int, String>{}
        : await _departments.getDepartmentNamesByIds(deptIds);
    final userNames = await _loadUserNames(userIds);
    final remoteToolNames = await _loadRemoteToolNames();
    if (departmentNames.isEmpty &&
        remoteToolNames.isEmpty &&
        userNames.isEmpty) {
      return AuditReferenceLabels.empty;
    }
    return AuditReferenceLabels(
      departmentNames: departmentNames,
      remoteToolNames: remoteToolNames,
      userNames: userNames,
    );
  }

  Future<Map<int, String>> _loadRemoteToolNames() =>
      loadRemoteToolNamesById(_departments.db);

  Future<Map<int, String>> _loadUserNames(Set<int> ids) =>
      UserRepository(_departments.db).getUserDisplayNamesByIds(ids);

  Future<AuditReferenceLabels> resolveForRow(AuditLogModel row) =>
      resolveForRows([row]);

  static void collectDepartmentIds(AuditLogModel row, Set<int> ids) {
    for (final map in [row.oldValuesMap, row.newValuesMap]) {
      if (map == null) continue;
      _collectIdsFromMap(map, 'department_id', ids);
    }
  }

  static void collectUserIds(AuditLogModel row, Set<int> ids) {
    for (final map in [row.oldValuesMap, row.newValuesMap]) {
      if (map == null) continue;
      _collectIdsFromMap(map, 'linked_user_id', ids);
    }
  }

  static void _collectIdsFromMap(
    Map<String, dynamic> map,
    String key,
    Set<int> ids,
  ) {
    _maybeAddId(map[key], ids);
    final fields = map['fields'];
    if (fields is Map) {
      _maybeAddId(fields[key], ids);
    }
  }

  static void _maybeAddId(dynamic value, Set<int> ids) {
    if (value == null) return;
    if (value is int) {
      ids.add(value);
      return;
    }
    final parsed = int.tryParse(value.toString().trim());
    if (parsed != null) ids.add(parsed);
  }
}
