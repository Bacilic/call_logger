import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

/// Προτεινόμενο όνομα για **νέο** αρχείο βάσης Καταγραφής Κλήσεων.
///
/// Κανόνας: `call_logger_yyyy-MM-dd.db`· αν υπάρχει ήδη στον φάκελο,
/// `call_logger_yyyy-MM-dd_HH-mm.db` (24ωρη ώρα). Αν και αυτό υπάρχει
/// (ίδιο λεπτό), προστίθεται `_ss` και τέλος αριθμητικό επίθημα.
String suggestNewCallLoggerDatabaseFileName({
  required String directory,
  DateTime? now,
  bool Function(String absolutePath)? fileExists,
}) {
  final dir = directory.trim();
  final n = now ?? DateTime.now();
  final date = DateFormat('yyyy-MM-dd').format(n);
  final time = DateFormat('HH-mm').format(n);

  bool exists(String fileName) {
    final full = p.join(dir, fileName);
    if (fileExists != null) return fileExists(full);
    try {
      return File(full).existsSync();
    } catch (_) {
      return false;
    }
  }

  final withDate = 'call_logger_$date.db';
  if (dir.isEmpty || !exists(withDate)) return withDate;

  final withDateTime = 'call_logger_${date}_$time.db';
  if (!exists(withDateTime)) return withDateTime;

  final withSeconds =
      'call_logger_${date}_${DateFormat('HH-mm-ss').format(n)}.db';
  if (!exists(withSeconds)) return withSeconds;

  var counter = 2;
  while (true) {
    final candidate =
        'call_logger_${date}_${DateFormat('HH-mm-ss').format(n)}_$counter.db';
    if (!exists(candidate)) return candidate;
    counter++;
  }
}
