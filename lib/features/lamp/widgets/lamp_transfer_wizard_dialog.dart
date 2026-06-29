import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/lamp_migration_service.dart';
import '../services/lamp_transfer_preview.dart';
import 'lamp_transfer_operations_preview_panel.dart';

class LampTransferWizardDialog extends StatefulWidget {
  const LampTransferWizardDialog({
    super.key,
    required this.target,
    required this.sourceRow,
    required this.service,
  });

  final LampTransferTarget target;
  final Map<String, Object?> sourceRow;
  final LampMigrationService service;

  @override
  State<LampTransferWizardDialog> createState() =>
      _LampTransferWizardDialogState();
}

class _LampTransferWizardDialogState extends State<LampTransferWizardDialog> {
  LampMigrationDraft? _draft;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _localError;
  int? _selectedCandidateId;
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.removeListener(_onFormValuesChanged);
      controller.dispose();
    }
    super.dispose();
  }

  void _onFormValuesChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Map<String, String> _currentFormValues() {
    return <String, String>{
      for (final entry in _controllers.entries)
        entry.key: entry.value.text.trim(),
    };
  }

  Future<void> _loadDraft() async {
    try {
      final draft = await widget.service.buildDraft(
        target: widget.target,
        sourceRow: widget.sourceRow,
      );
      for (final spec in lampTransferFormFieldSpecs(draft.target)) {
        final value = draft.formValues[spec.formKey] ?? '';
        final controller = TextEditingController(text: value);
        controller.addListener(_onFormValuesChanged);
        _controllers[spec.formKey] = controller;
      }
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _selectedCandidateId = draft.selectedCandidateId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_draft == null || _saving) return;
    final draft = _draft!;
    final formValues = <String, String>{
      for (final entry in _controllers.entries)
        entry.key: entry.value.text.trim(),
    };
    if ((formValues['name'] ?? '').isEmpty &&
        draft.target == LampTransferTarget.department) {
      _showLocalError('Το τμήμα είναι υποχρεωτικό.');
      return;
    }
    if ((formValues['code_equipment'] ?? '').isEmpty &&
        draft.target == LampTransferTarget.equipment) {
      _showLocalError('Ο κωδικός εξοπλισμού είναι υποχρεωτικός.');
      return;
    }

    setState(() => _saving = true);
    try {
      List<LampOwnerConflictDecision>? ownerConflictDecisions;
      if (draft.target == LampTransferTarget.owner) {
        final conflicts = await widget.service.detectOwnerConflicts(
          formValues: formValues,
          selectedCandidateId: _selectedCandidateId,
        );
        if (conflicts.isNotEmpty) {
          ownerConflictDecisions = await _showOwnerConflictsDialog(conflicts);
          if (ownerConflictDecisions == null) {
            if (!mounted) return;
            setState(() => _saving = false);
            return;
          }
        }
      } else if (draft.target == LampTransferTarget.department) {
        final conflicts = await widget.service.detectDepartmentConflicts(
          formValues: formValues,
          selectedCandidateId: _selectedCandidateId,
        );
        if (conflicts.isNotEmpty) {
          ownerConflictDecisions = await _showOwnerConflictsDialog(conflicts);
          if (ownerConflictDecisions == null) {
            if (!mounted) return;
            setState(() => _saving = false);
            return;
          }
        }
      } else if (draft.target == LampTransferTarget.equipment) {
        final conflicts = await widget.service.detectEquipmentConflicts(
          formValues: formValues,
          selectedCandidateId: _selectedCandidateId,
        );
        if (conflicts.isNotEmpty) {
          ownerConflictDecisions = await _showOwnerConflictsDialog(conflicts);
          if (ownerConflictDecisions == null) {
            if (!mounted) return;
            setState(() => _saving = false);
            return;
          }
        }
      }
      var confirmEntityCreations = false;
      final pendingCreations = await widget.service.detectPendingEntityCreations(
        target: draft.target,
        formValues: formValues,
        selectedCandidateId: _selectedCandidateId,
      );
      if (pendingCreations.isNotEmpty) {
        final confirmed = await _showPendingEntityCreationsDialog(
          pendingCreations,
        );
        if (confirmed != true) {
          if (!mounted) return;
          setState(() => _saving = false);
          return;
        }
        confirmEntityCreations = true;
      }
      LampSoftDeletedDecision? softDeletedDecision;
      if (_selectedCandidateId == null) {
        final softDeletedMatch = await widget.service.detectSoftDeletedMatch(
          target: draft.target,
          formValues: formValues,
          selectedCandidateId: null,
        );
        if (softDeletedMatch != null) {
          softDeletedDecision = await _showSoftDeletedMatchDialog(
            softDeletedMatch,
          );
          if (softDeletedDecision == null) {
            if (!mounted) return;
            setState(() => _saving = false);
            return;
          }
        }
      }
      final result = await widget.service.save(
        target: draft.target,
        formValues: formValues,
        selectedCandidateId: _selectedCandidateId,
        ownerConflictDecisions: ownerConflictDecisions,
        confirmEntityCreations: confirmEntityCreations,
        softDeletedDecision: softDeletedDecision,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showLocalError('Αποτυχία αποθήκευσης: $e');
    }
  }

  void _showLocalError(String message) {
    setState(() => _localError = message);
  }

  void _clearLocalError() {
    if (_localError == null) return;
    setState(() => _localError = null);
  }

  Future<void> _copyLocalError(String message) async {
    await Clipboard.setData(ClipboardData(text: message));
  }

  Widget _localErrorPanel(BuildContext context) {
    final message = _localError;
    if (message == null || message.isEmpty) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 20, color: scheme.onSurface),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Αντιγραφή μηνύματος',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copyLocalError(message),
                  icon: const Icon(Icons.copy_outlined, size: 18),
                ),
                IconButton(
                  tooltip: 'Απόκρυψη μηνύματος',
                  visualDensity: VisualDensity.compact,
                  onPressed: _clearLocalError,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Οδηγός Μεταφοράς'),
      content: SizedBox(
        width: 1180,
        height: 640,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildContent(context)),
            if (_localError != null) ...[
              const SizedBox(height: 12),
              _localErrorPanel(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    final draft = _draft!;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 980) {
          return _desktopThreePaneLayout(draft);
        }
        return _stackedLayout(draft);
      },
    );
  }

  Widget _desktopThreePaneLayout(LampMigrationDraft draft) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: _oldPane(draft)),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: _suggestionPane(draft)),
        const SizedBox(width: 12),
        Expanded(flex: 4, child: _rightPane(draft)),
      ],
    );
  }

  Widget _stackedLayout(LampMigrationDraft draft) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            children: [
              _oldPane(draft, fixedHeight: 240),
              const SizedBox(height: 12),
              _suggestionPane(draft, fixedHeight: 280),
              const SizedBox(height: 12),
              _rightPane(draft, fixedHeight: 420),
            ],
          ),
        ),
      ],
    );
  }

  Widget _oldPane(LampMigrationDraft draft, {double? fixedHeight}) {
    return _paneCard(
      title: 'Παλιά δεδομένα',
      fixedHeight: fixedHeight,
      child: ListView(
        children: [
          for (final entry in draft.oldValues.entries)
            if (entry.value.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _labeledValue(entry.key, entry.value),
              ),
        ],
      ),
    );
  }

  Widget _suggestionPane(LampMigrationDraft draft, {double? fixedHeight}) {
    return _paneCard(
      title: 'Πρόταση',
      fixedHeight: fixedHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (draft.hint != null && draft.hint!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                draft.hint!,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(child: _candidateSelector(draft)),
          ),
        ],
      ),
    );
  }

  Widget _rightPane(LampMigrationDraft draft, {double? fixedHeight}) {
    final preview = buildLampTransferPreview(
      draft: draft,
      currentFormValues: _currentFormValues(),
      selectedCandidateId: _selectedCandidateId,
    );

    return _paneCard(
      title: 'Προεπισκόπηση ενεργειών',
      fixedHeight: fixedHeight,
      child: LampTransferMigrationForm(
        target: draft.target,
        preview: preview,
        controllers: _controllers,
        saving: _saving,
        saveLabel: _selectedCandidateId == null ? 'Δημιουργία' : 'Ενημέρωση',
        onCancel: () => Navigator.of(context).pop(),
        onSave: _save,
      ),
    );
  }

  Widget _paneCard({
    required String title,
    required Widget child,
    double? fixedHeight,
  }) {
    final core = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(child: child),
          ],
        ),
      ),
    );
    if (fixedHeight == null) return core;
    return SizedBox(height: fixedHeight, child: core);
  }

  Widget _candidateSelector(LampMigrationDraft draft) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top-3 πιθανές αντιστοιχίσεις',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        if (draft.candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Καμία πιθανή αντιστοίχιση',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        RadioGroup<int?>(
          groupValue: _selectedCandidateId,
          onChanged: (value) => _handleCandidateSelectionChanged(draft, value),
          child: Column(
            children: [
              RadioListTile<int?>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Νέα εγγραφή'),
                subtitle: const Text('Χωρίς σύνδεση με υπάρχουσα οντότητα'),
                value: null,
              ),
              for (final candidate in draft.candidates)
                RadioListTile<int?>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: candidate.id,
                  title: Text(candidate.label),
                  subtitle: Text(
                    'Confidence: ${candidate.confidence}%${candidate.isExact ? ' · ακριβές ταίριασμα' : ''}',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _labeledValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(value),
      ],
    );
  }

  Future<List<LampOwnerConflictDecision>?> _showOwnerConflictsDialog(
    List<LampOwnerConflict> conflicts,
  ) {
    final selections = <String, LampOwnerConflictAction>{
      for (final conflict in conflicts)
        conflict.conflictId: LampOwnerConflictAction.keepWithoutAssignment,
    };
    return showDialog<List<LampOwnerConflictDecision>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Εντοπίστηκαν διενέξεις'),
              content: SizedBox(
                width: 760,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Για κάθε διένεξη επιλέξτε πολιτική ενημέρωσης.',
                      ),
                      const SizedBox(height: 12),
                      for (final conflict in conflicts) ...[
                        Text(
                          _conflictTitle(conflict),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        RadioGroup<LampOwnerConflictAction>(
                          groupValue: selections[conflict.conflictId],
                          onChanged: (value) {
                            if (value == null) return;
                            setStateDialog(
                              () => selections[conflict.conflictId] = value,
                            );
                          },
                          child: Column(
                            children: [
                              RadioListTile<LampOwnerConflictAction>(
                                value:
                                    LampOwnerConflictAction.transferToSelectedOwner,
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(_transferOptionLabel(conflict)),
                              ),
                              RadioListTile<LampOwnerConflictAction>(
                                value: LampOwnerConflictAction.keepWithoutAssignment,
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(_skipOptionLabel(conflict)),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 20),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text('Άκυρο'),
                ),
                FilledButton(
                  onPressed: () {
                    final decisions = <LampOwnerConflictDecision>[
                      for (final conflict in conflicts)
                        LampOwnerConflictDecision(
                          conflictId: conflict.conflictId,
                          action: selections[conflict.conflictId] ??
                              LampOwnerConflictAction.keepWithoutAssignment,
                        ),
                    ];
                    Navigator.of(dialogContext).pop(decisions);
                  },
                  child: const Text('Συνέχεια'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<LampSoftDeletedDecision?> _showSoftDeletedMatchDialog(
    LampSoftDeletedMatch match,
  ) {
    return showDialog<LampSoftDeletedDecision>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Διαγραμμένη όμοια εγγραφή'),
          content: SizedBox(
            width: 560,
            child: Text(
              'Υπάρχει διαγραμμένη όμοια εγγραφή: ${match.label}.\n'
              'Επαναφορά της υπάρχουσας ή δημιουργία νέας;',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Άκυρο'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                LampSoftDeletedDecision(
                  action: LampSoftDeletedDecisionAction.createNew,
                  recordId: match.id,
                ),
              ),
              child: const Text('Δημιουργία νέας'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                LampSoftDeletedDecision(
                  action: LampSoftDeletedDecisionAction.reactivate,
                  recordId: match.id,
                ),
              ),
              child: const Text('Επαναφορά'),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showPendingEntityCreationsDialog(
    List<LampPendingEntityCreation> pending,
  ) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Επιβεβαίωση δημιουργίας'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Θα δημιουργηθούν οι παρακάτω συσχετιζόμενες εγγραφές:',
                  ),
                  const SizedBox(height: 12),
                  for (final item in pending) ...[
                    Text(
                      _pendingCreationDescription(item),
                      style: Theme.of(dialogContext).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Άκυρο'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Δημιουργία'),
            ),
          ],
        );
      },
    );
  }

  String _pendingCreationDescription(LampPendingEntityCreation item) {
    return switch (item.entityKind) {
      LampPendingEntityKind.user =>
        'Θα δημιουργηθεί νέος χρήστης: ${item.label} χωρίς τηλέφωνα',
      LampPendingEntityKind.equipment =>
        'Θα δημιουργηθεί νέος εξοπλισμός: ${item.label} χωρίς τμήμα/τύπο',
    };
  }

  String _conflictTitle(LampOwnerConflict conflict) {
    final ownersText = conflict.currentOwners.join(', ');
    return switch (conflict.kind) {
      LampOwnerConflictKind.equipment =>
        'Ο εξοπλισμός ${conflict.value} ανήκει στον/στην: $ownersText',
      LampOwnerConflictKind.phone =>
        'Το τηλέφωνο ${conflict.value} ανήκει στον/στην: $ownersText',
    };
  }

  String _transferOptionLabel(LampOwnerConflict conflict) {
    return switch (conflict.kind) {
      LampOwnerConflictKind.equipment =>
        'Αφαίρεση από τωρινούς κατόχους και προσθήκη στον επιλεγμένο χρήστη',
      LampOwnerConflictKind.phone =>
        'Αφαίρεση από τωρινούς κατόχους και προσθήκη στον επιλεγμένο χρήστη',
    };
  }

  String _skipOptionLabel(LampOwnerConflict conflict) {
    return switch (conflict.kind) {
      LampOwnerConflictKind.equipment =>
        'Καταχώρηση χρήστη χωρίς αυτόν τον εξοπλισμό',
      LampOwnerConflictKind.phone =>
        'Καταχώρηση χρήστη χωρίς αυτό το τηλέφωνο',
    };
  }

  void _handleCandidateSelectionChanged(LampMigrationDraft draft, int? value) {
    final selectedValues = value == null
        ? draft.newRecordFormValues
        : draft.candidateFormValues[value] ?? draft.newRecordFormValues;
    setState(() {
      _selectedCandidateId = value;
      for (final entry in selectedValues.entries) {
        final controller = _controllers.putIfAbsent(
          entry.key,
          () {
            final created = TextEditingController();
            created.addListener(_onFormValuesChanged);
            return created;
          },
        );
        if (controller.text != entry.value) {
          controller.text = entry.value;
        }
      }
    });
  }
}
