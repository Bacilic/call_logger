import 'dart:io';

import '../database/remote_tools_repository.dart';
import '../models/remote_tool.dart';
import '../models/remote_tool_role.dart';

/// Επίλυση διαδρομής εκτελέσιμου από `remote_tools` (συγκεκριμένο εργαλείο ή πρώτο ενεργό ανά ρόλο).
Future<String?> validExecutablePathForTool({
  required RemoteToolsRepository repo,
  RemoteTool? tool,
  int? toolId,
  ToolRole? role,
}) async {
  RemoteTool? t = tool;
  if (t == null && toolId != null) {
    t = await repo.getById(toolId);
  }
  if (t != null) {
    try {
      final p = t.executablePath.trim();
      if (p.isNotEmpty && File(p).existsSync()) return p;
    } catch (_) {}
  }
  final r = t?.role ?? role;
  if (r != null && r != ToolRole.generic) {
    try {
      final t2 = await repo.getFirstActiveByRole(r);
      if (t2 != null) {
        final p = t2.executablePath.trim();
        if (p.isNotEmpty && File(p).existsSync()) return p;
      }
    } catch (_) {}
    if (r == ToolRole.rdp) {
      const fallback = r'C:\Windows\System32\mstsc.exe';
      if (File(fallback).existsSync()) return fallback;
    }
  }
  return null;
}

/// Διαδρομή χωρίς έλεγχο ύπαρξης αρχείου (για μηνύματα σφάλματος).
Future<String> rawExecutablePathForTool({
  required RemoteToolsRepository repo,
  RemoteTool? tool,
  int? toolId,
  ToolRole? role,
}) async {
  RemoteTool? t = tool;
  if (t == null && toolId != null) {
    t = await repo.getById(toolId);
  }
  if (t != null && t.executablePath.trim().isNotEmpty) {
    return t.executablePath.trim();
  }
  final r = t?.role ?? role;
  if (r != null && r != ToolRole.generic) {
    try {
      final t2 = await repo.getFirstActiveByRole(r);
      if (t2 != null && t2.executablePath.trim().isNotEmpty) {
        return t2.executablePath.trim();
      }
    } catch (_) {}
    if (r == ToolRole.rdp) {
      return r'C:\Windows\System32\mstsc.exe';
    }
  }
  return '';
}
