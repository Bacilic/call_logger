import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/settings_provider.dart';
import '../../../../core/services/remote_connection_service.dart';
import '../../../../core/services/remote_launcher_service.dart';
import '../../models/equipment_model.dart';
import '../../provider/remote_paths_provider.dart';

/// Widget κουμπιών απομακρυσμένης σύνδεσης (AnyDesk, VNC) και launcher icons.
/// Εμφανίζεται όταν υπάρχει κωδικός εξοπλισμού· στόχοι από [equipment] ή PC{equipmentCodeText}.
class RemoteConnectionButtons extends ConsumerStatefulWidget {
  const RemoteConnectionButtons({
    super.key,
    required this.equipment,
    required this.equipmentCodeText,
  });

  final EquipmentModel? equipment;
  final String equipmentCodeText;

  @override
  ConsumerState<RemoteConnectionButtons> createState() =>
      _RemoteConnectionButtonsState();
}

class _RemoteConnectionButtonsState
    extends ConsumerState<RemoteConnectionButtons> {
  bool _isConnecting = false;

  /// Έγκυρο AnyDesk target: 9 ή 10 ψηφία, ή μορφή name@namespace (μέχρι 25 χαρακτήρες).
  static bool _isValidAnyDeskTarget(String t) {
    final trimmed = t.trim();
    if (trimmed.length == 9 || trimmed.length == 10) {
      return RegExp(r'^\d+$').hasMatch(trimmed);
    }
    if (trimmed.contains('@')) {
      final parts = trimmed.split('@');
      if (parts.length != 2) return false;
      final regex = RegExp(r'^[a-zA-Z0-9\-._]+$');
      return parts[0].isNotEmpty &&
          parts[1].isNotEmpty &&
          regex.hasMatch(parts[0]) &&
          regex.hasMatch(parts[1]) &&
          trimmed.length <= 25;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pathsAsync = ref.watch(validRemotePathsProvider);
    final remoteService = ref.read(remoteConnectionServiceProvider);
    final launcherService = ref.read(remoteLauncherServiceProvider);
    final showAnyDesk = ref.watch(showAnyDeskRemoteProvider).value ?? true;

    final anydeskTarget = widget.equipment?.anydeskTarget?.trim();
    final vncTargetRaw = widget.equipment != null
        ? widget.equipment!.vncTarget.trim()
        : '';
    final vncTarget = widget.equipment != null
        ? vncTargetRaw
        : 'PC${widget.equipmentCodeText.trim()}';
    final hasValidAnydesk = anydeskTarget != null &&
        anydeskTarget.isNotEmpty &&
        _isValidAnyDeskTarget(anydeskTarget);
    final hasValidVnc = widget.equipment != null
        ? vncTargetRaw != 'Άγνωστο' && vncTargetRaw.isNotEmpty
        : widget.equipmentCodeText.trim().isNotEmpty;

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: pathsAsync.when(
          data: (paths) {
            final buttons = <Widget>[
              _buildConnectionButton(
                context: context,
                theme: theme,
                isAnydesk: false,
                label: 'VNC',
                targetDisplay: vncTarget,
                enabled: hasValidVnc &&
                    paths.vncPath != null &&
                    !_isConnecting,
                pathValid: paths.vncPath != null,
                onPressed: hasValidVnc && paths.vncPath != null && !_isConnecting
                    ? () => _handleConnection(remoteService, isAnydesk: false)
                    : null,
                tooltipDisabled: _vncTooltipDisabled(paths.vncPath != null),
              ),
              if (showAnyDesk) ...[
                const SizedBox(width: 12),
                _buildConnectionButton(
                  context: context,
                  theme: theme,
                  isAnydesk: true,
                  label: 'AnyDesk',
                  targetDisplay: anydeskTarget ?? '—',
                  enabled: hasValidAnydesk &&
                      paths.anydeskPath != null &&
                      !_isConnecting,
                  pathValid: paths.anydeskPath != null,
                  onPressed: hasValidAnydesk &&
                          paths.anydeskPath != null &&
                          !_isConnecting
                      ? () => _handleConnection(remoteService, isAnydesk: true)
                      : null,
                  tooltipDisabled: _anydeskTooltipDisabled(paths.anydeskPath != null),
                ),
              ],
              const SizedBox(width: 16),
              ref.watch(remoteLauncherStatusProvider).when(
                    data: (status) => _buildLauncherButtons(
                      theme,
                      showAnyDesk,
                      status,
                      launcherService,
                    ),
                    loading: () => _buildLauncherButtons(
                      theme,
                      showAnyDesk,
                      null,
                      launcherService,
                    ),
                    error: (_, _) => _buildLauncherButtons(
                      theme,
                      showAnyDesk,
                      null,
                      launcherService,
                    ),
                  ),
            ];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: buttons,
                ),
              ],
            );
          },
          loading: () => _buildLoadingRow(
            theme,
            showAnyDesk,
            hasValidAnydesk,
            hasValidVnc,
            anydeskTarget ?? '—',
            vncTarget,
            launcherService,
          ),
          error: (err, _) => _buildErrorRow(
            theme,
            showAnyDesk,
            hasValidAnydesk,
            hasValidVnc,
            anydeskTarget ?? '—',
            vncTarget,
            err.toString(),
            launcherService,
          ),
        ),
      ),
    );
  }

  String _anydeskTooltipDisabled(bool pathValid) {
    if (!pathValid) return 'Διαδρομή AnyDesk δεν βρέθηκε.';
    if (_isConnecting) return 'Γίνεται σύνδεση...';
    return 'AnyDesk target κενό / μη έγκυρο (9-10 ψηφία ή όνομα@namespace) / χωρίς διαδρομή / φόρτωση / σύνδεση...';
  }

  String _vncTooltipDisabled(bool pathValid) {
    if (!pathValid) return 'Διαδρομή VNC δεν βρέθηκε.';
    if (_isConnecting) return 'Γίνεται σύνδεση...';
    return 'VNC target άγνωστο / κενό / χωρίς διαδρομή / φόρτωση / σύνδεση...';
  }

  Widget _buildConnectionButton({
    required BuildContext context,
    required ThemeData theme,
    required bool isAnydesk,
    required String label,
    required String targetDisplay,
    required bool enabled,
    required bool pathValid,
    required VoidCallback? onPressed,
    required String tooltipDisabled,
  }) {
    final iconWidget = _isConnecting
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.onPrimary,
            ),
          )
        : Icon(
            isAnydesk ? Icons.screen_share : Icons.desktop_windows,
            size: 18,
          );

    final button = FilledButton.icon(
      onPressed: onPressed,
      icon: iconWidget,
      label: Text(label),
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
          targetDisplay,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  static const double _launcherIconSize = 28;
  static const double _launcherButtonSize = 36;
  static const BorderRadius _launcherButtonRadius =
      BorderRadius.all(Radius.circular(4));

  Widget _buildLauncherButtons(
    ThemeData theme,
    bool showAnyDesk,
    ({LauncherStatus anydesk, LauncherStatus vnc})? status,
    RemoteLauncherService launcherService,
  ) {
    final anydeskPathValid = (status?.anydesk)?.path != null;
    final vncEnabled = (status?.vnc)?.path != null;
    final anydeskTooltip = anydeskPathValid
        ? 'Άνοιγμα AnyDesk χωρίς παραμέτρους'
        : (status?.anydesk)?.errorReason ?? 'Φόρτωση...';
    final vncTooltip = vncEnabled
        ? 'Άνοιγμα VNC Viewer χωρίς παραμέτρους'
        : (status?.vnc)?.errorReason ?? 'Φόρτωση...';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showAnyDesk) ...[
          Tooltip(
            message: anydeskTooltip,
            child: _buildLauncherIconButton(
              theme: theme,
              enabled: anydeskPathValid,
              onPressed: () => _launchAnydeskEmpty(launcherService),
              assetPath: 'assets/anydesk_seeklogo.png',
              fallbackIcon: Icons.screen_share,
            ),
          ),
          const SizedBox(width: 4),
        ],
        Tooltip(
          message: vncTooltip,
          child: _buildLauncherIconButton(
            theme: theme,
            enabled: vncEnabled,
            onPressed: () => _launchVncEmpty(launcherService),
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
    required String assetPath,
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
                    child: Image.asset(
                      assetPath,
                      width: _launcherIconSize,
                      height: _launcherIconSize,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Icon(
                        fallbackIcon,
                        size: _launcherIconSize,
                        color: theme.colorScheme.primary,
                      ),
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

  Widget _buildLoadingRow(
    ThemeData theme,
    bool showAnyDesk,
    bool hasValidAnydesk,
    bool hasValidVnc,
    String anydeskDisplay,
    String vncDisplay,
    RemoteLauncherService launcherService,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        _buildConnectionButton(
          context: context,
          theme: theme,
          isAnydesk: false,
          label: 'VNC',
          targetDisplay: vncDisplay,
          enabled: false,
          pathValid: false,
          onPressed: null,
          tooltipDisabled: 'Φόρτωση...',
        ),
        if (showAnyDesk) ...[
          const SizedBox(width: 12),
          _buildConnectionButton(
            context: context,
            theme: theme,
            isAnydesk: true,
            label: 'AnyDesk',
            targetDisplay: anydeskDisplay,
            enabled: false,
            pathValid: false,
            onPressed: null,
            tooltipDisabled: 'Φόρτωση...',
          ),
        ],
        const SizedBox(width: 16),
        ref.watch(remoteLauncherStatusProvider).when(
              data: (status) => _buildLauncherButtons(theme, showAnyDesk, status, launcherService),
              loading: () => _buildLauncherButtons(theme, showAnyDesk, null, launcherService),
              error: (_, _) => _buildLauncherButtons(theme, showAnyDesk, null, launcherService),
            ),
      ],
    );
  }

  Widget _buildErrorRow(
    ThemeData theme,
    bool showAnyDesk,
    bool hasValidAnydesk,
    bool hasValidVnc,
    String anydeskDisplay,
    String vncDisplay,
    String errorMessage,
    RemoteLauncherService launcherService,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: errorMessage,
          child: Icon(Icons.error_outline, color: theme.colorScheme.error),
        ),
        const SizedBox(width: 12),
        _buildConnectionButton(
          context: context,
          theme: theme,
          isAnydesk: false,
          label: 'VNC',
          targetDisplay: vncDisplay,
          enabled: false,
          pathValid: false,
          onPressed: null,
          tooltipDisabled: 'Το VNC δεν βρέθηκε.',
        ),
        if (showAnyDesk) ...[
          const SizedBox(width: 12),
          _buildConnectionButton(
            context: context,
            theme: theme,
            isAnydesk: true,
            label: 'AnyDesk',
            targetDisplay: anydeskDisplay,
            enabled: false,
            pathValid: false,
            onPressed: null,
            tooltipDisabled: 'Διαδρομή AnyDesk δεν είναι έγκυρη.',
          ),
        ],
        const SizedBox(width: 16),
        ref.watch(remoteLauncherStatusProvider).when(
              data: (status) => _buildLauncherButtons(theme, showAnyDesk, status, launcherService),
              loading: () => _buildLauncherButtons(theme, showAnyDesk, null, launcherService),
              error: (_, _) => _buildLauncherButtons(theme, showAnyDesk, null, launcherService),
            ),
      ],
    );
  }

  Future<void> _launchAnydeskEmpty(RemoteLauncherService launcherService) async {
    try {
      await launcherService.launchAnydeskEmpty();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Αποτυχία εκκίνησης AnyDesk: $e')),
      );
    }
  }

  Future<void> _launchVncEmpty(RemoteLauncherService launcherService) async {
    try {
      await launcherService.launchVncEmpty();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Αποτυχία εκκίνησης VNC: $e')),
      );
    }
  }

  Future<void> _handleConnection(
    RemoteConnectionService remoteService, {
    required bool isAnydesk,
  }) async {
    setState(() => _isConnecting = true);
    try {
      if (isAnydesk) {
        final targetId = widget.equipment?.anydeskTarget ?? '';
        if (targetId.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Δεν υπάρχει AnyDesk ID για αυτόν τον εξοπλισμό.')),
          );
          return;
        }
        await remoteService.launchAnydesk(targetId);
      } else {
        final target = widget.equipment != null
            ? widget.equipment!.vncTarget
            : 'PC${widget.equipmentCodeText.trim()}';
        await remoteService.launchVnc(target);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }
}
