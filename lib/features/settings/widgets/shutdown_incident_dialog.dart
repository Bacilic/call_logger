import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/shutdown_trace_incident.dart';
import '../../../core/services/shutdown_trace_steps.dart';

/// Ένα κλείσιμο της εφαρμογής, βήμα-βήμα — μόνο αυτό, χωρίς αρχεία και οδηγό.
Future<void> showShutdownIncidentDialog(
  BuildContext context,
  ShutdownTraceIncident incident,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ShutdownIncidentDialog(incident: incident),
  );
}

class _ShutdownIncidentDialog extends StatefulWidget {
  const _ShutdownIncidentDialog({required this.incident});

  final ShutdownTraceIncident incident;

  @override
  State<_ShutdownIncidentDialog> createState() =>
      _ShutdownIncidentDialogState();
}

class _ShutdownIncidentDialogState extends State<_ShutdownIncidentDialog> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(
      ClipboardData(text: shutdownIncidentPlainText(widget.incident)),
    );
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final incident = widget.incident;
    final steps = parseShutdownTraceSteps(incident.trace);
    final when = MaterialLocalizations.of(context);
    final at = incident.occurredAt;

    return AlertDialog(
      title: const Text('Προηγούμενο κλείσιμο'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${when.formatCompactDate(at)}, '
                '${when.formatTimeOfDay(TimeOfDay.fromDateTime(at), alwaysUse24HourFormat: true)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(incident.describeEvent(), style: theme.textTheme.bodyLarge),
              const SizedBox(height: 16),
              if (steps.isEmpty)
                const Text('Τα βήματα δεν καταγράφηκαν.')
              else
                for (final step in steps) _StepRow(step: step),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _copy,
          icon: Icon(_copied ? Icons.check : Icons.copy_outlined, size: 18),
          label: Text(_copied ? 'Αντιγράφηκε' : 'Αντιγραφή'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Κλείσιμο'),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final ShutdownTraceStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = step.outcome != ShutdownTraceStepOutcome.completed;
    final resultColor = problem
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    final error = step.error?.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(step.label)),
              const SizedBox(width: 12),
              Text(
                step.resultText,
                style: theme.textTheme.bodyMedium?.copyWith(color: resultColor),
              ),
            ],
          ),
          if (error.isNotEmpty)
            Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}
