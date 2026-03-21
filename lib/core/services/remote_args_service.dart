import '../database/database_helper.dart';
import '../models/remote_tool_arg.dart';

/// Υπηρεσία διαχείρισης ορισμάτων γραμμής εντολών για VNC και AnyDesk.
/// Τα ορίσματα αποθηκεύονται στη βάση με placeholders {TARGET} και {PASSWORD}.
class RemoteArgsService {
  RemoteArgsService(this._db);

  final DatabaseHelper _db;

  /// Επιστρέφει τα ορίσματα για το δοσμένο εργαλείο (π.χ. 'vnc', 'anydesk').
  Future<List<RemoteToolArg>> getArgsForTool(String toolName) async {
    final db = await _db.database;
    final rows = await db.query(
      'remote_tool_args',
      where: 'tool_name = ?',
      whereArgs: [toolName],
      orderBy: 'id ASC',
    );
    return rows.map(RemoteToolArg.fromMap).toList();
  }

  /// Επιστρέφει μόνο τα ενεργά ορίσματα για το εργαλείο.
  Future<List<RemoteToolArg>> getActiveArgsForTool(String toolName) async {
    final all = await getArgsForTool(toolName);
    return all.where((a) => a.isActive).toList();
  }

  /// Προσθέτει νέο όρισμα.
  Future<void> addArg(RemoteToolArg arg) async {
    final db = await _db.database;
    final map = arg.toMap()..remove('id');
    await db.insert('remote_tool_args', map);
  }

  /// Ενημερώνει υπάρχον όρισμα.
  Future<void> updateArg(RemoteToolArg arg) async {
    if (arg.id == null) return;
    final db = await _db.database;
    final map = arg.toMap()..remove('id');
    await db.update(
      'remote_tool_args',
      map,
      where: 'id = ?',
      whereArgs: [arg.id],
    );
  }

  /// Διαγράφει όρισμα (φυσική διαγραφή — ο πίνακας remote_tool_args δεν χρησιμοποιεί soft delete).
  Future<void> deleteArg(int id) async {
    final db = await _db.database;
    await db.delete(
      'remote_tool_args',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Αλλάζει την κατάσταση isActive και αποθηκεύει.
  Future<void> toggleArg(RemoteToolArg arg) async {
    await updateArg(arg.copyWith(isActive: !arg.isActive));
  }
}
