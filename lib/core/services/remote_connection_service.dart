import 'dart:io';

import '../database/remote_tools_repository.dart';
import '../models/remote_tool.dart';
import '../models/remote_tool_role.dart';
import 'rdp_temp_file_launcher.dart';
import 'remote_args_service.dart';
import 'remote_tools_paths_helper.dart';
import 'settings_service.dart';

/// Υπηρεσία απομακρυσμένων συνδέσεων: διαδρομές από `remote_tools`, εκκίνηση ανά `launch_mode`.
class RemoteConnectionService {
  RemoteConnectionService(this._settings, this._argsService, this._toolsRepo);

  final SettingsService _settings;
  final RemoteArgsService _argsService;
  final RemoteToolsRepository _toolsRepo;

  List<String> _resolveArgs(
    List<String> argFlags, {
    required String target,
    String password = '',
  }) {
    return argFlags
        .map((flag) => flag
            .replaceAll('{TARGET}', target)
            .replaceAll('{PASSWORD}', password))
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
    const password = '';
    final activeArgs = await _argsService.getActiveArgsForRole(ToolRole.vnc);
    final argFlags = activeArgs.map((a) => a.argFlag).toList();
    final arguments = _resolveArgs(argFlags, target: target, password: password);
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
    final arguments = _resolveArgs(argFlags, target: targetId);
    await Process.start(path, arguments, mode: ProcessStartMode.detached);
  }

  /// Γενική εκκίνηση: `direct_exec` ή `template_file` (RDP).
  Future<void> launchRemoteTool({
    required RemoteTool tool,
    required String resolvedTarget,
    required Map<String, String> remoteParams,
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

    final mode = tool.launchMode.trim().toLowerCase();
    if (mode == 'template_file') {
      final user = _toolsRepo.resolveUsername(
        remoteParams: remoteParams,
        tool: tool,
      );
      await RdpTempFileLauncher.launch(
        mstscPath: path,
        serverIp: resolvedTarget,
        username: user,
        configTemplate: tool.configTemplate,
      );
      return;
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

    final password = tool.password?.trim() ?? '';
    final argFlags =
        tool.arguments.where((a) => a.isActive).map((a) => a.value).toList();
    final arguments = _resolveArgs(
      argFlags,
      target: resolvedTarget,
      password: password,
    );
    await Process.start(path, arguments, mode: ProcessStartMode.detached);
  }
}
