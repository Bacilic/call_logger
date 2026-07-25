import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../core/database/database_file_bundle.dart';
import '../../../core/database/database_file_classifier.dart';

/// Ταξινομητής αρχείου βάσης (προεπιλογή: [classifyDatabaseFile]).
typedef DatabaseFileClassifierFn = Future<DatabaseFileKind> Function(
  String path,
);

/// Αποτέλεσμα ασφαλούς αντικατάστασης αρχείου βάσης.
class DatabaseFileReplacementResult {
  const DatabaseFileReplacementResult.success({
    this.preRestoreBackupPath,
  })  : success = true,
        message = null;

  const DatabaseFileReplacementResult.failure(this.message)
      : success = false,
        preRestoreBackupPath = null;

  final bool success;
  final String? message;
  final String? preRestoreBackupPath;
}

/// Ασφαλής, αναστρέψιμη αντικατάσταση αρχείου βάσης με δεδομένα bytes.
///
/// Πολιτική ταξινόμησης στόχου (αν το αρχείο υπάρχει):
/// - Επιτρέπονται: βάση Καταγραφής, ημιτελής βάση Καταγραφής, κενό SQLite,
///   και αρχείο που δεν άνοιξε ([DatabaseFileKind.undetermined]) — το
///   κατεστραμμένο αρχείο είναι η κύρια αιτία επαναφοράς.
/// - Απαγορεύονται: βάση Λάμπας, υβρίδιο, άγνωστο σχήμα — με στοχευμένο
///   μήνυμα που ονομάζει τι βρέθηκε και προτείνει άλλη διαδρομή προορισμού.
class DatabaseFileReplacement {
  DatabaseFileReplacement._();

  static const preRestoreSuffix = '_pre_restore_';

  /// Προτεινόμενο όνομα φύλαξης της τρέχουσας βάσης (χωρίς να δημιουργηθεί).
  static String previewPreRestoreFileName(
    String targetDatabasePath, {
    DateTime? now,
    bool Function(String absolutePath)? fileExists,
  }) {
    final dir = p.dirname(targetDatabasePath);
    final stem = p.basenameWithoutExtension(targetDatabasePath);
    final ext = p.extension(targetDatabasePath);
    return resolveUniqueTimestampedFileName(
      directory: dir,
      baseName: stem,
      suffix: preRestoreSuffix,
      extension: ext.isEmpty ? '.db' : ext,
      now: now,
      fileExists: fileExists,
    );
  }

  /// Αντικαθιστά το [targetDatabasePath] με [bytes].
  ///
  /// Σειρά βημάτων (δεσμευτική): ταξινόμηση → εγγραφή προσωρινού στον ίδιο
  /// φάκελο → μετονομασία υπάρχοντος σε `_pre_restore_` → ατομική μετονομασία
  /// προσωρινού στον στόχο → καθαρισμός ορφανών sidecars.
  static Future<DatabaseFileReplacementResult> replaceWithBytes({
    required String targetDatabasePath,
    required List<int> bytes,
    DatabaseFileClassifierFn? classify,
    DateTime? now,
    Future<void> Function(String from, String to)? commitTempFile,
  }) async {
    return _replaceWithPreparedTemp(
      targetDatabasePath: targetDatabasePath,
      prepareTemp: (tempPath) async {
        await File(tempPath).writeAsBytes(
          bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
          flush: true,
        );
      },
      classify: classify,
      now: now,
      commitTempFile: commitTempFile,
    );
  }

  /// Αντικαθιστά το [targetDatabasePath] από ήδη εξαγμένο αρχείο-πηγή.
  ///
  /// Όταν πηγή και στόχος ταυτίζονται (ίδιος φάκελος και ίδιο αρχείο), δεν
  /// γίνεται περιττή αντιγραφή — επιστρέφει επιτυχία χωρίς αλλαγή.
  static Future<DatabaseFileReplacementResult> replaceFromFile({
    required String targetDatabasePath,
    required String sourceDatabasePath,
    DatabaseFileClassifierFn? classify,
    DateTime? now,
    Future<void> Function(String from, String to)? commitTempFile,
  }) async {
    final target = p.normalize(p.absolute(targetDatabasePath));
    final source = p.normalize(p.absolute(sourceDatabasePath));
    if (_samePath(target, source)) {
      return const DatabaseFileReplacementResult.success();
    }

    final sourceFile = File(source);
    if (!await sourceFile.exists()) {
      return DatabaseFileReplacementResult.failure(
        'Το εξαγμένο αρχείο βάσης δεν βρέθηκε: $source',
      );
    }

    return _replaceWithPreparedTemp(
      targetDatabasePath: target,
      prepareTemp: (tempPath) async {
        await sourceFile.copy(tempPath);
      },
      classify: classify,
      now: now,
      commitTempFile: commitTempFile,
    );
  }

  static Future<DatabaseFileReplacementResult> _replaceWithPreparedTemp({
    required String targetDatabasePath,
    required Future<void> Function(String tempPath) prepareTemp,
    DatabaseFileClassifierFn? classify,
    DateTime? now,
    Future<void> Function(String from, String to)? commitTempFile,
  }) async {
    final target = p.normalize(p.absolute(targetDatabasePath));
    final targetFile = File(target);
    final targetExists = await targetFile.exists();

    if (targetExists) {
      final kind = await (classify ?? classifyDatabaseFile)(target);
      final rejection = _rejectionMessageFor(kind, target);
      if (rejection != null) {
        return DatabaseFileReplacementResult.failure(rejection);
      }
    }

    final dir = p.dirname(target);
    await Directory(dir).create(recursive: true);

    final tempPath = p.join(
      dir,
      '.${p.basename(target)}.restore_tmp_${DateTime.now().microsecondsSinceEpoch}',
    );
    final tempFile = File(tempPath);

    String? preRestorePath;
    try {
      await prepareTemp(tempPath);

      if (targetExists) {
        final preRestoreName = previewPreRestoreFileName(
          target,
          now: now,
        );
        preRestorePath = p.join(dir, preRestoreName);
        await renameDatabaseBundle(target, preRestoreName);
      }

      try {
        final commit = commitTempFile ?? _defaultCommitTemp;
        await commit(tempPath, target);
      } catch (e) {
        await _rollbackAfterCommitFailure(
          target: target,
          tempPath: tempPath,
          preRestorePath: preRestorePath,
        );
        return DatabaseFileReplacementResult.failure(
          'Η τελική αντικατάσταση της βάσης απέτυχε· η προηγούμενη βάση '
          'δεν χάθηκε και παραμένει στη θέση της.\n'
          'Λεπτομέρεια: $e',
        );
      }

      await deleteDatabaseSidecars(target);

      return DatabaseFileReplacementResult.success(
        preRestoreBackupPath: preRestorePath,
      );
    } catch (e) {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      return DatabaseFileReplacementResult.failure(
        'Αποτυχία εγγραφής βάσης στον προορισμό: $e',
      );
    }
  }

  static bool _samePath(String a, String b) {
    final na = p.normalize(a).replaceAll('/', '\\').toLowerCase();
    final nb = p.normalize(b).replaceAll('/', '\\').toLowerCase();
    return na == nb;
  }

  static Future<void> _defaultCommitTemp(String from, String to) =>
      File(from).rename(to);

  static Future<void> _rollbackAfterCommitFailure({
    required String target,
    required String tempPath,
    required String? preRestorePath,
  }) async {
    try {
      final temp = File(tempPath);
      if (await temp.exists()) {
        await temp.delete();
      }
    } catch (_) {}

    if (preRestorePath == null) return;
    try {
      final preserved = File(preRestorePath);
      if (await preserved.exists()) {
        await renameDatabaseBundle(preRestorePath, p.basename(target));
      }
    } catch (_) {}
  }

  static String? _rejectionMessageFor(DatabaseFileKind kind, String path) {
    final fileName = p.basename(path);
    final displayName = fileName.isEmpty ? path : fileName;
    switch (kind) {
      case DatabaseFileKind.callLogger:
      case DatabaseFileKind.incompleteCallLogger:
      case DatabaseFileKind.empty:
      case DatabaseFileKind.undetermined:
        return null;
      case DatabaseFileKind.lamp:
        return 'Ο προορισμός «$displayName» είναι η βάση δεδομένων της Λάμπας. '
            'Η επαναφορά δεν θα τον αντικαταστήσει. '
            'Επιλέξτε διαφορετική διαδρομή προορισμού '
            '(π.χ. call_logger.db).';
      case DatabaseFileKind.hybrid:
        return 'Ο προορισμός «$displayName» περιέχει ταυτόχρονα πίνακες της '
            'Καταγραφής Κλήσεων και της Λάμπας. '
            'Η επαναφορά δεν θα τον αντικαταστήσει. '
            'Επιλέξτε διαφορετική διαδρομή προορισμού.';
      case DatabaseFileKind.unknown:
        return 'Ο προορισμός «$displayName» δεν είναι βάση της Καταγραφής '
            'Κλήσεων. Η επαναφορά δεν θα τον αντικαταστήσει. '
            'Επιλέξτε διαφορετική διαδρομή προορισμού.';
    }
  }
}
