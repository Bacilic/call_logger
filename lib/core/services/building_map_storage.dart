import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Αντίγραφα εικόνων κατόψεων σε `[applicationSupport]/building_map_images/`.
class BuildingMapStorage {
  BuildingMapStorage._();

  /// Αντιγραφή επιλεγμένου αρχείου εικόνας στον κατάλογο της εφαρμογής.
  static Future<String> copyPickedImageToStorage(String srcPath) async {
    final dir = await getApplicationSupportDirectory();
    final root = Directory(p.join(dir.path, 'building_map_images'));
    await root.create(recursive: true);
    final ext = p.extension(srcPath);
    final safeExt = ext.isEmpty ? '.png' : ext;
    final name = '${DateTime.now().millisecondsSinceEpoch}$safeExt';
    final destPath = p.join(root.path, name);
    await File(srcPath).copy(destPath);
    return destPath;
  }

  /// Προαιρετική διαγραφή αντιγράφου εικόνας από τον δίσκο (κατάλληλο μετά διαγραφή φύλλου κατόψης).
  /// Προσμετρά μόνο το συγκεκριμένο αρχείο· σε σφάλμα I/O δεν ρίχνει εξαίρεση προς τα έξω.
  static Future<bool> deleteStoredImageBestEffort(String absolutePath) async {
    final trimmed = absolutePath.trim();
    if (trimmed.isEmpty) return false;
    try {
      final file = File(trimmed);
      if (!await file.exists()) return false;
      await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
