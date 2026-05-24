import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/services/building_map_storage.dart';
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

/// Αποτέλεσμα επαναφοράς από zip αντιγράφου.
class DatabaseRestoreResult {
  const DatabaseRestoreResult({
    required this.success,
    this.databasePath,
    this.message,
    this.imagesRelinked = 0,
  });

  final bool success;
  final String? databasePath;
  final String? message;
  final int imagesRelinked;
}

/// Αφαιρετική κλάση εκτέλεσης αντιγράφου: φάκελος προορισμού, μορφή ονομασίας, zip (μέσω [DatabaseBackupService]).
class DatabaseBackupFileOperation {
  DatabaseBackupFileOperation._();

  /// Εκτελεί το αντίγραφο και επιστρέφει [DatabaseBackupResult] (επιτυχία / μήνυμα σφάλματος).
  static Future<DatabaseBackupResult> run(DatabaseBackupSettings settings) =>
      DatabaseBackupService.runBackup(settings);

  /// Επαναφορά από zip (βάση + εικόνες χαρτών).
  static Future<DatabaseRestoreResult> restoreFromZip(
    String zipPath, {
    required String targetDatabasePath,
  }) =>
      DatabaseBackupService.restoreFromBackupZip(
        zipPath,
        targetDatabasePath: targetDatabasePath,
      );
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
    if (!settings.backupOnExit) {
      return const DatabaseBackupResult(
        success: false,
        message:
            'Η λειτουργία αντιγράφων ασφαλείας είναι απενεργοποιημένη στις ρυθμίσεις.',
      );
    }

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

    final useZipBundle =
        settings.includeMapImagesInBackup || settings.zipOutput;
    var finalPath = outDbPath;

    if (useZipBundle) {
      final zipPath = p.join(dest, '$stem.zip');
      try {
        final archive = Archive();
        final dbBytes = await outDbFile.readAsBytes();
        final innerDbName = settings.includeMapImagesInBackup
            ? BuildingMapStorage.backupZipDbFileName
            : dbFileName;
        archive.addFile(ArchiveFile(innerDbName, dbBytes.length, dbBytes));

        if (settings.includeMapImagesInBackup) {
          final mapFiles = await BuildingMapStorage.listPortableImageFiles();
          for (final img in mapFiles) {
            try {
              final bytes = await img.readAsBytes();
              final entryName = p.posix.join(
                BuildingMapStorage.backupZipMapsFolderName,
                p.basename(img.path),
              );
              archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
            } catch (_) {}
          }
        }

        final zipped = ZipEncoder().encode(archive);
        await File(zipPath).writeAsBytes(zipped, flush: true);
        try {
          await outDbFile.delete();
        } catch (_) {}
        finalPath = zipPath;
      } catch (e) {
        return DatabaseBackupResult(
          success: false,
          message: settings.includeMapImagesInBackup
              ? 'Η συμπίεση zip (βάση + εικόνες χαρτών) απέτυχε: $e'
              : 'Η συμπίεση zip απέτυχε: $e',
          outputPath: outDbPath,
        );
      }
    }

    try {
      await _applyRetention(destDir, baseName, settings);
    } catch (_) {}

    final tail = settings.includeMapImagesInBackup
        ? ' (βάση + εικόνες χαρτών)'
        : '';
    return DatabaseBackupResult(
      success: true,
      outputPath: finalPath,
      message: 'Το αντίγραφο ολοκληρώθηκε$tail.',
    );
  }

  /// Αποσυμπίεση zip αντιγράφου· τοποθετεί `call_logger.db` και `maps_images/` δίπλα στο [targetDatabasePath].
  static Future<DatabaseRestoreResult> restoreFromBackupZip(
    String zipPath, {
    required String targetDatabasePath,
  }) async {
    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      return const DatabaseRestoreResult(
        success: false,
        message: 'Το αρχείο zip δεν βρέθηκε.',
      );
    }

    final targetDb = p.normalize(p.absolute(targetDatabasePath));
    final targetDir = p.dirname(targetDb);
    final mapsRoot = p.join(
      targetDir,
      BuildingMapStorage.mapsImagesDirName,
    );

    try {
      await Directory(targetDir).create(recursive: true);
      await Directory(mapsRoot).create(recursive: true);
    } catch (e) {
      return DatabaseRestoreResult(
        success: false,
        message: 'Δεν ήταν δυνατή η δημιουργία φακέλων προορισμού: $e',
      );
    }

    Archive archive;
    try {
      final bytes = await zipFile.readAsBytes();
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      return DatabaseRestoreResult(
        success: false,
        message: 'Αποτυχία ανάγνωσης/αποσυμπίεσης zip: $e',
      );
    }

    ArchiveFile? dbEntry;
    for (final f in archive.files) {
      if (f.isFile && f.name.toLowerCase().endsWith('.db')) {
        if (f.name == BuildingMapStorage.backupZipDbFileName ||
            dbEntry == null) {
          dbEntry = f;
          if (f.name == BuildingMapStorage.backupZipDbFileName) break;
        }
      }
    }

    if (dbEntry == null) {
      return const DatabaseRestoreResult(
        success: false,
        message: 'Δεν βρέθηκε αρχείο βάσης (.db) μέσα στο zip.',
      );
    }

    try {
      final existingDb = File(targetDb);
      if (await existingDb.exists()) {
        await existingDb.delete();
      }
      await existingDb.writeAsBytes(
        Uint8List.fromList(dbEntry.content),
        flush: true,
      );
    } catch (e) {
      return DatabaseRestoreResult(
        success: false,
        message: 'Αποτυχία εγγραφής βάσης στον προορισμό: $e',
      );
    }

    var imagesCopied = 0;
    final mapsPrefix = '${BuildingMapStorage.backupZipMapsFolderName}/';
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final name = f.name.replaceAll('\\', '/');
      if (!name.startsWith(mapsPrefix)) continue;
      final base = p.basename(name);
      if (base.isEmpty) continue;
      try {
        final dest = File(p.join(mapsRoot, base));
        await dest.writeAsBytes(Uint8List.fromList(f.content), flush: true);
        imagesCopied++;
      } catch (_) {}
    }

    var relinked = 0;
    try {
      final restoredDb = await openDatabase(
        targetDb,
        readOnly: false,
        singleInstance: false,
      );
      try {
        relinked =
            await BuildingMapStorage.relinkMissingFloorImagesAfterRestore(
          restoredDb,
        );
        await BuildingMapStorage.migrateStoredPathsToPortableIfNeeded(
          restoredDb,
        );
      } finally {
        await restoredDb.close();
      }
    } catch (_) {}

    return DatabaseRestoreResult(
      success: true,
      databasePath: targetDb,
      imagesRelinked: relinked,
      message: imagesCopied > 0
          ? 'Η επαναφορά ολοκληρώθηκε ($imagesCopied εικόνες χαρτών).'
          : 'Η επαναφορά της βάσης ολοκληρώθηκε.',
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
