import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';

import '../config/app_config.dart';

/// Οι **παλιές, τοπικές** κατόψεις δίπλα στο εκτελέσιμο: `<exeDir>/maps_images/`.
///
/// Από την έκδοση σχήματος 68 η κάτοψη ζει μέσα στη βάση. Ο φάκελος διαβάζεται
/// μόνο από το «Ανέβασμα κατόψεων στη βάση» και από την επαναφορά παλιών
/// αντιγράφων ασφαλείας, που ακόμη τον περιέχουν.
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

  /// Όλα τα αρχεία εικόνων στον portable κατάλογο (για zip backup).
  static Future<List<File>> listPortableImageFiles() async {
    final root = Directory(await getPortableMapsRoot());
    if (!await root.exists()) return [];

    final out = <File>[];
    try {
      await for (final entity in root.list(
        recursive: false,
        followLinks: false,
      )) {
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
      final rows = await db.query(
        'building_map_floors',
        columns: ['id', 'image_path'],
      );
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
}
