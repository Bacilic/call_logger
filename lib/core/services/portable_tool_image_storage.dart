import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/app_config.dart';

/// Φορητά εικονίδια εργαλείων απομακρυσμένης (`images/` δίπλα στο εκτελέσιμο).
class PortableToolImageStorage {
  PortableToolImageStorage._();

  static const String storedPrefix = 'images/';

  /// Αντιγραφή επιλεγμένου αρχείου στον portable φάκελο· επιστρέφει `images/<όνομα>`.
  static Future<String> copyPickedIconToPortable(String sourcePath) async {
    final src = p.normalize(p.absolute(sourcePath.trim()));
    await AppConfig.ensureDirectoryExists(AppConfig.portableImagesDirectory);
    final baseName = p.basename(src);
    var dest = p.join(AppConfig.portableImagesDirectory, baseName);
    if (p.normalize(src) == p.normalize(dest)) {
      return p.join(storedPrefix, baseName).replaceAll('\\', '/');
    }
    if (await File(dest).exists()) {
      final stem = p.basenameWithoutExtension(baseName);
      final ext = p.extension(baseName);
      var i = 1;
      while (await File(dest).exists()) {
        dest = p.join(
          AppConfig.portableImagesDirectory,
          '${stem}_$i$ext',
        );
        i++;
      }
    }
    await File(src).copy(dest);
    return p
        .join(storedPrefix, p.basename(dest))
        .replaceAll('\\', '/');
  }

  /// Επίλυση `icon_asset_key` σε απόλυτη διαδρομή αρχείου (ή null).
  static String? resolveIconFilePath(String? iconAssetKey) {
    final raw = iconAssetKey?.trim() ?? '';
    if (raw.isEmpty || raw.startsWith('assets/')) return null;

    final normalized = raw.replaceAll('\\', '/');
    if (normalized.startsWith(storedPrefix)) {
      final rel = normalized.substring(storedPrefix.length);
      if (rel.isEmpty) return null;
      final abs = p.normalize(
        p.join(AppConfig.portableImagesDirectory, rel.replaceAll('/', p.separator)),
      );
      if (File(abs).existsSync()) return abs;
      return null;
    }

    if (p.isAbsolute(raw)) {
      final abs = p.normalize(raw);
      if (File(abs).existsSync()) return abs;
    }
    return null;
  }

  static Future<bool> portableImagesFolderHasFiles() async {
    final dir = Directory(AppConfig.portableImagesDirectory);
    if (!await dir.exists()) return false;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) return true;
    }
    return false;
  }

  static Future<List<File>> listPortableImageFiles() async {
    final dir = Directory(AppConfig.portableImagesDirectory);
    if (!await dir.exists()) return [];
    final out = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) out.add(entity);
    }
    return out;
  }
}
