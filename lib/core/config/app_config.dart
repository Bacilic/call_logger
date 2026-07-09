import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Αποτέλεσμα ανάλυσης/επικύρωσης CLI ορισμάτων.
class CliArgumentsParseResult {
  const CliArgumentsParseResult._({
    this.profile,
    this.invalidParameter,
    this.restartedAfterCrash = false,
  });

  /// Έγκυρο όνομα προφίλ, null στην παραγωγική εκτέλεση χωρίς `--profile`.
  final String? profile;

  /// Η πρώτη άκυρη παράμετρος που εντοπίστηκε (για εμφάνιση στον χρήστη).
  final String? invalidParameter;

  /// True όταν η εφαρμογή επανεκκινήθηκε από τα Windows μετά από κατάρρευση.
  final bool restartedAfterCrash;

  bool get isValid => invalidParameter == null;

  String buildErrorMessage() {
    final bad = invalidParameter?.trim();
    final shown = (bad == null || bad.isEmpty) ? '(κενή)' : bad;
    return 'Άκυρη παράμετρος γραμμής εντολών: $shown\n\n'
        'Επιτρεπόμενες:\n'
        '--profile <όνομα> ή --profile=<όνομα>\n'
        '(όνομα: γράμματα, αριθμοί, _, -)\n'
        '--restarted-after-crash';
  }

  static CliArgumentsParseResult success({
    String? profile,
    bool restartedAfterCrash = false,
  }) =>
      CliArgumentsParseResult._(
        profile: profile,
        restartedAfterCrash: restartedAfterCrash,
      );

  static CliArgumentsParseResult failure(String invalidParameter) =>
      CliArgumentsParseResult._(invalidParameter: invalidParameter);
}

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

  /// True όταν η εφαρμογή επανεκκινήθηκε αυτόματα μετά από κατάρρευση/κόλλημα.
  static bool wasRestartedAfterCrash = false;

  /// Προεπιλεγμένη διαδρομή βάσης όταν τρέχει CLI προφίλ (μετά [initializeProfileStorage]).
  static String? _profileDefaultDbPath;

  /// True αν η διαδρομή μοιάζει με UNC δικτύου (Windows).
  static bool isUncDatabasePath(String dbPath) {
    final t = dbPath.trim();
    return t.startsWith(r'\\');
  }

  /// Επικυρώνει CLI ορίσματα. Κενή λίστα = παραγωγή.
  /// Επιτρέπονται `--profile` και `--restarted-after-crash`.
  static CliArgumentsParseResult validateCliArguments(List<String> arguments) {
    if (arguments.isEmpty) {
      return CliArgumentsParseResult.success();
    }

    String? profile;
    var restartedAfterCrash = false;
    var i = 0;
    while (i < arguments.length) {
      final arg = arguments[i];
      if (arg == '--restarted-after-crash') {
        restartedAfterCrash = true;
        i += 1;
        continue;
      }

      if (arg == '--profile') {
        if (profile != null) {
          return CliArgumentsParseResult.failure('--profile');
        }
        if (i + 1 >= arguments.length) {
          return CliArgumentsParseResult.failure('--profile');
        }
        final value = arguments[i + 1];
        final sanitized = _sanitizeProfileName(value);
        if (sanitized == null) {
          return CliArgumentsParseResult.failure(value);
        }
        profile = sanitized;
        i += 2;
        continue;
      }

      const prefix = '--profile=';
      if (arg.startsWith(prefix)) {
        if (profile != null) {
          return CliArgumentsParseResult.failure(arg);
        }
        final value = arg.substring(prefix.length);
        if (value.isEmpty) {
          return CliArgumentsParseResult.failure(arg);
        }
        final sanitized = _sanitizeProfileName(value);
        if (sanitized == null) {
          return CliArgumentsParseResult.failure(arg);
        }
        profile = sanitized;
        i += 1;
        continue;
      }

      return CliArgumentsParseResult.failure(arg);
    }

    return CliArgumentsParseResult.success(
      profile: profile,
      restartedAfterCrash: restartedAfterCrash,
    );
  }

  /// Αναλύει `--profile <name>` ή `--profile=<name>` από CLI arguments.
  static String? parseCliProfile(List<String> arguments) {
    final result = validateCliArguments(arguments);
    if (!result.isValid) return null;
    return result.profile;
  }

  /// Ορίζει [activeProfile] από CLI και προετοιμάζει φάκελο/προεπιλογή βάσης αν χρειάζεται.
  static Future<void> configureFromCliArguments(List<String> arguments) async {
    final result = validateCliArguments(arguments);
    assert(
      result.isValid,
      'Τα CLI ορίσματα πρέπει να έχουν επικυρωθεί πριν την εκκίνηση.',
    );
    wasRestartedAfterCrash = result.restartedAfterCrash;
    final profile = result.profile;
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
  /// Παραγωγή: `Data Base\call_logger.db` στον φάκελο του εκτελέσιμου.
  /// CLI προφίλ: `…/profiles/<profile>/call_logger.db` στο Application Support.
  static String get defaultDbPath {
    final profilePath = _profileDefaultDbPath;
    if (profilePath != null) {
      return profilePath;
    }
    return _portableProductionDefaultDbPath;
  }

  /// Ρίζα φορητών δεδομένων (ίδιος φάκελος με το εκτελέσιμο).
  static String get portableDataRoot =>
      path.normalize(applicationExecutableDirectory);

  static const String portableDataBaseDirName = 'Data Base';
  static const String portableMapsDirName = 'maps_images';
  static const String portableImagesDirName = 'images';
  static const String portableDictionariesDirName = 'dictionaries';

  static String get portableDataBaseDirectory => path.normalize(
    path.join(portableDataRoot, portableDataBaseDirName),
  );

  static String get portableMapsDirectory => path.normalize(
    path.join(portableDataRoot, portableMapsDirName),
  );

  static String get portableImagesDirectory => path.normalize(
    path.join(portableDataRoot, portableImagesDirName),
  );

  static String get _portableProductionDefaultDbPath => path.normalize(
    path.join(portableDataBaseDirectory, 'call_logger.db'),
  );

  /// Τοπική διαδρομή για εργαλεία CLI (`dart run` από τη ρίζα του project).
  static String get localDevDbPath =>
      path.join(Directory.current.path, portableDataBaseDirName, 'call_logger.db');

  /// Πρόθεμα assets για προαιρετικά bundled λεξικά (.txt).
  static const String bundledDictionariesAssetPrefix = 'assets/dictionaries/';

  /// Portable φάκελος λεξικού-πυρήνα στη ρίζα εφαρμογής.
  static String get portableDictionariesDirectory => path.normalize(
    path.join(portableDataRoot, portableDictionariesDirName),
  );

  /// Δημιουργεί φάκελο μόνο όταν κληθεί ρητά (όχι στην εκκίνηση).
  static Future<Directory> ensureDirectoryExists(String dirPath) async {
    final dir = Directory(path.normalize(dirPath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Πίνακας SQLite προσωπικών λέξεων ορθογραφίας.
  static const String userDictionaryTable = 'user_dictionary';

  /// Πίνακας master λεξικού (συσσωρευτής / Compile).
  static const String fullDictionaryTable = 'full_dictionary';

  /// Κατηγορία μόνο για αυτόματη ανάθεση (εισαγωγή TXT, πρόχειρο, compile).
  /// Δεν εμφανίζεται σε dropdowns επιλογής χρήστη ούτε στη λίστα ρυθμίσεων (κόμματα).
  static const String lexiconCategoryUnspecified = 'Χωρίς κατηγορία';
}
