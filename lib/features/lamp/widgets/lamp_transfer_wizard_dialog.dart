import 'package:flutter/material.dart';

import '../services/lamp_migration_service.dart';

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
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDraft() async {
    try {
      final draft = await widget.service.buildDraft(
        target: widget.target,
        sourceRow: widget.sourceRow,
      );
      for (final entry in draft.formValues.entries) {
        _controllers[entry.key] = TextEditingController(text: entry.value);
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
      }
      final result = await widget.service.save(
        target: draft.target,
        formValues: formValues,
        selectedCandidateId: _selectedCandidateId,
        ownerConflictDecisions: ownerConflictDecisions,
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Οδηγός Μεταφοράς'),
      content: SizedBox(
        width: 1120,
        height: 620,
        child: _buildContent(context),
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
        Expanded(flex: 4, child: _editPane(draft)),
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
              _editPane(draft, fixedHeight: 360),
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

  Widget _editPane(LampMigrationDraft draft, {double? fixedHeight}) {
    return _paneCard(
      title: 'Πεδία επεξεργασίας',
      fixedHeight: fixedHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(child: _formForTarget(draft.target)),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Άκυρο'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _loading || _error != null || _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _selectedCandidateId == null ? 'Δημιουργία' : 'Ενημέρωση',
                ),
              ),
            ],
          ),
        ],
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

  Widget _formForTarget(LampTransferTarget target) {
    return switch (target) {
      LampTransferTarget.department => Column(
        children: [
          _field('name', 'Τμήμα', required: true),
          const SizedBox(height: 8),
          _field('building', 'Κτίριο'),
          const SizedBox(height: 8),
          _field('level', 'Όροφος', keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          _field('notes', 'Σημειώσεις', maxLines: 3),
        ],
      ),
      LampTransferTarget.owner => Column(
        children: [
          _field('last_name', 'Επώνυμο'),
          const SizedBox(height: 8),
          _field('first_name', 'Όνομα'),
          const SizedBox(height: 8),
          _field('phones', 'Τηλέφωνα'),
          const SizedBox(height: 8),
          _field('equipment_codes', 'Εξοπλισμός'),
          const SizedBox(height: 8),
          _field('department_name', 'Τμήμα'),
          const SizedBox(height: 8),
          _field('location', 'Τοποθεσία'),
          const SizedBox(height: 8),
          _field('notes', 'Σημειώσεις', maxLines: 3),
        ],
      ),
      LampTransferTarget.equipment => Column(
        children: [
          _field('code_equipment', 'Κωδικός', required: true),
          const SizedBox(height: 8),
          _field('type', 'Τύπος/Περιγραφή'),
          const SizedBox(height: 8),
          _field('department_name', 'Τμήμα'),
          const SizedBox(height: 8),
          _field('owner_name', 'Κάτοχος'),
          const SizedBox(height: 8),
          _field('location', 'Τοποθεσία'),
          const SizedBox(height: 8),
          _field('notes', 'Σημειώσεις', maxLines: 3),
        ],
      ),
    };
  }

  Widget _field(
    String key,
    String label, {
    bool required = false,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final controller = _controllers.putIfAbsent(
      key,
      () => TextEditingController(),
    );
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        border: const OutlineInputBorder(),
      ),
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
          () => TextEditingController(),
        );
        if (controller.text != entry.value) {
          controller.text = entry.value;
        }
      }
    });
  }
}
