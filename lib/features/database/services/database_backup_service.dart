import 'dart:io';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database_helper.dart';
import '../models/database_backup_settings.dart';

/// Αποτέλεσμα χειροκίνητου ή προγραμματισμένου backup.
class DatabaseBackupResult {
  const DatabaseBackupResult({
    required this.success,
    this.outputPath,
    this.message,
  });

  final bool success;
  final String? outputPath;
  final String? message;
}

/// Δημιουργία αντιγράφων με `VACUUM INTO` (ατομικό, ενσωματώνει WAL/SHM),
/// προαιρετική συμπίεση zip και εφαρμογή πολιτικής διατήρησης.
class DatabaseBackupService {
  DatabaseBackupService._();

  static String _sqlEscapeSingleQuotedPath(String path) =>
      path.replaceAll("'", "''");

  /// Διαδρομή για SQLite: forward slashes, απόλυτη.
  static String _sqlitePathLiteral(String absoluteNativePath) {
    final abs = p.isAbsolute(absoluteNativePath)
        ? absoluteNativePath
        : p.absolute(absoluteNativePath);
    return abs.replaceAll('\\', '/');
  }

  static Future<DatabaseBackupResult> runBackup(
    DatabaseBackupSettings settings, {
    bool requireDestination = true,
  }) async {
    final dest = settings.destinationDirectory.trim();
    if (dest.isEmpty) {
      if (requireDestination) {
        return const DatabaseBackupResult(
          success: false,
          message: 'Ορίστε φάκελο προορισμού.',
        );
      }
      return const DatabaseBackupResult(success: false);
    }

    final destDir = Directory(dest);
    try {
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
    } catch (e) {
      return DatabaseBackupResult(
        success: false,
        message: 'Δεν ήταν δυνατή η δημιουργία φακέλου: $e',
      );
    }

    final db = await DatabaseHelper.instance.database;
    final sourcePath = db.path;
    final baseName = p.basenameWithoutExtension(sourcePath);
    final stamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final stem = settings.namingFormat ==
            DatabaseBackupNamingFormat.dateTimeThenBase
        ? '${stamp}_$baseName'
        : '${baseName}_$stamp';
    final dbFileName = '$stem.db';

    final outDbPath = p.join(dest, dbFileName);
    final outDbFile = File(outDbPath);
    try {
      if (await outDbFile.exists()) {
        await outDbFile.delete();
      }
    } catch (e) {
      return DatabaseBackupResult(
        success: false,
        message: 'Δεν ήταν δυνατή η διαγραφή υπάρχοντος αρχείου: $e',
      );
    }

    final vacuumLiteral =
        _sqlEscapeSingleQuotedPath(_sqlitePathLiteral(outDbPath));

    try {
      await db.execute("VACUUM INTO '$vacuumLiteral'");
    } catch (e) {
      try {
        if (await outDbFile.exists()) await outDbFile.delete();
      } catch (_) {}
      return DatabaseBackupResult(
        success: false,
        message: 'Το VACUUM INTO απέτυχε: $e',
      );
    }

    var finalPath = outDbPath;
    if (settings.zipOutput) {
      final zipPath = p.join(dest, '$stem.zip');
      try {
        final bytes = await outDbFile.readAsBytes();
        final archive = Archive()
          ..addFile(ArchiveFile(dbFileName, bytes.length, bytes));
        final zipped = ZipEncoder().encode(archive);
        if (zipped == null) {
          throw StateError('ZipEncoder.encode επέστρεψε null');
        }
        await File(zipPath).writeAsBytes(zipped, flush: true);
        await outDbFile.delete();
        finalPath = zipPath;
      } catch (e) {
        return DatabaseBackupResult(
          success: false,
          message: 'Η συμπίεση zip απέτυχε: $e',
          outputPath: outDbPath,
        );
      }
    }

    try {
      await _applyRetention(destDir, baseName, settings);
    } catch (_) {}

    return DatabaseBackupResult(
      success: true,
      outputPath: finalPath,
      message: 'Το αντίγραφο ολοκληρώθηκε.',
    );
  }

  static Future<void> _applyRetention(
    Directory destDir,
    String baseName,
    DatabaseBackupSettings settings,
  ) async {
    if (!settings.retentionMaxAgeEnabled && !settings.retentionMaxCopiesEnabled) {
      return;
    }

    final escapedBase = RegExp.escape(baseName);
    final dateFirst = RegExp(
      '^(\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2})_$escapedBase\\.(db|zip)\$',
    );
    final baseFirst = RegExp(
      '^${escapedBase}_(\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2})\\.(db|zip)\$',
    );

    final backups = <File>[];
    await for (final entity in destDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!dateFirst.hasMatch(name) && !baseFirst.hasMatch(name)) continue;
      backups.add(entity);
    }

    if (backups.isEmpty) return;

    if (settings.retentionMaxAgeEnabled) {
      final cutoff = DateTime.now().subtract(
        Duration(days: settings.retentionMaxAgeDays),
      );
      for (final f in backups) {
        try {
          final stat = await f.stat();
          if (stat.modified.isBefore(cutoff)) {
            await f.delete();
          }
        } catch (_) {}
      }
    }

    if (!settings.retentionMaxCopiesEnabled) return;

    final remaining = <File>[];
    await for (final entity in destDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!dateFirst.hasMatch(name) && !baseFirst.hasMatch(name)) continue;
      remaining.add(entity);
    }
    if (remaining.length <= settings.retentionMaxCopies) return;

    remaining.sort((a, b) {
      try {
        return b.lastModifiedSync().compareTo(a.lastModifiedSync());
      } catch (_) {
        return 0;
      }
    });

    final excess = remaining.skip(settings.retentionMaxCopies);
    for (final f in excess) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
}
