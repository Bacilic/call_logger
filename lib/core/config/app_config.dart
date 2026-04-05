import 'dart:io';

import 'package:path/path.dart' as path;

/// Κεντρικές σταθερές ρυθμίσεων της εφαρμογής.
class AppConfig {
  AppConfig._();

  /// Προεπιλεγμένο timeout ανοίγματος βάσης δεδομένων (δευτερόλεπτα).
  static const int databaseOpenTimeoutSeconds = 15;

  /// True αν η διαδρομή μοιάζει με UNC δικτύου (Windows).
  static bool isUncDatabasePath(String dbPath) {
    final t = dbPath.trim();
    return t.startsWith(r'\\');
  }

  /// Κατάλογος του εκτελέσιμου (ή [Directory.current] αν δεν επιλύεται).
  static String get applicationExecutableDirectory {
    try {
      final exe = Platform.resolvedExecutable;
      if (exe.isNotEmpty) {
        return path.dirname(exe);
      }
    } catch (_) {}
    return Directory.current.path;
  }

  /// Προεπιλεγμένη διαδρομή βάσης: `..\Data Base\call_logger.db` από το φάκελο του εκτελέσιμου.
  /// Κατάλληλο για portable εγκατάσταση και πρώτη εκτέλεση.
  static String get defaultDbPath => path.normalize(
    path.join(
      applicationExecutableDirectory,
      '..',
      'Data Base',
      'call_logger.db',
    ),
  );

  /// Τοπική διαδρομή για εργαλεία CLI (`dart run` από τη ρίζα του project).
  static String get localDevDbPath =>
      path.join(Directory.current.path, 'Data Base', 'call_logger.db');

  /// Asset ελληνικού core λεξικού για ορθογραφία / lookup.
  static const String greekDictionaryAsset =
      'assets/dictionaries/greek_core_60k.txt';

  /// Πίνακας SQLite προσωπικών λέξεων ορθογραφίας.
  static const String userDictionaryTable = 'user_dictionary';

  /// Πίνακας master λεξικού (συσσωρευτής / Compile).
  static const String fullDictionaryTable = 'full_dictionary';

  /// Κατηγορία μόνο για αυτόματη ανάθεση (εισαγωγή TXT, πρόχειρο, compile).
  /// Δεν εμφανίζεται σε dropdowns επιλογής χρήστη ούτε στη λίστα ρυθμίσεων (κόμματα).
  static const String lexiconCategoryUnspecified = 'Χωρίς κατηγορία';
}
