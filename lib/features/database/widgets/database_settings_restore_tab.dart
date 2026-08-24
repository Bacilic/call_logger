import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/app_permission.dart';
import '../../../core/services/permission_service.dart';
import '../utils/backup_restore_tooltip.dart';
import 'database_settings_switch_flows.dart';

/// Καρτέλα «Επαναφορά»: επαναφορά της βάσης από αντίγραφο ασφαλείας (zip/db).
///
/// Η ενέργεια αντικαθιστά ολόκληρη την κοινόχρηστη βάση, για όλους ταυτόχρονα
/// — γι' αυτό φυλάσσεται πίσω από το δικαίωμα «Συντήρηση και επαναφορά βάσης»,
/// όπως πριν από την καρτελοποίηση.
class DatabaseSettingsRestoreTab extends ConsumerStatefulWidget {
  const DatabaseSettingsRestoreTab({
    super.key,
    this.onDatabaseLifecycleChanged,
  });

  /// Μετά από επιτυχές άνοιγμα της βάσης που επαναφέρθηκε.
  final Future<void> Function()? onDatabaseLifecycleChanged;

  @override
  ConsumerState<DatabaseSettingsRestoreTab> createState() =>
      _DatabaseSettingsRestoreTabState();
}

class _DatabaseSettingsRestoreTabState
    extends ConsumerState<DatabaseSettingsRestoreTab>
    with
        AutomaticKeepAliveClientMixin,
        DatabaseSettingsSwitchFlows<DatabaseSettingsRestoreTab> {
  @override
  bool get wantKeepAlive => true;

  @override
  Future<void> Function()? get onDatabaseLifecycleChanged =>
      widget.onDatabaseLifecycleChanged;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final canRestore = PermissionService.instance.can(
      AppPermission.databaseMaintenance,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Επαναφορά από Αντίγραφο Ασφαλείας',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Επιλέγετε αρχείο αντιγράφου (.zip ή .db) και η βάση επαναφέρεται '
          'στην κατάσταση εκείνης της στιγμής. Η τρέχουσα βάση αντικαθίσταται '
          '— η επαναφορά αφορά όλους όσους τη μοιράζονται.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (canRestore)
          _RestoreFromBackupZipButton(onPressed: restoreFromBackupZip)
        else
          Card(
            margin: EdgeInsets.zero,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Την επαναφορά της βάσης τη χειρίζεται όποιος έχει το '
                      'δικαίωμα «Συντήρηση και επαναφορά βάσης».',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RestoreFromBackupZipButton extends ConsumerWidget {
  const _RestoreFromBackupZipButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tooltipAsync = ref.watch(backupRestoreTooltipProvider);
    final message = tooltipAsync.when(
      data: (value) => value,
      loading: () => 'Φόρτωση πληροφοριών αντιγράφου…',
      error: (_, _) => BackupRestoreTooltipBuilder.fallbackMessage,
    );

    return Tooltip(
      message: message,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 400),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.unarchive_outlined),
        label: const Text('Επαναφορά από Αντίγραφο Ασφαλείας'),
      ),
    );
  }
}
