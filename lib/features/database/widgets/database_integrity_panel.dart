import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/database_integrity_finding.dart';
import '../models/database_integrity_report.dart';
import '../providers/database_integrity_provider.dart';

/// Ενότητα ελέγχου ακεραιότητας βάσης (embed στο DatabaseSettingsPanel).
class DatabaseIntegrityPanel extends ConsumerStatefulWidget {
  const DatabaseIntegrityPanel({super.key});

  @override
  ConsumerState<DatabaseIntegrityPanel> createState() =>
      _DatabaseIntegrityPanelState();
}

class _DatabaseIntegrityPanelState extends ConsumerState<DatabaseIntegrityPanel> {
  String _formatRowsChecked(int count) {
    if (count == 0) return '—';
    return NumberFormat.decimalPattern('el_GR').format(count);
  }

  String _progressLine(DatabaseIntegrityLoading loading) {
    final rows = _formatRowsChecked(loading.totalRowsChecked);
    final label = loading.tableScopeLabel ?? '';
    if (label.isEmpty) {
      return '${loading.currentCheckName}: έλεγχος $rows';
    }
    return '${loading.currentCheckName}: έλεγχος $rows [$label]';
  }

  Future<void> _copyReport(BuildContext context) async {
    final state = ref.read(databaseIntegrityProvider);
    if (state is! DatabaseIntegritySuccess) return;
    final report = state.report;
    if (!report.hasFindings) return;

    await Clipboard.setData(ClipboardData(text: report.toMarkdown()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Η αναφορά αντιγράφηκε στο πρόχειρο.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(databaseIntegrityProvider);
    final isLoading = state is DatabaseIntegrityLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.fact_check_outlined,
              color: theme.colorScheme.primary,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              'Έλεγχος ακεραιότητας',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Read-only διάγνωση αναφορών, ευρετηρίων και ορφανών συσχετίσεων. '
          'Δεν τροποποιεί δεδομένα.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: isLoading
              ? null
              : () => ref.read(databaseIntegrityProvider.notifier).runCheck(),
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Έλεγχος ακεραιότητας'),
        ),
        if (state is DatabaseIntegrityLoading) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: state.totalSteps > 0
                ? state.currentStep / state.totalSteps
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            _progressLine(state),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            'Βήμα ${state.currentStep} από ${state.totalSteps}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (state is DatabaseIntegritySuccess) ...[
          const SizedBox(height: 12),
          if (!state.report.hasFindings)
            Material(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Δεν εντοπίστηκαν προβλήματα',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(
              'Εντοπίστηκαν ${state.report.criticalCount} κρίσιμα και '
              '${state.report.warningCount} προειδοποιήσεις',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: state.report.findings.length,
              itemBuilder: (context, index) {
                final finding = state.report.findings[index];
                return _FindingTile(finding: finding);
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _copyReport(context),
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Αντιγραφή αναφοράς'),
            ),
          ],
        ],
        if (state is DatabaseIntegrityError) ...[
          const SizedBox(height: 12),
          Material(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: isLoading
                ? null
                : () => ref.read(databaseIntegrityProvider.notifier).runCheck(),
            icon: const Icon(Icons.refresh),
            label: const Text('Επανάληψη'),
          ),
        ],
      ],
    );
  }
}

class _FindingTile extends StatelessWidget {
  const _FindingTile({required this.finding});

  final DatabaseIntegrityFinding finding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCritical = finding.severity == IntegritySeverity.critical;
    final dotColor =
        isCritical ? theme.colorScheme.error : Colors.amber.shade700;

    final entityRef = finding.affectedEntity != null && finding.affectedId != null
        ? '${DatabaseIntegrityReport.entityLabelEl(finding.affectedEntity)} #${finding.affectedId}'
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.circle, size: 12, color: dotColor),
        title: Text(
          finding.title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: finding.description,
              child: Text(
                finding.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (entityRef != null)
              Text(
                entityRef,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
