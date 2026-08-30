import 'dart:convert';

import '../utils/backup_schedule_utils.dart';
import '../utils/portable_backup_availability.dart';

/// Μορφή ονόματος αρχείου αντιγράφου (.db / .zip).
enum DatabaseBackupNamingFormat {
  /// `yyyy-MM-dd_HH-mm_<βάση>.db` (προτεινόμενο)
  dateTimeThenBase,

  /// `<βάση>_yyyy-MM-dd_HH-mm.db`
  baseThenDateTime,
}

/// Ρυθμίσεις αντιγράφων ασφαλείας βάσης (αποθήκευση σε `app_settings` ως JSON).
///
/// Το «πότε» οδηγείται από **αλλαγές**, όχι από ημερολόγιο (Φάση 3): αντίγραφο
/// όταν μαζευτούν [changeThreshold] αλλαγές ή περάσει το πολύ
/// [maxWaitMinutes] από το τελευταίο, ποτέ πιο συχνά από
/// [minSpacingMinutes] — βάση χωρίς καμία αλλαγή δεν αντιγράφεται ποτέ.
class DatabaseBackupSettings {
  const DatabaseBackupSettings({
    required this.destinationDirectory,
    required this.namingFormat,
    required this.includeMapImagesInBackup,
    required this.includeToolImages,
    required this.includeLexicon,
    required this.includeLampDb,
    required this.backupOnExit,
    required this.changeThreshold,
    required this.minSpacingMinutes,
    required this.maxWaitMinutes,
    required this.backupOnCloseIfPending,
    this.lastBackupAuditId,
    this.lastBackupAttempt,
    this.lastManualBackupAttempt,
    this.lastFullBackupFingerprint,
    this.lastFullBackupAt,
    required this.lastBackupStatus,
    required this.retentionQuickMaxCopiesEnabled,
    required this.retentionQuickMaxCopies,
    required this.retentionQuickMaxAgeEnabled,
    required this.retentionQuickMaxAgeDays,
    required this.retentionFullMaxCopiesEnabled,
    required this.retentionFullMaxCopies,
  });

  static const String appSettingsKey = 'database_backup_settings_v1';

  /// Κάτω όριο ελάχιστης απόστασης: κάθε αντίγραφο διαβάζει ολόκληρη τη βάση
  /// μέσα από το δίκτυο — πιο πυκνά από 15΄ φορτώνει τη γραμμή χωρίς κέρδος
  /// (απόφαση Διευθυντή 24/08/2026).
  static const int minAllowedSpacingMinutes = 15;

  final String destinationDirectory;
  final DatabaseBackupNamingFormat namingFormat;

  /// Συμπερίληψη φακέλου `maps_images` στο zip (με `call_logger.db` εσωτερικά).
  final bool includeMapImagesInBackup;

  /// Συμπερίληψη φακέλου `images/` (εικονίδια εργαλείων).
  final bool includeToolImages;

  /// Συμπερίληψη φακέλου `dictionaries/` (λεξικό-πυρήνας).
  final bool includeLexicon;

  /// Συμπερίληψη αρχείου βάσης Λάμπας από portable `Data Base/`.
  final bool includeLampDb;

  /// Κύριος διακόπτης: αν false, δεν εκτελείται κανένα αυτόματο αντίγραφο.
  /// (Ιστορικό όνομα — καλύπτει ΟΛΑ τα αυτόματα, όχι μόνο του κλεισίματος.)
  final bool backupOnExit;

  /// Πλήθος αλλαγών που πυροδοτεί αντίγραφο.
  final int changeThreshold;

  /// Ελάχιστη απόσταση δύο αυτόματων αντιγράφων, σε λεπτά.
  final int minSpacingMinutes;

  /// Μέγιστη αναμονή με αφύλακτες αλλαγές, σε λεπτά — όποιο έρθει πρώτο
  /// (κατώφλι ή αναμονή) πυροδοτεί.
  final int maxWaitMinutes;

  /// Αντίγραφο και στο κλείσιμο της εφαρμογής, αν υπάρχουν αφύλακτες αλλαγές.
  final bool backupOnCloseIfPending;

  /// Ο αύξων αριθμός Ιστορικού μέχρι τον οποίο οι αλλαγές είναι φυλαγμένες.
  /// `null` = δεν έχει καταγραφεί αντίγραφο με το νέο σύστημα.
  final int? lastBackupAuditId;

  final DateTime? lastBackupAttempt;

  /// Τελευταίο επιτυχές χειροκίνητο αντίγραφο (για ένδειξη/διάλογο).
  final DateTime? lastManualBackupAttempt;

  /// Αποτύπωμα των φορητών (ονόματα, μεγέθη, ώρες) στο τελευταίο ΠΛΗΡΕΣ
  /// αντίγραφο — ίδιο αποτύπωμα σημαίνει «τίποτα δεν άλλαξε ⇒ γρήγορο».
  final String? lastFullBackupFingerprint;

  /// Πότε πάρθηκε το τελευταίο πλήρες αντίγραφο (βάση + φορητά).
  final DateTime? lastFullBackupAt;

  /// `success` | `failed` | `folder_missing` | `none` — βλ. [BackupScheduleStatus].
  final String lastBackupStatus;

  /// Διατήρηση ΓΡΗΓΟΡΩΝ αντιγράφων (.db — μόνο βάση).
  final bool retentionQuickMaxCopiesEnabled;
  final int retentionQuickMaxCopies;
  final bool retentionQuickMaxAgeEnabled;
  final int retentionQuickMaxAgeDays;

  /// Διατήρηση ΠΛΗΡΩΝ αντιγράφων (.zip — βάση + φορητά). Το πιο πρόσφατο
  /// πλήρες δεν διαγράφεται ΠΟΤΕ, ό,τι κι αν λένε τα όρια.
  final bool retentionFullMaxCopiesEnabled;
  final int retentionFullMaxCopies;

  static DatabaseBackupSettings defaults() => const DatabaseBackupSettings(
    destinationDirectory: '',
    namingFormat: DatabaseBackupNamingFormat.dateTimeThenBase,
    includeMapImagesInBackup: false,
    includeToolImages: true,
    includeLexicon: false,
    includeLampDb: false,
    backupOnExit: false,
    changeThreshold: 100,
    minSpacingMinutes: 15,
    maxWaitMinutes: 240,
    backupOnCloseIfPending: true,
    lastBackupAuditId: null,
    lastBackupAttempt: null,
    lastManualBackupAttempt: null,
    lastFullBackupFingerprint: null,
    lastFullBackupAt: null,
    lastBackupStatus: BackupScheduleStatus.none,
    retentionQuickMaxCopiesEnabled: true,
    retentionQuickMaxCopies: 48,
    retentionQuickMaxAgeEnabled: true,
    retentionQuickMaxAgeDays: 7,
    retentionFullMaxCopiesEnabled: true,
    retentionFullMaxCopies: 6,
  );

  /// Η μέγιστη αναμονή δεν μπορεί να είναι μικρότερη από την ελάχιστη
  /// απόσταση — αλλιώς η μία ρύθμιση θα ακύρωνε σιωπηλά την άλλη.
  int get effectiveMaxWaitMinutes =>
      maxWaitMinutes < minSpacingMinutes ? minSpacingMinutes : maxWaitMinutes;

  /// Η πιο πρόσφατη στιγμή οποιουδήποτε αντιγράφου (αυτόματου ή χειροκίνητου)
  /// — από αυτήν μετρούν απόσταση και αναμονή.
  DateTime? get lastAnyBackupAt {
    final auto = lastBackupAttempt;
    final manual = lastManualBackupAttempt;
    if (auto == null) return manual;
    if (manual == null) return auto;
    return manual.isAfter(auto) ? manual : auto;
  }

  /// Προτίμηση χρήστη: κάποιο portable περιεχόμενο επιλέχθηκε (χωρίς έλεγχο διαθεσιμότητας).
  bool get includesPortableBundleInZip =>
      includeMapImagesInBackup ||
      includeToolImages ||
      includeLexicon ||
      includeLampDb;

  /// Ενεργή συμπερίληψη portable bundle: προτίμηση ΚΑΙ διαθέσιμο περιεχόμενο.
  bool effectiveIncludesPortableBundleInZip(
    PortableBackupAvailability availability,
  ) =>
      effectiveIncludeMapImagesInBackup(availability) ||
      effectiveIncludeToolImages(availability) ||
      effectiveIncludeLexicon(availability) ||
      effectiveIncludeLampDb(availability);

  bool effectiveIncludeMapImagesInBackup(
    PortableBackupAvailability availability,
  ) => includeMapImagesInBackup && availability.hasMapImages;

  bool effectiveIncludeToolImages(PortableBackupAvailability availability) =>
      includeToolImages && availability.hasToolImages;

  bool effectiveIncludeLexicon(PortableBackupAvailability availability) =>
      includeLexicon && availability.hasLoadedLexicon;

  bool effectiveIncludeLampDb(PortableBackupAvailability availability) =>
      includeLampDb && availability.hasLampDbInPortableDataBase;

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
    bool? includeMapImagesInBackup,
    bool? includeToolImages,
    bool? includeLexicon,
    bool? includeLampDb,
    bool? backupOnExit,
    int? changeThreshold,
    int? minSpacingMinutes,
    int? maxWaitMinutes,
    bool? backupOnCloseIfPending,
    int? lastBackupAuditId,
    DateTime? lastBackupAttempt,
    bool clearLastBackupAttempt = false,
    DateTime? lastManualBackupAttempt,
    bool clearLastManualBackupAttempt = false,
    String? lastFullBackupFingerprint,
    DateTime? lastFullBackupAt,
    String? lastBackupStatus,
    bool? retentionQuickMaxCopiesEnabled,
    int? retentionQuickMaxCopies,
    bool? retentionQuickMaxAgeEnabled,
    int? retentionQuickMaxAgeDays,
    bool? retentionFullMaxCopiesEnabled,
    int? retentionFullMaxCopies,
  }) {
    return DatabaseBackupSettings(
      destinationDirectory: destinationDirectory ?? this.destinationDirectory,
      namingFormat: namingFormat ?? this.namingFormat,
      includeMapImagesInBackup:
          includeMapImagesInBackup ?? this.includeMapImagesInBackup,
      includeToolImages: includeToolImages ?? this.includeToolImages,
      includeLexicon: includeLexicon ?? this.includeLexicon,
      includeLampDb: includeLampDb ?? this.includeLampDb,
      backupOnExit: backupOnExit ?? this.backupOnExit,
      changeThreshold: changeThreshold ?? this.changeThreshold,
      minSpacingMinutes: minSpacingMinutes ?? this.minSpacingMinutes,
      maxWaitMinutes: maxWaitMinutes ?? this.maxWaitMinutes,
      backupOnCloseIfPending:
          backupOnCloseIfPending ?? this.backupOnCloseIfPending,
      lastBackupAuditId: lastBackupAuditId ?? this.lastBackupAuditId,
      lastBackupAttempt: clearLastBackupAttempt
          ? null
          : (lastBackupAttempt ?? this.lastBackupAttempt),
      lastManualBackupAttempt: clearLastManualBackupAttempt
          ? null
          : (lastManualBackupAttempt ?? this.lastManualBackupAttempt),
      lastFullBackupFingerprint:
          lastFullBackupFingerprint ?? this.lastFullBackupFingerprint,
      lastFullBackupAt: lastFullBackupAt ?? this.lastFullBackupAt,
      lastBackupStatus: lastBackupStatus ?? this.lastBackupStatus,
      retentionQuickMaxCopiesEnabled:
          retentionQuickMaxCopiesEnabled ?? this.retentionQuickMaxCopiesEnabled,
      retentionQuickMaxCopies:
          retentionQuickMaxCopies ?? this.retentionQuickMaxCopies,
      retentionQuickMaxAgeEnabled:
          retentionQuickMaxAgeEnabled ?? this.retentionQuickMaxAgeEnabled,
      retentionQuickMaxAgeDays:
          retentionQuickMaxAgeDays ?? this.retentionQuickMaxAgeDays,
      retentionFullMaxCopiesEnabled:
          retentionFullMaxCopiesEnabled ?? this.retentionFullMaxCopiesEnabled,
      retentionFullMaxCopies:
          retentionFullMaxCopies ?? this.retentionFullMaxCopies,
    );
  }

  Map<String, dynamic> toJson() => {
    'destinationDirectory': destinationDirectory,
    'namingFormat': namingFormat.index,
    'includeMapImagesInBackup': includeMapImagesInBackup,
    'includeToolImages': includeToolImages,
    'includeLexicon': includeLexicon,
    'includeLampDb': includeLampDb,
    'backupOnExit': backupOnExit,
    'changeThreshold': changeThreshold,
    'minSpacingMinutes': minSpacingMinutes,
    'maxWaitMinutes': maxWaitMinutes,
    'backupOnCloseIfPending': backupOnCloseIfPending,
    'lastBackupAuditId': lastBackupAuditId,
    'lastBackupAttempt': lastBackupAttempt?.toIso8601String(),
    'lastManualBackupAttempt': lastManualBackupAttempt?.toIso8601String(),
    'lastFullBackupFingerprint': lastFullBackupFingerprint,
    'lastFullBackupAt': lastFullBackupAt?.toIso8601String(),
    'lastBackupStatus': lastBackupStatus,
    'retentionQuickMaxCopiesEnabled': retentionQuickMaxCopiesEnabled,
    'retentionQuickMaxCopies': retentionQuickMaxCopies,
    'retentionQuickMaxAgeEnabled': retentionQuickMaxAgeEnabled,
    'retentionQuickMaxAgeDays': retentionQuickMaxAgeDays,
    'retentionFullMaxCopiesEnabled': retentionFullMaxCopiesEnabled,
    'retentionFullMaxCopies': retentionFullMaxCopies,
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

    DateTime? dt(String k) {
      final v = json[k];
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final nf = i('namingFormat', 0).clamp(0, 1);

    int? auditId() {
      final v = json['lastBackupAuditId'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    }

    // Πεδία παλαιότερων εκδόσεων (interval, backupDays, backupTime,
    // scheduleAnchorAt) αγνοούνται σιωπηλά — το «πότε» δεν είναι πια
    // ημερολογιακό.
    return DatabaseBackupSettings(
      destinationDirectory: s('destinationDirectory', ''),
      namingFormat: DatabaseBackupNamingFormat.values[nf],
      includeMapImagesInBackup: b('includeMapImagesInBackup', false),
      includeToolImages: b('includeToolImages', true),
      includeLexicon: b('includeLexicon', true),
      includeLampDb: b('includeLampDb', true),
      backupOnExit: b('backupOnExit', false),
      changeThreshold: i('changeThreshold', 100).clamp(1, 9999),
      minSpacingMinutes: i(
        'minSpacingMinutes',
        15,
      ).clamp(minAllowedSpacingMinutes, 1440),
      maxWaitMinutes: i(
        'maxWaitMinutes',
        240,
      ).clamp(minAllowedSpacingMinutes, 10080),
      backupOnCloseIfPending: b('backupOnCloseIfPending', true),
      lastBackupAuditId: auditId(),
      lastBackupAttempt: dt('lastBackupAttempt'),
      lastManualBackupAttempt: dt('lastManualBackupAttempt'),
      lastFullBackupFingerprint: () {
        final v = json['lastFullBackupFingerprint'];
        if (v is String && v.trim().isNotEmpty) return v;
        return null;
      }(),
      lastFullBackupAt: dt('lastFullBackupAt'),
      lastBackupStatus: BackupScheduleStatus.normalize(
        s('lastBackupStatus', 'none'),
      ),
      retentionQuickMaxCopiesEnabled: b('retentionQuickMaxCopiesEnabled', true),
      retentionQuickMaxCopies: i('retentionQuickMaxCopies', 48).clamp(1, 9999),
      retentionQuickMaxAgeEnabled: b('retentionQuickMaxAgeEnabled', true),
      retentionQuickMaxAgeDays: i('retentionQuickMaxAgeDays', 7).clamp(1, 9999),
      retentionFullMaxCopiesEnabled: b('retentionFullMaxCopiesEnabled', true),
      retentionFullMaxCopies: i('retentionFullMaxCopies', 6).clamp(1, 9999),
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
    return o.destinationDirectory == destinationDirectory &&
        o.namingFormat == namingFormat &&
        o.includeMapImagesInBackup == includeMapImagesInBackup &&
        o.includeToolImages == includeToolImages &&
        o.includeLexicon == includeLexicon &&
        o.includeLampDb == includeLampDb &&
        o.backupOnExit == backupOnExit &&
        o.changeThreshold == changeThreshold &&
        o.minSpacingMinutes == minSpacingMinutes &&
        o.maxWaitMinutes == maxWaitMinutes &&
        o.backupOnCloseIfPending == backupOnCloseIfPending &&
        o.lastBackupAuditId == lastBackupAuditId &&
        o.lastBackupAttempt == lastBackupAttempt &&
        o.lastManualBackupAttempt == lastManualBackupAttempt &&
        o.lastFullBackupFingerprint == lastFullBackupFingerprint &&
        o.lastFullBackupAt == lastFullBackupAt &&
        o.lastBackupStatus == lastBackupStatus &&
        o.retentionQuickMaxCopiesEnabled == retentionQuickMaxCopiesEnabled &&
        o.retentionQuickMaxCopies == retentionQuickMaxCopies &&
        o.retentionQuickMaxAgeEnabled == retentionQuickMaxAgeEnabled &&
        o.retentionQuickMaxAgeDays == retentionQuickMaxAgeDays &&
        o.retentionFullMaxCopiesEnabled == retentionFullMaxCopiesEnabled &&
        o.retentionFullMaxCopies == retentionFullMaxCopies;
  }

  @override
  int get hashCode => Object.hashAll([
    destinationDirectory,
    namingFormat,
    includeMapImagesInBackup,
    includeToolImages,
    includeLexicon,
    includeLampDb,
    backupOnExit,
    changeThreshold,
    minSpacingMinutes,
    maxWaitMinutes,
    backupOnCloseIfPending,
    lastBackupAuditId,
    lastBackupAttempt,
    lastManualBackupAttempt,
    lastFullBackupFingerprint,
    lastFullBackupAt,
    lastBackupStatus,
    retentionQuickMaxCopiesEnabled,
    retentionQuickMaxCopies,
    retentionQuickMaxAgeEnabled,
    retentionQuickMaxAgeDays,
    retentionFullMaxCopiesEnabled,
    retentionFullMaxCopies,
  ]);
}
