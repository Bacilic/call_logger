import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import '../database/old_database/lamp_settings_store.dart';

/// Φορητή βάση Λάμπας στο `Data Base/` δίπλα στο εκτελέσιμο.
class PortableLampStorage {
  PortableLampStorage._();

  static const String backupZipLampDbFolderName = 'lamp_db';

  /// Αντιγραφή επιλεγμένου `.db` στο portable `Data Base/`· σε αποτυχία επιστρέφει την αρχική διαδρομή.
  static Future<String> tryCopyLampDbToPortableDataBase(String pickedPath) async {
    final src = p.normalize(p.absolute(pickedPath.trim()));
    if (!await File(src).exists()) return pickedPath;

    try {
      await AppConfig.ensureDirectoryExists(AppConfig.portableDataBaseDirectory);
      final dest = p.normalize(
        p.join(AppConfig.portableDataBaseDirectory, p.basename(src)),
      );
      if (src == dest) return dest;
      await File(src).copy(dest);
      return dest;
    } catch (_) {
      return pickedPath;
    }
  }

  /// True αν η αποθηκευμένη διαδρομή ανάγνωσης αντιστοιχεί σε αρχείο στο portable `Data Base/`.
  static Future<bool> lampReadDbExistsInPortableDataBase() async {
    final readPath = await LampSettingsStore().getReadPath();
    if (readPath == null || readPath.trim().isEmpty) return false;
    final expected = p.normalize(
      p.join(
        AppConfig.portableDataBaseDirectory,
        p.basename(readPath.trim()),
      ),
    );
    return File(expected).exists();
  }

  /// Απόλυτη διαδρομή αρχείου Λάμπας για backup (μόνο αν στο portable Data Base).
  static Future<String?> portableLampDbPathForBackup() async {
    final readPath = await LampSettingsStore().getReadPath();
    if (readPath == null || readPath.trim().isEmpty) return null;
    final expected = p.normalize(
      p.join(
        AppConfig.portableDataBaseDirectory,
        p.basename(readPath.trim()),
      ),
    );
    if (await File(expected).exists()) return expected;
    return null;
  }
}
