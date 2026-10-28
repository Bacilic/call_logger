import 'dart:math';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Το κλειδί της ταυτότητας της βάσης στο `app_settings`.
const String kDatabaseIdentitySettingKey = 'database_identity';

/// Ποια βάση είναι αυτή — ανεξάρτητα από το όνομα ή τη θέση του αρχείου.
///
/// **Γιατί όχι η διαδρομή:** η βάση του νοσοκομείου, φερμένη αυτούσια στο
/// σπίτι, κάθεται συχνά στην ίδια διαδρομή και με το ίδιο όνομα με την
/// προηγούμενη βάση του σπιτιού. Το όνομα του αρχείου δεν λέει ποια βάση
/// είναι· το λέει το περιεχόμενό της. Η ταυτότητα γράφεται **μέσα** στη βάση
/// και ταξιδεύει μαζί της: ένα αντίγραφο είναι η ίδια βάση, μια άλλη βάση
/// στην ίδια διαδρομή είναι άλλη.
///
/// Γεννιέται στο πρώτο άνοιγμα που τη χρειαστεί. Δύο σταθμοί που ανοίγουν
/// ταυτόχρονα μια βάση χωρίς ταυτότητα δεν γράφουν δύο: η εγγραφή αγνοείται
/// αν προλάβει άλλος, και και οι δύο διαβάζουν ό,τι κέρδισε.
///
/// **Ποτέ μοιραίο:** επιστρέφει `null` αν η βάση δεν απαντά ή δεν δέχεται
/// εγγραφή — η ταυτότητα είναι ευκολία, όχι προϋπόθεση εκκίνησης.
Future<String?> ensureDatabaseIdentity(
  DatabaseExecutor db, {
  Random? random,
}) async {
  try {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT)',
    );
    final existing = await _readIdentity(db);
    if (existing != null) return existing;
    await db.insert('app_settings', {
      'key': kDatabaseIdentitySettingKey,
      'value': _newIdentity(random ?? Random.secure()),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return await _readIdentity(db);
  } catch (_) {
    return null;
  }
}

Future<String?> _readIdentity(DatabaseExecutor db) async {
  final rows = await db.query(
    'app_settings',
    columns: ['value'],
    where: 'key = ?',
    whereArgs: [kDatabaseIdentitySettingKey],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  final value = (rows.first['value'] as String?)?.trim() ?? '';
  return value.isEmpty ? null : value;
}

String _newIdentity(Random random) => [
  for (var i = 0; i < 16; i++)
    random.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();
