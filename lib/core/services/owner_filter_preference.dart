import 'package:sqflite_common/sqlite_api.dart';

import '../models/owner_filter.dart';
import 'current_operator.dart';
import 'profile_settings.dart';

/// Διάβασμα και γράψιμο μιας επιλογής φίλτρου «χρήστης» στις προσωπικές
/// ρυθμίσεις — μία φορά, για όλες τις οθόνες που θυμούνται τέτοιο φίλτρο.
///
/// Κάθε οθόνη έχει δικό της κλειδί (οι Εκκρεμότητες, το Ιστορικό Κλήσεων και η
/// αναφορά Lansweeper είναι διαφορετικές δουλειές με διαφορετικές ανάγκες),
/// αλλά ο μηχανισμός είναι κοινός: χωρίς αναγνωρισμένο χρήστη δεν
/// αποθηκεύεται τίποτα, και άγνωστη αποθηκευμένη τιμή δεν μαντεύεται.
abstract final class OwnerFilterPreference {
  /// Η αποθηκευμένη επιλογή του ενεργού χρήστη· `null` όταν δεν έχει (ή δεν
  /// διαβάζεται) — ο καλών αποφασίζει την προεπιλογή της δικής του οθόνης.
  static Future<OwnerFilter?> read(Database db, ProfileSettingKey key) async {
    if (CurrentOperator.active?.id == null) return null;
    final stored = await ProfileSettings(db, setting: key).read(key);
    return OwnerFilter.fromStorage(stored);
  }

  /// Θυμάται την επιλογή για τον ενεργό χρήστη — τον ακολουθεί σε όποιον
  /// υπολογιστή καθίσει. Χωρίς χρήστη δεν γράφει τίποτα.
  static Future<void> write(
    Database db,
    ProfileSettingKey key,
    OwnerFilter owner,
  ) async {
    if (CurrentOperator.active?.id == null) return;
    await ProfileSettings(db, setting: key).write(key, owner.storageValue);
  }
}
