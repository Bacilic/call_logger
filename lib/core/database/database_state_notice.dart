import 'package:path/path.dart' as p;

import 'database_file_classifier.dart';
import 'database_staleness.dart';

/// Είδος προειδοποίησης για ανοιχτή βάση Καταγραφής.
enum DatabaseNoticeKind {
  none,
  oldDatabase,
  emptyDatabase,

  /// Το ίδιο το SQLite δηλώνει ότι μέρος του αρχείου δεν διαβάζεται.
  ///
  /// Προηγείται όλων: μια βάση που φθείρεται δεν είναι «παλιά» ή «ημιτελής»
  /// — είναι βάση που χάνει δεδομένα όσο μένει σε χρήση.
  corruptedContent,
}

/// Ειδοποίηση κατάστασης βάσης για εμφάνιση στη λωρίδα UI.
class DatabaseStateNotice {
  const DatabaseStateNotice({
    required this.kind,
    required this.message,
    required this.identity,
  });

  final DatabaseNoticeKind kind;
  final String message;

  /// Ταυτότητα περιεχομένου — για «το είπα ήδη» χωρίς εξάρτηση μόνο από διαδρομή.
  final String identity;
}

/// Το όριο των ημερών **δεν** ζει πια εδώ ως σταθερά.
///
/// Ως τις 19/09/2026 ήταν σκληρογραμμένο στις 60 ημέρες, ενώ παράλληλα
/// υπήρχε δεύτερη ειδοποίηση με δικό της ρυθμιζόμενο όριο. Οι δύο ενοποιήθηκαν:
/// το κατώφλι έρχεται πλέον ως παράμετρος από τη ρύθμιση του χρήστη, και η
/// προεπιλογή του ζει στο [kDefaultDatabaseStalenessDays].

/// Σταθερό κλειδί από περιεχόμενο βάσης (όχι μόνο διαδρομή).
String databaseContentIdentity({
  required String dbPath,
  required String? latestCallDate,
  required int? callCount,
  required int fileModifiedMs,
  int? userCount,
  int? phoneCount,
  int? equipmentCount,
  int? departmentCount,
}) {
  return '$dbPath|${latestCallDate ?? ''}|${callCount ?? ''}|'
      '${userCount ?? ''}|${phoneCount ?? ''}|${equipmentCount ?? ''}|'
      '${departmentCount ?? ''}|$fileModifiedMs';
}

/// Αποφασίζει αν χρειάζεται προειδοποίηση για παλιά ή ημιτελή βάση.
///
/// Η ημιτελής/κενή προηγείται της παλιάς. Μόνο [DatabaseFileKind.callLogger]
/// αξιολογείται.
DatabaseStateNotice evaluateDatabaseStateNotice({
  required DatabaseFileProfile? profile,
  required String dbPath,
  required DateTime fileModifiedAt,
  required DateTime now,
  int thresholdDays = kDefaultDatabaseStalenessDays,
}) {
  final identity = databaseContentIdentity(
    dbPath: dbPath,
    latestCallDate: profile?.latestCallDate,
    callCount: profile?.callCount,
    userCount: profile?.userCount,
    phoneCount: profile?.phoneCount,
    equipmentCount: profile?.equipmentCount,
    departmentCount: profile?.departmentCount,
    fileModifiedMs: fileModifiedAt.millisecondsSinceEpoch,
  );

  if (profile == null || profile.kind != DatabaseFileKind.callLogger) {
    return DatabaseStateNotice(
      kind: DatabaseNoticeKind.none,
      message: '',
      identity: identity,
    );
  }

  final fileName = p.basename(dbPath);
  final displayName = fileName.isEmpty ? dbPath : fileName;

  // Πρώτο απ' όλα: η φθορά δεν περιμένει στη σειρά πίσω από «παλιά βάση».
  // Ο χρήστης πρέπει να πάρει αντίγραφο ΤΩΡΑ, όσο ό,τι απομένει διαβάζεται.
  if (profile.contentIsCorrupt) {
    return DatabaseStateNotice(
      kind: DatabaseNoticeKind.corruptedContent,
      message:
          'ΦΘΟΡΑ ΣΤΗ ΒΑΣΗ: $displayName — μέρος του αρχείου δεν διαβάζεται. '
          'Πάρτε αντίγραφο ασφαλείας τώρα και επαναφέρετε από παλαιότερο.',
      identity: identity,
    );
  }

  final missing = <String>[];
  if (profile.callCount == 0) missing.add('κλήσεις');
  if (profile.userCount == 0) missing.add('υπάλληλοι');
  if (profile.phoneCount == 0) missing.add('τηλέφωνα');
  if (profile.equipmentCount == 0) missing.add('εξοπλισμός');
  if (profile.departmentCount == 0) missing.add('τμήματα');

  if (missing.isNotEmpty) {
    return DatabaseStateNotice(
      kind: DatabaseNoticeKind.emptyDatabase,
      message:
          'ημιτελής βάση \'$displayName\' - Δεν υπάρχουν καθόλου: '
          '${missing.join(', ')}',
      identity: identity,
    );
  }

  // «Πότε δούλεψε κάποιος εδώ» — η πιο πρόσφατη από τις δύο απαντήσεις που
  // κρατά η βάση για τον εαυτό της. Καθεμιά μόνη της είναι τυφλή κάπου: οι
  // κλήσεις δεν πιάνουν δουλειά στον Κατάλογο, το Ιστορικό καθαρίζεται
  // περιοδικά.
  final verdict = judgeDatabaseStaleness(
    lastChangeAt: latestDatabaseActivityAt(
      latestCallDate: profile.latestCallDate,
      latestAuditAt: profile.latestAuditAt,
    ),
    thresholdDays: thresholdDays,
    now: now,
  );

  if (verdict.isStale) {
    final countLabel = _formatGreekInteger(profile.callCount ?? 0);
    final dateLabel = _formatDisplayDate(verdict.lastChangeAt!);
    final days = verdict.daysSinceLastChange ?? 0;
    return DatabaseStateNotice(
      kind: DatabaseNoticeKind.oldDatabase,
      // Η διαδρομή μπαίνει στο μήνυμα επίτηδες: η ημερομηνία λέει **ότι**
      // κάτι δεν πάει καλά, η διαδρομή λέει **ποια βάση** φταίει — και αυτό
      // ακριβώς έλειπε στο επεισόδιο του «χαμένου» τμήματος (17/07/2026).
      message:
          'ΠΑΛΙΑ ΒΑΣΗ: $displayName — καμία αλλαγή εδώ και $days μέρες '
          '(τελευταία $dateLabel· $countLabel κλήσεις)\n$dbPath',
      identity: identity,
    );
  }

  return DatabaseStateNotice(
    kind: DatabaseNoticeKind.none,
    message: '',
    identity: identity,
  );
}

/// Η πιο πρόσφατη στιγμή που κάτι συνέβη σε αυτή τη βάση.
///
/// Δύο ανεξάρτητες πηγές, γιατί καθεμιά μόνη της έχει ένα τυφλό σημείο:
/// 1. **Η τελευταία κλήση** δεν αλλάζει ποτέ σε βάση όπου δουλεύεται μόνο ο
///    Κατάλογος — μια ζωντανή βάση θα φαινόταν νεκρή.
/// 2. **Η τελευταία εγγραφή Ιστορικού** πιάνει κάθε είδους δουλειά, αλλά το
///    Ιστορικό καθαρίζεται περιοδικά και μπορεί να μείνει άδειο.
///
/// `null` μόνο όταν **καμία** από τις δύο δεν έχει να πει κάτι — και τότε η
/// βάση δεν κρίνεται καθόλου ως παλιά, γιατί δεν υπάρχει στοιχείο ηλικίας.
DateTime? latestDatabaseActivityAt({
  required String? latestCallDate,
  required DateTime? latestAuditAt,
}) {
  final call = _tryParseCallDate(latestCallDate);
  if (call == null) return latestAuditAt;
  if (latestAuditAt == null) return call;
  return latestAuditAt.isAfter(call) ? latestAuditAt : call;
}

DateTime? _tryParseCallDate(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final iso = DateTime.tryParse(trimmed);
  if (iso != null) return iso;

  final parts = trimmed.split(RegExp(r'[./-]'));
  if (parts.length == 3) {
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d != null && m != null && y != null && y > 31) {
      return DateTime(y, m, d);
    }
    if (d != null && m != null && y != null && d > 31) {
      // yyyy-MM-dd ήδη καλύπτεται από tryParse· εδώ y πρώτο χωρίς παύλες.
      return DateTime(d, m, y);
    }
  }
  return null;
}

String _formatDisplayDate(DateTime date) {
  final d = date.day.toString().padLeft(2, '0');
  final m = date.month.toString().padLeft(2, '0');
  return '$d/$m/${date.year}';
}

String _formatGreekInteger(int value) {
  final digits = value.abs().toString();
  final buf = StringBuffer();
  if (value < 0) buf.write('-');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return buf.toString();
}
