import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqflite.dart';

import '../config/app_config.dart';
import '../database/database_helper.dart';
import '../utils/safe_file_base_name.dart';

/// Φορητές κατόψεις δίπλα στη βάση: `[dbDir]/maps_images/`.
///
/// Στη βάση αποθηκεύεται σχετική διαδρομή `maps_images/<αρχείο>`.
class BuildingMapStorage {
  BuildingMapStorage._();

  static const String mapsImagesDirName = 'maps_images';

  /// Παλιός κατάλογος Application Support (μετανάστευση ανάγνωσης).
  static const String legacyAppSupportDirName = 'building_map_images';

  /// Όνομα αρχείου βάσης μέσα στο zip αντιγράφου με εικόνες χαρτών.
  static const String backupZipDbFileName = 'call_logger.db';

  /// Όνομα φακέλου εικόνων μέσα στο zip αντιγράφου.
  static const String backupZipMapsFolderName = mapsImagesDirName;

  /// Κατάλογος δίπλα στο αρχείο `.db` (προεπιλογή portable).
  static Future<String> getDatabaseDirectory() async {
    final db = await DatabaseHelper.instance.database;
    return p.normalize(p.dirname(db.path));
  }

  /// Απόλυτος φάκελος `maps_images` δίπλα στη βάση.
  static Future<String> getPortableMapsRoot() async {
    final dbDir = await getDatabaseDirectory();
    return p.normalize(p.join(dbDir, mapsImagesDirName));
  }

  /// Παλιός κατάλογος `[ApplicationSupport]/building_map_images/`.
  static Future<String?> getLegacyAppSupportMapsRoot() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return p.normalize(p.join(dir.path, legacyAppSupportDirName));
    } catch (_) {
      return null;
    }
  }

  /// Επιλύει αποθηκευμένη διαδρομή (σχετική ή απόλυτη/παλιά) σε απόλυτη για I/O.
  static Future<String> resolveToAbsolute(String stored) async {
    final trimmed = stored.trim();
    if (trimmed.isEmpty) return '';

    final dbDir = await getDatabaseDirectory();
    final portableRoot = await getPortableMapsRoot();

    if (p.isAbsolute(trimmed)) {
      final norm = p.normalize(trimmed);
      if (await File(norm).exists()) return norm;

      final byBase = p.join(portableRoot, p.basename(trimmed));
      if (await File(byBase).exists()) return byBase;

      final legacyRoot = await getLegacyAppSupportMapsRoot();
      if (legacyRoot != null) {
        final legacy = p.join(legacyRoot, p.basename(trimmed));
        if (await File(legacy).exists()) return legacy;
      }
      return norm;
    }

    final rel = trimmed.replaceAll('\\', '/');
    if (rel.startsWith('$mapsImagesDirName/') ||
        rel == mapsImagesDirName) {
      final underDb = p.normalize(p.join(dbDir, rel.replaceAll('/', p.separator)));
      if (await File(underDb).exists()) return underDb;
      final onlyName = p.basename(rel);
      final inPortable = p.join(portableRoot, onlyName);
      if (await File(inPortable).exists()) return inPortable;
      return underDb;
    }

    final inPortable = p.join(portableRoot, rel.replaceAll('/', p.separator));
    if (await File(inPortable).exists()) return inPortable;
    return p.normalize(p.join(dbDir, rel.replaceAll('/', p.separator)));
  }

  /// Αρχείο για αποθηκευμένη διαδρομή (μετά επίλυση).
  static Future<File> fileForStoredPath(String stored) async {
    final abs = await resolveToAbsolute(stored);
    return File(abs);
  }

  /// True αν το αρχείο δεν βρίσκεται ήδη στον portable/legacy κατάλογο της εφαρμογής.
  static Future<bool> isOutsidePortableStorage(String srcPath) async {
    final norm = p.normalize(p.absolute(srcPath));
    if (!await File(norm).exists()) return true;

    final portableRoot = await getPortableMapsRoot();
    if (_isPathInsideDirectory(norm, portableRoot)) return false;

    final legacyRoot = await getLegacyAppSupportMapsRoot();
    if (legacyRoot != null && _isPathInsideDirectory(norm, legacyRoot)) {
      return false;
    }

    final dbDir = await getDatabaseDirectory();
    if (_isPathInsideDirectory(norm, dbDir)) {
      return false;
    }

    try {
      final exeDir = p.normalize(AppConfig.applicationExecutableDirectory);
      if (_isPathInsideDirectory(norm, exeDir)) return false;
    } catch (_) {}

    return true;
  }

  static bool _isPathInsideDirectory(String filePath, String directoryPath) {
    final file = p.normalize(p.absolute(filePath));
    final dir = p.normalize(p.absolute(directoryPath));
    if (file == dir) return true;
    final prefix = dir.endsWith(p.separator) ? dir : '$dir${p.separator}';
    return file.startsWith(prefix);
  }

  /// Μετατρέπει απόλυτη διαδρομή σε `maps_images/<όνομα>` για αποθήκευση στη βάση.
  static Future<String> toStoredRelativePath(String absolutePath) async {
    final norm = p.normalize(p.absolute(absolutePath));
    final portableRoot = await getPortableMapsRoot();
    if (_isPathInsideDirectory(norm, portableRoot)) {
      return p.join(mapsImagesDirName, p.basename(norm)).replaceAll('\\', '/');
    }
    final dbDir = await getDatabaseDirectory();
    if (_isPathInsideDirectory(norm, dbDir)) {
      final rel = p.relative(norm, from: dbDir);
      return rel.replaceAll('\\', '/');
    }
    return p.join(mapsImagesDirName, p.basename(norm)).replaceAll('\\', '/');
  }

  /// Αντιγραφή επιλεγμένης εικόνας στον portable κατάλογο· επιστρέφει σχετική διαδρομή.
  ///
  /// Το όνομα αρχείου προκύπτει από [floorLabel] (π.χ. `1st_floor.png`).
  /// Αν υπάρχει ήδη αρχείο με το ίδιο όνομα, προστίθεται `yyyy-MM-dd_HH-mm-ss`.
  static Future<String> copyPickedImageToStorage(
    String srcPath, {
    required String floorLabel,
  }) async {
    final src = p.normalize(p.absolute(srcPath));
    final portableRoot = await getPortableMapsRoot();
    await Directory(portableRoot).create(recursive: true);

    if (!_isPathInsideDirectory(src, portableRoot)) {
      final ext = p.extension(src).toLowerCase();
      final safeExt = ext.isEmpty || ext == '.'
          ? '.png'
          : (ext == '.jpeg' ? '.jpg' : ext);
      final fileName = await _allocateUniqueImageFileName(
        portableRoot,
        floorLabel,
        safeExt,
      );
      final destPath = p.join(portableRoot, fileName);
      try {
        await File(src).copy(destPath);
      } catch (e) {
        throw BuildingMapStorageException('Αποτυχία αντιγραφής εικόνας: $e');
      }
      return p.join(mapsImagesDirName, fileName).replaceAll('\\', '/');
    }

    return toStoredRelativePath(src);
  }

  static Future<String> _allocateUniqueImageFileName(
    String portableRoot,
    String floorLabel,
    String extension,
  ) async {
    final base = safeFloorImageBaseName(floorLabel);
    var candidate = '$base$extension';
    if (!await File(p.join(portableRoot, candidate)).exists()) {
      return candidate;
    }
    final stamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    candidate = '${base}_$stamp$extension';
    if (!await File(p.join(portableRoot, candidate)).exists()) {
      return candidate;
    }
    final ms = DateTime.now().millisecondsSinceEpoch;
    return '${base}_${stamp}_$ms$extension';
  }

  /// Εισαγωγή εικόνας: αν είναι εξωτερική χρειάζεται [userApprovedPortableCopy].
  static Future<BuildingMapImageIngestResult> ingestPickedImage(
    String srcPath, {
    required String floorLabel,
    required bool userApprovedPortableCopy,
  }) async {
    final src = srcPath.trim();
    if (src.isEmpty) {
      return const BuildingMapImageIngestResult.failure('Κενή διαδρομή εικόνας.');
    }

    final outside = await isOutsidePortableStorage(src);
    if (outside && !userApprovedPortableCopy) {
      return const BuildingMapImageIngestResult.needsPortableConfirmation();
    }

    try {
      final stored = await copyPickedImageToStorage(
        src,
        floorLabel: floorLabel,
      );
      return BuildingMapImageIngestResult.success(stored);
    } catch (e) {
      return BuildingMapImageIngestResult.failure(e.toString());
    }
  }

  /// Όλα τα αρχεία εικόνων στον portable κατάλογο (για zip backup).
  static Future<List<File>> listPortableImageFiles() async {
    final root = Directory(await getPortableMapsRoot());
    if (!await root.exists()) return [];

    final out = <File>[];
    try {
      await for (final entity in root.list(recursive: false, followLinks: false)) {
        if (entity is! File) continue;
        final lower = entity.path.toLowerCase();
        if (lower.endsWith('.png') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.webp') ||
            lower.endsWith('.gif') ||
            lower.endsWith('.bmp')) {
          out.add(entity);
        }
      }
    } catch (_) {}
    return out;
  }

  /// Μετά restore: ενημέρωση `image_path` όπου λείπει το αρχείο αλλά υπάρχει στο `maps_images`.
  static Future<int> relinkMissingFloorImagesAfterRestore(Database db) async {
    var updated = 0;
    try {
      final rows = await db.query('building_map_floors', columns: ['id', 'image_path']);
      final portableRoot = await getPortableMapsRoot();
      for (final row in rows) {
        final id = row['id'] as int?;
        final stored = (row['image_path'] as String?)?.trim() ?? '';
        if (id == null || stored.isEmpty) continue;

        final abs = await resolveToAbsolute(stored);
        if (abs.isNotEmpty && await File(abs).exists()) continue;

        final name = p.basename(stored);
        if (name.isEmpty) continue;
        final candidate = p.join(portableRoot, name);
        if (!await File(candidate).exists()) continue;

        final rel = p.join(mapsImagesDirName, name).replaceAll('\\', '/');
        await db.update(
          'building_map_floors',
          {'image_path': rel},
          where: 'id = ?',
          whereArgs: [id],
        );
        updated++;
      }
    } catch (_) {}
    return updated;
  }

  /// Μία φορά: μετατροπή αποθηκευμένων απόλυτων διαδρομών σε σχετικές όπου το αρχείο υπάρχει.
  static Future<int> migrateStoredPathsToPortableIfNeeded(Database db) async {
    var updated = 0;
    try {
      final rows = await db.query('building_map_floors', columns: ['id', 'image_path']);
      for (final row in rows) {
        final id = row['id'] as int?;
        final stored = (row['image_path'] as String?)?.trim() ?? '';
        if (id == null || stored.isEmpty) continue;
        if (!p.isAbsolute(stored) && stored.replaceAll('\\', '/').startsWith('$mapsImagesDirName/')) {
          continue;
        }

        final abs = await resolveToAbsolute(stored);
        if (abs.isEmpty || !await File(abs).exists()) continue;

        final rel = await toStoredRelativePath(abs);
        if (rel == stored) continue;

        await db.update(
          'building_map_floors',
          {'image_path': rel},
          where: 'id = ?',
          whereArgs: [id],
        );
        updated++;
      }
    } catch (_) {}
    return updated;
  }

  /// Διαγραφή αρχείου από αποθηκευμένη διαδρομή (best-effort).
  static Future<bool> deleteStoredImageBestEffort(String storedPath) async {
    final trimmed = storedPath.trim();
    if (trimmed.isEmpty) return false;
    try {
      final abs = await resolveToAbsolute(trimmed);
      if (abs.isEmpty) return false;
      final file = File(abs);
      if (!await file.exists()) return false;
      await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}

class BuildingMapStorageException implements Exception {
  BuildingMapStorageException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BuildingMapImageIngestResult {
  const BuildingMapImageIngestResult._({
    required this.ok,
    this.storedRelativePath,
    this.needsPortableConfirmation = false,
    this.errorMessage,
  });

  const BuildingMapImageIngestResult.success(String relativePath)
      : this._(ok: true, storedRelativePath: relativePath);

  const BuildingMapImageIngestResult.needsPortableConfirmation()
      : this._(ok: false, needsPortableConfirmation: true);

  const BuildingMapImageIngestResult.failure(String message)
      : this._(ok: false, errorMessage: message);

  final bool ok;
  final String? storedRelativePath;
  final bool needsPortableConfirmation;
  final String? errorMessage;
}
