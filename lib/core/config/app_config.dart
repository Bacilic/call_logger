import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Κεντρικές σταθερές ρυθμίσεων της εφαρμογής.
class AppConfig {
  AppConfig._();

  /// Προεπιλεγμένο timeout ανοίγματος βάσης δεδομένων (δευτερόλεπτα).
  static const int databaseOpenTimeoutSeconds = 8;

  /// Προεπιλεγμένος μέγιστος αριθμός προσπαθειών ανοίγματος βάσης.
  static const int databaseOpenMaxAttempts = 2;

  /// Όνομα CLI προφίλ (`--profile test1`). Null = κανονική παραγωγική λειτουργία.
  static String? activeProfile;

  /// True όταν εκτελείται με `--profile <όνομα>`.
  static bool get hasActiveProfile {
    final name = activeProfile?.trim();
    return name != null && name.isNotEmpty;
  }

  /// Προεπιλεγμένη διαδρομή βάσης όταν τρέχει CLI προφίλ (μετά [initializeProfileStorage]).
  static String? _profileDefaultDbPath;

  /// True αν η διαδρομή μοιάζει με UNC δικτύου (Windows).
  static bool isUncDatabasePath(String dbPath) {
    final t = dbPath.trim();
    return t.startsWith(r'\\');
  }

  /// Αναλύει `--profile <name>` ή `--profile=<name>` από CLI arguments.
  static String? parseCliProfile(List<String> arguments) {
    for (var i = 0; i < arguments.length; i++) {
      final arg = arguments[i];
      if (arg == '--profile') {
        if (i + 1 >= arguments.length) return null;
        return _sanitizeProfileName(arguments[i + 1]);
      }
      const prefix = '--profile=';
      if (arg.startsWith(prefix)) {
        final value = arg.substring(prefix.length);
        return _sanitizeProfileName(value);
      }
    }
    return null;
  }

  /// Ορίζει [activeProfile] από CLI και προετοιμάζει φάκελο/προεπιλογή βάσης αν χρειάζεται.
  static Future<void> configureFromCliArguments(List<String> arguments) async {
    final profile = parseCliProfile(arguments);
    if (profile == null) {
      activeProfile = null;
      _profileDefaultDbPath = null;
      return;
    }
    activeProfile = profile;
    await initializeProfileStorage();
  }

  /// Δημιουργεί `…/profiles/<profile>/` κάτω από Application Support και ορίζει default `.db`.
  static Future<void> initializeProfileStorage() async {
    final name = activeProfile?.trim();
    if (name == null || name.isEmpty) {
      _profileDefaultDbPath = null;
      return;
    }
    final profileDir = await profileDatabaseDirectory();
    await Directory(profileDir).create(recursive: true);
    _profileDefaultDbPath = path.normalize(
      path.join(profileDir, 'call_logger.db'),
    );
  }

  /// Κατάλογος προφίλ: `%AppData%\Roaming\<Company>\<Product>\profiles\<profile>\`.
  static Future<String> profileDatabaseDirectory() async {
    final name = activeProfile?.trim();
    if (name == null || name.isEmpty) {
      throw StateError('Δεν έχει οριστεί ενεργό CLI προφίλ.');
    }
    final support = await getApplicationSupportDirectory();
    return path.normalize(path.join(support.path, 'profiles', name));
  }

  /// Πρόθεμα κλειδιών SharedPreferences όταν τρέχει CLI προφίλ.
  static String prefixedPreferencesKey(String baseKey) {
    final name = activeProfile?.trim();
    if (name == null || name.isEmpty) {
      return baseKey;
    }
    return 'profile_${_sanitizeProfileName(name)}_$baseKey';
  }

  static String? _sanitizeProfileName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(trimmed)) {
      return null;
    }
    return trimmed;
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

  /// Προεπιλεγμένη διαδρομή βάσης.
  /// Παραγωγή: `..\Data Base\call_logger.db` δίπλα στο εκτελέσιμο.
  /// CLI προφίλ: `…/profiles/<profile>/call_logger.db` στο Application Support.
  static String get defaultDbPath {
    final profilePath = _profileDefaultDbPath;
    if (profilePath != null) {
      return profilePath;
    }
    return _portableProductionDefaultDbPath;
  }

  static String get _portableProductionDefaultDbPath => path.normalize(
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
