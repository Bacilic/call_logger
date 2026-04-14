import 'dart:io';

import 'package:path/path.dart' as p;

import '../database/remote_tools_repository.dart';
import '../models/remote_tool.dart';
import '../models/remote_tool_role.dart';
import 'rdp_temp_file_launcher.dart';
import 'remote_tools_paths_helper.dart';
import 'settings_service.dart';

/// Εκκίνηση εργαλείων χωρίς παραμέτρους και δοκιμή ορισμάτων.
class RemoteLauncherService {
  RemoteLauncherService(this._settings, this._toolsRepo);

  final SettingsService _settings;
  final RemoteToolsRepository _toolsRepo;

  /// Ίδια λογική με [testRemoteTool] για ενεργά ορίσματα + placeholders.
  static List<String> testArgumentList(RemoteTool tool, String testIp) {
    final ip = testIp.trim();
    final password = tool.password?.trim() ?? '';
    return tool.arguments
        .where((a) => a.isActive)
        .map((a) => a.value)
        .map(
          (flag) => flag
              .replaceAll('{TARGET}', ip)
              .replaceAll('{PASSWORD}', password),
        )
        .toList();
  }

  /// Προεπισκόπηση κειμένου για UI (ίδια ουσία με την εκτέλεση δοκιμής).
  /// Για `template_file` το δεύτερο «όρισμα» είναι δυναμική διαδρομή `.rdp` στο temp.
  static String formatTestCommandPreview(RemoteTool tool) {
    final testIp = tool.testTargetIp?.trim() ?? '';
    if (testIp.isEmpty) {
      return '';
    }
    final mode = tool.launchMode.trim().toLowerCase();
    final exe = tool.executablePath.trim();
    if (mode == 'template_file') {
      if (exe.isEmpty) {
        return 'Δοκιμή: (συμπληρώστε διαδρομή εκτελέσιμου — π.χ. mstsc.exe)';
      }
      final user = tool.defaultUsername?.trim() ?? '';
      final userNote = user.isNotEmpty ? ' · χρήστης στο .rdp: $user' : '';
      final rdpName =
          '%TEMP%\\${RdpTempFileLauncher.fileNamePrefix}<μοναδικό>.rdp';
      final exeName = _executableDisplayName(exe);
      return 'Δοκιμή: ${_shellQuoteDisplay(exeName)} ${_shellQuoteDisplay(rdpName)}\n'
          'Το .rdp περιέχει διακομιστή (full address): $testIp$userNote';
    }
    if (exe.isEmpty) {
      return 'Δοκιμή: (συμπληρώστε διαδρομή εκτελέσιμου)';
    }
    final args = testArgumentList(tool, testIp);
    final buf = StringBuffer('Δοκιμή: ');
    buf.write(_shellQuoteDisplay(_executableDisplayName(exe)));
    for (final a in args) {
      buf.write(' ');
      buf.write(_shellQuoteDisplay(a));
    }
    return buf.toString();
  }

  /// Μόνο όνομα αρχείου (χωρίς πλήρη διαδρομή) για ευανάγνωστη προεπισκόπηση UI.
  static String _executableDisplayName(String executablePath) {
    final t = executablePath.trim();
    if (t.isEmpty) return '';
    return p.basename(t);
  }

  static String _shellQuoteDisplay(String s) {
    if (s.isEmpty) return '""';
    if (RegExp(r'[\s"&|<>^%]').hasMatch(s)) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
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
      settings: _settings,
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
      settings: _settings,
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
      settings: _settings,
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
      settings: _settings,
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

  /// Δοκιμή: `direct_exec` με placeholders ή `template_file` με δοκιμαστική IP.
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
    final mode = tool.launchMode.trim().toLowerCase();

    if (mode == 'template_file') {
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
      await RdpTempFileLauncher.launch(
        mstscPath: path,
        serverIp: testIp,
        username: tool.defaultUsername,
        configTemplate: tool.configTemplate,
      );
      return;
    }

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

    final arguments = testArgumentList(tool, testIp);
    await Process.start(path, arguments, mode: ProcessStartMode.detached);
  }
}
