import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/app_config.dart';
import 'database_v1_schema.dart';

/// Κανονικοποιήσεις λεξικού και επιπλέον στήλες κατά το άνοιγμα βάσης (onOpen).
Future<void> applyLexiconOpenNormalizations(Database db) async {
  await normalizeLexiconSourceOnOpen(db);
  await normalizeLexiconCategoryLegacyOnOpen(db);
  await ensureDepartmentsMapRotationColumn(db);
  await ensureDepartmentsMapHiddenColumn(db);
  await ensureCallsNoSolutionColumn(db);
  await clearEquipmentDefaultRemoteToolOnOpen(db);
}

/// Το «κύριο εργαλείο» είναι πλέον υπολογιζόμενο (σειρά προτεραιότητας) — το παλιό
/// αποθηκευμένο `equipment.default_remote_tool` είναι νεκρό/παραπλανητικό. Καθαρίζεται
/// σε NULL (idempotent) ώστε να μη μένουν μπαγιάτικες τιμές που έκρυβαν κουμπιά κλήσης.
Future<void> clearEquipmentDefaultRemoteToolOnOpen(Database db) async {
  try {
    await db.rawUpdate(
      'UPDATE equipment SET default_remote_tool = NULL '
      'WHERE default_remote_tool IS NOT NULL',
    );
  } catch (_) {
    // Ο πίνακας μπορεί να λείπει σε ασυνήθιστα σενάρια.
  }
}

/// Παλιά τιμή πηγής `system` (asset) → `imported` (ίδια κατηγορία με TXT).
Future<void> normalizeLexiconSourceOnOpen(Database db) async {
  try {
    await db.rawUpdate(
      'UPDATE ${AppConfig.fullDictionaryTable} SET source = ? WHERE source = ?',
      ['imported', 'system'],
    );
  } catch (_) {
    // Πίνακας μπορεί να λείπει σε ασυνήθιστα σενάρια.
  }
}

/// Παλιές ετικέτες κατηγορίας `general` / `user` → `Γενική`.
Future<void> normalizeLexiconCategoryLegacyOnOpen(Database db) async {
  try {
    await db.rawUpdate(
      'UPDATE ${AppConfig.fullDictionaryTable} SET category = ? WHERE category = ?',
      ['Γενική', 'general'],
    );
    await db.rawUpdate(
      'UPDATE ${AppConfig.fullDictionaryTable} SET category = ? WHERE category = ?',
      ['Γενική', 'user'],
    );
  } catch (_) {
    // Πίνακας μπορεί να λείπει σε ασυνήθιστα σενάρια.
  }
}
