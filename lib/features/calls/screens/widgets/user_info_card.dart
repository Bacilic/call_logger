import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/remote_connection_service.dart';
import '../../../../core/services/remote_launcher_service.dart';
import '../../models/equipment_model.dart';
import '../../models/user_model.dart';
import '../../provider/remote_paths_provider.dart';

/// Κάρτα στοιχείων χρήστη και εξοπλισμού με ένα δυναμικό κουμπί απομακρυσμένης σύνδεσης (VNC ή AnyDesk).
/// Εμφάνιση κουμπιού με βάση το πεδίο κωδικός εξοπλισμού [equipmentCodeText].
/// Στόχος VNC: από matched [equipment] ή PC{κωδικός}. AnyDesk ID μόνο από matched equipment.
class UserInfoCard extends ConsumerStatefulWidget {
  const UserInfoCard({
    super.key,
    required this.user,
    this.equipment,
    this.equipmentCodeText = '',
  });

  final UserModel user;
  final EquipmentModel? equipment;
  /// Κείμενο πεδίου κωδικός εξοπλισμού (πληκτρολογημένο). Κουμπί εμφανίζεται όταν δεν είναι κενό.
  final String equipmentCodeText;

  @override
  ConsumerState<UserInfoCard> createState() => _UserInfoCardState();
}

class _UserInfoCardState extends ConsumerState<UserInfoCard> {
  bool _isConnecting = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pathsAsync = ref.watch(validRemotePathsProvider);
    final remoteService = ref.read(remoteConnectionServiceProvider);
    final launcherService = ref.read(remoteLauncherServiceProvider);

    final hasEquipmentCode = widget.equipmentCodeText.trim().isNotEmpty;
    final hasAnydesk = widget.equipment != null &&
        widget.equipment!.anydeskTarget != null &&
        widget.equipment!.anydeskTarget!.trim().isNotEmpty;
    final vncTarget = widget.equipment != null
        ? widget.equipment!.vncTarget
        : 'PC${widget.equipmentCodeText.trim()}';
    final hasVnc = widget.equipment != null
        ? widget.equipment!.vncTarget != 'Άγνωστο'
        : hasEquipmentCode;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.person, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.user.name ?? '—',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (hasAnydesk || hasVnc)
                  ...pathsAsync.when(
                    data: (paths) {
                      final buttons = <Widget>[];
                      if (hasAnydesk) {
                        final pathValid = paths.anydeskPath != null;
                        buttons.add(
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildRemoteButton(
                                context,
                                theme,
                                isAnydesk: true,
                                label: 'AnyDesk',
                                targetDisplay:
                                    widget.equipment?.anydeskTarget ?? '—',
                                pathValid: pathValid,
                                onPressed: (pathValid && !_isConnecting)
                                    ? () => _handleConnection(
                                          remoteService,
                                          isAnydesk: true,
                                        )
                                    : null,
                                tooltipDisabled:
                                    'Διαδρομή AnyDesk δεν είναι έγκυρη.',
                              ),
                            ],
                          ),
                        );
                      }
                      if (hasAnydesk && hasVnc) {
                        buttons.add(const SizedBox(width: 12));
                      }
                      if (hasVnc) {
                        final pathValid = paths.vncPath != null;
                        buttons.add(
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildRemoteButton(
                                context,
                                theme,
                                isAnydesk: false,
                                label: 'VNC',
                                targetDisplay: vncTarget,
                                pathValid: pathValid,
                                onPressed: (pathValid && !_isConnecting)
                                    ? () => _handleConnection(
                                          remoteService,
                                          isAnydesk: false,
                                        )
                                    : null,
                                tooltipDisabled: 'Το VNC δεν βρέθηκε.',
                              ),
                            ],
                          ),
                        );
                      }
                      return buttons;
                    },
                    loading: () {
                      final buttons = <Widget>[];
                      if (hasAnydesk) {
                        buttons.add(
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildRemoteButton(
                                context,
                                theme,
                                isAnydesk: true,
                                label: 'AnyDesk',
                                targetDisplay:
                                    widget.equipment?.anydeskTarget ?? '—',
                                pathValid: false,
                                onPressed: null,
                                tooltipDisabled: 'Φόρτωση...',
                              ),
                            ],
                          ),
                        );
                      }
                      if (hasAnydesk && hasVnc) {
                        buttons.add(const SizedBox(width: 12));
                      }
                      if (hasVnc) {
                        buttons.add(
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildRemoteButton(
                                context,
                                theme,
                                isAnydesk: false,
                                label: 'VNC',
                                targetDisplay: vncTarget,
                                pathValid: false,
                                onPressed: null,
                                tooltipDisabled: 'Φόρτωση...',
                              ),
                            ],
                          ),
                        );
                      }
                      return buttons;
                    },
                    error: (_, _) {
                      final buttons = <Widget>[];
                      if (hasAnydesk) {
                        buttons.add(
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildRemoteButton(
                                context,
                                theme,
                                isAnydesk: true,
                                label: 'AnyDesk',
                                targetDisplay:
                                    widget.equipment?.anydeskTarget ?? '—',
                                pathValid: false,
                                onPressed: null,
                                tooltipDisabled:
                                    'Διαδρομή AnyDesk δεν είναι έγκυρη.',
                              ),
                            ],
                          ),
                        );
                      }
                      if (hasAnydesk && hasVnc) {
                        buttons.add(const SizedBox(width: 12));
                      }
                      if (hasVnc) {
                        buttons.add(
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildRemoteButton(
                                context,
                                theme,
                                isAnydesk: false,
                                label: 'VNC',
                                targetDisplay: vncTarget,
                                pathValid: false,
                                onPressed: null,
                                tooltipDisabled: 'Το VNC δεν βρέθηκε.',
                              ),
                            ],
                          ),
                        );
                      }
                      return buttons;
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _row(theme, Icons.business, 'Τμήμα', widget.user.department),
                      _row(theme, Icons.phone, 'Τηλ.', widget.user.phone),
                      _row(theme, Icons.location_on, 'Τοποθεσία', widget.user.location),
                    ],
                  ),
                ),
                if (hasEquipmentCode)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ref.watch(remoteLauncherStatusProvider).when(
                      data: (status) => _buildLauncherButtons(
                        theme,
                        status,
                        launcherService,
                      ),
                      loading: () => _buildLauncherButtons(
                        theme,
                        null,
                        launcherService,
                      ),
                      error: (_, _) => _buildLauncherButtons(
                        theme,
                        null,
                        launcherService,
                      ),
                    ),
                  ),
              ],
            ),
            if (widget.equipment != null) ...[
              const Divider(height: 24),
              Text(
                'Εξοπλισμός',
                style: theme.textTheme.titleSmall,
              ),
              _row(theme, Icons.computer, 'Τύπος', widget.equipment!.type),
              _row(theme, Icons.tag, 'Κωδικός εξοπλισμού', widget.equipment!.code),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteButton(
    BuildContext context,
    ThemeData theme, {
    required bool isAnydesk,
    required String label,
    required String targetDisplay,
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

    final content = Column(
      mainAxisSize: MainAxisSize.min,
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

    return content;
  }

  static const double _launcherIconSize = 28;

  Widget _buildLauncherButtons(
    ThemeData theme,
    ({LauncherStatus anydesk, LauncherStatus vnc})? status,
    RemoteLauncherService launcherService,
  ) {
    final anydeskEnabled = (status?.anydesk)?.path != null;
    final vncEnabled = (status?.vnc)?.path != null;
    final anydeskTooltip = anydeskEnabled
        ? 'Ανοιγμα AnyDesk χωρίς παραμέτρους'
        : ((status?.anydesk)?.errorReason ?? 'Φόρτωση...');
    final vncTooltip = vncEnabled
        ? 'Ανοιγμα VNC Viewer χωρίς παραμέτρους'
        : ((status?.vnc)?.errorReason ?? 'Φόρτωση...');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: anydeskTooltip,
          child: _buildLauncherIconButton(
            theme: theme,
            enabled: anydeskEnabled,
            onPressed: () => _launchAnydeskEmpty(launcherService),
            assetPath: 'assets/anydesk_seeklogo.png',
            fallbackIcon: Icons.screen_share,
          ),
        ),
        const SizedBox(width: 4),
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

  static const double _launcherButtonSize = 36;
  static const BorderRadius _launcherButtonRadius = BorderRadius.all(Radius.circular(4));

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
          overlayColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
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
            const SnackBar(content: Text('Δεν υπάρχει AnyDesk ID για αυτόν τον εξοπλισμό.')),
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

  Widget _row(
    ThemeData theme,
    IconData icon,
    String label,
    String? value,
  ) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text('$label: ', style: theme.textTheme.bodySmall),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
