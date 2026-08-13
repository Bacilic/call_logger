import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/database/services/database_label.dart';
import 'settings_repository.dart';

/// Ό,τι ξέρει η ίδια η βάση για τον εαυτό της: ταυτότητα και υγεία.
///
/// Τα ερωτήματα ζουν εδώ και όχι στην υπηρεσία που τα εμφανίζει, όπως κάθε
/// άλλη πρόσβαση στη βάση: η υπηρεσία ρωτά, το repository ξέρει SQL.
class DatabaseIdentityRepository {
  DatabaseIdentityRepository(this.db);

  final Database db;

  /// Το όνομα που έδωσε ο χρήστης· `null` όταν δεν έχει οριστεί.
  Future<String?> readLabel() async {
    final raw = await SettingsRepository(
      db,
    ).getSetting(kDatabaseLabelSettingsKey);
    return normalizeDatabaseLabel(raw);
  }

  /// Αποθηκεύει το όνομα· `null` ή κενό το σβήνει.
  Future<void> writeLabel(String? label) async {
    final normalized = normalizeDatabaseLabel(label);
    await SettingsRepository(
      db,
    ).saveSetting(kDatabaseLabelSettingsKey, normalized ?? '');
  }

  /// Έκδοση σχήματος (`PRAGMA user_version`).
  Future<int?> readSchemaVersion() async {
    return _firstInt(await db.rawQuery('PRAGMA user_version'));
  }

  /// Χώρος που κρατά το αρχείο χωρίς να τον χρησιμοποιεί (`freelist`).
  Future<int?> readReclaimableBytes() async {
    final pageSize = _firstInt(await db.rawQuery('PRAGMA page_size'));
    final freelist = _firstInt(await db.rawQuery('PRAGMA freelist_count'));
    if (pageSize == null || freelist == null) return null;
    return pageSize * freelist;
  }

  /// Πότε άλλαξε κάτι τελευταία φορά, κατά το ιστορικό της εφαρμογής.
  Future<DateTime?> readLastChangeAt() async {
    final rows = await db.rawQuery('SELECT MAX(timestamp) AS v FROM audit_log');
    if (rows.isEmpty) return null;
    return DateTime.tryParse('${rows.first['v'] ?? ''}');
  }

  /// Πρώτη και τελευταία ημέρα με καταγεγραμμένη κλήση.
  ///
  /// Οι κλήσεις —σε αντίθεση με το ιστορικό— δεν καθαρίζονται περιοδικά, οπότε
  /// το εύρος τους λέει την αλήθεια για την ηλικία των δεδομένων.
  Future<({String? first, String? last})> readCallDateRange() async {
    final rows = await db.rawQuery(
      'SELECT MIN(date) AS a, MAX(date) AS b FROM calls',
    );
    if (rows.isEmpty) return (first: null, last: null);
    String? clean(Object? value) {
      final s = (value as String?)?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return (first: clean(rows.first['a']), last: clean(rows.first['b']));
  }

  static int? _firstInt(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return null;
    final value = rows.first.values.first;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }
}
