import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/database_integrity_finding.dart';
import '../models/database_integrity_report.dart';
import '../models/integrity_fix_models.dart';
import '../providers/database_integrity_provider.dart';
import 'integrity_fix_dialogs.dart';

/// Callback για μηνύματα επιτυχίας/σφάλματος μέσα στον διάλογο ακεραιότητας.
typedef IntegrityFeedbackCallback = void Function(
  String message, {
  bool isError,
});

/// Κατανοητές περιγραφές των ελέγχων (για tooltip πληροφοριών).
const _integrityCheckDescriptions = <String>[
  'Φυσική κατάσταση του αρχείου βάσης δεδομένων',
  'Τηλέφωνα που δεν ανήκουν σε υπάλληλο ούτε σε τμήμα',
  'Κλήσεις που λείπουν από την αναζήτηση',
  'Εκκρεμότητες που λείπουν από την αναζήτηση',
  'Υπάλληλοι χωρίς καταχωρημένο τμήμα',
  'Υπάλληλοι συνδεδεμένοι με ανύπαρκτο ή διαγραμμένο τμήμα',
  'Εκκρεμότητες συνδεδεμένες με ανύπαρκτη ή διαγραμμένη κλήση',
  'Τμήματα με μη συμβαδίζον εσωτερικό όνομα (π.χ. μετά από μετονομασία)',
  'Εξωτερικοί σύνδεσμοι κλήσεων χωρίς αντίστοιχη κλήση',
  'Συνδέσεις τηλεφώνου–υπαλλήλου με ανύπαρκτες εγγραφές',
  'Συνδέσεις τηλεφώνου–τμήματος με ανύπαρκτες εγγραφές',
  'Συνδέσεις εξοπλισμού–υπαλλήλου με ανύπαρκτες εγγραφές',
  'Κλήσεις με αναφορές σε εγγραφές που λείπουν εντελώς από τη βάση '
      '(οι διαγραμμένες οντότητες ΔΕΝ είναι σφάλμα — εμφανίζονται ως ιστορικό)',
  'Εκκρεμότητες με αναφορές σε εγγραφές που λείπουν εντελώς από τη βάση '
      '(οι διαγραμμένες οντότητες ΔΕΝ είναι σφάλμα — εμφανίζονται ως ιστορικό)',
  'Εκκρεμότητες με αλλόκοτη χρονολογική σειρά ημερομηνιών',
  'Εγγραφές ιστορικού ενεργειών χωρίς κείμενο αναζήτησης',
];

/// Tooltip λίστας ελέγχων (ρυθμίσεις βάσης — δίπλα στο κουμπί εκκίνησης).
String get integrityChecksTooltipMessage {
  final buffer = StringBuffer('Ο έλεγχος περιλαμβάνει:\n');
  for (var i = 0; i < _integrityCheckDescriptions.length; i++) {
    buffer.writeln('${i + 1}. ${_integrityCheckDescriptions[i]}');
  }
  return buffer.toString().trimRight();
}

/// Διάλογος βηματικής διάγνωσης και επιδιόρθωσης ακεραιότητας (όπως συντήρηση βάσης / Λάμπα).
class DatabaseIntegrityDialog extends ConsumerStatefulWidget {
  const DatabaseIntegrityDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const DatabaseIntegrityDialog(),
    );
  }

  @override
  ConsumerState<DatabaseIntegrityDialog> createState() =>
      _DatabaseIntegrityDialogState();
}

class _DatabaseIntegrityDialogState extends ConsumerState<DatabaseIntegrityDialog> {
  String? _feedback;
  bool _feedbackIsError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(databaseIntegrityProvider.notifier).runCheck(force: true);
    });
  }

  void _showFeedback(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _feedback = message;
      _feedbackIsError = isError;
    });
  }

  void _clearFeedback() {
    if (_feedback == null && !_feedbackIsError) return;
    if (!mounted) return;
    setState(() {
      _feedback = null;
      _feedbackIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.sizeOf(context);
    final contentWidth = (mq.width * 0.85).clamp(480.0, 920.0);
    final contentHeight = (mq.height * 0.78).clamp(420.0, 720.0);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.fact_check_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Έλεγχος ακεραιότητας'),
          ),
        ],
      ),
      content: SizedBox(
        width: contentWidth,
        height: contentHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_feedback != null) ...[
              Material(
                color: _feedbackIsError
                    ? theme.colorScheme.errorContainer.withValues(alpha: 0.9)
                    : theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _feedbackIsError
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        size: 18,
                        color: _feedbackIsError
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _feedback!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _feedbackIsError
                                ? theme.colorScheme.onErrorContainer
                                : theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _clearFeedback,
                        icon: const Icon(Icons.close, size: 18),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        tooltip: 'Κλείσιμο μηνύματος',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: SingleChildScrollView(
                child: DatabaseIntegrityPanel(onFeedback: _showFeedback),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: ref.watch(databaseIntegrityProvider) is DatabaseIntegrityLoading
              ? null
              : () => ref.read(databaseIntegrityProvider.notifier).runCheck(force: true),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Επανάληψη ελέγχου'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Κλείσιμο'),
        ),
      ],
    );
  }
}

/// Περιεχόμενο ελέγχου/επιδιόρθωσης ακεραιότητας (μέσα στο [DatabaseIntegrityDialog]).
class DatabaseIntegrityPanel extends ConsumerStatefulWidget {
  const DatabaseIntegrityPanel({
    super.key,
    this.onFeedback,
  });

  final IntegrityFeedbackCallback? onFeedback;

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

  void _feedback(String message, {bool isError = false}) {
    if (widget.onFeedback != null) {
      widget.onFeedback!(message, isError: isError);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _copyReport() async {
    final state = ref.read(databaseIntegrityProvider);
    if (state is! DatabaseIntegritySuccess) return;
    final report = state.report;
    if (!report.hasFindings) return;

    await Clipboard.setData(ClipboardData(text: report.toMarkdown()));
    if (!mounted) return;
    _feedback('Η αναφορά αντιγράφηκε στο πρόχειρο.');
  }

  Map<IntegrityCheckType, List<DatabaseIntegrityFinding>> _groupFindings(
    List<DatabaseIntegrityFinding> findings,
  ) {
    final map = <IntegrityCheckType, List<DatabaseIntegrityFinding>>{};
    for (final f in findings) {
      map.putIfAbsent(f.checkType, () => []).add(f);
    }
    return map;
  }

  Future<void> _handleFixResult(
    BuildContext context,
    DatabaseIntegrityFinding finding,
    IntegrityFixResult result, {
    required Future<IntegrityFixResult> Function() retry,
  }) async {
    if (!mounted) return;
    switch (result) {
      case IntegrityFixSuccess():
        _feedback('Η επιδιόρθωση ολοκληρώθηκε.');
      case IntegrityFixFailure(:final message):
        _feedback(message, isError: true);
      case IntegrityFixLockFailure(:final dbPath, :final message):
        final retryRequested = await showIntegrityLockRetryDialog(
          context,
          dbPath: dbPath,
          message: message,
        );
        if (!context.mounted || !retryRequested) return;
        final retryResult = await retry();
        if (!context.mounted) return;
        await _handleFixResult(
          context,
          finding,
          retryResult,
          retry: retry,
        );
    }
  }

  Future<void> _runSingleFix(
    BuildContext context,
    DatabaseIntegrityFinding finding,
  ) async {
    if (finding.checkType == IntegrityCheckType.pragmaQuickCheck) {
      await showIntegrityCorruptionBlockoutDialog(context);
      return;
    }

    final uiMode = finding.checkType.fixUiMode;
    IntegrityFixDecision? decision;

    if (uiMode == IntegrityFixUiMode.confirmOnly) {
      final ok = await showIntegrityConfirmDialog(
        context,
        message: finding.checkType.singleConfirmMessage(finding),
        affectedCount: 1,
      );
      if (!ok || !context.mounted) return;
      decision = const IntegrityFixConfirm();
    } else if (uiMode == IntegrityFixUiMode.choiceRequired) {
      decision = await showIntegrityChoiceDialog(context, finding);
      if (decision == null || !context.mounted) return;
    } else {
      return;
    }

    final notifier = ref.read(databaseIntegrityProvider.notifier);
    Future<IntegrityFixResult> apply() =>
        notifier.applyFix(finding, decision!);

    final result = await apply();
    if (!context.mounted) return;
    await _handleFixResult(context, finding, result, retry: apply);
  }

  Future<void> _runBulkFix(
    BuildContext context,
    IntegrityCheckType checkType,
    List<DatabaseIntegrityFinding> findings,
  ) async {
    if (!checkType.allowsBulkFix || findings.length <= 1) return;

    final ok = await showIntegrityConfirmDialog(
      context,
      message: checkType.bulkConfirmMessage(findings.length),
      affectedCount: findings.length,
    );
    if (!ok || !context.mounted) return;

    final notifier = ref.read(databaseIntegrityProvider.notifier);
    final result = await notifier.applyBulkFix(checkType, findings);
    if (!context.mounted) return;

    if (result.hasLockFailures) {
      final failedFindings = result.lockFailureFindings;
      final firstLock = result.results.firstWhere(
        (r) => r is IntegrityFixLockFailure,
      ) as IntegrityFixLockFailure;
      final retryRequested = await showIntegrityLockRetryDialog(
        context,
        dbPath: firstLock.dbPath,
        message: firstLock.message,
      );
      if (retryRequested && context.mounted && failedFindings.isNotEmpty) {
        await _runBulkFix(context, checkType, failedFindings);
        return;
      }
    }

    if (!mounted) return;
    _feedback(
      'Διορθώθηκαν ${result.successCount} από ${findings.length} ευρήματα.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(databaseIntegrityProvider);
    final fixingKeys = ref.watch(integrityFixingKeysProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state is DatabaseIntegrityLoading) ...[
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
            ..._groupFindings(state.report.findings).entries.map((entry) {
              final checkType = entry.key;
              final groupFindings = entry.value;
              final groupFixing = groupFindings.any(
                (f) => fixingKeys.contains(f.findingKey),
              );
              return _FindingGroup(
                checkType: checkType,
                findings: groupFindings,
                isGroupFixing: groupFixing,
                onBulkFix: groupFindings.length > 1 &&
                        checkType.allowsBulkFix
                    ? () => _runBulkFix(context, checkType, groupFindings)
                    : null,
                onFixFinding: (finding) => _runSingleFix(context, finding),
                fixingKeys: fixingKeys,
              );
            }),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _copyReport,
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
        ],
      ],
    );
  }
}

class _FindingGroup extends StatelessWidget {
  const _FindingGroup({
    required this.checkType,
    required this.findings,
    required this.isGroupFixing,
    required this.onFixFinding,
    required this.fixingKeys,
    this.onBulkFix,
  });

  final IntegrityCheckType checkType;
  final List<DatabaseIntegrityFinding> findings;
  final bool isGroupFixing;
  final VoidCallback? onBulkFix;
  final void Function(DatabaseIntegrityFinding finding) onFixFinding;
  final Set<String> fixingKeys;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${checkType.displayNameEl} (${findings.length})',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isGroupFixing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (onBulkFix != null)
                TextButton.icon(
                  onPressed: onBulkFix,
                  icon: const Icon(Icons.build_circle_outlined, size: 18),
                  label: const Text('Επιδιόρθωση όλων αυτού του τύπου'),
                ),
            ],
          ),
        ),
        if (onBulkFix != null) const Divider(height: 1),
        ...findings.map(
          (finding) => _FindingTile(
            finding: finding,
            isFixing: fixingKeys.contains(finding.findingKey),
            onFix: () => onFixFinding(finding),
          ),
        ),
      ],
    );
  }
}

class _FindingTile extends StatelessWidget {
  const _FindingTile({
    required this.finding,
    required this.isFixing,
    required this.onFix,
  });

  final DatabaseIntegrityFinding finding;
  final bool isFixing;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCritical = finding.severity == IntegritySeverity.critical;
    final dotColor =
        isCritical ? theme.colorScheme.error : Colors.amber.shade700;

    final entityRef = finding.affectedEntity != null && finding.affectedId != null
        ? '${DatabaseIntegrityReport.entityLabelEl(finding.affectedEntity)} #${finding.affectedId}'
        : null;

    final isBlockout = finding.checkType == IntegrityCheckType.pragmaQuickCheck;

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
        trailing: isFixing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: onFix,
                child: Text(isBlockout ? 'Οδηγίες ανάκτησης' : 'Επιδιόρθωση'),
              ),
      ),
    );
  }
}
