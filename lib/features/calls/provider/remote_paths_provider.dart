import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/remote_tools_repository.dart';
import '../../../core/models/remote_tool.dart';
import '../../../core/models/remote_tool_role.dart';
import '../../../core/services/remote_args_service.dart';
import '../../../core/services/remote_connection_service.dart';
import '../../../core/services/remote_launcher_service.dart';
import '../../../core/services/settings_service.dart';

/// Provider για το [RemoteArgsService].
final remoteArgsServiceProvider = Provider<RemoteArgsService>((ref) {
  return RemoteArgsService(DatabaseHelper.instance);
});

/// Repository `remote_tools`.
final remoteToolsRepositoryProvider = Provider<RemoteToolsRepository>((ref) {
  return RemoteToolsRepository(DatabaseHelper.instance);
});

/// Ενεργά εργαλεία (για κλήσεις, dropdowns).
final remoteToolsCatalogProvider = FutureProvider<List<RemoteTool>>((ref) async {
  final repo = ref.read(remoteToolsRepositoryProvider);
  try {
    final list = await repo.getActiveTools();
    if (list.isNotEmpty) return list;
  } catch (_) {}
  return const [];
});

/// Όλα τα εργαλεία (CRUD / ρυθμίσεις).
final remoteToolsAllCatalogProvider = FutureProvider<List<RemoteTool>>((ref) async {
  final repo = ref.read(remoteToolsRepositoryProvider);
  return repo.getAllTools();
});

/// Ζεύγη (εμφανιζόμενο όνομα, κλειδί JSON) για φόρμες εξοπλισμού — μόνο ενεργά `remote_tools` με μη κενό `name`.
typedef RemoteToolFormPair = ({String label, String key});

final remoteToolFormPairsProvider =
    FutureProvider<List<RemoteToolFormPair>>((ref) async {
  final repo = ref.read(remoteToolsRepositoryProvider);
  try {
    final tools = await repo.getActiveTools();
    return [
      for (final t in tools)
        if (t.name.trim().isNotEmpty)
          (label: t.name.trim(), key: t.id.toString()),
    ];
  } catch (_) {
    return const [];
  }
});

/// Ονόματα εργαλείων για dropdown εξοπλισμού· κενή λίστα όταν δεν υπάρχει επιλογή (μόνο «Κανένα» στο UI).
final remotePathsProvider = FutureProvider<List<String>>((ref) async {
  final pairs = await ref.watch(remoteToolFormPairsProvider.future);
  return pairs.map((p) => p.label).toList();
});

/// Έγκυρες διαδρομές ανά id εργαλείου (μόνο ενεργά εργαλεία όταν η λίστα δεν είναι κενή).
final validRemoteToolPathsByIdProvider =
    FutureProvider<Map<int, String?>>((ref) async {
  final repo = ref.read(remoteToolsRepositoryProvider);
  final conn = ref.read(remoteConnectionServiceProvider);
  try {
    final tools = await repo.getActiveTools();
    final map = <int, String?>{};
    for (final t in tools) {
      map[t.id] = await conn.getValidPathForTool(t);
    }
    return map;
  } catch (_) {
    return {};
  }
});

/// VNC / AnyDesk / RDP paths για συμβατότητα με παλιό UI.
final validRemotePathsProvider =
    FutureProvider<({String? vncPath, String? anydeskPath, String? rdpPath})>(
        (ref) async {
  final conn = ref.read(remoteConnectionServiceProvider);
  return (
    vncPath: await conn.getValidVncPath(),
    anydeskPath: await conn.getValidAnydeskPath(),
    rdpPath: await conn.getValidRdpPath(),
  );
});

typedef LauncherStatus = ({String? path, String? errorReason});

/// Κατάσταση launcher ανά id εργαλείου.
final remoteLauncherStatusesByIdProvider =
    FutureProvider<Map<int, LauncherStatus>>((ref) async {
  final launcher = ref.read(remoteLauncherServiceProvider);
  final repo = ref.read(remoteToolsRepositoryProvider);
  try {
    final tools = await repo.getActiveTools();
    final map = <int, LauncherStatus>{};
    for (final t in tools) {
      map[t.id] = await launcher.getStatusForTool(t);
    }
    return map;
  } catch (_) {
    return {};
  }
});

/// Συμβατότητα: μόνο VNC + AnyDesk.
final remoteLauncherStatusProvider = FutureProvider<
    ({
      LauncherStatus anydesk,
      LauncherStatus vnc,
    })>((ref) async {
  final launcher = ref.read(remoteLauncherServiceProvider);
  final ad = await launcher.getStatusForRole(ToolRole.anydesk);
  final vn = await launcher.getStatusForRole(ToolRole.vnc);
  return (
    anydesk: ad.path != null
        ? ad
        : (path: null, errorReason: RemoteLauncherService.errorPathNotSet),
    vnc: vn.path != null
        ? vn
        : (path: null, errorReason: RemoteLauncherService.errorPathNotSet),
  );
});

final remoteConnectionServiceProvider = Provider<RemoteConnectionService>((ref) {
  return RemoteConnectionService(
    SettingsService(),
    ref.read(remoteArgsServiceProvider),
    ref.read(remoteToolsRepositoryProvider),
  );
});

final remoteLauncherServiceProvider = Provider<RemoteLauncherService>((ref) {
  return RemoteLauncherService(
    SettingsService(),
    ref.read(remoteToolsRepositoryProvider),
  );
});

/// Ρυθμίσεις UI κλήσεων (κύριο εργαλείο + overflow + κενές εκκινήσεις).
final callsRemoteUiConfigProvider = FutureProvider<
    ({
      int? primaryToolId,
      bool showSecondaryInOverflow,
      bool showEmptyRemoteLaunchers,
    })>((ref) async {
  final s = SettingsService();
  return (
    primaryToolId: await s.getCallsPrimaryToolId(),
    showSecondaryInOverflow: await s.getCallsShowSecondaryRemoteActions(),
    showEmptyRemoteLaunchers: await s.getCallsShowEmptyRemoteLaunchers(),
  );
});
