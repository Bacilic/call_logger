import 'package:sqflite_common/sqlite_api.dart';

import '../models/managed_server.dart';
import 'database_helper.dart';

/// Ανάγνωση/εγγραφή του πίνακα `servers`.
///
/// Οι διαγραφές είναι **soft**: μια εγγραφή που έφυγε μπορεί να αναφέρεται
/// ακόμη από ιστορικό ή από ανοιχτό διάλογο, και η σκληρή διαγραφή θα άφηνε
/// τον διάλογο να δείχνει κενό όνομα.
class ServersRepository {
  ServersRepository(this._db);

  final DatabaseHelper _db;

  Future<Database> get _database => _db.database;

  static int _compareSortOrder(ManagedServer a, ManagedServer b) {
    final c = a.sortOrder.compareTo(b.sortOrder);
    if (c != 0) return c;
    final n = a.name.compareTo(b.name);
    if (n != 0) return n;
    return a.id.compareTo(b.id);
  }

  /// Όλοι οι μη διαγραμμένοι, ταξινομημένοι.
  Future<List<ManagedServer>> getAll() async {
    final rows = await (await _database).query(
      'servers',
      where: 'deleted_at IS NULL',
      orderBy: 'sort_order ASC, name ASC',
    );
    return rows.map(ManagedServer.fromMap).toList();
  }

  Future<ManagedServer?> getById(int id) async {
    final rows = await (await _database).query(
      'servers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ManagedServer.fromMap(rows.first);
  }

  Future<int> insert(ManagedServer server) async {
    final db = await _database;
    final all = await getAll();
    final nextOrder = all.isEmpty
        ? 1
        : (all.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b) + 1);
    final id = await db.insert(
      'servers',
      server.copyWith(sortOrder: nextOrder).toInsertMap(),
    );
    if (server.isDefault) await setDefault(id);
    return id;
  }

  Future<void> update(ManagedServer server) async {
    await (await _database).update(
      'servers',
      server.toInsertMap(),
      where: 'id = ?',
      whereArgs: [server.id],
    );
    if (server.isDefault) await setDefault(server.id);
  }

  /// Ένας και μόνο προεπιλεγμένος: η σήμανση καθαρίζεται από όλους τους άλλους
  /// στην ίδια δοσοληψία, ώστε να μη μείνουν ποτέ δύο «προεπιλογές».
  Future<void> setDefault(int id) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.update('servers', {'is_default': 0}, where: 'is_default = 1');
      await txn.update(
        'servers',
        {'is_default': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Soft delete + συμπύκνωση σειράς ώστε το `sort_order` να μένει 1..n.
  ///
  /// Αν έφυγε ο προεπιλεγμένος, η προεπιλογή περνά στον πρώτο που απομένει —
  /// αλλιώς η επίλυση στόχου θα έμενε χωρίς εφεδρεία.
  Future<void> softDelete(int id) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.update(
        'servers',
        {'deleted_at': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      final rows = await txn.query('servers', where: 'deleted_at IS NULL');
      final remaining = rows.map(ManagedServer.fromMap).toList()
        ..sort(_compareSortOrder);
      for (var i = 0; i < remaining.length; i++) {
        await txn.update(
          'servers',
          {'sort_order': i + 1},
          where: 'id = ?',
          whereArgs: [remaining[i].id],
        );
      }
      if (remaining.isNotEmpty && !remaining.any((s) => s.isDefault)) {
        await txn.update(
          'servers',
          {'is_default': 1},
          where: 'id = ?',
          whereArgs: [remaining.first.id],
        );
      }
    });
  }
}
