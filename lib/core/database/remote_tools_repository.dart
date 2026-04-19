import 'package:sqflite_common/sqlite_api.dart';

import '../models/remote_tool.dart';
import '../models/remote_tool_role.dart';
import 'database_helper.dart';

/// Ανάγνωση/ενημέρωση `remote_tools` + επίλυση τιμών από `remote_params` εξοπλισμού.
class RemoteToolsRepository {
  RemoteToolsRepository(this._db);

  final DatabaseHelper _db;

  Future<Database> get _database => _db.database;

  static const String _appKeyRemoteToolsV2Migrated = 'remote_tools_v2_migrated';

  /// One-shot migration: legacy στήλες → `arguments_json`· idempotent μέσω `app_settings`.
  Future<void> migrateLegacyFieldsToArguments() async {
    final db = await _database;
    final fr = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_appKeyRemoteToolsV2Migrated],
      limit: 1,
    );
    if (fr.isNotEmpty && ((fr.first['value'] as String?)?.trim() == '1')) {
      return;
    }

    final rows = await db.query('remote_tools');
    for (final row in rows) {
      final t = RemoteTool.fromMap(row);
      final updated = _migrateSingleToolArguments(t, row);
      if (updated != null) {
        await updateTool(updated);
      }
    }

    await db.execute(
      'INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?)',
      [_appKeyRemoteToolsV2Migrated, '1'],
    );
  }

  RemoteTool? _migrateSingleToolArguments(
    RemoteTool t,
    Map<String, dynamic> rawRow,
  ) {
    var args = List<RemoteToolArgument>.from(t.arguments);
    var changed = false;

    final hasRdpRow = args.any((a) => a.description.trim() == '__rdp_file__');
    final ct = (rawRow['config_template'] as String?)?.trim();
    if (ct != null && ct.isNotEmpty && !hasRdpRow) {
      args.add(
        RemoteToolArgument(
          value: ct,
          description: '__rdp_file__',
          isActive: true,
        ),
      );
      changed = true;
    }

    final rawPrefix = rawRow['vnc_host_prefix'] as String?;
    if (t.role == ToolRole.vnc && rawPrefix != null) {
      final p = rawPrefix.trim().isNotEmpty ? rawPrefix.trim() : 'PC';
      final hostArg = '-host=$p{EQUIPMENT_CODE}';
      final hasHost = args.any(
        (a) =>
            a.value.contains('{EQUIPMENT_CODE}') &&
            (a.value.startsWith('-host=') || a.value.contains('host=')),
      );
      if (!hasHost) {
        args.add(
          RemoteToolArgument(value: hostArg, description: '', isActive: true),
        );
        changed = true;
      }
    }

    if (!changed) return null;
    return t.copyWith(arguments: args);
  }

  /// `equipment.default_remote_tool` αποθηκεύεται ως TEXT· επιστρέφει null αν δεν είναι έγκυρο ακέραιο id.
  static int? parseDefaultRemoteToolId(String? stored) {
    final t = stored?.trim() ?? '';
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  static String? defaultRemoteToolIdToDbString(int? id) =>
      id == null ? null : '$id';

  /// Πρώτο ενεργό εργαλείο με τον ρόλο (ταξινόμηση `sort_order`, `name`) — **fallback** όταν δεν υπάρχει συγκεκριμένο id.
  Future<RemoteTool?> getFirstActiveByRole(ToolRole role) async {
    final rows = await (await _database).query(
      'remote_tools',
      where: 'is_active = ? AND deleted_at IS NULL AND role = ?',
      whereArgs: [1, role.dbValue],
      orderBy: 'sort_order ASC, name ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return RemoteTool.fromMap(rows.first);
  }

  Future<List<RemoteTool>> getActiveByRole(ToolRole role) async {
    final rows = await (await _database).query(
      'remote_tools',
      where: 'is_active = ? AND deleted_at IS NULL AND role = ?',
      whereArgs: [1, role.dbValue],
      orderBy: 'sort_order ASC, name ASC',
    );
    return rows.map(RemoteTool.fromMap).toList();
  }

  Future<RemoteTool?> getById(int id) async {
    final rows = await (await _database).query(
      'remote_tools',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return RemoteTool.fromMap(rows.first);
  }

  /// Ενεργά εργαλεία (χωρίς soft delete), ταξινόμηση `sort_order`, μετά `name`.
  Future<List<RemoteTool>> getActiveTools() async {
    final rows = await (await _database).query(
      'remote_tools',
      where: 'is_active = ? AND deleted_at IS NULL',
      whereArgs: [1],
      orderBy: 'sort_order ASC, name ASC',
    );
    return rows.map(RemoteTool.fromMap).toList();
  }

  /// Όλα τα εργαλεία συμπεριλαμβανομένων soft-deleted (επίλυση id, διαχείριση).
  Future<List<RemoteTool>> getAllTools() async {
    final rows = await (await _database).query(
      'remote_tools',
      orderBy: 'sort_order ASC, name ASC',
    );
    return rows.map(RemoteTool.fromMap).toList();
  }

  /// Μόνο μη διαγραμμένα (για λίστα ρυθμίσεων όπου τα soft-deleted κρύβονται).
  Future<List<RemoteTool>> getAllNonDeletedTools() async {
    final rows = await (await _database).query(
      'remote_tools',
      where: 'deleted_at IS NULL',
      orderBy: 'sort_order ASC, name ASC',
    );
    return rows.map(RemoteTool.fromMap).toList();
  }

  /// Πρώτο ενεργό εργαλείο (default primary όταν `calls_primary_tool_id` είναι null).
  Future<RemoteTool?> getFirstActiveTool() async {
    final list = await getActiveTools();
    return list.isEmpty ? null : list.first;
  }

  /// Τιμή στόχου από `remote_params`: πρώτα κλειδί `toolId` ως string, μετά legacy κλειδί ρόλου.
  String? resolveParamValue({
    required Map<String, String> remoteParams,
    required RemoteTool tool,
  }) {
    final idKey = tool.id.toString();
    final v = remoteParams[idKey]?.trim();
    if (v != null && v.isNotEmpty) return v;
    final roleKey = tool.role.dbValue;
    final legacy = remoteParams[roleKey]?.trim();
    if (legacy != null && legacy.isNotEmpty) return legacy;
    if (tool.role == ToolRole.anydesk) {
      final a = remoteParams['anydesk']?.trim();
      if (a != null && a.isNotEmpty) return a;
    }
    if (tool.role == ToolRole.vnc) {
      final vnc = remoteParams['vnc']?.trim();
      if (vnc != null && vnc.isNotEmpty) return vnc;
    }
    return null;
  }

  /// Προαιρετικό username: μόνο `remote_params['<id>_user']` (plaintext credentials live in arguments).
  String? resolveUsername({
    required Map<String, String> remoteParams,
    required RemoteTool tool,
  }) {
    final u = remoteParams['${tool.id}_user']?.trim();
    if (u != null && u.isNotEmpty) return u;
    return null;
  }

  /// Αντιστοίχιση εμφανιζόμενου ονόματος (π.χ. από `default_remote_tool`) → εργαλείο.
  Future<RemoteTool?> findByNameLoose(String? name) async {
    if (name == null) return null;
    final t = name.trim();
    if (t.isEmpty) return null;
    final lower = t.toLowerCase();
    final all = await getAllTools();
    for (final tool in all) {
      if (tool.name.trim().toLowerCase() == lower) return tool;
    }
    for (final tool in all) {
      if (tool.role.dbValue == lower) return tool;
    }
    if (lower.contains('anydesk')) {
      return getFirstActiveByRole(ToolRole.anydesk);
    }
    if (lower.contains('vnc')) {
      return getFirstActiveByRole(ToolRole.vnc);
    }
    if (lower.contains('rdp') || lower.contains('remote desktop')) {
      return getFirstActiveByRole(ToolRole.rdp);
    }
    return null;
  }

  Future<int> insertTool(RemoteTool tool) async {
    return (await _database).insert('remote_tools', tool.toInsertMap());
  }

  Future<void> updateTool(RemoteTool tool) async {
    await (await _database).update(
      'remote_tools',
      tool.toInsertMap(),
      where: 'id = ?',
      whereArgs: [tool.id],
    );
  }

  /// Soft delete: το εξάρτημα παραμένει στη βάση για επιλύσεις id σε εξοπλισμό/κλήσεις.
  /// Μετά την απομάκρυνση, αναριθμεί τα υπόλοιπα μη διαγραμμένα ώστε `sort_order`
  /// να είναι 1..n χωρίς κενά (όσα ήταν στη θέση > διαγραμμένη μετακινούνται κατά -1).
  Future<void> deleteTool(int id) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.update(
        'remote_tools',
        {'deleted_at': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _compactSortOrderNonDeletedInTransaction(txn);
    });
  }

  static int _compareSortOrder(RemoteTool a, RemoteTool b) {
    final c = a.sortOrder.compareTo(b.sortOrder);
    if (c != 0) return c;
    final n = a.name.compareTo(b.name);
    if (n != 0) return n;
    return a.id.compareTo(b.id);
  }

  Future<void> _compactSortOrderNonDeletedInTransaction(Transaction txn) async {
    final rows = await txn.query(
      'remote_tools',
      where: 'deleted_at IS NULL',
    );
    if (rows.isEmpty) return;
    final tools = rows.map(RemoteTool.fromMap).toList()
      ..sort(_compareSortOrder);
    for (var i = 0; i < tools.length; i++) {
      await txn.update(
        'remote_tools',
        {'sort_order': i + 1},
        where: 'id = ?',
        whereArgs: [tools[i].id],
      );
    }
  }

  /// Ενημέρωση διαδρομής εκτελέσιμου για όλα τα ενεργά εργαλεία με τον ρόλο (π.χ. μαζική ενημέρωση από ρυθμίσεις).
  Future<void> updateExecutablePathByRole(ToolRole role, String path) async {
    await (await _database).update(
      'remote_tools',
      {'executable_path': path.trim()},
      where: 'LOWER(role) = ? AND is_active = ? AND deleted_at IS NULL',
      whereArgs: [role.dbValue, 1],
    );
  }

  /// Τοποθετεί το εργαλείο στη θέση `positionOneBased` (1..n) και αναριθμεί όλα τα
  /// μη διαγραμμένα ώστε `sort_order` να είναι 1..n χωρίς κενά ή διπλότυπα.
  Future<void> reorderToolToPosition({
    required int toolId,
    required int positionOneBased,
  }) async {
    final all = await getAllNonDeletedTools();
    if (all.isEmpty) return;
    final sorted = [...all]..sort(_compareSortOrder);
    final ids = sorted.map((t) => t.id).toList();
    if (!ids.contains(toolId)) return;
    ids.remove(toolId);
    final maxPos = ids.length + 1;
    final pos = (positionOneBased.clamp(1, maxPos)) - 1;
    ids.insert(pos, toolId);
    final db = await _database;
    await db.transaction((txn) async {
      for (var i = 0; i < ids.length; i++) {
        await txn.update(
          'remote_tools',
          {'sort_order': i + 1},
          where: 'id = ?',
          whereArgs: [ids[i]],
        );
      }
    });
  }

  /// Ανταλλάσσει τις θέσεις ταξινόμησης δύο μη διαγραμμένων εργαλείων και
  /// αναριθμεί όλα ώστε `sort_order` να είναι 1..n χωρίς κενά ή διπλότυπα.
  /// Πρώτο εργαλείο με `deleted_at` set και ίδιο όνομα (trim, case-insensitive).
  /// [excludeToolId]: αγνόηση (π.χ. τρέχουσα επεξεργασία).
  Future<RemoteTool?> findFirstSoftDeletedByNameInsensitive(
    String name, {
    int? excludeToolId,
  }) async {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return null;
    final rows = await (await _database).query(
      'remote_tools',
      where: 'deleted_at IS NOT NULL',
    );
    for (final row in rows) {
      final t = RemoteTool.fromMap(row);
      if (excludeToolId != null && t.id == excludeToolId) continue;
      if (t.name.trim().toLowerCase() == n) return t;
    }
    return null;
  }

  /// Μετονομασία soft-deleted γραμμής ώστε να ελευθερωθεί το εμφανιζόμενο όνομα για νέο/ενημέρωση.
  Future<void> disambiguateSoftDeletedToolName(int id) async {
    final rows = await (await _database).query(
      'remote_tools',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final t = RemoteTool.fromMap(rows.first);
    var newName = '${t.name.trim()} · διεγραμμένο #${t.id}';
    final all = await getAllTools();
    final taken = {for (final x in all) x.name.trim().toLowerCase()};
    var u = 0;
    while (taken.contains(newName.trim().toLowerCase())) {
      u++;
      newName = '${t.name.trim()} · διεγραμμένο #${t.id} ($u)';
    }
    await (await _database).update(
      'remote_tools',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Επαναφορά soft-deleted: πλήρης ενημέρωση πεδίων και `deleted_at = NULL`.
  Future<void> restoreToolClearDeleted(RemoteTool tool) async {
    final cleared = tool.copyWith(clearDeletedAt: true);
    await (await _database).update(
      'remote_tools',
      cleared.toInsertMap(),
      where: 'id = ?',
      whereArgs: [tool.id],
    );
  }

  Future<void> swapSortOrderBetweenTools({
    required int toolIdA,
    required int toolIdB,
  }) async {
    if (toolIdA == toolIdB) return;
    final all = await getAllNonDeletedTools();
    if (all.length < 2) return;
    final sorted = [...all]..sort(_compareSortOrder);
    final ids = sorted.map((t) => t.id).toList();
    final ia = ids.indexOf(toolIdA);
    final ib = ids.indexOf(toolIdB);
    if (ia < 0 || ib < 0) return;
    final tmp = ids[ia];
    ids[ia] = ids[ib];
    ids[ib] = tmp;
    final db = await _database;
    await db.transaction((txn) async {
      for (var i = 0; i < ids.length; i++) {
        await txn.update(
          'remote_tools',
          {'sort_order': i + 1},
          where: 'id = ?',
          whereArgs: [ids[i]],
        );
      }
    });
  }
}
