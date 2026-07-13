import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/database/old_database/lamp_issue_resolution_service.dart';
import 'lamp_entity_code_autocomplete.dart';

/// Αποτέλεσμα διαλόγου για πρόταση με [LampIssueResolutionAction.unresolved].
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

/// Χειροκίνητη σύνδεση με αριθμητικό κωδικό.
final class LampUnresolvedSetFieldManual extends LampUnresolvedResolutionOutcome {
  const LampUnresolvedSetFieldManual(this.codeInput);

  final String codeInput;
}

/// Εκκαθάριση (NULL) του πεδίου της εγγραφής.
final class LampUnresolvedClearField extends LampUnresolvedResolutionOutcome {
  const LampUnresolvedClearField();
}

/// Αναβολή της τρέχουσας πρότασης.
final class LampUnresolvedDeferCurrent extends LampUnresolvedResolutionOutcome {
  const LampUnresolvedDeferCurrent();
}

/// Μαζική αναβολή όλων των υπόλοιπων ανεπίλυτων προτάσεων.
final class LampUnresolvedDeferAll extends LampUnresolvedResolutionOutcome {
  const LampUnresolvedDeferAll();
}

String columnLabelEl(String? column) {
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

typedef LampManualFkLookup = Future<String?> Function(
  String column,
  int targetId,
);

typedef LampEntityCodeSearch = Future<List<LampEntityCodeSuggestion>> Function(
  String column,
  String query,
);

Future<LampUnresolvedResolutionOutcome?> showLampUnresolvedResolutionDialog({
  required BuildContext context,
  required LampIssueResolutionProposal proposal,
  required String databasePath,
  LampIssueResolutionService? resolutionService,
  LampManualFkLookup? manualFkLookup,
  LampEntityCodeSearch? entityCodeSearch,
}) {
  return showDialog<LampUnresolvedResolutionOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (context) => LampUnresolvedResolutionDialog(
      proposal: proposal,
      databasePath: databasePath,
      resolutionService: resolutionService ?? LampIssueResolutionService(),
      manualFkLookup: manualFkLookup,
      entityCodeSearch: entityCodeSearch,
    ),
  );
}

class LampUnresolvedResolutionDialog extends StatefulWidget {
  const LampUnresolvedResolutionDialog({
    super.key,
    required this.proposal,
    required this.databasePath,
    required this.resolutionService,
    this.manualFkLookup,
    this.entityCodeSearch,
  });

  final LampIssueResolutionProposal proposal;
  final String databasePath;
  final LampIssueResolutionService resolutionService;
  final LampManualFkLookup? manualFkLookup;
  final LampEntityCodeSearch? entityCodeSearch;

  @override
  State<LampUnresolvedResolutionDialog> createState() =>
      _LampUnresolvedResolutionDialogState();
}

class _LampUnresolvedResolutionDialogState
    extends State<LampUnresolvedResolutionDialog> {
  final TextEditingController _codeController = TextEditingController();
  Timer? _lookupDebounce;
  String? _resolvedLabel;
  bool _lookupInFlight = false;
  String? _lookupError;

  bool get _supportsFieldActions =>
      ManualFkTargetSpec.forColumn(widget.proposal.column) != null;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _codeController
      ..removeListener(_onCodeChanged)
      ..dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    _lookupDebounce?.cancel();
    _lookupDebounce = Timer(const Duration(milliseconds: 300), _runLookup);
    if (_resolvedLabel != null || _lookupError != null || _lookupInFlight) {
      setState(() {
        _resolvedLabel = null;
        _lookupError = null;
        _lookupInFlight = false;
      });
    }
  }

  Future<void> _runLookup() async {
    final raw = _codeController.text.trim();
    final targetId = int.tryParse(raw);
    if (raw.isEmpty) {
      if (!mounted) return;
      setState(() {
        _resolvedLabel = null;
        _lookupError = null;
        _lookupInFlight = false;
      });
      return;
    }
    if (targetId == null) {
      if (!mounted) return;
      setState(() {
        _resolvedLabel = null;
        _lookupError = 'Ο κωδικός πρέπει να είναι ακέραιος αριθμός.';
        _lookupInFlight = false;
      });
      return;
    }

    setState(() => _lookupInFlight = true);
    final column = widget.proposal.column ?? '';
    final label = widget.manualFkLookup != null
        ? await widget.manualFkLookup!(column, targetId)
        : await widget.resolutionService.lookupManualFkTargetLabel(
            databasePath: widget.databasePath,
            column: column,
            targetId: targetId,
          );
    if (!mounted) return;
    setState(() {
      _lookupInFlight = false;
      if (label == null) {
        _resolvedLabel = null;
        _lookupError = 'Δεν βρέθηκε εγγραφή με κωδικό $targetId.';
      } else {
        _resolvedLabel = label;
        _lookupError = null;
      }
    });
  }

  bool get _canApplyManualCode =>
      !_lookupInFlight &&
      _lookupError == null &&
      _resolvedLabel != null &&
      _codeController.text.trim().isNotEmpty;

  Future<List<LampEntityCodeSuggestion>> _searchEntityCodes(String query) {
    final column = widget.proposal.column ?? '';
    if (widget.entityCodeSearch != null) {
      return widget.entityCodeSearch!(column, query);
    }
    return widget.resolutionService.searchManualFkTargets(
      databasePath: widget.databasePath,
      column: column,
      query: query,
    );
  }

  String? _metadataText(String key) {
    final raw = widget.proposal.metadata[key];
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final proposal = widget.proposal;
    final entityType = _entityTypeLabel(
      _metadataText('diagnosticEntityType') ?? 'equipment',
    );
    final origin = _originLabel(_metadataText('diagnosticOrigin') ?? 'manual');
    final diagnosticType = _metadataText('diagnosticType');
    final fieldLabel = columnLabelEl(proposal.column);

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
                  Text(
                    'Κωδικός εξοπλισμού: ${proposal.row ?? '-'}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    'Πεδίο: $fieldLabel',
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
              if (_supportsFieldActions) ...[
                const SizedBox(height: 20),
                Text(
                  'Διόρθωση με κωδικό',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                LampEntityCodeAutocomplete(
                  controller: _codeController,
                  searchSuggestions: _searchEntityCodes,
                  onCodeSelected: (_) => _runLookup(),
                  decoration: InputDecoration(
                    labelText: 'Κωδικός ή όνομα $fieldLabel',
                    border: const OutlineInputBorder(),
                    errorText: _lookupError,
                  ),
                ),
                if (_lookupInFlight)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(),
                  ),
                if (_resolvedLabel != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Θα συνδεθεί με: $_resolvedLabel',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _canApplyManualCode
                        ? () => Navigator.of(context).pop(
                              LampUnresolvedSetFieldManual(
                                _codeController.text.trim(),
                              ),
                            )
                        : null,
                    child: const Text('Εφαρμογή κωδικού'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Εκκαθάριση πεδίου',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Θα αδειάσει το πεδίο «$fieldLabel» του εξοπλισμού '
                  'με κωδικό ${proposal.row ?? '-'} (τιμή NULL).',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(
                      const LampUnresolvedClearField(),
                    ),
                    child: const Text('Εκκαθάριση πεδίου'),
                  ),
                ),
              ],
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
              Navigator.of(context).pop(const LampUnresolvedDeferAll()),
          child: const Text('Αναβολή όλων των ανεπίλυτων'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const LampUnresolvedSkipCurrent()),
          child: const Text('Παράλειψη τρέχουσας'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const LampUnresolvedDeferCurrent()),
          child: const Text('Αναβολή'),
        ),
      ],
    );
  }
}
