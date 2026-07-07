import 'dart:io';

import '../database/remote_tools_repository.dart';
import '../models/remote_tool.dart';
import '../models/remote_tool_role.dart';
import 'remote_launcher_service.dart';
import 'remote_tools_paths_helper.dart';

/// Υπηρεσία απομακρυσμένων συνδέσεων: διαδρομές από `remote_tools`, εκκίνηση με ανάλυση ορισμάτων.
class RemoteConnectionService {
  RemoteConnectionService(this._toolsRepo);

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

  String? _resolvedFilePathForLaunch(
    RemoteTool tool,
    Map<String, String> remoteParams,
  ) {
    if (tool.acceptsFileParam) {
      final fromEquipment = _toolsRepo.resolveParamValue(
        remoteParams: remoteParams,
        tool: tool,
      );
      final v = fromEquipment?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return firstExistingRdpPathFromArguments(tool);
  }

  List<String> _resolvedLaunchArguments(
    RemoteTool tool, {
    required String? equipmentCode,
    required String resolvedTarget,
    required Map<String, String> remoteParams,
  }) {
    final fp = _resolvedFilePathForLaunch(tool, remoteParams);
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

  Future<String?> getValidPathForTool(RemoteTool tool) =>
      validExecutablePathForTool(
        repo: _toolsRepo,
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

  /// Γενική εκκίνηση με ανάλυση placeholders στα ορίσματα.
  Future<void> launchRemoteTool({
    required RemoteTool tool,
    required String resolvedTarget,
    required Map<String, String> remoteParams,
    String? equipmentCode,
  }) async {
    final path = await validExecutablePathForTool(
      repo: _toolsRepo,
      tool: tool,
      role: tool.role,
    );
    if (path == null) {
      throw Exception(
        'Δεν βρέθηκε εκτελέσιμο για «${tool.name}». Ορίστε διαδρομή στη διαχείριση εργαλείων.',
      );
    }

    if (tool.role == ToolRole.vnc) {
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
      remoteParams: remoteParams,
    );
    await Process.start(path, arguments, mode: ProcessStartMode.detached);
  }
}
