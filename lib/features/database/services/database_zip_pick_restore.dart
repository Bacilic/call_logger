import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/database/database_file_bundle.dart';

/// Επαναφορά αντιγράφου `.zip` που ο χρήστης έδωσε στον επιλογέα αρχείου βάσης.
///
/// Ζει **έξω** από το widget: υπολογίζει τη διαδρομή στόχου εξαγωγής.
/// Η πραγματική επαναφορά και η εναλλαγή συνεδρίας γίνονται από άλλους εκτελεστές.
class DatabaseZipPickRestore {
  DatabaseZipPickRestore._();

  /// Έσχατο όνομα όταν η εγγραφή του zip δεν έχει αξιοποιήσιμο όνομα αρχείου.
  static const restoredDatabaseFileName = 'call_logger.db';

  /// Η βάση εξάγεται στον ίδιο φάκελο με το `.zip`, με το πραγματικό όνομα
  /// της εγγραφής (ή [restoredDatabaseFileName] ως έσχατη λύση). Αν υπάρχει
  /// ήδη ομώνυμο αρχείο, χρησιμοποιείται ο κοινός μηχανισμός κλιμάκωσης.
  static String targetDatabasePathFor(
    String zipPath, {
    String? preferredDatabaseFileName,
    bool Function(String absolutePath)? fileExists,
  }) {
    final dir = p.dirname(zipPath);
    final usable = _usableDatabaseFileName(preferredDatabaseFileName);
    final fileName = usable ?? restoredDatabaseFileName;

    bool exists(String absolutePath) {
      if (fileExists != null) return fileExists(absolutePath);
      try {
        return File(absolutePath).existsSync();
      } catch (_) {
        return false;
      }
    }

    final preferredPath = p.join(dir, fileName);
    if (!exists(preferredPath)) return preferredPath;

    final stem = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    final uniqueName = resolveUniqueTimestampedFileName(
      directory: dir,
      baseName: stem.isEmpty ? 'call_logger' : stem,
      suffix: '_',
      extension: ext.isEmpty ? '.db' : ext,
      fileExists: fileExists,
    );
    return p.join(dir, uniqueName);
  }

  static String? _usableDatabaseFileName(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final base = p.basename(trimmed.replaceAll('\\', '/'));
    if (base.isEmpty || base == '.' || base == '..') return null;
    if (!base.toLowerCase().endsWith('.db')) {
      return '$base.db';
    }
    return base;
  }
}
