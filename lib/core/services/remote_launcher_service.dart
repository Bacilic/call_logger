import 'dart:io';

import 'package:path/path.dart' as p;

import '../database/remote_tools_repository.dart';
import '../models/remote_tool.dart';
import '../models/remote_tool_role.dart';
import 'remote_tools_paths_helper.dart';

/// Dummy διαδρομή για προεπισκόπηση/δοκιμή όταν το όρισμα περιέχει `{FILE}`.
const String kPreviewRdpFilePath = r'C:\call_logger_preview.rdp';

/// Εκκίνηση εργαλείων χωρίς παραμέτρους και δοκιμή ορισμάτων.
class RemoteLauncherService {
  RemoteLauncherService(this._toolsRepo);

  final RemoteToolsRepository _toolsRepo;

  /// Αντικατάσταση placeholders: `{EQUIPMENT_CODE}` → [equipmentCode], `{TARGET}` →
  /// [resolvedTarget] αν μη κενό αλλιώς [equipmentCode], `{FILE}` → [filePath] (ή κενό).
  static String replaceAllPlaceholders(
    String input, {
    required String? equipmentCode,
    required String? resolvedTarget,
    String? filePath,
  }) {
    final code = equipmentCode?.trim() ?? '';
    final target = (resolvedTarget != null && resolvedTarget.trim().isNotEmpty)
        ? resolvedTarget.trim()
        : code;
    return input
        .replaceAll('{EQUIPMENT_CODE}', code)
        .replaceAll('{TARGET}', target)
        .replaceAll('{FILE}', filePath?.trim() ?? '');
  }

  /// Ίδια λογική με [testRemoteTool] για ενεργά ορίσματα + placeholders.
  /// Το [testIp] τροφοδοτεί και `{EQUIPMENT_CODE}` και `{TARGET}`.
  static List<String> testArgumentList(
    RemoteTool tool,
    String testIp, {
    String? filePathForTest,
  }) {
    final host = testIp.trim();
    final fp = filePathForTest ??
        (tool.arguments.any(
          (a) => a.isActive && a.value.contains('{FILE}'),
        )
            ? kPreviewRdpFilePath
            : null);
    return tool.arguments
        .where((a) => a.isActive)
        .map((a) => a.value)
        .map(
          (v) => replaceAllPlaceholders(
            v,
            equipmentCode: host,
            resolvedTarget: host,
            filePath: fp,
          ),
        )
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Προεπισκόπηση εντολής για UI (ίδια ουσία με την εκτέλεση δοκιμής).
  static String formatTestCommandPreview(RemoteTool tool) {
    final testIp = tool.testTargetIp?.trim() ?? '';
    if (testIp.isEmpty) {
      return '';
    }
    final exe = tool.executablePath.trim();
    if (exe.isEmpty) {
      return '(συμπληρώστε διαδρομή εκτελέσιμου)';
    }
    final args = testArgumentList(tool, testIp);
    final buf = StringBuffer(_executableDisplayName(exe));
    for (final a in args) {
      buf.write(' ');
      buf.write(a);
    }
    return buf.toString();
  }

  /// Μόνο όνομα αρχείου (χωρίς πλήρη διαδρομή) για ευανάγνωστη προεπισκόπηση UI.
  static String _executableDisplayName(String executablePath) {
    final t = executablePath.trim();
    if (t.isEmpty) return '';
    return p.basename(t);
  }

  static const String errorPathNotSet = 'Η διαδρομή δεν ορίζεται.';
  static const String errorPathOrFileInvalid =
      'Η διαδρομή είναι λάθος ή το αρχείο δεν βρέθηκε.';
  static const String errorAccessDenied =
      'Δεν επιτρέπεται η πρόσβαση ή χρειάζονται δικαιώματα.';

  Future<String?> getValidAnydeskPath() async {
    final st = await getAnydeskStatus();
    return st.path;
  }

  Future<({String? path, String? errorReason})> getAnydeskStatus() async {
    final path = await rawExecutablePathForTool(
      repo: _toolsRepo,
      role: ToolRole.anydesk,
    );
    final trimmed = path.trim();
    if (trimmed.isEmpty) return (path: null, errorReason: errorPathNotSet);
    try {
      if (File(trimmed).existsSync()) return (path: trimmed, errorReason: null);
      return (path: null, errorReason: errorPathOrFileInvalid);
    } catch (_) {
      return (path: null, errorReason: errorAccessDenied);
    }
  }

  Future<String?> getValidVncPath() async {
    final st = await getVncStatus();
    return st.path;
  }

  Future<({String? path, String? errorReason})> getVncStatus() async {
    final path = await rawExecutablePathForTool(
      repo: _toolsRepo,
      role: ToolRole.vnc,
    );
    final trimmed = path.trim();
    if (trimmed.isEmpty) return (path: null, errorReason: errorPathNotSet);
    try {
      if (File(trimmed).existsSync()) return (path: trimmed, errorReason: null);
      return (path: null, errorReason: errorPathOrFileInvalid);
    } catch (_) {
      return (path: null, errorReason: errorAccessDenied);
    }
  }

  Future<({String? path, String? errorReason})> getStatusForTool(
    RemoteTool tool,
  ) async {
    final path = await rawExecutablePathForTool(
      repo: _toolsRepo,
      tool: tool,
      role: tool.role,
    );
    final trimmed = path.trim();
    if (trimmed.isEmpty) return (path: null, errorReason: errorPathNotSet);
    try {
      if (File(trimmed).existsSync()) return (path: trimmed, errorReason: null);
      return (path: null, errorReason: errorPathOrFileInvalid);
    } catch (_) {
      return (path: null, errorReason: errorAccessDenied);
    }
  }

  Future<({String? path, String? errorReason})> getStatusForRole(
    ToolRole role,
  ) async {
    final path = await rawExecutablePathForTool(
      repo: _toolsRepo,
      role: role,
    );
    final trimmed = path.trim();
    if (trimmed.isEmpty) return (path: null, errorReason: errorPathNotSet);
    try {
      if (File(trimmed).existsSync()) return (path: trimmed, errorReason: null);
      return (path: null, errorReason: errorPathOrFileInvalid);
    } catch (_) {
      return (path: null, errorReason: errorAccessDenied);
    }
  }

  Future<void> launchAnydeskEmpty() async {
    final path = await getValidAnydeskPath();
    if (path == null) {
      throw Exception('Δεν βρέθηκε εγκατάσταση AnyDesk. Ελέγξτε τις ρυθμίσεις.');
    }
    await Process.start(path, [], mode: ProcessStartMode.detached);
  }

  Future<void> launchVncEmpty() async {
    final path = await getValidVncPath();
    if (path == null) {
      throw Exception('Δεν βρέθηκε εγκατάσταση VNC. Ελέγξτε τις ρυθμίσεις.');
    }
    await Process.start(path, [], mode: ProcessStartMode.detached);
  }

  Future<void> launchToolEmptyByRole(ToolRole role) async {
    final status = await getStatusForRole(role);
    if (status.path == null) {
      throw Exception(status.errorReason ?? errorPathOrFileInvalid);
    }
    await Process.start(status.path!, [], mode: ProcessStartMode.detached);
  }

  /// Δοκιμή εκκίνησης με ανάλυση placeholders στα ορίσματα.
  /// Η IP/hostname πρέπει να είναι ορισμένα στο πεδίο δοκιμής του εργαλείου (`test_target_ip`).
  Future<void> testToolArguments(String toolName) async {
    final role = toolRoleFromDb(toolName);
    final tool = await _toolsRepo.getFirstActiveByRole(role);
    if (tool == null) {
      throw Exception('Δεν βρέθηκε ορισμός εργαλείου.');
    }
    await testRemoteTool(tool);
  }

  /// Δοκιμή με πλήρες [RemoteTool] (π.χ. από τη φόρμα πριν την αποθήκευση).
  Future<void> testRemoteTool(RemoteTool tool) async {
    final testIp = tool.testTargetIp?.trim() ?? '';
    if (testIp.isEmpty) {
      throw Exception(
        'Ορίστε δοκιμαστική IP ή hostname στη φόρμα εργαλείου (πεδίο «Δοκιμαστική IP / Hostname»).',
      );
    }

    final roleLabel = tool.role.dbValue;
    final path = tool.executablePath.trim();
    if (path.isEmpty) {
      throw Exception('Δεν ορίστηκε εκτελέσιμο για δοκιμή ($roleLabel).');
    }
    try {
      if (!File(path).existsSync()) {
        throw Exception(errorPathOrFileInvalid);
      }
    } catch (_) {
      throw Exception(errorAccessDenied);
    }

    final fp = tool.arguments.any(
          (a) => a.isActive && a.value.contains('{FILE}'),
        )
        ? kPreviewRdpFilePath
        : null;
    final arguments = testArgumentList(
      tool,
      testIp,
      filePathForTest: fp,
    );
    await Process.start(path, arguments, mode: ProcessStartMode.detached);
  }
}
