import 'dart:io';

import 'package:path/path.dart' as p;

/// Μετονομάζει το κύριο αρχείο βάσης και τα υπαρκτά sidecars `-wal` / `-shm`.
Future<void> renameDatabaseBundle(
  String dbPath,
  String newMainFileName,
) async {
  final dir = p.dirname(dbPath);
  final newMain = p.join(dir, newMainFileName);
  final wal = '$dbPath-wal';
  final shm = '$dbPath-shm';
  final newWal = '$newMain-wal';
  final newShm = '$newMain-shm';

  await File(dbPath).rename(newMain);
  if (await File(wal).exists()) {
    await File(wal).rename(newWal);
  }
  if (await File(shm).exists()) {
    await File(shm).rename(newShm);
  }
}

/// Σβήνει ανεκτικά μόνο τα συνοδευτικά `-wal` / `-shm` του [dbPath].
Future<void> deleteDatabaseSidecars(String dbPath) async {
  for (final sidecar in <String>['$dbPath-wal', '$dbPath-shm']) {
    try {
      final file = File(sidecar);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}

/// Μοναδικό όνομα με κλιμάκωση: ημερομηνία → `HH-mm` → `HH-mm-ss` → αριθμός.
///
/// Μορφή ημερομηνίας: `dd-MM-yyyy` (ίδια με τα αντίγραφα αναβάθμισης σχήματος).
String resolveUniqueTimestampedFileName({
  required String directory,
  required String baseName,
  required String suffix,
  required String extension,
  DateTime? now,
  bool Function(String absolutePath)? fileExists,
}) {
  final n = now ?? DateTime.now();
  final ext = extension.isEmpty
      ? '.db'
      : (extension.startsWith('.') ? extension : '.$extension');
  final date = _dateStamp(n);

  bool exists(String fileName) {
    final full = p.join(directory, fileName);
    if (fileExists != null) return fileExists(full);
    try {
      return File(full).existsSync();
    } catch (_) {
      return false;
    }
  }

  final withDate = '$baseName$suffix$date$ext';
  if (!exists(withDate)) return withDate;

  final withMinutes = '$baseName$suffix${date}_${_timeStamp(n)}$ext';
  if (!exists(withMinutes)) return withMinutes;

  final withSeconds =
      '$baseName$suffix${date}_${_timeStamp(n, seconds: true)}$ext';
  if (!exists(withSeconds)) return withSeconds;

  var counter = 2;
  while (true) {
    final candidate =
        '$baseName$suffix${date}_${_timeStamp(n, seconds: true)}_$counter$ext';
    if (!exists(candidate)) return candidate;
    counter++;
  }
}

String _dateStamp(DateTime value) {
  final d = value.day.toString().padLeft(2, '0');
  final m = value.month.toString().padLeft(2, '0');
  return '$d-$m-${value.year}';
}

String _timeStamp(DateTime value, {bool seconds = false}) {
  final h = value.hour.toString().padLeft(2, '0');
  final min = value.minute.toString().padLeft(2, '0');
  if (!seconds) return '$h-$min';
  final s = value.second.toString().padLeft(2, '0');
  return '$h-$min-$s';
}
