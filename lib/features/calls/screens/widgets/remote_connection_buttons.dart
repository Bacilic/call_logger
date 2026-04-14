import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/remote_tool.dart';
import '../../../../core/models/remote_tool_role.dart';
import '../../../../core/services/remote_connection_service.dart';
import '../../../../core/services/remote_launcher_service.dart';
import '../../provider/call_header_provider.dart';
import '../../provider/remote_paths_provider.dart';
import '../../utils/call_remote_targets.dart';

/// Κουμπιά απομακρυσμένης σύνδεσης: κύριο εργαλείο + overflow, εικονίδια launcher.
class RemoteConnectionButtons extends ConsumerStatefulWidget {
  const RemoteConnectionButtons({
    super.key,
    required this.header,
    required this.tools,
  });

  final CallHeaderState header;
  final List<RemoteTool> tools;

  @override
  ConsumerState<RemoteConnectionButtons> createState() =>
      _RemoteConnectionButtonsState();
}

class _RemoteConnectionButtonsState extends ConsumerState<RemoteConnectionButtons> {
  bool _isConnecting = false;

  List<RemoteTool> _orderedForUi(
    List<RemoteTool> visible,
    int? primaryId,
  ) {
    if (visible.isEmpty) return visible;
    RemoteTool? primary;
    if (primaryId != null) {
      for (final t in visible) {
        if (t.id == primaryId) {
          primary = t;
          break;
        }
      }
    }
    final chosen = primary ?? visible.first;
    final rest = visible.where((t) => t.id != chosen.id).toList();
    return [chosen, ...rest];
  }

  IconData _iconForTool(RemoteTool t) {
    return switch (t.role) {
      ToolRole.anydesk => Icons.screen_share,
      ToolRole.rdp => Icons.monitor,
      _ => Icons.desktop_windows,
    };
  }

  String _assetForLauncher(RemoteTool t) {
    return switch (t.role) {
      ToolRole.anydesk => 'assets/anydesk_seeklogo.png',
      ToolRole.vnc => 'assets/vnc_viewer.png',
      _ => '',
    };
  }

  Widget _buildNoRemoteToolsState(
    BuildContext context,
    ThemeData theme, {
    required bool noRows,
  }) {
    final message = noRows
        ? 'Δεν έχουν ρυθμιστεί εργαλεία απομακρυσμένης επιφάνειας.'
        : 'Όλα τα εργαλεία απομακρυσμένης επιφάνειας είναι ανεργά.';
    final screenW = MediaQuery.sizeOf(context).width;
    final textMax = math.max(
      110.0,
      math.min(170.0, screenW * 0.22),
    );
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 80 + 12 + textMax,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              'assets/no_remote_tool_icon.png',
              width: 80,
              height: 80,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                textAlign: TextAlign.start,
                softWrap: true,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allCatalogAsync = ref.watch(remoteToolsAllCatalogProvider);
    final pathsAsync = ref.watch(validRemoteToolPathsByIdProvider);
    final legacyPathsAsync = ref.watch(validRemotePathsProvider);
    final uiConfig = ref.watch(callsRemoteUiConfigProvider);
    final remoteService = ref.read(remoteConnectionServiceProvider);
    final launcherService = ref.read(remoteLauncherServiceProvider);
    final visible = CallRemoteTargets.visibleRemoteToolsForCallState(
      widget.header,
      widget.tools,
    );
    final toolsForTargets = widget.tools.isEmpty ? <RemoteTool>[] : widget.tools;

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: allCatalogAsync.when(
          data: (allTools) {
            final noRows = allTools.isEmpty;
            final allInactive = allTools.isNotEmpty &&
                allTools.every((t) => !t.isActive);
            if (noRows || allInactive) {
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: _buildNoRemoteToolsState(
                  context,
                  theme,
                  noRows: noRows,
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(12),
              child: pathsAsync.when(
          data: (pathMap) {
            return uiConfig.when(
              data: (cfg) {
                if (visible.isEmpty) {
                  if (widget.tools.isEmpty) {
                  return legacyPathsAsync.when(
                    data: (legacyPaths) => _legacyLayout(
                      context,
                      theme,
                      legacyPaths,
                      cfg.showEmptyRemoteLaunchers,
                      remoteService,
                      launcherService,
                      ref,
                    ),
                    loading: () => const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    error: (e, _) => Text('Διαδρομές: $e'),
                  );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Δεν υπάρχουν εργαλεία απομακρυσμένης σύνδεσης για την τρέχουσα επιλογή.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                final ordered = _orderedForUi(visible, cfg.primaryToolId);
                final primary = ordered.first;
                final secondary = ordered.skip(1).toList();
                final useOverflow =
                    cfg.showSecondaryInOverflow && secondary.isNotEmpty;

                final primaryPath = pathMap[primary.id];
                final canPrimary = CallRemoteTargets.canConnectForTool(
                  widget.header,
                  primary,
                  toolsForTargets,
                );
                final targetPrimary =
                    CallRemoteTargets.resolvedLaunchTarget(
                  widget.header,
                  primary,
                  toolsForTargets,
                );

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildToolButton(
                          context: context,
                          theme: theme,
                          tool: primary,
                          pathValid: primaryPath != null,
                          enabled: canPrimary &&
                              primaryPath != null &&
                              !_isConnecting,
                          subtitle: CallRemoteTargets.targetSubtitle(
                            widget.header,
                            primary,
                            toolsForTargets,
                          ),
                          onPressed: canPrimary &&
                                  primaryPath != null &&
                                  !_isConnecting
                              ? () => _connect(
                                    remoteService,
                                    primary,
                                    targetPrimary,
                                  )
                              : null,
                          tooltipDisabled: _tooltipForTool(
                            primary,
                            primaryPath != null,
                            canPrimary,
                          ),
                        ),
                        if (useOverflow) ...[
                          const SizedBox(width: 8),
                          PopupMenuButton<RemoteTool>(
                            tooltip: 'Περισσότερα εργαλεία',
                            enabled: !_isConnecting,
                            itemBuilder: (ctx) => [
                              for (final t in secondary)
                                PopupMenuItem(
                                  value: t,
                                  enabled: pathMap[t.id] !=
                                          null &&
                                      CallRemoteTargets.canConnectForTool(
                                        widget.header,
                                        t,
                                        toolsForTargets,
                                      ),
                                  child: Text(t.name),
                                ),
                            ],
                            onSelected: (t) {
                              final p = pathMap[t.id];
                              final tgt = CallRemoteTargets.resolvedLaunchTarget(
                                widget.header,
                                t,
                                toolsForTargets,
                              );
                              if (p != null && tgt != null) {
                                _connect(remoteService, t, tgt);
                              }
                            },
                            child: Icon(
                              Icons.more_horiz,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ] else
                          for (final t in secondary) ...[
                            const SizedBox(width: 12),
                            _buildToolButton(
                              context: context,
                              theme: theme,
                              tool: t,
                              pathValid:
                                  pathMap[t.id] != null,
                              enabled: CallRemoteTargets.canConnectForTool(
                                    widget.header,
                                    t,
                                    toolsForTargets,
                                  ) &&
                                  pathMap[t.id] != null &&
                                  !_isConnecting,
                              subtitle: CallRemoteTargets.targetSubtitle(
                                widget.header,
                                t,
                                toolsForTargets,
                              ),
                              onPressed: CallRemoteTargets.canConnectForTool(
                                        widget.header,
                                        t,
                                        toolsForTargets,
                                      ) &&
                                      pathMap[t.id] != null &&
                                      !_isConnecting
                                  ? () => _connect(
                                        remoteService,
                                        t,
                                        CallRemoteTargets.resolvedLaunchTarget(
                                          widget.header,
                                          t,
                                          toolsForTargets,
                                        ),
                                      )
                                  : null,
                              tooltipDisabled: _tooltipForTool(
                                t,
                                pathMap[t.id] != null,
                                CallRemoteTargets.canConnectForTool(
                                  widget.header,
                                  t,
                                  toolsForTargets,
                                ),
                              ),
                            ),
                          ],
                        if (cfg.showEmptyRemoteLaunchers) ...[
                          const SizedBox(width: 16),
                          ref.watch(remoteLauncherStatusesByIdProvider).when(
                                data: (statusMap) => _buildLauncherRow(
                                  theme,
                                  visible,
                                  statusMap,
                                  launcherService,
                                ),
                                loading: () => const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                error: (_, _) => const SizedBox.shrink(),
                              ),
                        ],
                      ],
                    ),
                  ],
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (e, _) => Text('Ρυθμίσεις UI: $e'),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (e, _) => Text('Διαδρομές: $e'),
              ),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Κατάλογος εργαλείων: $e'),
          ),
        ),
    );
  }

  Widget _legacyLayout(
    BuildContext context,
    ThemeData theme,
    ({String? vncPath, String? anydeskPath, String? rdpPath}) legacyPaths,
    bool showEmptyRemoteLaunchers,
    RemoteConnectionService remoteService,
    RemoteLauncherService launcherService,
    WidgetRef ref,
  ) {
    const emptyTools = <RemoteTool>[];
    final vncTarget =
        CallRemoteTargets.resolvedVncTarget(widget.header, emptyTools);
    final hasValidVnc = CallRemoteTargets.canConnectVnc(widget.header, emptyTools);
    final hasValidAd =
        CallRemoteTargets.canConnectAnyDesk(widget.header, emptyTools);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildToolButton(
              context: context,
              theme: theme,
              label: 'VNC',
              icon: Icons.desktop_windows,
              pathValid: legacyPaths.vncPath != null,
              enabled:
                  hasValidVnc && legacyPaths.vncPath != null && !_isConnecting,
              subtitle: vncTarget,
              onPressed: hasValidVnc && legacyPaths.vncPath != null && !_isConnecting
                  ? () => _connectLegacyVnc(remoteService, vncTarget)
                  : null,
              tooltipDisabled: legacyPaths.vncPath == null
                  ? 'Διαδρομή VNC δεν βρέθηκε.'
                  : 'VNC: δεν υπάρχει έγκυρος στόχος.',
            ),
            const SizedBox(width: 12),
            _buildToolButton(
              context: context,
              theme: theme,
              label: 'AnyDesk',
              icon: Icons.screen_share,
              pathValid: legacyPaths.anydeskPath != null,
              enabled: hasValidAd &&
                  legacyPaths.anydeskPath != null &&
                  !_isConnecting,
              subtitle: CallRemoteTargets.anydeskTargetDisplay(
                widget.header,
                emptyTools,
              ),
              onPressed: hasValidAd &&
                      legacyPaths.anydeskPath != null &&
                      !_isConnecting
                  ? () => _connectLegacyAnydesk(remoteService)
                  : null,
              tooltipDisabled: 'AnyDesk…',
            ),
            if (showEmptyRemoteLaunchers) ...[
              const SizedBox(width: 16),
              ref.watch(remoteLauncherStatusProvider).when(
                    data: (status) => _buildLegacyLaunchers(
                      theme,
                      status,
                      launcherService,
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
            ],
          ],
        ),
      ],
    );
  }

  /// Εικονίδιο κουμπιού εργαλείου: προτεραιότητα [RemoteTool.iconAssetKey], αλλιώς ρόλος.
  Widget _toolButtonIcon({
    required RemoteTool? tool,
    required IconData fallbackIcon,
  }) {
    if (tool == null) {
      return Icon(fallbackIcon, size: 18);
    }
    final raw = tool.iconAssetKey?.trim() ?? '';
    if (raw.isEmpty) {
      return Icon(fallbackIcon, size: 18);
    }
    Widget fallback() => Icon(fallbackIcon, size: 18);
    if (raw.startsWith('assets/')) {
      return Image.asset(
        raw,
        width: 18,
        height: 18,
        errorBuilder: (context, error, stackTrace) => fallback(),
      );
    }
    final f = File(raw);
    if (f.existsSync()) {
      return Image.file(
        f,
        width: 18,
        height: 18,
        errorBuilder: (context, error, stackTrace) => fallback(),
      );
    }
    return Image.asset(
      raw,
      width: 18,
      height: 18,
      errorBuilder: (context, error, stackTrace) => fallback(),
    );
  }

  Widget _buildToolButton({
    required BuildContext context,
    required ThemeData theme,
    RemoteTool? tool,
    String? label,
    IconData? icon,
    required bool pathValid,
    required bool enabled,
    required String subtitle,
    required VoidCallback? onPressed,
    required String tooltipDisabled,
  }) {
    final displayLabel = label ?? tool?.name ?? '';
    final ic = icon ?? (tool != null ? _iconForTool(tool) : Icons.link);
    final buttonChild = _isConnecting
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.onPrimary,
            ),
          )
        : _toolButtonIcon(tool: tool, fallbackIcon: ic);

    final button = FilledButton.icon(
      onPressed: onPressed,
      icon: buttonChild,
      label: Text(displayLabel),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        (onPressed == null && !_isConnecting)
            ? Tooltip(message: tooltipDisabled, child: button)
            : button,
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _tooltipForTool(
    RemoteTool tool,
    bool pathValid,
    bool canConnect,
  ) {
    if (!pathValid) {
      return 'Διαδρομή για «${tool.name}» δεν βρέθηκε.';
    }
    if (_isConnecting) return 'Γίνεται σύνδεση…';
    if (!canConnect) {
      return 'Δεν υπάρχει έγκυρος στόχος για «${tool.name}».';
    }
    return 'Απομακρυσμένη σύνδεση';
  }

  static const double _launcherIconSize = 28;
  static const double _launcherButtonSize = 36;
  static final BorderRadius _launcherButtonRadius =
      BorderRadius.circular(4);

  Widget _buildLauncherRow(
    ThemeData theme,
    List<RemoteTool> visible,
    Map<int, ({String? path, String? errorReason})> statusMap,
    RemoteLauncherService launcherService,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          _launcherForTool(
            theme,
            visible[i],
            statusMap[visible[i].id],
            launcherService,
          ),
        ],
      ],
    );
  }

  Widget _launcherForTool(
    ThemeData theme,
    RemoteTool tool,
    ({String? path, String? errorReason})? status,
    RemoteLauncherService launcherService,
  ) {
    final pathValid = status?.path != null;
    final tooltip = pathValid
        ? 'Άνοιγμα ${tool.name} χωρίς παραμέτρους'
        : (status?.errorReason ?? 'Φόρτωση...');
    final asset = _assetForLauncher(tool);
    return Tooltip(
      message: tooltip,
      child: _buildLauncherIconButton(
        theme: theme,
        enabled: pathValid,
        onPressed: () => _launchEmpty(launcherService, tool.role),
        assetPath: asset.isNotEmpty ? asset : null,
        fallbackIcon: _iconForTool(tool),
      ),
    );
  }

  Widget _buildLegacyLaunchers(
    ThemeData theme,
    ({
      ({String? path, String? errorReason}) anydesk,
      ({String? path, String? errorReason}) vnc,
    }) status,
    RemoteLauncherService launcherService,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: status.anydesk.path != null
              ? 'Άνοιγμα AnyDesk χωρίς παραμέτρους'
              : (status.anydesk.errorReason ?? ''),
          child: _buildLauncherIconButton(
            theme: theme,
            enabled: status.anydesk.path != null,
            onPressed: () => _launchEmpty(launcherService, ToolRole.anydesk),
            assetPath: 'assets/anydesk_seeklogo.png',
            fallbackIcon: Icons.screen_share,
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: status.vnc.path != null
              ? 'Άνοιγμα VNC Viewer χωρίς παραμέτρους'
              : (status.vnc.errorReason ?? ''),
          child: _buildLauncherIconButton(
            theme: theme,
            enabled: status.vnc.path != null,
            onPressed: () => _launchEmpty(launcherService, ToolRole.vnc),
            assetPath: 'assets/vnc_viewer.png',
            fallbackIcon: Icons.desktop_windows,
          ),
        ),
      ],
    );
  }

  Widget _buildLauncherIconButton({
    required ThemeData theme,
    required bool enabled,
    required VoidCallback onPressed,
    String? assetPath,
    required IconData fallbackIcon,
  }) {
    return IgnorePointer(
      ignoring: !enabled,
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: _launcherButtonRadius),
        elevation: 1,
        shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.25),
        child: InkWell(
          onTap: onPressed,
          borderRadius: _launcherButtonRadius,
          overlayColor:
              WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
            if (states.contains(WidgetState.pressed)) {
              return theme.colorScheme.onSurface.withValues(alpha: 0.2);
            }
            if (states.contains(WidgetState.hovered)) {
              return theme.colorScheme.onSurface.withValues(alpha: 0.08);
            }
            return null;
          }),
          child: SizedBox(
            width: _launcherButtonSize,
            height: _launcherButtonSize,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: _launcherButtonRadius,
                    child: assetPath != null
                        ? Image.asset(
                            assetPath,
                            width: _launcherIconSize,
                            height: _launcherIconSize,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Icon(
                              fallbackIcon,
                              size: _launcherIconSize,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : Icon(
                            fallbackIcon,
                            size: _launcherIconSize,
                            color: theme.colorScheme.primary,
                          ),
                  ),
                  if (!enabled)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.85),
                          borderRadius: _launcherButtonRadius,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _launchEmpty(
    RemoteLauncherService launcherService,
    ToolRole role,
  ) async {
    try {
      await launcherService.launchToolEmptyByRole(role);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Αποτυχία εκκίνησης: $e')),
      );
    }
  }

  Future<void> _connectLegacyVnc(
    RemoteConnectionService remoteService,
    String target,
  ) async {
    setState(() => _isConnecting = true);
    try {
      await remoteService.launchVnc(target);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _connectLegacyAnydesk(RemoteConnectionService remoteService) async {
    final targetId = CallRemoteTargets.resolvedAnyDeskTarget(
          widget.header,
          widget.tools,
        ) ??
        '';
    setState(() => _isConnecting = true);
    try {
      if (targetId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Δεν υπάρχει έγκυρος στόχος AnyDesk.')),
          );
        }
        return;
      }
      await remoteService.launchAnydesk(targetId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _connect(
    RemoteConnectionService remoteService,
    RemoteTool tool,
    String? target,
  ) async {
    if (target == null || target.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Δεν υπάρχει έγκυρος στόχος για ${tool.name}.')),
        );
      }
      return;
    }
    setState(() => _isConnecting = true);
    try {
      final params = widget.header.selectedEquipment?.remoteParams ?? {};
      await remoteService.launchRemoteTool(
        tool: tool,
        resolvedTarget: target,
        remoteParams: Map<String, String>.from(params),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }
}
