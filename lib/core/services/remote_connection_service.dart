import 'dart:io';

import '../database/remote_tools_repository.dart';
import '../models/remote_tool.dart';
import '../models/remote_tool_role.dart';
import 'remote_args_service.dart';
import 'remote_launcher_service.dart';
import 'remote_tools_paths_helper.dart';
import 'settings_service.dart';

/// Υπηρεσία απομακρυσμένων συνδέσεων: διαδρομές από `remote_tools`, εκκίνηση ανά `launch_mode`.
class RemoteConnectionService {
  RemoteConnectionService(this._settings, this._argsService, this._toolsRepo);

  final SettingsService _settings;
  final RemoteArgsService _argsService;
  final RemoteToolsRepository _toolsRepo;

  /// Πρώτο υπαρκτό `.rdp` path από ενεργά ορίσματα (εκτός `__rdp_file__` template body).
  static String? firstExistingRdpPathFromArguments(RemoteTool tool) {
    for (final a in tool.arguments.where((x) => x.isActive)) {
      if (a.description.trim() == '__rdp_file__') continue;
      final v = a.value.trim();
      if (v.toLowerCase().endsWith('.rdp')) {
        try {
          if (File(v).existsSync()) return v;
        } catch (_) {}
      }
    }
    return null;
  }

  List<String> _resolvedLaunchArguments(
    RemoteTool tool, {
    required String? equipmentCode,
    required String resolvedTarget,
  }) {
    final fp = firstExistingRdpPathFromArguments(tool);
    return tool.arguments
        .where(
          (a) => a.isActive && a.description.trim() != '__rdp_file__',
        )
        .map(
          (a) => RemoteLauncherService.replaceAllPlaceholders(
            a.value,
            equipmentCode: equipmentCode,
            resolvedTarget: resolvedTarget,
            filePath: fp,
          ),
        )
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<String?> getValidVncPath() => validExecutablePathForTool(
        repo: _toolsRepo,
        settings: _settings,
        role: ToolRole.vnc,
      );

  Future<String?> getValidAnydeskPath() => validExecutablePathForTool(
        repo: _toolsRepo,
        settings: _settings,
        role: ToolRole.anydesk,
      );

  Future<String?> getValidRdpPath() => validExecutablePathForTool(
        repo: _toolsRepo,
        settings: _settings,
        role: ToolRole.rdp,
      );

  /// Έγκυρο path για συγκεκριμένο εργαλείο (ή fallback ανά ρόλο).
  Future<String?> getValidPathForTool(RemoteTool tool) =>
      validExecutablePathForTool(
        repo: _toolsRepo,
        settings: _settings,
        tool: tool,
        role: tool.role,
      );

  Future<bool> _isVncPortOpen(String host) async {
    try {
      final socket = await Socket.connect(
        host,
        5900,
        timeout: const Duration(milliseconds: 1500),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> launchVnc(String target) async {
    final tool = await _toolsRepo.getFirstActiveByRole(ToolRole.vnc);
    if (tool != null) {
      await launchRemoteTool(
        tool: tool,
        resolvedTarget: target,
        remoteParams: const {},
      );
      return;
    }
    final path = await getValidVncPath();
    if (path == null) {
      throw Exception('Δεν βρέθηκε εγκατάσταση TightVNC στις ρυθμισμένες διαδρομές.');
    }
    final portOpen = await _isVncPortOpen(target);
    if (!portOpen) {
      throw Exception(
        'Ο υπολογιστής $target δεν απαντά ή το VNC δεν τρέχει (Port 5900).',
      );
    }
    final activeArgs = await _argsService.getActiveArgsForRole(ToolRole.vnc);
    final argFlags = activeArgs.map((a) => a.argFlag).toList();
    final arguments = argFlags
        .map(
          (f) => RemoteLauncherService.replaceAllPlaceholders(
            f,
            equipmentCode: null,
            resolvedTarget: target,
            filePath: null,
          ),
        )
        .where((s) => s.isNotEmpty)
        .toList();
    await Process.start(path, arguments, mode: ProcessStartMode.detached);
  }

  Future<void> launchAnydesk(String targetId) async {
    final tool = await _toolsRepo.getFirstActiveByRole(ToolRole.anydesk);
    if (tool != null) {
      await launchRemoteTool(
        tool: tool,
        resolvedTarget: targetId,
        remoteParams: const {},
      );
      return;
    }
    final path = await getValidAnydeskPath();
    if (path == null) {
      throw Exception('Δεν βρέθηκε εγκατάσταση AnyDesk. Ελέγξτε τις ρυθμίσεις.');
    }
    final activeArgs = await _argsService.getActiveArgsForRole(ToolRole.anydesk);
    final argFlags = activeArgs.map((a) => a.argFlag).toList();
    final arguments = argFlags
        .map(
          (f) => RemoteLauncherService.replaceAllPlaceholders(
            f,
            equipmentCode: null,
            resolvedTarget: targetId,
            filePath: null,
          ),
        )
        .where((s) => s.isNotEmpty)
        .toList();
    await Process.start(path, arguments, mode: ProcessStartMode.detached);
  }

  /// Γενική εκκίνηση: `direct_exec` ή `template_file` (ίδια ανάλυση ορισμάτων).
  Future<void> launchRemoteTool({
    required RemoteTool tool,
    required String resolvedTarget,
    required Map<String, String> remoteParams,
    String? equipmentCode,
  }) async {
    final path = await validExecutablePathForTool(
      repo: _toolsRepo,
      settings: _settings,
      tool: tool,
      role: tool.role,
    );
    if (path == null) {
      throw Exception(
        'Δεν βρέθηκε εκτελέσιμο για «${tool.name}». Ορίστε διαδρομή στη διαχείριση εργαλείων.',
      );
    }

    final needsVncPort = tool.role == ToolRole.vnc;
    if (needsVncPort) {
      final portOpen = await _isVncPortOpen(resolvedTarget);
      if (!portOpen) {
        throw Exception(
          'Ο υπολογιστής $resolvedTarget δεν απαντά ή το VNC δεν τρέχει (Port 5900).',
        );
      }
    }

    final arguments = _resolvedLaunchArguments(
      tool,
      equipmentCode: equipmentCode,
      resolvedTarget: resolvedTarget,
    );
    await Process.start(path, arguments, mode: ProcessStartMode.detached);
  }
}
