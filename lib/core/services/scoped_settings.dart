import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/database_helper.dart';
import '../database/settings_repository.dart';
import 'current_operator.dart';
import 'profile_settings.dart';
import 'settings_service.dart';

/// Τυπωμένη αποθήκη ρυθμίσεων που **ξέρει μόνη της σε ποια εμβέλεια ανήκει
/// κάθε κλειδί** — η καθημερινή πόρτα προς την [ProfileSettings].
///
/// Υπάρχει ώστε η μετακόμιση ενός κλειδιού στα προσωπικά να κοστίζει **μία
/// γραμμή**: ο καλών γράφει `ScopedSettings.getBool(κλειδί)` αντί για
/// `prefs.getBool(...)`, και η απόφαση «πού ζει αυτό;» παίρνεται στον
/// κατάλογο [ProfileSettingKeys] — σε ένα και μόνο σημείο.
///
/// **Με συνδεδεμένο χρήστη** η τιμή ζει στο προφίλ του (πίνακας
/// `operator_settings`), ως κείμενο, και τον ακολουθεί σε όποιον υπολογιστή
/// καθίσει.
///
/// **Χωρίς συνδεδεμένο χρήστη όλα δουλεύουν όπως χθες:** η τιμή πηγαίνει
/// ακριβώς εκεί που πήγαινε πριν τη Φάση 2 — τα κοινά κλειδιά στον πίνακα
/// `app_settings` της βάσης, τα τοπικά στις ρυθμίσεις του υπολογιστή, με τους
/// **τυπωμένους** τρόπους που χρησιμοποιούσαν ως τώρα. Έτσι οι έλεγχοι και
/// κάθε ροή χωρίς προφίλ μένουν ανέγγιχτοι, και καμία αποθηκευμένη τιμή δεν
/// αλλάζει τύπο κάτω από τα πόδια παλαιότερης έκδοσης.
abstract final class ScopedSettings {
  /// Το κλειδί όπως αποθηκεύεται τοπικά (με πρόθεμα προφίλ CLI `--profile`).
  static String _prefKey(String baseKey) =>
      AppConfig.prefixedPreferencesKey(baseKey);

  static bool get _hasOperator => CurrentOperator.active?.id != null;

  /// Η πύλη προφίλ — μόνο όταν υπάρχει ΚΑΙ χρήστης ΚΑΙ ανοιχτή βάση.
  static Future<ProfileSettings?> _profileGate(
    ProfileSettingKey setting,
  ) async {
    if (!_hasOperator) return null;
    final db = _database();
    if (db == null) return null;
    return ProfileSettings(db, setting: setting);
  }

  /// **Ποτέ δεν ανοίγει βάση**: επιστρέφει μόνο ήδη ανοιχτή σύνδεση.
  ///
  /// Μια ρύθμιση δεν είναι λόγος να ξεκινήσει σύνδεση — και ένα άνοιγμα μέσα
  /// σε έλεγχο με παγωμένο ρολόι δεν ολοκληρώνεται ποτέ, οπότε η οθόνη που
  /// ζήτησε τη ρύθμιση θα έμενε για πάντα να περιμένει.
  static Database? _database() => DatabaseHelper.instance.openDatabaseOrNull;

  /// Ανάγνωση/εγγραφή στην παλιά, κοινή θέση (πίνακας `app_settings`).
  ///
  /// Περνά από τον **καθιερωμένο πάροχο** του [SettingsService] και όχι
  /// κατευθείαν από το repository: είναι το ίδιο σημείο που χρησιμοποιούν όλοι
  /// οι συνεργάτες, και το μόνο που μπορεί να αντικατασταθεί σε ελέγχους.
  /// Ο πάροχος καταχωρείται μετά το άνοιγμα της βάσης· όσο λείπει (π.χ. σε
  /// ελέγχους που στήνουν βάση απευθείας) η ίδια τιμή διαβάζεται από το
  /// repository. Δύο δρόμοι προς **την ίδια** αποθήκη, όχι δεύτερη πηγή.
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

  static bool _isMachineScoped(ProfileSettingKey setting) =>
      setting.legacySource == ProfileSettingLegacySource.machine;

  static Future<String?> getString(ProfileSettingKey setting) async {
    final gate = await _profileGate(setting);
    if (gate != null) return gate.read(setting);
    if (!_isMachineScoped(setting)) return _readShared(setting.key);
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey(setting.key));
  }

  static Future<void> setString(ProfileSettingKey setting, String value) async {
    final gate = await _profileGate(setting);
    if (gate != null) return gate.write(setting, value);
    if (!_isMachineScoped(setting)) return _writeShared(setting.key, value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey(setting.key), value);
  }

  /// Ανεκτική ανάγνωση λογικής τιμής.
  ///
  /// Δέχεται και τις **δύο ιστορικές γραφές**: `true/false` (τοπικές
  /// ρυθμίσεις) και `1/0` (πίνακας `app_settings`). Χωρίς αυτό, ένα κοινό
  /// κλειδί που κληρονομείται στο προφίλ θα διαβαζόταν ανάποδα.
  static Future<bool?> getBool(ProfileSettingKey setting) async {
    final gate = await _profileGate(setting);
    if (gate != null) return _parseBool(await gate.read(setting));
    if (!_isMachineScoped(setting)) {
      return _parseBool(await _readShared(setting.key));
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(setting.key));
  }

  static bool? _parseBool(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    if (value == 'true' || value == '1' || value == 'yes') return true;
    if (value == 'false' || value == '0' || value == 'no') return false;
    return null;
  }

  static Future<void> setBool(ProfileSettingKey setting, bool value) async {
    final gate = await _profileGate(setting);
    if (gate != null) return gate.write(setting, value ? 'true' : 'false');
    if (!_isMachineScoped(setting)) {
      // Τα κοινά κλειδιά γράφονταν πάντα ως `1`/`0` στη βάση — η γραφή μένει
      // ίδια, αλλιώς παλαιότερη έκδοση θα διάβαζε τιμή που δεν αναγνωρίζει.
      return _writeShared(setting.key, value ? '1' : '0');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(setting.key), value);
  }

  static Future<int?> getInt(ProfileSettingKey setting) async {
    final gate = await _profileGate(setting);
    if (gate != null) return int.tryParse((await gate.read(setting)) ?? '');
    if (!_isMachineScoped(setting)) {
      return int.tryParse((await _readShared(setting.key))?.trim() ?? '');
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefKey(setting.key));
  }

  static Future<void> setInt(ProfileSettingKey setting, int value) async {
    final gate = await _profileGate(setting);
    if (gate != null) return gate.write(setting, '$value');
    if (!_isMachineScoped(setting)) return _writeShared(setting.key, '$value');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey(setting.key), value);
  }

  static Future<double?> getDouble(ProfileSettingKey setting) async {
    final gate = await _profileGate(setting);
    if (gate != null) return double.tryParse((await gate.read(setting)) ?? '');
    if (!_isMachineScoped(setting)) {
      return double.tryParse((await _readShared(setting.key))?.trim() ?? '');
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_prefKey(setting.key));
  }

  static Future<void> setDouble(ProfileSettingKey setting, double value) async {
    final gate = await _profileGate(setting);
    if (gate != null) return gate.write(setting, '$value');
    if (!_isMachineScoped(setting)) return _writeShared(setting.key, '$value');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefKey(setting.key), value);
  }

  /// «Δεν έχω δική μου τιμή» — όχι «έχω δική μου και είναι κενή».
  static Future<void> remove(ProfileSettingKey setting) async {
    final gate = await _profileGate(setting);
    if (gate != null) return gate.clear(setting);
    if (!_isMachineScoped(setting)) return _writeShared(setting.key, '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey(setting.key));
  }
}
