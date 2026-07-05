import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/models/remote_tool.dart';
import '../../../../core/widgets/remote_tool_icon.dart';
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
    this.framed = true,
  });

  final CallHeaderState header;
  final List<RemoteTool> tools;

  /// `false`: χωρίς δική του Card — όταν φιλοξενείται σε εξωτερική κάρτα
  /// (π.χ. SectionCard στην οθόνη κλήσεων).
  final bool framed;

  @override
  ConsumerState<RemoteConnectionButtons> createState() =>
      _RemoteConnectionButtonsState();
}

class _RemoteConnectionButtonsState extends ConsumerState<RemoteConnectionButtons> {
  bool _isConnecting = false;
  bool _showAll = false;

  @override
  void didUpdateWidget(RemoteConnectionButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldEq = oldWidget.header.selectedEquipment;
    final newEq = widget.header.selectedEquipment;
    final equipmentChanged =
        oldEq?.id != newEq?.id ||
        oldWidget.header.equipmentText.trim() !=
            widget.header.equipmentText.trim();
    if (equipmentChanged) {
      _showAll = false;
    }
  }

  Widget _buildExclusiveToolsBanner(ThemeData theme) {
    final message = _showAll
        ? 'Εμφανίζονται όλα τα εργαλεία'
        : 'Εμφανίζονται μόνο τα κύρια εργαλεία';
    final actionLabel = _showAll ? 'Μόνο τα κύρια' : 'Εμφάνιση όλων';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: _isConnecting
                ? null
                : () => setState(() => _showAll = !_showAll),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

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
    final uiConfig = ref.watch(callsRemoteUiConfigProvider);
    final remoteService = ref.read(remoteConnectionServiceProvider);
    final launcherService = ref.read(remoteLauncherServiceProvider);
    final visible = CallRemoteTargets.visibleRemoteToolsForCallState(
      widget.header,
      widget.tools,
      applyExclusive: !_showAll,
    );
    final exclusiveHides = CallRemoteTargets.exclusiveHidesTools(
      widget.header,
      widget.tools,
    );
    final toolsForTargets = widget.tools.isEmpty ? <RemoteTool>[] : widget.tools;

    final content = allCatalogAsync.when(
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
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      widget.tools.isEmpty
                          ? 'Δεν έχουν ρυθμιστεί ενεργά εργαλεία απομακρυσμένης επιφάνειας.'
                          : 'Δεν υπάρχουν εργαλεία απομακρυσμένης σύνδεσης για την τρέχουσα επιλογή.',
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

                return LayoutBuilder(
                  builder: (context, constraints) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (exclusiveHides) _buildExclusiveToolsBanner(theme),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
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
                                  final tgt = CallRemoteTargets
                                      .resolvedLaunchTarget(
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
                                _buildToolButton(
                                  context: context,
                                  theme: theme,
                                  tool: t,
                                  pathValid: pathMap[t.id] != null,
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
                                  onPressed: CallRemoteTargets
                                              .canConnectForTool(
                                            widget.header,
                                            t,
                                            toolsForTargets,
                                          ) &&
                                          pathMap[t.id] != null &&
                                          !_isConnecting
                                      ? () => _connect(
                                            remoteService,
                                            t,
                                            CallRemoteTargets
                                                .resolvedLaunchTarget(
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
        );
    if (!widget.framed) return content;
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: content,
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
    return RemoteToolIcon(
      iconAssetKey: tool.iconAssetKey,
      size: 18,
      fallback: fallbackIcon,
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
    final displaySubtitle = _formatSubtitleForDisplay(tool, subtitle);
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
          displaySubtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _formatSubtitleForDisplay(RemoteTool? tool, String subtitle) {
    final t = subtitle.trim();
    if (t.isEmpty || t == '—') return subtitle;
    if (tool == null || !tool.acceptsFileParam) return subtitle;
    final baseWin = p.windows.basename(t);
    if (baseWin.isNotEmpty && baseWin != '.' && baseWin != '..') {
      return baseWin;
    }
    final base = p.basename(t);
    if (base.isNotEmpty && base != '.' && base != '..') return base;
    return subtitle;
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
        equipmentCode: widget.header.selectedEquipment?.code?.trim(),
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
