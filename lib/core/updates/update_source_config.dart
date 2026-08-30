import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/app_config.dart';

/// Επίλυση διαδρομής φακέλου ενημερώσεων (ρύθμιση χρήστη → update_source.json → null).
class UpdateSourceConfig {
  UpdateSourceConfig({
    required this.getUserUpdateFolderPath,
    String Function()? executableDirectoryResolver,
    Future<String?> Function(String filePath)? readUpdateSourceJson,
  }) : _executableDirectoryResolver =
           executableDirectoryResolver ??
           (() => AppConfig.applicationExecutableDirectory),
       _readUpdateSourceJson =
           readUpdateSourceJson ?? _defaultReadUpdateSourceJson;

  final Future<String?> Function() getUserUpdateFolderPath;
  final String Function() _executableDirectoryResolver;
  final Future<String?> Function(String filePath) _readUpdateSourceJson;

  static const String updateSourceFileName = 'update_source.json';
  static const String updateFolderPathKey = 'updateFolderPath';

  /// (α) τοπική ρύθμιση, (β) `update_source.json` δίπλα στο εκτελέσιμο, (γ) null.
  Future<String?> resolveUpdateFolderPath() async {
    final user = (await getUserUpdateFolderPath())?.trim();
    if (user != null && user.isNotEmpty) {
      return user;
    }
    return readInstallerRecordedFolder();
  }

  /// Ο φάκελος που κατέγραψε το πρόγραμμα εγκατάστασης δίπλα στο εκτελέσιμο.
  ///
  /// Είναι ο φάκελος **από τον οποίο έγινε η εγκατάσταση** — όχι εργοστασιακή
  /// προεπιλογή και όχι «τελευταία σωστή ρύθμιση». Γράφεται μία φορά, από το
  /// script εγκατάστασης, και επιβιώνει τις ενημερώσεις: η αποσυμπίεση νέας
  /// έκδοσης τον παραλείπει ρητά ώστε να μη χαθεί.
  ///
  /// `null` όταν το αρχείο λείπει ή δεν έχει έγκυρη διαδρομή — τυπικό σε
  /// εκτέλεση από τον φάκελο ανάπτυξης, που δεν εγκαταστάθηκε ποτέ.
  Future<String?> readInstallerRecordedFolder() async {
    final exeDir = _executableDirectoryResolver();
    final jsonPath = p.join(exeDir, updateSourceFileName);
    final fromFile = await _readUpdateSourceJson(jsonPath);
    final trimmed = fromFile?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return null;
  }

  static Future<String?> _defaultReadUpdateSourceJson(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      final path = raw[updateFolderPathKey];
      if (path is! String) return null;
      return path.trim().isEmpty ? null : path.trim();
    } catch (_) {
      return null;
    }
  }
}
