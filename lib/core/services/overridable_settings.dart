import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../config/app_config.dart';
import '../database/database_helper.dart';
import '../database/operator_settings_repository.dart';
import 'current_operator.dart';

/// Πού ζει η **παράκαμψη** μιας κοινής τιμής.
enum OverrideScope {
  /// Στον υπολογιστή. Δεν ταξιδεύει — και δεν την βλέπει κανείς άλλος.
  machine,

  /// Στο προφίλ του χρήστη. Τον ακολουθεί σε όποιο μηχάνημα καθίσει.
  profile,
}

/// Δήλωση ρύθμισης με **αλυσίδα**: κοινή τιμή για όλους, με προαιρετική
/// παράκαμψη.
class OverridableSettingKey {
  const OverridableSettingKey(this.key, {required this.scope});

  /// Το κλειδί της **παράκαμψης** (η κοινή τιμή ζει αλλού — στο `app_settings`
  /// ή σε στήλη πίνακα — και δίνεται στον [OverridableSettings.resolve]).
  final String key;

  final OverrideScope scope;

  /// Παράκαμψη ανά εργαλείο/οντότητα: το ίδιο κλειδί με επίθημα ταυτότητας.
  OverridableSettingKey forId(Object id) =>
      OverridableSettingKey('$key::$id', scope: scope);
}

/// **Η μία θέση** όπου δηλώνονται οι ρυθμίσεις με παράκαμψη (Φάση 3).
abstract final class OverridableSettingKeys {
  /// Διαδρομή εκτελέσιμου εργαλείου απομακρυσμένης, **ανά υπολογιστή**.
  ///
  /// Ο ορισμός του εργαλείου (όνομα, παράμετροι, εικονίδιο, σειρά) μένει
  /// κοινός· μόνο το πού βρίσκεται το πρόγραμμα αλλάζει από μηχάνημα σε
  /// μηχάνημα. Χωρίς αυτό, όποιος «διόρθωνε» τη διαδρομή του AnyDesk για το
  /// δικό του μηχάνημα τη χαλούσε για όλους.
  static const OverridableSettingKey remoteToolExecutablePath =
      OverridableSettingKey(
        'remote_tool_path_override',
        scope: OverrideScope.machine,
      );

  /// Κλειδί API της ΤΝ, **ανά χρήστη**.
  ///
  /// Η κοινή τιμή ανήκει στην ομάδα και την ορίζει ο διαχειριστής· όποιος
  /// θέλει δικό του κλειδί (δική του χρέωση ή δικά του όρια) το δηλώνει και
  /// τον ακολουθεί όπου καθίσει.
  static const OverridableSettingKey geminiApiKey = OverridableSettingKey(
    'gemini_api_key_override',
    scope: OverrideScope.profile,
  );

  static const List<OverridableSettingKey> all = [
    remoteToolExecutablePath,
    geminiApiKey,
  ];
}

/// Το τρίτο στρώμα εμβέλειας: **κοινή τιμή με προαιρετική παράκαμψη**.
///
/// Συμπληρώνει τα άλλα δύο (`SharedSettings` = μόνο κοινή, `ProfileSettings` =
/// μόνο προσωπική) για τις περιπτώσεις όπου χρειάζονται **και τα δύο**: μια
/// τιμή που ισχύει για όλους, την οποία ο καθένας μπορεί να παρακάμψει.
///
/// **Ο κανόνας της αλυσίδας:** ρωτάμε πρώτα την παράκαμψη· μόνο αν **δεν έχει
/// δηλωθεί** πέφτουμε στην κοινή.
///
/// **Η κρίσιμη διάκριση:** «δεν έχω δική μου τιμή» ≠ «έχω δική μου και είναι
/// επίτηδες κενή». Χωρίς αυτή, όποιος έσβηνε το περιεχόμενο της παράκαμψής του
/// δεν θα μπορούσε ποτέ να γυρίσει στην κοινή τιμή — θα κολλούσε σε μια κενή
/// που δεν θα μπορούσε να ξεκλειδώσει. Γι' αυτό υπάρχει ρητό
/// [clearOverride] («Χρήση της κοινής τιμής»), χωριστό από το γράψιμο κενού.
abstract final class OverridableSettings {
  static String _prefKey(String baseKey) =>
      AppConfig.prefixedPreferencesKey(baseKey);

  static Database? _database() => DatabaseHelper.instance.openDatabaseOrNull;

  /// Η παράκαμψη όπως έχει δηλωθεί, ή `null` όταν **δεν έχει δηλωθεί**.
  ///
  /// Κενό αλφαριθμητικό είναι έγκυρη απάντηση: σημαίνει «δήλωσα παράκαμψη και
  /// είναι επίτηδες κενή».
  static Future<String?> overrideOf(OverridableSettingKey setting) async {
    switch (setting.scope) {
      case OverrideScope.machine:
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(_prefKey(setting.key));
      case OverrideScope.profile:
        final operatorId = CurrentOperator.active?.id;
        final db = _database();
        if (operatorId == null || db == null) return null;
        return OperatorSettingsRepository(db).getValue(operatorId, setting.key);
    }
  }

  static Future<bool> hasOverride(OverridableSettingKey setting) async =>
      await overrideOf(setting) != null;

  /// Δηλώνει παράκαμψη. Κενό [value] = «δική μου, επίτηδες κενή».
  static Future<void> setOverride(
    OverridableSettingKey setting,
    String value,
  ) async {
    switch (setting.scope) {
      case OverrideScope.machine:
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefKey(setting.key), value);
      case OverrideScope.profile:
        final operatorId = CurrentOperator.active?.id;
        final db = _database();
        if (operatorId == null || db == null) return;
        await OperatorSettingsRepository(
          db,
        ).setValue(operatorId, setting.key, value);
    }
  }

  /// «Χρήση της κοινής τιμής»: αφαιρεί εντελώς τη δήλωση παράκαμψης.
  static Future<void> clearOverride(OverridableSettingKey setting) async {
    switch (setting.scope) {
      case OverrideScope.machine:
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefKey(setting.key));
      case OverrideScope.profile:
        final operatorId = CurrentOperator.active?.id;
        final db = _database();
        if (operatorId == null || db == null) return;
        await OperatorSettingsRepository(
          db,
        ).deleteValue(operatorId, setting.key);
    }
  }

  /// Η τιμή που ισχύει **εδώ και τώρα**: η παράκαμψη αν έχει δηλωθεί, αλλιώς
  /// η [shared].
  static Future<String> resolve(
    OverridableSettingKey setting, {
    required String shared,
  }) async {
    return (await overrideOf(setting)) ?? shared;
  }
}
