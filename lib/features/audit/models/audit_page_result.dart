import 'audit_log_model.dart';

class AuditPageResult {
  const AuditPageResult({
    required this.items,
    required this.totalCount,
  });

  final List<AuditLogModel> items;
  final int totalCount;
}
