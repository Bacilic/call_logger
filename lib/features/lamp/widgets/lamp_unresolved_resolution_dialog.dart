import 'package:flutter/material.dart';

import '../../../core/database/old_database/lamp_issue_resolution_service.dart';

/// Αποτέλεμα διαλόγου για πρόταση με [LampIssueResolutionAction.unresolved].
sealed class LampUnresolvedResolutionOutcome {
  const LampUnresolvedResolutionOutcome();
}

/// Διακοπή όλης της διαδικασίας επίλυσης (ίδιο αποτέλεσμα με `null` από το διάλογο).
final class LampUnresolvedCancelAll extends LampUnresolvedResolutionOutcome {
  const LampUnresolvedCancelAll();
}

/// Μαζική παράλειψη όλων των υπόλοιπων ανεπίλυτων προτάσεων.
final class LampUnresolvedSkipAll extends LampUnresolvedResolutionOutcome {
  const LampUnresolvedSkipAll();
}

/// Παράλειψη μόνο της τρέχουσας ανεπίλυτης πρότασης.
final class LampUnresolvedSkipCurrent extends LampUnresolvedResolutionOutcome {
  const LampUnresolvedSkipCurrent();
}

String _columnLabelEl(String? column) {
  if (column == null || column.isEmpty) return '-';
  switch (column.trim().toLowerCase()) {
    case 'office':
      return 'γραφείο';
    case 'owner':
      return 'υπάλληλος';
    case 'model':
      return 'μοντέλο';
    case 'contract':
      return 'συμβόλαιο';
    case 'set_master':
      return 'κύριος εξοπλισμός';
    default:
      return column;
  }
}

Future<LampUnresolvedResolutionOutcome?> showLampUnresolvedResolutionDialog({
  required BuildContext context,
  required LampIssueResolutionProposal proposal,
}) {
  return showDialog<LampUnresolvedResolutionOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        LampUnresolvedResolutionDialog(proposal: proposal),
  );
}

class LampUnresolvedResolutionDialog extends StatelessWidget {
  const LampUnresolvedResolutionDialog({
    super.key,
    required this.proposal,
  });

  final LampIssueResolutionProposal proposal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entityType = _entityTypeLabel(
      _metadataText('diagnosticEntityType') ?? 'equipment',
    );
    final origin = _originLabel(_metadataText('diagnosticOrigin') ?? 'manual');
    final diagnosticType = _metadataText('diagnosticType');
    return AlertDialog(
      title: Text('${proposal.issueType.label} · ανεπίλυτη πρόταση'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  Text('Οντότητα: $entityType', style: theme.textTheme.bodyMedium),
                  Text('Προέλευση: $origin', style: theme.textTheme.bodyMedium),
                  Text('Γραμμή: ${proposal.row ?? '-'}',
                      style: theme.textTheme.bodyMedium),
                  Text(
                    'Πεδίο: ${_columnLabelEl(proposal.column)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    'Βεβαιότητα: ${proposal.confidence}%',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (proposal.originalValue != null &&
                  proposal.originalValue!.trim().isNotEmpty)
                SelectableText(
                  'Αρχική τιμή: ${proposal.originalValue}',
                  style: theme.textTheme.bodyLarge,
                ),
              if (diagnosticType != null && diagnosticType.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                SelectableText(
                  'Φύση σφάλματος: ${_diagnosticTypeLabel(diagnosticType)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 8),
              SelectableText(
                proposal.notes,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Text(
                'Η πρόταση δεν μπορεί να επιλυθεί αυτόματα. Επιλέξτε πώς να '
                'συνεχίσετε με τις ανεπίλυτες εγγραφές.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const LampUnresolvedCancelAll()),
          child: const Text('Ακύρωση επίλυσης'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const LampUnresolvedSkipAll()),
          child: const Text('Παράλειψη όλων των ανεπίλυτων'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const LampUnresolvedSkipCurrent()),
          child: const Text('Παράλειψη τρέχουσας'),
        ),
      ],
    );
  }

  String? _metadataText(String key) {
    final raw = proposal.metadata[key];
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty || value == '(κενό)') return null;
    return value;
  }

  String _entityTypeLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'equipment':
        return 'Εξοπλισμός';
      default:
        return value;
    }
  }

  String _originLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'integrity_scan':
        return 'Έλεγχος ακεραιότητας';
      case 'manual':
        return 'Χειροκίνητη καταχώρηση';
      default:
        return value;
    }
  }

  String _diagnosticTypeLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'fk_resolution_eligibility':
        return 'Μη επιλέξιμο για αυτόματη επίλυση κλειδιού αναφοράς';
      case 'fk_resolution_unsupported_column':
        return 'Μη υποστηριζόμενο πεδίο κλειδιού αναφοράς';
      default:
        return value;
    }
  }
}
