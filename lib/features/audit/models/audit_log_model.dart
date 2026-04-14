import 'dart:convert';

/// Μοντέλο γραμμής `audit_log` για UI.
class AuditLogModel {
  const AuditLogModel({
    required this.id,
    this.action,
    this.timestamp,
    this.userPerforming,
    this.details,
    this.entityType,
    this.entityId,
    this.entityName,
    this.oldValuesJson,
    this.newValuesJson,
  });

  final int id;
  final String? action;
  final String? timestamp;
  final String? userPerforming;
  final String? details;
  final String? entityType;
  final int? entityId;
  final String? entityName;
  final String? oldValuesJson;
  final String? newValuesJson;

  bool get hasOldJson =>
      oldValuesJson != null && oldValuesJson!.trim().isNotEmpty;
  bool get hasNewJson =>
      newValuesJson != null && newValuesJson!.trim().isNotEmpty;

  /// Έχει τουλάχιστον ένα από τα JSON πεδία «πριν/μετά».
  bool get hasAnyDeltaJson => hasOldJson || hasNewJson;

  /// `tasks id=45` κ.λπ. — ήδη καλύπτεται από το φιλικό `summaryLine`.
  bool get isTechnicalTableDetailsOnly {
    final d = details?.trim() ?? '';
    return RegExp(
      r'^(tasks|users|categories|departments|equipment)\s+id=\d+\s*$',
      caseSensitive: false,
    ).hasMatch(d);
  }

  /// Όταν υπάρχει πραγματικό όνομα χρήστη (όχι κενό / placeholder `—`).
  /// Για μελλοντική ρύθμιση· τώρα συχνά κενό ώστε να κρύβεται γραμμή «Χρήστης».
  bool get hasMeaningfulPerformingUser {
    final t = userPerforming?.trim() ?? '';
    if (t.isEmpty) return false;
    if (t == '—' || t == '-') return false;
    return true;
  }

  Map<String, dynamic>? get oldValuesMap => _decode(oldValuesJson);
  Map<String, dynamic>? get newValuesMap => _decode(newValuesJson);

  static Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final d = jsonDecode(raw);
      if (d is Map<String, dynamic>) return d;
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return null;
  }

  factory AuditLogModel.fromMap(Map<String, Object?> map) {
    final idRaw = map['id'];
    final id = idRaw is int ? idRaw : (idRaw as num).toInt();
    final eid = map['entity_id'];
    return AuditLogModel(
      id: id,
      action: map['action'] as String?,
      timestamp: map['timestamp'] as String?,
      userPerforming: map['user_performing'] as String?,
      details: map['details'] as String?,
      entityType: map['entity_type'] as String?,
      entityId: eid == null
          ? null
          : (eid is int ? eid : (eid as num).toInt()),
      entityName: map['entity_name'] as String?,
      oldValuesJson: map['old_values_json'] as String?,
      newValuesJson: map['new_values_json'] as String?,
    );
  }
}
