import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/database_integrity_provider.dart';
import 'database_integrity_panel.dart';
import 'settings_panel_info_tooltip.dart';

/// Καρτέλα «Συντήρηση»: έλεγχος ακεραιότητας της βάσης.
class DatabaseSettingsMaintenanceTab extends StatelessWidget {
  const DatabaseSettingsMaintenanceTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Έλεγχος ακεραιότητας',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Διάγνωση ορφανών συσχετίσεων, ευρετηρίων αναζήτησης και βηματική '
          'επιδιόρθωση με επιβεβαίωση.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        const _IntegrityLaunchSection(),
      ],
    );
  }
}

class _IntegrityLaunchSection extends ConsumerWidget {
  const _IntegrityLaunchSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final integrityState = ref.watch(databaseIntegrityProvider);

    String? statusHint;
    if (integrityState is DatabaseIntegritySuccess) {
      if (!integrityState.report.hasFindings) {
        statusHint = 'Τελευταίος έλεγχος: δεν εντοπίστηκαν προβλήματα.';
      } else {
        statusHint =
            'Τελευταίος έλεγχος: ${integrityState.report.findings.length} ευρήματα '
            '(${integrityState.report.criticalCount} κρίσιμα).';
      }
    } else if (integrityState is DatabaseIntegrityError) {
      statusHint = 'Τελευταίος έλεγχος απέτυχε.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => DatabaseIntegrityDialog.show(context),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('Έλεγχος ακεραιότητας…'),
              ),
            ),
            SettingsPanelInfoTooltip(
              message: integrityChecksTooltipMessage,
              iconColor: theme.colorScheme.onSurfaceVariant,
              maxWidth: 560,
            ),
          ],
        ),
        if (statusHint != null) ...[
          const SizedBox(height: 6),
          Text(
            statusHint,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
