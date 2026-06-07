import 'dart:io';

import 'package:path/path.dart' as p;

/// Κατάσταση φακέλου προορισμού ως προς ύπαρξη και αρχεία αντιγράφου.
enum BackupDestinationContentKind {
  folderMissing,
  folderEmptyNoFiles,
  folderOk,
}

class BackupDestinationContentResult {
  const BackupDestinationContentResult({
    required this.kind,
    this.matchingBackupFileCount = 0,
    this.latestBackupModified,
  });

  final BackupDestinationContentKind kind;
  final int matchingBackupFileCount;
  final DateTime? latestBackupModified;
}

/// Αποτέλεσμα ελέγχου διαδρομής φακέλου αντιγράφων ασφαλείας.
enum BackupDestinationValidationKind {
  ok,
  invalidPath,
  missingDirectory,
  notADirectory,
  accessDenied,
}

class BackupDestinationValidationResult {
  const BackupDestinationValidationResult(this.kind);

  final BackupDestinationValidationKind kind;

  static const BackupDestinationValidationResult ok =
      BackupDestinationValidationResult(BackupDestinationValidationKind.ok);

  String? get errorMessage => switch (kind) {
        BackupDestinationValidationKind.ok => null,
        BackupDestinationValidationKind.invalidPath => 'Δώστε έγκυρη διαδρομή',
        BackupDestinationValidationKind.missingDirectory =>
          'Ο φάκελος δεν υπάρχει',
        BackupDestinationValidationKind.notADirectory =>
          'Η διαδρομή δεν είναι φάκελος',
        BackupDestinationValidationKind.accessDenied =>
          'Δεν επιτρέπεται η πρόσβαση',
      };
}

/// Έλεγχος διαδρομής προορισμού backup (κενό = χωρίς φάκελο).
class BackupDestinationFolderValidator {
  BackupDestinationFolderValidator._();

  static const _forbiddenCharsWindows = '<>"|?*/';

  /// Κενό μετά το trim → έγκυρο (χωρίς ορισμό φακέλου).
  static Future<BackupDestinationValidationResult> validate(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return BackupDestinationValidationResult.ok;
    }

    if (Platform.isWindows) {
      if (_isWindowsDotRelative(trimmed)) {
        return const BackupDestinationValidationResult(
          BackupDestinationValidationKind.invalidPath,
        );
      }
      for (var i = 0; i < trimmed.length; i++) {
        if (_forbiddenCharsWindows.contains(trimmed[i])) {
          return const BackupDestinationValidationResult(
            BackupDestinationValidationKind.invalidPath,
          );
        }
      }
      if (_hasInvalidWindowsColonUse(trimmed)) {
        return const BackupDestinationValidationResult(
          BackupDestinationValidationKind.invalidPath,
        );
      }
    }

    return Future(() => _validateFilesystem(trimmed));
  }

  /// `.\\` ή `./` στην αρχή (Windows) — μη έγκυρη διαδρομή.
  static bool _isWindowsDotRelative(String path) {
    if (path.length < 2) return false;
    if (path.codeUnitAt(0) != 0x2e /* . */) return false;
    final s1 = path.codeUnitAt(1);
    return s1 == 0x5c /* \ */ || s1 == 0x2f /* / */;
  }

  /// Επιτρέπεται μόνο `X:` ως δεύτερος χαρακτήρας (γράμμα τόμου).
  static bool _hasInvalidWindowsColonUse(String path) {
    final idx = path.indexOf(':');
    if (idx < 0) return false;
    if (idx != 1) return true;
    final c0 = path.codeUnitAt(0);
    final isLetter =
        (c0 >= 0x41 && c0 <= 0x5a) || (c0 >= 0x61 && c0 <= 0x7a);
    if (!isLetter) return true;
    return path.indexOf(':', 2) >= 0;
  }

  static BackupDestinationValidationResult _validateFilesystem(String path) {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return const BackupDestinationValidationResult(
        BackupDestinationValidationKind.invalidPath,
      );
    }

    Directory dir;
    try {
      dir = Directory(path);
    } catch (_) {
      return const BackupDestinationValidationResult(
        BackupDestinationValidationKind.invalidPath,
      );
    }

    if (!dir.existsSync()) {
      return const BackupDestinationValidationResult(
        BackupDestinationValidationKind.missingDirectory,
      );
    }

    try {
      final type = FileSystemEntity.typeSync(path, followLinks: true);
      if (type == FileSystemEntityType.file) {
        return const BackupDestinationValidationResult(
          BackupDestinationValidationKind.notADirectory,
        );
      }
      if (type != FileSystemEntityType.directory) {
        return const BackupDestinationValidationResult(
          BackupDestinationValidationKind.invalidPath,
        );
      }
    } on FileSystemException {
      return const BackupDestinationValidationResult(
        BackupDestinationValidationKind.invalidPath,
      );
    }

    if (!_probeWriteAccess(dir)) {
      return const BackupDestinationValidationResult(
        BackupDestinationValidationKind.accessDenied,
      );
    }

    return BackupDestinationValidationResult.ok;
  }

  /// Έλεγχος ύπαρξης φακέλου και αρχείων αντιγράφου (μορφή ονομασίας backup).
  static Future<BackupDestinationContentResult> inspectDestinationContent({
    required String destinationDirectory,
    required String dbBaseName,
  }) async {
    final dest = destinationDirectory.trim();
    if (dest.isEmpty) {
      return const BackupDestinationContentResult(
        kind: BackupDestinationContentKind.folderMissing,
      );
    }

    final dir = Directory(dest);
    if (!await dir.exists()) {
      return const BackupDestinationContentResult(
        kind: BackupDestinationContentKind.folderMissing,
      );
    }

    var count = 0;
    DateTime? newest;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!isBackupArtifactFileName(name, dbBaseName)) continue;
      count++;
      try {
        final modified = await entity.lastModified();
        if (newest == null || modified.isAfter(newest)) {
          newest = modified;
        }
      } catch (_) {}
    }

    if (count == 0) {
      return const BackupDestinationContentResult(
        kind: BackupDestinationContentKind.folderEmptyNoFiles,
      );
    }
    return BackupDestinationContentResult(
      kind: BackupDestinationContentKind.folderOk,
      matchingBackupFileCount: count,
      latestBackupModified: newest,
    );
  }

  /// Ταιριάζει με τα πρότυπα ονομασίας [DatabaseBackupService].
  static bool isBackupArtifactFileName(String fileName, String dbBaseName) {
    final base = dbBaseName.trim();
    if (base.isEmpty) return false;
    final escapedBase = RegExp.escape(base);
    final dateFirst = RegExp(
      r'^(\d{4}-\d{2}-\d{2}_\d{2}-\d{2})_' + escapedBase + r'\.(db|zip)$',
    );
    final baseFirst = RegExp(
      r'^' + escapedBase + r'_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2})\.(db|zip)$',
    );
    return dateFirst.hasMatch(fileName) || baseFirst.hasMatch(fileName);
  }

  static bool _probeWriteAccess(Directory dir) {
    final name =
        '.call_logger_write_probe_${DateTime.now().microsecondsSinceEpoch}.tmp';
    final file = File(p.join(dir.path, name));
    try {
      file.writeAsStringSync('1', flush: true);
      return true;
    } on FileSystemException {
      return false;
    } catch (_) {
      return false;
    } finally {
      try {
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    }
  }
}
