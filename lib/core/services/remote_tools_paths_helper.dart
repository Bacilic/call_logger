import 'dart:io';

import '../database/remote_tools_repository.dart';
import '../models/remote_tool.dart';
import '../models/remote_tool_role.dart';
import 'overridable_settings.dart';

/// Η διαδρομή του εργαλείου **όπως ισχύει σε αυτόν τον υπολογιστή**.
///
/// Ο ορισμός του εργαλείου είναι κοινός για όλους· η διαδρομή του εκτελέσιμου
/// όμως αλλάζει από μηχάνημα σε μηχάνημα. Αν έχει δηλωθεί τοπική παράκαμψη,
/// αυτή κερδίζει — αλλιώς ισχύει η κοινή του ορισμού (Φάση 3).
///
/// **Το μοναδικό σημείο** όπου απαντάται «ποια διαδρομή;»: κάθε ροή που θέλει
/// να εκτελέσει ή να ελέγξει εργαλείο περνά από εδώ, ώστε η παράκαμψη να μην
/// μπορεί να ξεχαστεί σε κάποια γωνιά.
Future<String> effectiveExecutablePath(RemoteTool tool) async {
  final resolved = await OverridableSettings.resolve(
    OverridableSettingKeys.remoteToolExecutablePath.forId(tool.id),
    shared: tool.executablePath,
  );
  return resolved.trim();
}

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
    final p = await effectiveExecutablePath(t);
    try {
      if (p.isNotEmpty && File(p).existsSync()) return p;
    } catch (_) {}
  }
  final r = t?.role ?? role;
  if (r != null && r != ToolRole.generic) {
    try {
      final t2 = await repo.getFirstActiveByRole(r);
      if (t2 != null) {
        final p = await effectiveExecutablePath(t2);
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
  if (t != null) {
    final p = await effectiveExecutablePath(t);
    if (p.isNotEmpty) return p;
  }
  final r = t?.role ?? role;
  if (r != null && r != ToolRole.generic) {
    try {
      final t2 = await repo.getFirstActiveByRole(r);
      if (t2 != null) {
        final p = await effectiveExecutablePath(t2);
        if (p.isNotEmpty) return p;
      }
    } catch (_) {}
    if (r == ToolRole.rdp) {
      return r'C:\Windows\System32\mstsc.exe';
    }
  }
  return '';
}
