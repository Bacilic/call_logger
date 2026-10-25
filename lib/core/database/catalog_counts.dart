import 'package:sqflite_common/sqlite_api.dart';

/// Πόσα **ενεργά** στοιχεία έχει κάθε κατάλογος — όσα δεν έχουν σβηστεί.
///
/// Η ρύθμιση της προειδοποίησης μαζικής διαγραφής λέει ποιοι κατάλογοι
/// καλύπτονται από αυτά τα πλήθη, όχι από νούμερα γραμμένα σταθερά: στο
/// αντίγραφο δοκιμών τα τμήματα ήταν 72, ενώ υπολογίζονταν κάτω από 50.
Future<({int users, int departments, int equipment})> activeCatalogCounts(
  DatabaseExecutor db,
) async {
  Future<int> count(String table) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table WHERE COALESCE(is_deleted, 0) = 0',
    );
    final value = rows.isEmpty ? null : rows.first['c'];
    return value is int ? value : (value is num ? value.toInt() : 0);
  }

  return (
    users: await count('users'),
    departments: await count('departments'),
    equipment: await count('equipment'),
  );
}
