import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';

import '../config/app_config.dart';

/// Φορητές κατόψεις δίπλα στο εκτελέσιμο: `<exeDir>/maps_images/`.
///
/// Στη βάση αποθηκεύεται σχετική διαδρομή `maps_images/<αρχείο>`.
class BuildingMapStorage {
  BuildingMapStorage._();

  static const String mapsImagesDirName = 'maps_images';

  /// Όνομα αρχείου βάσης μέσα στο zip αντιγράφου με εικόνες χαρτών.
  static const String backupZipDbFileName = 'call_logger.db';

  /// Όνομα φακέλου εικόνων μέσα στο zip αντιγράφου.
  static const String backupZipMapsFolderName = mapsImagesDirName;

  /// Απόλυτος φάκελος `maps_images` δίπλα στο εκτελέσιμο.
  static Future<String> getPortableMapsRoot() async =>
      AppConfig.portableMapsDirectory;

  static Future<String?> _firstExistingPath(List<String> candidates) async {
    for (final c in candidates) {
      if (c.isEmpty) continue;
      if (await File(c).exists()) return c;
    }
    return null;
  }

  /// Επιλύει αποθηκευμένη διαδρομή (σχετική ή απόλυτη) σε απόλυτη για I/O.
  static Future<String> resolveToAbsolute(String stored) async {
    final trimmed = stored.trim();
    if (trimmed.isEmpty) return '';

    final portableRoot = await getPortableMapsRoot();
    final fileName = p.basename(trimmed.replaceAll('\\', '/'));

    if (p.isAbsolute(trimmed)) {
      final norm = p.normalize(trimmed);
      final candidate = p.join(portableRoot, fileName);
      return await _firstExistingPath([candidate, norm]) ?? norm;
    }

    final rel = trimmed.replaceAll('\\', '/');
    if (rel.startsWith('$mapsImagesDirName/') || rel == mapsImagesDirName) {
      final onlyName = p.basename(rel);
      return p.join(portableRoot, onlyName);
    }

    return p.join(portableRoot, rel.replaceAll('/', p.separator));
  }

  /// Αρχείο για αποθηκευμένη διαδρομή (μετά επίλυση).
  static Future<File> fileForStoredPath(String stored) async {
    final abs = await resolveToAbsolute(stored);
    return File(abs);
  }

  /// True αν το αρχείο δεν βρίσκεται ήδη στον portable κατάλογο της εφαρμογής.
  static Future<bool> isOutsidePortableStorage(String srcPath) async {
    final norm = p.normalize(p.absolute(srcPath));
    if (!await File(norm).exists()) return true;

    final portableRoot = await getPortableMapsRoot();
    if (_isPathInsideDirectory(norm, portableRoot)) return false;

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
    return p
        .join(mapsImagesDirName, p.basename(norm))
        .replaceAll('\\', '/');
  }

  /// Αντιγραφή επιλεγμένης εικόνας στον portable κατάλογο· επιστρέφει σχετική διαδρομή.
  ///
  /// Το [targetFileName] ορίζει το τελικό όνομα αρχείου (με κατάληξη).
  static Future<String> copyPickedImageToStorage(
    String srcPath, {
    required String targetFileName,
  }) async {
    final src = p.normalize(p.absolute(srcPath));
    final portableRoot = await getPortableMapsRoot();
    await Directory(portableRoot).create(recursive: true);

    if (!_isPathInsideDirectory(src, portableRoot)) {
      final fileName = p.basename(targetFileName.replaceAll('\\', '/'));
      final destPath = p.join(portableRoot, fileName);
      if (await File(destPath).exists()) {
        throw BuildingMapStorageException(
          'Υπάρχει ήδη αρχείο με το όνομα «$fileName» στο maps_images.',
        );
      }
      try {
        await File(src).copy(destPath);
      } catch (e) {
        throw BuildingMapStorageException('Αποτυχία αντιγραφής εικόνας: $e');
      }
      return p.join(mapsImagesDirName, fileName).replaceAll('\\', '/');
    }

    return toStoredRelativePath(src);
  }

  /// Εισαγωγή εικόνας: αν είναι εξωτερική χρειάζεται απάντηση στον διάλογο
  /// ([userRespondedToPortablePrompt]) και επιλογή αντιγραφής ή εξωτερικής διαδρομής.
  static Future<BuildingMapImageIngestResult> ingestPickedImage(
    String srcPath, {
    required bool userRespondedToPortablePrompt,
    required bool copyToPortable,
    required String? targetFileName,
  }) async {
    final src = srcPath.trim();
    if (src.isEmpty) {
      return const BuildingMapImageIngestResult.failure('Κενή διαδρομή εικόνας.');
    }

    final outside = await isOutsidePortableStorage(src);
    if (outside && !userRespondedToPortablePrompt) {
      return const BuildingMapImageIngestResult.needsPortableConfirmation();
    }

    try {
      if (outside && !copyToPortable) {
        final abs = p.normalize(p.absolute(src));
        if (!await File(abs).exists()) {
          return const BuildingMapImageIngestResult.failure(
            'Το αρχείο εικόνας δεν βρέθηκε στην επιλεγμένη διαδρομή.',
          );
        }
        return BuildingMapImageIngestResult.success(abs);
      }

      final name = targetFileName?.trim();
      if (name == null || name.isEmpty) {
        return const BuildingMapImageIngestResult.failure(
          'Δεν ορίστηκε όνομα αρχείου για μεταφορά.',
        );
      }
      final stored = await copyPickedImageToStorage(
        src,
        targetFileName: name,
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
