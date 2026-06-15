// Έλεγχος ακεραιότητας βάσης: πρόοδος, αναφορές, καταχώρηση ευρημάτων.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/database/old_database/lamp_data_issue_type_labels.dart';
import '../../../core/database/old_database/old_equipment_repository.dart';
import '../../database/services/database_stats_service.dart';
import 'lamp_path_management.dart';
import 'lamp_screen_host.dart';

class LampIntegrityController {
  LampIntegrityController({
    required this.host,
    required this.path,
  });

  final LampScreenHost host;
  final LampPathController path;

  bool integrityChecking = false;

  Future<void> runIntegrityCheck({
    required Future<void> Function() reloadIssues,
  }) async {
    if (integrityChecking) return;
    final dbPath = path.readDbController.text.trim();
    if (dbPath.isEmpty) {
      host.showSnack('Δεν έχει οριστεί βάση για έλεγχο.', isError: true);
      return;
    }
    final cancellationToken = OldIntegrityCancellationToken();
    final progressNotifier = ValueNotifier<OldIntegrityScanProgress?>(null);
    integrityChecking = true;
    host.lampSettingsDialogSetState?.call(() {});
    host.notifyState();
    Future<void>? progressDialog;
    var progressDialogOpen = false;

    Future<void> closeProgressDialog() async {
      if (!progressDialogOpen || !host.mounted) return;
      progressDialogOpen = false;
      Navigator.of(host.context, rootNavigator: true).pop();
      await progressDialog;
    }

    try {
      final historicalDurationsMs = await host.shared.settings
          .getIntegrityStepDurationsMs();
      final screenContext = host.context;
      if (!screenContext.mounted) return;
      final historicalDurations = <String, Duration>{
        for (final entry in historicalDurationsMs.entries)
          entry.key: Duration(milliseconds: entry.value),
      };
      progressDialog = showDialog<void>(
        context: screenContext,
        barrierDismissible: false,
        builder: (context) => LampIntegrityProgressDialog(
          progressListenable: progressNotifier,
          onCancel: cancellationToken.cancel,
        ),
      );
      progressDialogOpen = true;
      final scan = await host.shared.repository.scanIntegrityIssues(
        dbPath,
        cancellationToken: cancellationToken,
        onProgress: (progress) {
          progressNotifier.value = progress;
        },
        onStepError: (step, error, partialIssues) =>
            askIntegrityStepErrorDecision(step, error, partialIssues),
        historicalStepDurations: historicalDurations,
      );
      if (!host.mounted) return;
      await closeProgressDialog();
      await saveIntegrityStepDurations(scan);
      final newIssues = await host.shared.repository.filterToNewDataIssuesOnly(
        dbPath,
        scan.issues,
      );
      final reportScan = OldIntegrityScanResult(
        issues: newIssues,
        steps: scan.steps,
        cancelled: scan.cancelled,
        stoppedAfterError: scan.stoppedAfterError,
      );
      final persist = await askPersistIntegrityIssues(
        reportScan: reportScan,
        rawTotalIssueCount: scan.issues.length,
      );
      if (persist != true) {
        final suffix = scan.isPartial ? ' (μερική αναφορά)' : '';
        host.showSnack(
          'Ο έλεγχος ολοκληρώθηκε χωρίς καταχώρηση στον πίνακα ασυμφωνίας δεδομένων$suffix.',
        );
        return;
      }
      final inserted = await host.shared.repository.insertDataIssues(
        dbPath,
        newIssues,
      );
      await reloadIssues();
      if (!host.mounted) return;
      final suffix = scan.isPartial ? ' από μερικό έλεγχο' : '';
      host.showSnack(
        'Καταχωρήθηκαν $inserted νέα προβλήματα$suffix στον πίνακα ασυμφωνίας δεδομένων.',
      );
    } catch (e) {
      if (!host.mounted) return;
      await closeProgressDialog();
      host.showSnack('Ο έλεγχος ακεραιότητας απέτυχε: $e', isError: true);
    } finally {
      progressNotifier.dispose();
      if (host.mounted) {
        integrityChecking = false;
        host.notifyState();
      }
      host.lampSettingsDialogSetState?.call(() {});
    }
  }

  Future<OldIntegrityStepErrorDecision> askIntegrityStepErrorDecision(
    OldIntegrityScanStepState step,
    Object error,
    List<Map<String, Object?>> partialIssues,
  ) async {
    if (!host.mounted) {
      return OldIntegrityStepErrorDecision.stopWithPartialReport;
    }
    final decision = await showDialog<OldIntegrityStepErrorDecision>(
      context: host.context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Σφάλμα σε βήμα ελέγχου'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SelectableText(
            'Το βήμα «${step.label}» απέτυχε.\n\n'
            'Σφάλμα: $error\n\n'
            'Έχουν συλλεχθεί ${partialIssues.length} ευρήματα μέχρι τώρα. '
            'Μπορείτε να συνεχίσετε με τα επόμενα βήματα ή να δείτε μερική αναφορά.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(OldIntegrityStepErrorDecision.stopWithPartialReport),
            child: const Text('Προβολή αναφοράς'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(OldIntegrityStepErrorDecision.continueScan),
            child: const Text('Συνέχεια'),
          ),
        ],
      ),
    );
    return decision ?? OldIntegrityStepErrorDecision.stopWithPartialReport;
  }

  Future<void> saveIntegrityStepDurations(OldIntegrityScanResult scan) async {
    final completedDurations = <String, int>{
      for (final step in scan.steps)
        if (step.status == OldIntegrityStepStatus.success &&
            step.elapsed.inMilliseconds > 0)
          step.id: step.elapsed.inMilliseconds,
    };
    await host.shared.settings.updateIntegrityStepDurationsMs(
      completedDurations,
    );
  }

  Future<bool?> askPersistIntegrityIssues({
    required OldIntegrityScanResult reportScan,
    required int rawTotalIssueCount,
  }) {
    final theme = Theme.of(host.context);
    final scheme = theme.colorScheme;
    final breakdown = reportScan.countByType.entries
        .map((e) => '- ${lampDataIssueTypeDisplayLabel(e.key)}: ${e.value}')
        .join('\n');
    final stepReport = reportScan.steps.isEmpty
        ? ''
        : '\n\nΒήματα:\n${reportScan.steps.map(integrityStepReportLine).join('\n')}';
    final partialPrefix = reportScan.cancelled
        ? 'Ο έλεγχος ακυρώθηκε από τον χρήστη. Εμφανίζονται ευρήματα από ${reportScan.completedSteps} από ${reportScan.totalSteps} βήματα.\n\n'
        : reportScan.stoppedAfterError
        ? 'Ο έλεγχος σταμάτησε μετά από σφάλμα. Εμφανίζονται τα ευρήματα που συλλέχθηκαν μέχρι εκείνο το σημείο.\n\n'
        : '';

    final rawFmt = DatabaseStatsService.formatIntegerEl(rawTotalIssueCount);

    return showDialog<bool>(
      context: host.context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Αναφορά ελέγχου προβλημάτων'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (partialPrefix.isNotEmpty)
                  SelectableText(
                    partialPrefix,
                    style: theme.textTheme.bodyMedium,
                  ),
                if (reportScan.totalCount == 0) ...[
                  SelectableText(
                    'Δεν εντοπίστηκαν νέα προβλήματα.',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF2E7D32),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (rawTotalIssueCount > 0) ...[
                    const SizedBox(height: 10),
                    SelectableText(
                      'Ο έλεγχος επανέλεγξε $rawFmt ευρήματα συνολικά· όλα είναι '
                      'ήδη καταγεγραμμένα στον πίνακα ασυμφωνίας δεδομένων.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ] else ...[
                  SelectableText(
                    'Εντοπίστηκαν ${reportScan.totalCount} νέα προβλήματα σε '
                    '${reportScan.countByType.length} κατηγορίες.',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(breakdown, style: theme.textTheme.bodyMedium),
                ],
                if (stepReport.isNotEmpty)
                  SelectableText(stepReport, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Μόνο αναφορά'),
          ),
          FilledButton(
            onPressed: reportScan.issues.isEmpty
                ? null
                : () => Navigator.of(dialogContext).pop(true),
            child: const Text('Καταχώρηση στον πίνακα ασυμφωνίας δεδομένων'),
          ),
        ],
      ),
    );
  }

  String integrityStepReportLine(OldIntegrityScanStepState step) {
    final status = switch (step.status) {
      OldIntegrityStepStatus.pending => 'Σε αναμονή',
      OldIntegrityStepStatus.running => 'Σε εξέλιξη',
      OldIntegrityStepStatus.success =>
        'Ολοκληρώθηκε (${step.issuesFound} ευρήματα)',
      OldIntegrityStepStatus.error =>
        'Σφάλμα (${step.errorMessage ?? 'άγνωστο σφάλμα'})',
      OldIntegrityStepStatus.cancelled => 'Ακυρώθηκε',
    };
    return '- ${step.index}/${step.total}: ${step.label} - $status';
  }
}

class LampIntegrityProgressDialog extends StatefulWidget {
  const LampIntegrityProgressDialog({
    super.key,
    required this.progressListenable,
    required this.onCancel,
  });

  final ValueListenable<OldIntegrityScanProgress?> progressListenable;
  final VoidCallback onCancel;

  @override
  State<LampIntegrityProgressDialog> createState() =>
      _LampIntegrityProgressDialogState();
}

class _LampIntegrityProgressDialogState
    extends State<LampIntegrityProgressDialog> {
  bool cancelRequested = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Έλεγχος ακεραιότητας'),
      content: SizedBox(
        width: 640,
        child: ValueListenableBuilder<OldIntegrityScanProgress?>(
          valueListenable: widget.progressListenable,
          builder: (context, progress, _) {
            if (progress == null) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Προετοιμασία ελέγχου...'),
                  ],
                ),
              );
            }
            OldIntegrityScanStepState? current;
            for (final step in progress.steps) {
              if (step.status == OldIntegrityStepStatus.running) {
                current = step;
                break;
              }
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: progress.fraction),
                const SizedBox(height: 12),
                Text(
                  current == null
                      ? 'Ολοκληρωμένα βήματα: ${progress.completedSteps}/${progress.steps.length}'
                      : current.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('Ευρήματα: ${progress.totalIssuesFound}'),
                    Text(
                      'Χρόνος: ${formatIntegrityDuration(progress.elapsed)}',
                    ),
                    Text(
                      progress.estimatedRemaining == null
                          ? 'Υπόλοιπο: υπολογίζεται...'
                          : 'Υπόλοιπο: ~${formatIntegrityDuration(progress.estimatedRemaining!)}',
                    ),
                  ],
                ),
                if (cancelRequested || progress.cancelRequested) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Ζητήθηκε ακύρωση. Ο έλεγχος θα σταματήσει στο πρώτο ασφαλές σημείο.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: progress.steps.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final step = progress.steps[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          integrityStepIcon(step.status),
                          color: integrityStepColor(context, step.status),
                        ),
                        title: Text(step.label),
                        subtitle: Text(integrityStepSubtitle(step)),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: cancelRequested
              ? null
              : () {
                  setState(() => cancelRequested = true);
                  widget.onCancel();
                },
          icon: const Icon(Icons.cancel_outlined),
          label: Text(cancelRequested ? 'Ακύρωση ζητήθηκε' : 'Ακύρωση'),
        ),
      ],
    );
  }
}

String formatIntegrityDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  if (totalSeconds < 60) return '${totalSeconds}s';
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
}

IconData integrityStepIcon(OldIntegrityStepStatus status) {
  return switch (status) {
    OldIntegrityStepStatus.pending => Icons.schedule,
    OldIntegrityStepStatus.running => Icons.hourglass_top,
    OldIntegrityStepStatus.success => Icons.check_circle_outline,
    OldIntegrityStepStatus.error => Icons.error_outline,
    OldIntegrityStepStatus.cancelled => Icons.block,
  };
}

Color? integrityStepColor(BuildContext context, OldIntegrityStepStatus status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    OldIntegrityStepStatus.pending => scheme.outline,
    OldIntegrityStepStatus.running => scheme.primary,
    OldIntegrityStepStatus.success => Colors.green,
    OldIntegrityStepStatus.error => scheme.error,
    OldIntegrityStepStatus.cancelled => scheme.outline,
  };
}

String integrityStepSubtitle(OldIntegrityScanStepState step) {
  return switch (step.status) {
    OldIntegrityStepStatus.pending => 'Σε αναμονή',
    OldIntegrityStepStatus.running => 'Σε εξέλιξη...',
    OldIntegrityStepStatus.success =>
      'Ολοκληρώθηκε (${step.issuesFound} ευρήματα, ${formatIntegrityDuration(step.elapsed)})',
    OldIntegrityStepStatus.error =>
      'Σφάλμα: ${step.errorMessage ?? 'άγνωστο σφάλμα'}',
    OldIntegrityStepStatus.cancelled => 'Ακυρώθηκε',
  };
}
