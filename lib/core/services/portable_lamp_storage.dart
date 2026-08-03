import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import '../database/old_database/lamp_settings_store.dart';

/// Φορητή βάση Λάμπας στο `Data Base/` δίπλα στο εκτελέσιμο.
class PortableLampStorage {
  PortableLampStorage._();

  static const String backupZipLampDbFolderName = 'lamp_db';

  /// Πλήρης διαδρομή προορισμού μέσα στο portable `Data Base/`.
  static String portableDestinationFor(
    String pickedPath, {
    String? destinationFileName,
  }) {
    final name = destinationFileName?.trim();
    return p.normalize(
      p.join(
        AppConfig.portableDataBaseDirectory,
        (name == null || name.isEmpty)
            ? p.basename(p.normalize(p.absolute(pickedPath.trim())))
            : name,
      ),
    );
  }

  /// Αντιγραφή επιλεγμένου `.db` στο portable `Data Base/`.
  ///
  /// Ο καλών έχει ήδη αποφασίσει τη σύγκρουση: είτε δίνει [destinationFileName]
  /// (διατήρηση και των δύο) είτε [allowOverwrite]. Αν ο προορισμός υπάρχει και
  /// δεν ισχύει κανένα από τα δύο, ρίχνει σφάλμα αντί να αντιγράψει σιωπηλά ή
  /// να επιστρέψει άλλη διαδρομή από αυτήν που ζητήθηκε.
  ///
  /// Σε αποτυχία αντιγραφής προωθεί το πραγματικό σφάλμα (δεν το καταπίνει).
  static Future<String> tryCopyLampDbToPortableDataBase(
    String pickedPath, {
    String? destinationFileName,
    bool allowOverwrite = false,
  }) async {
    final src = p.normalize(p.absolute(pickedPath.trim()));
    // Ανύπαρκτη πηγή = διαδρομή αποθήκευσης που δεν δημιουργήθηκε ακόμα.
    if (!await File(src).exists()) return pickedPath;

    await AppConfig.ensureDirectoryExists(AppConfig.portableDataBaseDirectory);
    final dest = portableDestinationFor(
      src,
      destinationFileName: destinationFileName,
    );
    if (src == dest) return dest;
    if (await File(dest).exists() && !allowOverwrite) {
      throw StateError(
        'Ο προορισμός «$dest» υπάρχει ήδη και δεν δόθηκε άδεια αντικατάστασης '
        'ούτε εναλλακτικό όνομα.',
      );
    }
    await File(src).copy(dest);
    return dest;
  }

  /// True αν η αποθηκευμένη διαδρομή ανάγνωσης αντιστοιχεί σε αρχείο στο portable `Data Base/`.
  static Future<bool> lampReadDbExistsInPortableDataBase() async {
    final readPath = await LampSettingsStore().getReadPath();
    if (readPath == null || readPath.trim().isEmpty) return false;
    final expected = p.normalize(
      p.join(AppConfig.portableDataBaseDirectory, p.basename(readPath.trim())),
    );
    return File(expected).exists();
  }

  /// Απόλυτη διαδρομή αρχείου Λάμπας για backup (μόνο αν στο portable Data Base).
  static Future<String?> portableLampDbPathForBackup() async {
    final readPath = await LampSettingsStore().getReadPath();
    if (readPath == null || readPath.trim().isEmpty) return null;
    final expected = p.normalize(
      p.join(AppConfig.portableDataBaseDirectory, p.basename(readPath.trim())),
    );
    if (await File(expected).exists()) return expected;
    return null;
  }
}
