import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/database_helper.dart';
import '../database/settings_repository.dart';
import 'current_operator.dart';
import 'settings_service.dart';

/// Δήλωση **κοινού** κλειδιού: ανήκει στα δεδομένα, άρα είναι ίδιο για όλους.
///
/// Το αντίθετο του `ProfileSettingKey`. Εδώ μπαίνουν ρυθμίσεις που δεν έχει
/// νόημα —ή είναι επικίνδυνο— να διαφέρουν ανά χρήστη.
class SharedSettingKey {
  const SharedSettingKey(this.key, {this.migratesFromMachine = true});

  final String key;

  /// Η ρύθμιση ζούσε ως τώρα στον **υπολογιστή** του καθενός και ανεβαίνει
  /// στα κοινά μία φορά. Ό,τι γεννιέται κοινό εξαρχής δηλώνει `false`.
  final bool migratesFromMachine;
}

/// **Η μία θέση** όπου δηλώνεται ποια κλειδιά είναι κοινά ύστερα από τη
/// μετακόμιση της Φάσης 2.
abstract final class SharedSettingKeys {
  /// Πολιτική εκκαθάρισης Ιστορικού.
  ///
  /// **Γιατί κοινή:** καθαρίζει το ΚΟΙΝΟ Ιστορικό. Όσο ζούσε ανά μηχάνημα, ο
  /// χρήστης με την πιο «σφιχτή» ρύθμιση έσβηνε τις εγγραφές όλων — χωρίς
  /// κανείς άλλος να το ξέρει.
  static const SharedSettingKey auditRetentionConfig = SharedSettingKey(
    'audit_retention_config_v1',
  );

  /// Φάκελος από τον οποίο η εφαρμογή παίρνει τις ενημερώσεις.
  ///
  /// **Γιατί κοινός:** τον ορίζει ο διαχειριστής μία φορά και από εκεί
  /// ενημερώνονται όλοι.
  static const SharedSettingKey updateFolderPath = SharedSettingKey(
    'update_folder_path',
  );

  /// Οι προσαρμοσμένες αποχρώσεις των τμημάτων.
  ///
  /// **Γιατί κοινές:** το χρώμα ενός τμήματος είναι κοινή γλώσσα της ομάδας —
  /// «το κόκκινο τμήμα» πρέπει να σημαίνει το ίδιο για όλους.
  static const SharedSettingKey departmentPaletteSlots = SharedSettingKey(
    'department_custom_palette_slots_v2',
  );

  static const List<SharedSettingKey> all = [
    auditRetentionConfig,
    updateFolderPath,
    departmentPaletteSlots,
  ];
}

/// Ρυθμίσεις **των δεδομένων**: ζουν στον πίνακα `app_settings` και είναι ίδιες
/// για όλους όσοι ανοίγουν την ίδια βάση.
///
/// Συμμετρικό του `ProfileSettings`, με ανάποδη φορά μετάβασης: εκεί η κοινή
/// τιμή **κατεβαίνει** στο προφίλ· εδώ η τοπική τιμή **ανεβαίνει** στα κοινά.
///
/// **Το ανέβασμα γίνεται μία φορά και μόνο όταν τα κοινά είναι άδεια.** Ποιος
/// το κάνει:
/// - ο **διαχειριστής** — αυτός όρισε τη ρύθμιση για την ομάδα·
/// - ή **οποιοσδήποτε όταν δεν υπάρχει συνδεδεμένος χρήστης**, ώστε η
///   μονοχρηστική εγκατάσταση να μη χάσει τη ρύθμισή της στην αναβάθμιση.
///
/// Απλός χρήστης με δική του τοπική τιμή **δεν** την ανεβάζει: θα άλλαζε
/// σιωπηλά τη ρύθμιση όλων.
abstract final class SharedSettings {
  static String _prefKey(String baseKey) =>
      AppConfig.prefixedPreferencesKey(baseKey);

  static Future<String?> read(SharedSettingKey setting) async {
    final current = await _readShared(setting.key);
    if (current != null && current.trim().isNotEmpty) return current;
    if (!setting.migratesFromMachine) return null;
    return _promoteFromMachine(setting);
  }

  static Future<void> write(SharedSettingKey setting, String value) =>
      _writeShared(setting.key, value);

  /// Το ανέβασμα της τοπικής τιμής στα κοινά — μία φορά, στην πρώτη ανάγνωση
  /// μετά την αναβάθμιση. Η τοπική τιμή **δεν** σβήνεται: παλαιότερη έκδοση
  /// της εφαρμογής τη διαβάζει ακόμη.
  static Future<String?> _promoteFromMachine(SharedSettingKey setting) async {
    final operator = CurrentOperator.active;
    final mayPromote = operator == null || operator.isAdmin;
    if (!mayPromote) return null;

    final prefs = await SharedPreferences.getInstance();
    final local = prefs.get(_prefKey(setting.key));
    final text = _asText(local);
    if (text == null || text.trim().isEmpty) return null;

    await _writeShared(setting.key, text);
    return text;
  }

  /// Οι τοπικές τιμές είναι αποθηκευμένες τυπωμένες· οι λίστες (π.χ. η παλέτα)
  /// γίνονται κείμενο με διαχωριστικό που δεν εμφανίζεται σε τιμές χρώματος.
  static String? _asText(Object? value) {
    if (value == null) return null;
    if (value is List<String>) return value.join(listSeparator);
    return value.toString();
  }

  /// Διαχωριστικό για ρυθμίσεις που ήταν λίστες στις τοπικές ρυθμίσεις.
  static const String listSeparator = '';

  static List<String> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return raw.split(listSeparator);
  }

  static String encodeList(List<String> values) => values.join(listSeparator);

  static Future<String?> _readShared(String key) async {
    final reader = SettingsService.appSettingReader;
    if (reader != null) return reader(key);
    final db = _database();
    if (db == null) return null;
    return SettingsRepository(db).getSetting(key);
  }

  static Future<void> _writeShared(String key, String value) async {
    final writer = SettingsService.appSettingWriter;
    if (writer != null) return writer(key, value);
    final db = _database();
    if (db == null) return;
    await SettingsRepository(db).saveSetting(key, value);
  }

  /// **Ποτέ δεν ανοίγει βάση**: επιστρέφει μόνο ήδη ανοιχτή σύνδεση.
  ///
  /// Μια ρύθμιση δεν είναι λόγος να ξεκινήσει σύνδεση — και ένα άνοιγμα μέσα
  /// σε έλεγχο με παγωμένο ρολόι δεν ολοκληρώνεται ποτέ, οπότε η οθόνη που
  /// ζήτησε τη ρύθμιση θα έμενε για πάντα να περιμένει.
  static Database? _database() => DatabaseHelper.instance.openDatabaseOrNull;
}
