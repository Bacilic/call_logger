import 'dart:convert';

import '../utils/backup_schedule_utils.dart';

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
    required this.backupDays,
    required this.backupTime,
    this.lastBackupAttempt,
    required this.lastBackupStatus,
    required this.retentionMaxCopiesEnabled,
    required this.retentionMaxCopies,
    required this.retentionMaxAgeEnabled,
    required this.retentionMaxAgeDays,
  });

  static const String appSettingsKey = 'database_backup_settings_v1';

  final String destinationDirectory;
  final DatabaseBackupNamingFormat namingFormat;
  final bool zipOutput;
  /// Κύριος διακόπτης: αν false, δεν εκτελείται κανένα backup (ούτε χειροκίνητο).
  final bool backupOnExit;
  final DatabaseBackupInterval interval;

  /// Ημέρες εβδομάδας (DateTime.weekday: Δευτέρα=1 … Κυριακή=7).
  final List<int> backupDays;

  /// Ώρα εκκίνησης αντιγράφου, π.χ. `14:30`.
  final String backupTime;

  final DateTime? lastBackupAttempt;

  /// `success` | `failed` | `missed` | `none` — βλ. [BackupScheduleStatus].
  final String lastBackupStatus;

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
        backupDays: <int>[],
        backupTime: '09:00',
        lastBackupAttempt: null,
        lastBackupStatus: BackupScheduleStatus.none,
        retentionMaxCopiesEnabled: false,
        retentionMaxCopies: 30,
        retentionMaxAgeEnabled: false,
        retentionMaxAgeDays: 60,
      );

  /// Προσαρμοσμένο εβδομαδιαίο χρονοδιάγραμμα (αντικαθιστά το περιοδικό [interval] όταν ενεργό).
  bool get usesCustomSchedule =>
      backupDays.isNotEmpty && BackupScheduleUtils.hasValidTimeString(backupTime);

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
    List<int>? backupDays,
    String? backupTime,
    DateTime? lastBackupAttempt,
    bool clearLastBackupAttempt = false,
    String? lastBackupStatus,
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
      backupDays: backupDays ?? this.backupDays,
      backupTime: backupTime ?? this.backupTime,
      lastBackupAttempt: clearLastBackupAttempt
          ? null
          : (lastBackupAttempt ?? this.lastBackupAttempt),
      lastBackupStatus:
          lastBackupStatus ?? this.lastBackupStatus,
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
        'backupDays': backupDays,
        'backupTime': backupTime,
        'lastBackupAttempt': lastBackupAttempt?.toIso8601String(),
        'lastBackupStatus': lastBackupStatus,
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

    List<int> daysList(String k) {
      final v = json[k];
      if (v is! List) return [];
      final out = <int>[];
      for (final e in v) {
        if (e is int) {
          out.add(e);
        } else if (e is num) {
          out.add(e.toInt());
        }
      }
      return BackupScheduleUtils.normalizeDays(out);
    }

    DateTime? parseAttempt() {
      final v = json['lastBackupAttempt'];
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    return DatabaseBackupSettings(
      destinationDirectory: s('destinationDirectory', ''),
      namingFormat: DatabaseBackupNamingFormat.values[nf],
      zipOutput: b('zipOutput', false),
      backupOnExit: b('backupOnExit', false),
      interval: DatabaseBackupInterval.values[iv],
      backupDays: daysList('backupDays'),
      backupTime: s('backupTime', '09:00'),
      lastBackupAttempt: parseAttempt(),
      lastBackupStatus:
          BackupScheduleStatus.normalize(s('lastBackupStatus', 'none')),
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
    if (other is! DatabaseBackupSettings) return false;
    final o = other;
    if (o.destinationDirectory != destinationDirectory ||
        o.namingFormat != namingFormat ||
        o.zipOutput != zipOutput ||
        o.backupOnExit != backupOnExit ||
        o.interval != interval ||
        o.backupTime != backupTime ||
        o.lastBackupAttempt != lastBackupAttempt ||
        o.lastBackupStatus != lastBackupStatus ||
        o.retentionMaxCopiesEnabled != retentionMaxCopiesEnabled ||
        o.retentionMaxCopies != retentionMaxCopies ||
        o.retentionMaxAgeEnabled != retentionMaxAgeEnabled ||
        o.retentionMaxAgeDays != retentionMaxAgeDays) {
      return false;
    }
    if (o.backupDays.length != backupDays.length) return false;
    for (var i = 0; i < backupDays.length; i++) {
      if (o.backupDays[i] != backupDays[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([
        destinationDirectory,
        namingFormat,
        zipOutput,
        backupOnExit,
        interval,
        Object.hashAll(backupDays),
        backupTime,
        lastBackupAttempt,
        lastBackupStatus,
        retentionMaxCopiesEnabled,
        retentionMaxCopies,
        retentionMaxAgeEnabled,
        retentionMaxAgeDays,
      ]);
}
