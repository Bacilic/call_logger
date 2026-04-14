import 'dart:convert';

/// Ρυθμίσεις εκκαθάρισης πίνακα `audit_log` (SharedPreferences JSON).
class AuditRetentionConfig {
  const AuditRetentionConfig({
    this.enabled = false,
    this.maxAgeDays,
    this.maxRows,
    this.purgeOnAppStart = false,
  });

  final bool enabled;
  /// Διαγραφή εγγραφών παλαιότερων των N ημερών (null = χωρίς όριο ηλικίας).
  final int? maxAgeDays;
  /// Μέγιστο πλήθος γραμμών audit (null = χωρίς όριο πλήθους).
  final int? maxRows;
  final bool purgeOnAppStart;

  AuditRetentionConfig copyWith({
    bool? enabled,
    int? maxAgeDays,
    bool clearMaxAgeDays = false,
    int? maxRows,
    bool clearMaxRows = false,
    bool? purgeOnAppStart,
  }) {
    return AuditRetentionConfig(
      enabled: enabled ?? this.enabled,
      maxAgeDays:
          clearMaxAgeDays ? null : (maxAgeDays ?? this.maxAgeDays),
      maxRows: clearMaxRows ? null : (maxRows ?? this.maxRows),
      purgeOnAppStart: purgeOnAppStart ?? this.purgeOnAppStart,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'max_age_days': maxAgeDays,
        'max_rows': maxRows,
        'purge_on_app_start': purgeOnAppStart,
      };

  factory AuditRetentionConfig.fromJson(Map<String, dynamic> m) {
    return AuditRetentionConfig(
      enabled: m['enabled'] == true,
      maxAgeDays: (m['max_age_days'] as num?)?.toInt(),
      maxRows: (m['max_rows'] as num?)?.toInt(),
      purgeOnAppStart: m['purge_on_app_start'] == true,
    );
  }

  static AuditRetentionConfig fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const AuditRetentionConfig();
    }
    try {
      final d = jsonDecode(raw);
      if (d is Map<String, dynamic>) {
        return AuditRetentionConfig.fromJson(d);
      }
      if (d is Map) {
        return AuditRetentionConfig.fromJson(Map<String, dynamic>.from(d));
      }
    } catch (_) {}
    return const AuditRetentionConfig();
  }
}
