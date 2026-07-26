import 'package:path/path.dart' as p;

import 'database_file_classifier.dart';

/// Είδος προειδοποίησης για ανοιχτή βάση Καταγραφής (παλιά / κενή / ημιτελής).
enum DatabaseNoticeKind { none, oldDatabase, emptyDatabase }

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

/// Μοναδικό σημείο ρύθμισης του ορίου «παλιάς» βάσης (ημέρες από την τελευταία κλήση).
const int kOldDatabaseNoticeThresholdDays = 60;

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

  final latest = _tryParseCallDate(profile.latestCallDate);
  if (latest != null) {
    final ageDays = now.difference(latest).inDays;
    if (ageDays >= kOldDatabaseNoticeThresholdDays) {
      final countLabel = _formatGreekInteger(profile.callCount ?? 0);
      final dateLabel = _formatDisplayDate(latest);
      return DatabaseStateNotice(
        kind: DatabaseNoticeKind.oldDatabase,
        message:
            'ΠΑΛΙΑ ΒΑΣΗ: $displayName — $countLabel κλήσεις, '
            'τελευταία στις $dateLabel',
        identity: identity,
      );
    }
  }

  return DatabaseStateNotice(
    kind: DatabaseNoticeKind.none,
    message: '',
    identity: identity,
  );
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
