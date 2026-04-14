import 'dart:io';

import '../database/remote_tools_repository.dart';
import '../models/remote_tool.dart';
import '../models/remote_tool_role.dart';
import 'settings_service.dart';

/// Επίλυση διαδρομής εκτελέσιμου: πρώτα συγκεκριμένο εργαλείο/id, μετά πρώτο ενεργό ανά ρόλο, τέλος `app_settings` (legacy).
Future<String?> validExecutablePathForTool({
  required RemoteToolsRepository repo,
  required SettingsService settings,
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
    switch (r) {
      case ToolRole.vnc:
        final p = (await settings.getVncPath()).trim();
        if (p.isNotEmpty && File(p).existsSync()) return p;
        return null;
      case ToolRole.anydesk:
        final p = (await settings.getAnydeskPath()).trim();
        if (p.isNotEmpty && File(p).existsSync()) return p;
        return null;
      case ToolRole.rdp:
        try {
          final tr = await repo.getFirstActiveByRole(ToolRole.rdp);
          final p = tr?.executablePath.trim() ?? '';
          if (p.isNotEmpty && File(p).existsSync()) return p;
        } catch (_) {}
        const fallback = r'C:\Windows\System32\mstsc.exe';
        if (File(fallback).existsSync()) return fallback;
        return null;
      case ToolRole.generic:
        return null;
    }
  }
  return null;
}

/// Διαδρομή χωρίς έλεγχο ύπαρξης αρχείου (για μηνύματα σφάλματος).
Future<String> rawExecutablePathForTool({
  required RemoteToolsRepository repo,
  required SettingsService settings,
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
    switch (r) {
      case ToolRole.vnc:
        return await settings.getVncPath();
      case ToolRole.anydesk:
        return await settings.getAnydeskPath();
      case ToolRole.rdp:
        try {
          final tr = await repo.getFirstActiveByRole(ToolRole.rdp);
          final p = tr?.executablePath.trim() ?? '';
          if (p.isNotEmpty) return p;
        } catch (_) {}
        return r'C:\Windows\System32\mstsc.exe';
      case ToolRole.generic:
        return '';
    }
  }
  return '';
}
