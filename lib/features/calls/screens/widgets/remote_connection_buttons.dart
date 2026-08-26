import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/models/remote_tool.dart';
import '../../../../core/widgets/remote_tool_icon.dart';
import '../../../../core/widgets/app_asset_image.dart';
import '../../../../core/models/remote_tool_role.dart';
import '../../../../core/services/remote_launcher_service.dart';
import '../../../../core/utils/user_facing_error_messages.dart';
import '../../provider/call_header_provider.dart';
import '../../provider/remote_connect_cooldown_provider.dart';
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

class _RemoteConnectionButtonsState
    extends ConsumerState<RemoteConnectionButtons> {
  bool _showAll = false;

  /// Η κατάσταση ενός κουμπιού σύνδεσης, τη στιγμή που ζωγραφίζεται.
  ///
  /// Δεν ζει στο widget: το κλείδωμα κρατά δεκάδες δευτερόλεπτα, μέσα στα
  /// οποία ο χρήστης αλλάζει εξοπλισμό ή καθαρίζει τη φόρμα — και κάθε τέτοια
  /// κίνηση ξαναχτίζει αυτό εδώ το widget.
  _ConnectButtonStatus _statusFor(RemoteTool tool, String? target) {
    if (target == null || target.isEmpty) return const _ConnectButtonStatus();
    if (ref
        .read(remoteConnectLauncherProvider.notifier)
        .isStarting(toolId: tool.id, target: target)) {
      return const _ConnectButtonStatus(starting: true);
    }
    final left = ref
        .read(remoteConnectCooldownProvider.notifier)
        .remaining(toolId: tool.id, target: target);
    if (left <= Duration.zero) return const _ConnectButtonStatus();
    return _ConnectButtonStatus(
      secondsLeft: (left.inMilliseconds / 1000).ceil(),
    );
  }

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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _showAll = !_showAll),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  List<RemoteTool> _orderedForUi(List<RemoteTool> visible, int? primaryId) {
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
    final textMax = math.max(110.0, math.min(170.0, screenW * 0.22));
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 80 + 12 + textMax),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppAssetImage(
              assetPath: 'assets/no_remote_tool_icon.png',
              width: 80,
              height: 80,
              fallbackIcon: Icons.desktop_access_disabled,
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
    // Παρακολούθηση για το ξαναζωγράφισμα· οι τιμές διαβάζονται ανά εργαλείο
    // στο [_statusFor], γιατί κάθε κουμπί έχει δικό του ζεύγος με τον στόχο.
    ref.watch(remoteConnectCooldownProvider);
    ref.watch(remoteConnectLauncherProvider);
    final allCatalogAsync = ref.watch(remoteToolsAllCatalogProvider);
    final pathsAsync = ref.watch(validRemoteToolPathsByIdProvider);
    final uiConfig = ref.watch(callsRemoteUiConfigProvider);
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
    final toolsForTargets = widget.tools.isEmpty
        ? <RemoteTool>[]
        : widget.tools;

    final content = allCatalogAsync.when(
      data: (allTools) {
        final noRows = allTools.isEmpty;
        final allInactive =
            allTools.isNotEmpty && allTools.every((t) => !t.isActive);
        if (noRows || allInactive) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: _buildNoRemoteToolsState(context, theme, noRows: noRows),
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
                  final targetPrimary = CallRemoteTargets.resolvedLaunchTarget(
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
                                status: _statusFor(primary, targetPrimary),
                                pathValid: primaryPath != null,
                                enabled: canPrimary && primaryPath != null,
                                subtitle: CallRemoteTargets.targetSubtitle(
                                  widget.header,
                                  primary,
                                  toolsForTargets,
                                ),
                                onPressed: () =>
                                    _connect(primary, targetPrimary),
                                tooltipDisabled: _tooltipForTool(
                                  primary,
                                  primaryPath != null,
                                  canPrimary,
                                ),
                              ),
                              if (useOverflow) ...[
                                PopupMenuButton<RemoteTool>(
                                  tooltip: 'Περισσότερα εργαλεία',
                                  itemBuilder: (ctx) => [
                                    for (final t in secondary)
                                      PopupMenuItem(
                                        value: t,
                                        // Η ίδια σύνδεση δεν ξεκινά από την
                                        // πίσω πόρτα όσο κλειδώνει το κουμπί
                                        // της.
                                        enabled:
                                            pathMap[t.id] != null &&
                                            CallRemoteTargets.canConnectForTool(
                                              widget.header,
                                              t,
                                              toolsForTargets,
                                            ) &&
                                            !_statusFor(
                                              t,
                                              CallRemoteTargets.resolvedLaunchTarget(
                                                widget.header,
                                                t,
                                                toolsForTargets,
                                              ),
                                            ).busy,
                                        child: Text(t.name),
                                      ),
                                  ],
                                  onSelected: (t) {
                                    final p = pathMap[t.id];
                                    final tgt =
                                        CallRemoteTargets.resolvedLaunchTarget(
                                          widget.header,
                                          t,
                                          toolsForTargets,
                                        );
                                    if (p != null && tgt != null) {
                                      _connect(t, tgt);
                                    }
                                  },
                                  child: Icon(
                                    Icons.more_horiz,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ] else
                                for (final t in secondary) ...[
                                  Builder(
                                    builder: (context) {
                                      final target =
                                          CallRemoteTargets.resolvedLaunchTarget(
                                            widget.header,
                                            t,
                                            toolsForTargets,
                                          );
                                      final canConnect =
                                          CallRemoteTargets.canConnectForTool(
                                            widget.header,
                                            t,
                                            toolsForTargets,
                                          );
                                      return _buildToolButton(
                                        context: context,
                                        theme: theme,
                                        tool: t,
                                        status: _statusFor(t, target),
                                        pathValid: pathMap[t.id] != null,
                                        enabled:
                                            canConnect &&
                                            pathMap[t.id] != null,
                                        subtitle:
                                            CallRemoteTargets.targetSubtitle(
                                              widget.header,
                                              t,
                                              toolsForTargets,
                                            ),
                                        onPressed: () => _connect(t, target),
                                        tooltipDisabled: _tooltipForTool(
                                          t,
                                          pathMap[t.id] != null,
                                          canConnect,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              if (cfg.showEmptyRemoteLaunchers) ...[
                                ref
                                    .watch(remoteLauncherStatusesByIdProvider)
                                    .when(
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
                error: (e, _) =>
                    Text('Ρυθμίσεις UI: ${humanizeUserFacingError(e)}'),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (e, _) => Text('Διαδρομές: ${humanizeUserFacingError(e)}'),
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Κατάλογος εργαλείων: ${humanizeUserFacingError(e)}'),
      ),
    );
    if (!widget.framed) return content;
    return Card(elevation: 1, margin: EdgeInsets.zero, child: content);
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
    _ConnectButtonStatus status = const _ConnectButtonStatus(),
  }) {
    final ic = icon ?? (tool != null ? _iconForTool(tool) : Icons.link);
    final displaySubtitle = _formatSubtitleForDisplay(tool, subtitle);
    // Όσο κρατά η αναμονή, η ετικέτα λέει τι γίνεται και **πόσο ακόμη**: ένας
    // αριθμός που πέφτει είναι πολύ σαφέστερη ένδειξη από κυκλάκι που γυρίζει.
    final displayLabel = switch (status) {
      _ConnectButtonStatus(starting: true) => 'Σύνδεση…',
      _ConnectButtonStatus(secondsLeft: final int left) => 'Σύνδεση… $left″',
      _ => label ?? tool?.name ?? '',
    };
    final buttonChild = status.busy
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        : _toolButtonIcon(tool: tool, fallbackIcon: ic);

    final button = FilledButton.icon(
      onPressed: (enabled && !status.busy) ? onPressed : null,
      icon: buttonChild,
      label: Text(displayLabel),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          (!enabled && !status.busy)
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
      ),
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

  String _tooltipForTool(RemoteTool tool, bool pathValid, bool canConnect) {
    if (!pathValid) {
      return 'Διαδρομή για «${tool.name}» δεν βρέθηκε.';
    }
    if (!canConnect) {
      return 'Δεν υπάρχει έγκυρος στόχος για «${tool.name}».';
    }
    return 'Απομακρυσμένη σύνδεση';
  }

  static const double _launcherIconSize = 28;
  static const double _launcherButtonSize = 36;
  static final BorderRadius _launcherButtonRadius = BorderRadius.circular(4);

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
          overlayColor: WidgetStateProperty.resolveWith<Color?>((
            Set<WidgetState> states,
          ) {
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
        SnackBar(
          content: Text('Αποτυχία εκκίνησης: ${humanizeUserFacingError(e)}'),
        ),
      );
    }
  }

  Future<void> _connect(RemoteTool tool, String? target) async {
    if (target == null || target.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Δεν υπάρχει έγκυρος στόχος για ${tool.name}.'),
          ),
        );
      }
      return;
    }
    final messenger = mounted ? ScaffoldMessenger.maybeOf(context) : null;
    final params = widget.header.selectedEquipment?.remoteParams ?? {};
    // Η εντολή δόθηκε — λέγεται αμέσως, πριν από τους ελέγχους: η αμφιβολία
    // «πάτησα ή όχι;» είναι ακριβώς αυτό που γεννούσε τα επαναλαμβανόμενα
    // πατήματα.
    messenger?.showSnackBar(
      SnackBar(content: Text('Ξεκινά η σύνδεση με $target…')),
    );
    final error = await ref
        .read(remoteConnectLauncherProvider.notifier)
        .connect(
          tool: tool,
          target: target,
          remoteParams: Map<String, String>.from(params),
          equipmentCode: widget.header.selectedEquipment?.code?.trim(),
        );
    if (error == null) return;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error)));
  }
}

/// Τι δείχνει ένα κουμπί σύνδεσης αυτή τη στιγμή.
///
/// Δύο διαφορετικές αναμονές, που ο χρήστης δεν χρειάζεται να ξεχωρίζει αλλά ο
/// κώδικας ναι: η σύντομη των ελέγχων ([starting]) και η μεγάλη μέχρι να
/// εμφανιστεί η απομακρυσμένη επιφάνεια ([secondsLeft]).
class _ConnectButtonStatus {
  const _ConnectButtonStatus({this.starting = false, this.secondsLeft});

  final bool starting;
  final int? secondsLeft;

  bool get busy => starting || secondsLeft != null;
}
