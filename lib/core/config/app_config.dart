import 'dart:io';

import 'package:path/path.dart' as path;

/// Κεντρικές σταθερές ρυθμίσεων της εφαρμογής.
class AppConfig {
  AppConfig._();

  /// Προεπιλεγμένη διαδρομή δικτύου για το αρχείο της βάσης δεδομένων.
  static const String defaultDbPath =
      r'\\gnk.local\Departments\TPO\Multilab\call_logger.db';

  /// Τοπική διαδρομή για ανάπτυξη (fallback όταν το δίκτυο δεν είναι διαθέσιμο).
  static String get localDevDbPath =>
      path.join(Directory.current.path, 'Data Base', 'call_logger.db');

  /// Asset ελληνικού core λεξικού για ορθογραφία / lookup.
  static const String greekDictionaryAsset =
      'assets/dictionaries/greek_core_60k.txt';

  /// Πίνακας SQLite προσωπικών λέξεων ορθογραφίας.
  static const String userDictionaryTable = 'user_dictionary';
}
