import 'dart:io';

import 'package:path/path.dart' as path;

import '../config/app_config.dart';

/// Έλεγχος ύπαρξης μη-μοιραίων κρίσιμων πόρων στο `flutter_assets` κατά την εκκίνηση.
///
/// Μόνο ανάγνωση (`existsSync`) — καμία εγγραφή/διαγραφή. Χρησιμοποιείται για
/// μη-μπλοκάρουσα προειδοποίηση όταν η εφαρμογή έχει ήδη ξεκινήσει επιτυχώς.
class StartupAssetIntegrityService {
  StartupAssetIntegrityService({String? flutterAssetsDirectory})
    : flutterAssetsDirectory =
          flutterAssetsDirectory ??
          path.join(
            AppConfig.applicationExecutableDirectory,
            'data',
            'flutter_assets',
          );

  /// Ρίζα του φακέλου `flutter_assets` (εγχύσιμη για τεστ).
  final String flutterAssetsDirectory;

  static const List<({String relativePath, String label, bool isDirectory})>
  _criticalAssets = [
    (
      relativePath: 'fonts',
      label: 'Γραμματοσειρές/εικονίδια',
      isDirectory: true,
    ),
    (
      relativePath: 'FontManifest.json',
      label: 'Κατάλογος γραμματοσειρών',
      isDirectory: false,
    ),
    (
      relativePath: 'AssetManifest.bin',
      label: 'Κατάλογος πόρων',
      isDirectory: false,
    ),
    (relativePath: 'assets', label: 'Εικόνες εφαρμογής', isDirectory: true),
    (
      relativePath: 'packages/cupertino_icons/assets/CupertinoIcons.ttf',
      label: 'Εικονίδια Cupertino',
      isDirectory: false,
    ),
  ];

  /// Επιστρέφει φιλικές ελληνικές ετικέτες για όσα κρίσιμα λείπουν.
  ///
  /// Αν λείπει ολόκληρος ο φάκελος [flutterAssetsDirectory], θεωρεί όλα ως
  /// ελλείποντα χωρίς να πετάξει εξαίρεση.
  List<String> findMissingCriticalAssets() {
    final root = Directory(flutterAssetsDirectory);
    if (!root.existsSync()) {
      return _criticalAssets.map((e) => e.label).toList(growable: false);
    }

    final missing = <String>[];
    for (final entry in _criticalAssets) {
      final fullPath = path.join(flutterAssetsDirectory, entry.relativePath);
      final exists = entry.isDirectory
          ? Directory(fullPath).existsSync()
          : File(fullPath).existsSync();
      if (!exists) {
        missing.add(entry.label);
      }
    }
    return missing;
  }
}
