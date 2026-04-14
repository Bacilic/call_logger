import '../database/database_helper.dart';
import '../models/remote_tool.dart';
import '../models/remote_tool_arg.dart';
import '../models/remote_tool_role.dart';

/// Συμβατότητα: τα ορίσματα διαβάζονται από `remote_tools.arguments_json` ([RemoteTool.arguments]).
class RemoteArgsService {
  RemoteArgsService(this._db);

  final DatabaseHelper _db;

  Future<List<RemoteToolArg>> _argsForToolRow(Map<String, dynamic> toolRow) async {
    final tool = RemoteTool.fromMap(toolRow);
    final key = tool.role.dbValue;
    return tool.arguments
        .map(
          (a) => RemoteToolArg(
            toolName: key,
            argFlag: a.value,
            description: a.description,
            isActive: a.isActive,
          ),
        )
        .toList();
  }

  /// Επιστρέφει τα ορίσματα ως [RemoteToolArg] (για υπάρχοντα call sites).
  Future<List<RemoteToolArg>> getArgsForTool(String toolName) async {
    final db = await _db.database;
    final roleKey = toolName.trim().toLowerCase();
    final toolRows = await db.query(
      'remote_tools',
      where: 'LOWER(role) = ?',
      whereArgs: [roleKey],
      limit: 1,
    );
    if (toolRows.isEmpty) return [];
    return _argsForToolRow(toolRows.first);
  }

  Future<List<RemoteToolArg>> getArgsForRole(ToolRole role) =>
      getArgsForTool(role.dbValue);

  /// Επιστρέφει μόνο τα ενεργά ορίσματα.
  Future<List<RemoteToolArg>> getActiveArgsForTool(String toolName) async {
    final all = await getArgsForTool(toolName);
    return all.where((a) => a.isActive).toList();
  }

  Future<List<RemoteToolArg>> getActiveArgsForRole(ToolRole role) =>
      getActiveArgsForTool(role.dbValue);
}
