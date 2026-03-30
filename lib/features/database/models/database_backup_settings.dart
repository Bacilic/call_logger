import 'dart:convert';

/// Μορφή ονόματος αρχείου αντιγράφου (.db / .zip).
enum DatabaseBackupNamingFormat {
  /// `yyyy-MM-dd_HH-mm_<βάση>.db` (προτεινόμενο)
  dateTimeThenBase,

  /// `<βάση>_yyyy-MM-dd_HH-mm.db`
  baseThenDateTime,
}

/// Περιοδικό αυτόματο αντίγραφο (ενεργό όσο τρέχει η εφαρμογή).
enum DatabaseBackupInterval {
  never,
  every4Hours,
  daily,
}

/// Ρυθμίσεις αντιγράφων ασφαλείας βάσης (αποθήκευση σε `app_settings` ως JSON).
class DatabaseBackupSettings {
  const DatabaseBackupSettings({
    required this.destinationDirectory,
    required this.namingFormat,
    required this.zipOutput,
    required this.backupOnExit,
    required this.interval,
    required this.retentionMaxCopiesEnabled,
    required this.retentionMaxCopies,
    required this.retentionMaxAgeEnabled,
    required this.retentionMaxAgeDays,
  });

  static const String appSettingsKey = 'database_backup_settings_v1';

  final String destinationDirectory;
  final DatabaseBackupNamingFormat namingFormat;
  final bool zipOutput;
  final bool backupOnExit;
  final DatabaseBackupInterval interval;

  final bool retentionMaxCopiesEnabled;
  final int retentionMaxCopies;
  final bool retentionMaxAgeEnabled;
  final int retentionMaxAgeDays;

  static DatabaseBackupSettings defaults() => const DatabaseBackupSettings(
        destinationDirectory: '',
        namingFormat: DatabaseBackupNamingFormat.dateTimeThenBase,
        zipOutput: false,
        backupOnExit: false,
        interval: DatabaseBackupInterval.never,
        retentionMaxCopiesEnabled: false,
        retentionMaxCopies: 30,
        retentionMaxAgeEnabled: false,
        retentionMaxAgeDays: 60,
      );

  /// True αν ο επιλεγμένος φάκελος είναι στον τόμο `C:` (συστήματος).
  bool get destinationLooksLikeWindowsSystemDriveC {
    final d = destinationDirectory.trim();
    if (d.isEmpty) return false;
    final norm = d.replaceAll('/', '\\').toLowerCase();
    if (norm.startsWith('c:\\')) return true;
    if (norm == 'c:') return true;
    return false;
  }

  DatabaseBackupSettings copyWith({
    String? destinationDirectory,
    DatabaseBackupNamingFormat? namingFormat,
    bool? zipOutput,
    bool? backupOnExit,
    DatabaseBackupInterval? interval,
    bool? retentionMaxCopiesEnabled,
    int? retentionMaxCopies,
    bool? retentionMaxAgeEnabled,
    int? retentionMaxAgeDays,
  }) {
    return DatabaseBackupSettings(
      destinationDirectory:
          destinationDirectory ?? this.destinationDirectory,
      namingFormat: namingFormat ?? this.namingFormat,
      zipOutput: zipOutput ?? this.zipOutput,
      backupOnExit: backupOnExit ?? this.backupOnExit,
      interval: interval ?? this.interval,
      retentionMaxCopiesEnabled:
          retentionMaxCopiesEnabled ?? this.retentionMaxCopiesEnabled,
      retentionMaxCopies: retentionMaxCopies ?? this.retentionMaxCopies,
      retentionMaxAgeEnabled:
          retentionMaxAgeEnabled ?? this.retentionMaxAgeEnabled,
      retentionMaxAgeDays: retentionMaxAgeDays ?? this.retentionMaxAgeDays,
    );
  }

  Map<String, dynamic> toJson() => {
        'destinationDirectory': destinationDirectory,
        'namingFormat': namingFormat.index,
        'zipOutput': zipOutput,
        'backupOnExit': backupOnExit,
        'interval': interval.index,
        'retentionMaxCopiesEnabled': retentionMaxCopiesEnabled,
        'retentionMaxCopies': retentionMaxCopies,
        'retentionMaxAgeEnabled': retentionMaxAgeEnabled,
        'retentionMaxAgeDays': retentionMaxAgeDays,
      };

  static DatabaseBackupSettings fromJson(Map<String, dynamic> json) {
    int i(String k, int fallback) {
      final v = json[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return fallback;
    }

    bool b(String k, bool fallback) {
      final v = json[k];
      if (v is bool) return v;
      return fallback;
    }

    String s(String k, String fallback) {
      final v = json[k];
      if (v is String) return v;
      return fallback;
    }

    final nf = i('namingFormat', 0).clamp(0, 1);
    final iv = i('interval', 0).clamp(0, 2);

    return DatabaseBackupSettings(
      destinationDirectory: s('destinationDirectory', ''),
      namingFormat: DatabaseBackupNamingFormat.values[nf],
      zipOutput: b('zipOutput', false),
      backupOnExit: b('backupOnExit', false),
      interval: DatabaseBackupInterval.values[iv],
      retentionMaxCopiesEnabled: b('retentionMaxCopiesEnabled', false),
      retentionMaxCopies: i('retentionMaxCopies', 30).clamp(1, 9999),
      retentionMaxAgeEnabled: b('retentionMaxAgeEnabled', false),
      retentionMaxAgeDays: i('retentionMaxAgeDays', 60).clamp(1, 9999),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static DatabaseBackupSettings fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaults();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return defaults();
      return fromJson(decoded);
    } catch (_) {
      return defaults();
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DatabaseBackupSettings &&
        other.destinationDirectory == destinationDirectory &&
        other.namingFormat == namingFormat &&
        other.zipOutput == zipOutput &&
        other.backupOnExit == backupOnExit &&
        other.interval == interval &&
        other.retentionMaxCopiesEnabled == retentionMaxCopiesEnabled &&
        other.retentionMaxCopies == retentionMaxCopies &&
        other.retentionMaxAgeEnabled == retentionMaxAgeEnabled &&
        other.retentionMaxAgeDays == retentionMaxAgeDays;
  }

  @override
  int get hashCode => Object.hash(
        destinationDirectory,
        namingFormat,
        zipOutput,
        backupOnExit,
        interval,
        retentionMaxCopiesEnabled,
        retentionMaxCopies,
        retentionMaxAgeEnabled,
        retentionMaxAgeDays,
      );
}
