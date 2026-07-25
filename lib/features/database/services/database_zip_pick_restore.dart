import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/database/database_file_bundle.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import 'database_backup_service.dart';

/// Εκτελεστής επαναφοράς `.zip` — σημείο εισαγωγής ψεύτικου εκτελεστή στα τεστ.
typedef ZipRestoreRunner = Future<DatabaseRestoreResult> Function(
  String zipPath, {
  required String targetDatabasePath,
  String? databaseEntryName,
});

/// Αποτέλεσμα επαναφοράς αντιγράφου `.zip` που δόθηκε ως «διαδρομή βάσης»:
/// είτε η διαδρομή της επαναφερμένης βάσης, είτε μήνυμα για τον χρήστη.
class ZipPickRestoreResult {
  const ZipPickRestoreResult.restored(
    String path, {
    this.summaryMessage,
    this.preRestoreBackupPath,
    this.warnings = const <String>[],
  })  : databasePath = path,
        errorMessage = null;

  const ZipPickRestoreResult.failed(String message)
      : databasePath = null,
        errorMessage = message,
        summaryMessage = null,
        preRestoreBackupPath = null,
        warnings = const <String>[];

  final String? databasePath;
  final String? errorMessage;
  final String? summaryMessage;
  final String? preRestoreBackupPath;
  final List<String> warnings;

  bool get isRestored => databasePath != null;
}

/// Επαναφορά αντιγράφου `.zip` που ο χρήστης έδωσε στον επιλογέα αρχείου βάσης.
///
/// Ζει **έξω** από το widget: το πάνελ ρυθμίσεων δείχνει μόνο τον διάλογο
/// επιβεβαίωσης και το αποτέλεσμα — δεν κλείνει συνδέσεις βάσης και δεν
/// υπολογίζει διαδρομές αρχείων.
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

  /// Κλείνει την τρέχουσα σύνδεση και επαναφέρει το αντίγραφο στον [targetDatabasePath].
  ///
  /// Η αποτυχία κλεισίματος **δεν καταπίνεται σιωπηλά**: αν η επαναφορά
  /// αποτύχει, η αιτία προσαρτάται στο μήνυμα — το κλειδωμένο από άλλη σύνδεση
  /// αρχείο είναι η συνηθέστερη πραγματική αιτία της αποτυχίας. Όταν η
  /// επαναφορά πετύχει παρά την αποτυχία κλεισίματος, δεν ενοχλούμε τον χρήστη.
  static Future<ZipPickRestoreResult> restoreToTarget(
    String zipPath, {
    required String targetDatabasePath,
    String? databaseEntryName,
    Future<void> Function()? closeConnection,
    ZipRestoreRunner? runRestore,
  }) async {
    Object? closeFailure;
    try {
      await (closeConnection ?? DatabaseHelper.instance.closeConnection)();
    } catch (e) {
      closeFailure = e;
    }

    final restored =
        await (runRestore ?? DatabaseBackupFileOperation.restoreFromZip)(
      zipPath,
      targetDatabasePath: targetDatabasePath,
      databaseEntryName: databaseEntryName,
    );

    final restoredPath = restored.databasePath;
    if (!restored.success || restoredPath == null) {
      return ZipPickRestoreResult.failed(
        _failureMessage(restored.message, closeFailure),
      );
    }
    return ZipPickRestoreResult.restored(
      restoredPath,
      summaryMessage: restored.message,
      preRestoreBackupPath: restored.preRestoreBackupPath,
      warnings: restored.warnings,
    );
  }

  /// Κλείνει την τρέχουσα σύνδεση και επαναφέρει το αντίγραφο.
  ///
  /// Ο στόχος υπολογίζεται με [targetDatabasePathFor]· η εκτέλεση γίνεται
  /// μέσω [restoreToTarget].
  static Future<ZipPickRestoreResult> restore(
    String zipPath, {
    String? preferredDatabaseFileName,
    String? databaseEntryName,
    Future<void> Function()? closeConnection,
    ZipRestoreRunner? runRestore,
  }) {
    return restoreToTarget(
      zipPath,
      targetDatabasePath: targetDatabasePathFor(
        zipPath,
        preferredDatabaseFileName: preferredDatabaseFileName,
      ),
      databaseEntryName: databaseEntryName,
      closeConnection: closeConnection,
      runRestore: runRestore,
    );
  }

  static String _failureMessage(String? serviceMessage, Object? closeFailure) {
    final trimmed = serviceMessage?.trim() ?? '';
    final base =
        trimmed.isNotEmpty ? trimmed : 'Αποτυχία επαναφοράς από zip.';
    if (closeFailure == null) return base;
    return '$base\n\n'
        'Το κλείσιμο της τρέχουσας σύνδεσης απέτυχε: '
        '${humanizeUserFacingError(closeFailure)}\n'
        'Αν το αρχείο είναι κλειδωμένο, κλείστε τυχόν άλλο ανοιχτό αντίγραφο '
        'της εφαρμογής και δοκιμάστε ξανά.';
  }
}
