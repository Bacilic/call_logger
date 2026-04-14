import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/services/audit_service.dart';
import '../../tasks/models/task.dart';
import 'audit_formatter_service.dart';

/// Σύνοψη οντότητας για side panel (κλήση, εκκρεμότητα, χρήστης, εξοπλισμός).
class AuditEntityPreview {
  const AuditEntityPreview({
    required this.title,
    required this.lines,
  });

  final String title;
  final List<String> lines;
}

class AuditEntityPreviewResolver {
  AuditEntityPreviewResolver(this._db);

  final Database _db;

  static const AuditFormatterService _fmt = AuditFormatterService();

  Future<AuditEntityPreview?> resolve({
    required String entityType,
    required int entityId,
  }) async {
    switch (entityType) {
      case AuditEntityTypes.call:
        return _call(entityId);
      case AuditEntityTypes.task:
        return _task(entityId);
      case AuditEntityTypes.user:
        return _user(entityId);
      case AuditEntityTypes.equipment:
        return _equipment(entityId);
      case AuditEntityTypes.phone:
        return _phone(entityId);
      default:
        return null;
    }
  }

  static String _callStatusEl(String? raw) {
    final s = raw?.trim().toLowerCase() ?? '';
    if (s.isEmpty) return '—';
    return switch (s) {
      'pending' => 'εκκρεμής',
      'completed' => 'ολοκληρωμένη',
      _ => raw!.trim(),
    };
  }

  Future<AuditEntityPreview?> _call(int id) async {
    final rows = await _db.query(
      'calls',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final lines = <String>[
      'Ημ/νία: ${r['date'] ?? '—'} ${r['time'] ?? ''}'.trim(),
      'Θέμα/σημειώσεις: ${(r['issue'] as String?)?.trim().isNotEmpty == true ? r['issue'] : '—'}',
      'Κατάσταση: ${_callStatusEl(r['status'] as String?)}',
    ];
    return AuditEntityPreview(title: 'Κλήση #$id', lines: lines);
  }

  Future<AuditEntityPreview?> _task(int id) async {
    final rows = await _db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final statusRaw = (r['status'] as String?)?.trim() ?? '';
    final statusEl =
        TaskStatusX.fromString(statusRaw).displayLabelEl;
    final dueRaw = r['due_date'] as String?;
    final dueFmt = (dueRaw == null || dueRaw.trim().isEmpty)
        ? '—'
        : _fmt.formatAuditTimestamp(dueRaw);
    final lines = <String>[
      'Κατάσταση: $statusEl',
      'Λήξη: $dueFmt',
    ];
    return AuditEntityPreview(title: 'Εκκρεμότητα #$id', lines: lines);
  }

  Future<AuditEntityPreview?> _user(int id) async {
    final rows = await _db.rawQuery(
      '''
      SELECT u.first_name, u.last_name, d.name AS dept
      FROM users u
      LEFT JOIN departments d ON u.department_id = d.id
      WHERE u.id = ?
      LIMIT 1
      ''',
      [id],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final fn = r['first_name'] as String? ?? '';
    final ln = r['last_name'] as String? ?? '';
    final name = '$fn $ln'.trim();
    return AuditEntityPreview(
      title: name.isEmpty ? 'Χρήστης #$id' : name,
      lines: [
        'Τμήμα: ${r['dept'] ?? '—'}',
        'Id: $id',
      ],
    );
  }

  Future<AuditEntityPreview?> _phone(int id) async {
    final rows = await _db.query(
      'phones',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final num = r['number'] as String? ?? '';
    final deptId = r['department_id'] as int?;
    String? deptLabel;
    if (deptId != null) {
      final dr = await _db.query(
        'departments',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [deptId],
        limit: 1,
      );
      if (dr.isNotEmpty) {
        deptLabel = (dr.first['name'] as String?)?.trim();
      }
    }
    return AuditEntityPreview(
      title: num.isEmpty ? 'Τηλέφωνο #$id' : num,
      lines: [
        'Τμήμα (department_id): ${deptLabel ?? '—'}',
        'Id: $id',
      ],
    );
  }

  Future<AuditEntityPreview?> _equipment(int id) async {
    final rows = await _db.query(
      'equipment',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final code = r['code_equipment'] as String? ?? '';
    return AuditEntityPreview(
      title: code.isEmpty ? 'Εξοπλισμός #$id' : 'Εξοπλισμός $code',
      lines: [
        'Τύπος: ${r['type'] ?? '—'}',
        'IP: ${r['custom_ip'] ?? '—'}',
        'Id: $id',
      ],
    );
  }
}
