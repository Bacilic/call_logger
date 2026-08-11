import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/config/app_config.dart';
import '../../../core/database/database_file_bundle.dart';
import '../../../core/database/database_lock_recovery.dart';

/// Αποτέλεσμα δημιουργίας αντιγράφου προς αναβάθμιση σχήματος.
class UpgradeCopyResult {
  const UpgradeCopyResult.success(this.copyPath) : errorMessage = null;

  const UpgradeCopyResult.failure(this.errorMessage) : copyPath = null;

  final String? copyPath;
  final String? errorMessage;

  bool get isSuccess => copyPath != null && copyPath!.trim().isNotEmpty;
}

/// Επίθημα προηγούμενου αντιγράφου αναβάθμισης Ή υποβάθμισης (ημερομηνία,
/// προαιρετική ώρα) — αφαιρείται πριν προστεθεί νέο, ώστε να μη συσσωρεύεται.
final RegExp _upgradeCopySuffix = RegExp(
  r'_(αναβαθμισμένη|υποβαθμισμένη)_\d{2}-\d{2}-\d{4}(_\d{2}-\d{2}(-\d{2})?)?(_\d+)?$',
);

/// Το όνομα που θα πάρει το αντίγραφο αναβάθμισης (χωρίς να δημιουργηθεί).
///
/// Χρησιμοποιείται στα κείμενα του διαλόγου συγκατάθεσης, ώστε ο χρήστης να
/// βλέπει εκ των προτέρων ποιο αρχείο θα δημιουργηθεί. Αν το αρχείο-πηγή είναι
/// ήδη αντίγραφο αναβάθμισης, το παλιό επίθημα αντικαθίσταται αντί να
/// συσσωρεύεται (`..._αναβαθμισμένη_25-07-2026_αναβαθμισμένη_25-07-2026.db`).
String upgradeCopyFileName(
  String sourceDbPath, {
  DateTime? now,
  String suffix = '_αναβαθμισμένη_',
}) {
  final stem = p
      .basenameWithoutExtension(sourceDbPath)
      .replaceFirst(_upgradeCopySuffix, '');
  final ext = p.extension(sourceDbPath);
  final effectiveExt = ext.isEmpty ? '.db' : ext;
  return resolveUniqueTimestampedFileName(
    directory: '',
    baseName: stem,
    suffix: suffix,
    extension: effectiveExt,
    now: now,
    fileExists: (_) => false,
  );
}

/// Το τελικό όνομα αντιγράφου, με κλιμάκωση σε ώρα όταν υπάρχει ομώνυμο.
///
/// Ίδιος μηχανισμός ομώνυμων αρχείων με το προτεινόμενο όνομα νέας βάσης:
/// ημερομηνία → `HH-mm` → `HH-mm-ss` → αριθμητικό επίθημα ως έσχατη λύση.
String resolveUpgradeCopyFileName({
  required String sourceDbPath,
  required String directory,
  DateTime? now,
  bool Function(String absolutePath)? fileExists,
  String suffix = '_αναβαθμισμένη_',
}) {
  final stem = p
      .basenameWithoutExtension(sourceDbPath)
      .replaceFirst(_upgradeCopySuffix, '');
  final ext = p.extension(sourceDbPath);
  final effectiveExt = ext.isEmpty ? '.db' : ext;
  return resolveUniqueTimestampedFileName(
    directory: directory,
    baseName: stem,
    suffix: suffix,
    extension: effectiveExt,
    now: now,
    fileExists: fileExists,
  );
}

/// Δημιουργεί αντίγραφο βάσης για ασφαλή αναβάθμιση — ή, με [suffix]
/// «_υποβαθμισμένη_», για υποβάθμιση — σχήματος.
/// Ποτέ δεν γράφει στο πρωτότυπο αρχείο.
Future<UpgradeCopyResult> createUpgradeCopy(
  String sourceDbPath, {
  DateTime? now,
  String suffix = '_αναβαθμισμένη_',
}) async {
  final source = File(sourceDbPath);
  if (!await source.exists()) {
    return UpgradeCopyResult.failure(
      'Το αρχείο «${p.basename(sourceDbPath)}» δεν βρέθηκε.',
    );
  }

  await tryEphemeralWalCheckpoint(sourceDbPath);

  final dir = source.parent.path;
  final candidate = p.join(
    dir,
    resolveUpgradeCopyFileName(
      sourceDbPath: sourceDbPath,
      directory: dir,
      now: now,
      suffix: suffix,
    ),
  );

  final requiredBytes = await _bytesNeededForCopy(sourceDbPath);
  final freeBytes = await _tryGetFreeBytes(dir);
  // Μόνο αξιόπιστες μετρήσεις (>= 1 MiB). Μικρά νούμερα είναι θόρυβος ανάλυσης
  // (π.χ. διαχωριστικά χιλιάδων στο fsutil) και δεν μπλοκάρουν την αντιγραφή.
  if (freeBytes != null &&
      freeBytes >= 1024 * 1024 &&
      freeBytes < requiredBytes) {
    return UpgradeCopyResult.failure(
      'Δεν υπάρχει επαρκής ελεύθερος χώρος για αντίγραφο '
      '(χρειάζονται περίπου ${_formatBytes(requiredBytes)}, '
      'διαθέσιμα ${_formatBytes(freeBytes)}).',
    );
  }

  try {
    await source.copy(candidate);
  } catch (e) {
    return UpgradeCopyResult.failure(
      'Αποτυχία αντιγραφής του αρχείου βάσης: $e',
    );
  }

  for (final sidecar in const <String>['-wal', '-shm']) {
    final sideFile = File('$sourceDbPath$sidecar');
    if (!await sideFile.exists()) continue;
    try {
      await sideFile.copy('$candidate$sidecar');
    } catch (e) {
      return UpgradeCopyResult.failure(
        'Αποτυχία αντιγραφής sidecar $sidecar: $e',
      );
    }
  }

  return UpgradeCopyResult.success(candidate);
}

Future<int> _bytesNeededForCopy(String sourceDbPath) async {
  var total = await File(sourceDbPath).length();
  for (final sidecar in const <String>['-wal', '-shm']) {
    final f = File('$sourceDbPath$sidecar');
    if (await f.exists()) {
      total += await f.length();
    }
  }
  // Μικρό περιθώριο για μεταδεδομένα συστήματος αρχείων.
  return total + (256 * 1024);
}

Future<int?> _tryGetFreeBytes(String directoryPath) async {
  if (!Platform.isWindows) return null;
  if (AppConfig.isUncDatabasePath(directoryPath)) return null;
  final drive = _windowsDrive(directoryPath);
  if (drive == null) return null;
  try {
    final result = await Process.run('fsutil', <String>[
      'volume',
      'diskfree',
      drive,
    ], runInShell: true).timeout(const Duration(seconds: 3));
    if (result.exitCode != 0) return null;
    final out = (result.stdout as String).replaceAll(',', '');
    final matches = RegExp(r'(\d+)').allMatches(out).toList();
    if (matches.isEmpty) return null;
    // Το πρώτο μεγάλο νούμερο είναι τα ελεύθερα bytes (τα μικρά είναι θόρυβος).
    for (final match in matches) {
      final value = int.tryParse(match.group(1)!);
      if (value != null && value >= 1024 * 1024) return value;
    }
    return int.tryParse(matches.first.group(1)!);
  } catch (_) {
    return null;
  }
}

String? _windowsDrive(String path) {
  final match = RegExp(r'^([A-Za-z]:)').firstMatch(path.trim());
  if (match == null) return null;
  return '${match.group(1)}\\';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}
