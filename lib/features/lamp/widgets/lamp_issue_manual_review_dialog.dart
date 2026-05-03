import 'package:flutter/material.dart';

import '../../../core/database/old_database/lamp_issue_resolution_service.dart';

String _lampIssueColumnLabelEl(String? column) {
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

Future<List<LampIssueResolutionDecision>?> showLampIssueManualReviewDialog({
  required BuildContext context,
  required LampIssueType issueType,
  required List<LampIssueResolutionProposal> proposals,
}) {
  return showDialog<List<LampIssueResolutionDecision>>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        LampIssueManualReviewDialog(issueType: issueType, proposals: proposals),
  );
}

class LampIssueManualReviewDialog extends StatefulWidget {
  const LampIssueManualReviewDialog({
    super.key,
    required this.issueType,
    required this.proposals,
  });

  final LampIssueType issueType;
  final List<LampIssueResolutionProposal> proposals;

  @override
  State<LampIssueManualReviewDialog> createState() =>
      _LampIssueManualReviewDialogState();
}

class _LampIssueManualReviewDialogState
    extends State<LampIssueManualReviewDialog> {
  final Map<int, LampIssueResolutionOption?> _selectedOptions =
      <int, LampIssueResolutionOption?>{};
  final Map<int, TextEditingController> _textControllers =
      <int, TextEditingController>{};

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedOptions.values
        .whereType<LampIssueResolutionOption>()
        .length;
    return AlertDialog(
      title: Text('${widget.issueType.label} · χειροκίνητος έλεγχος'),
      content: SizedBox(
        width: 860,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Επιλέξτε ενέργεια για όσα θέλετε να εφαρμοστούν τώρα. '
              'Όσα μείνουν χωρίς επιλογή παραμένουν ανοικτά.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: widget.proposals.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final proposal = widget.proposals[index];
                  return _ManualReviewCard(
                    index: index,
                    proposal: proposal,
                    selectedOption: _selectedOptions[index],
                    textController: _controllerFor(index),
                    onChanged: (option) {
                      setState(() => _selectedOptions[index] = option);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Επιλεγμένες ενέργειες: $selectedCount/${widget.proposals.length}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Άκυρο'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const <LampIssueResolutionDecision>[]),
          child: const Text('Παράλειψη όλων'),
        ),
        FilledButton(
          onPressed: selectedCount == 0
              ? null
              : () => Navigator.of(context).pop(_buildDecisions()),
          child: const Text('Εφαρμογή επιλεγμένων'),
        ),
      ],
    );
  }

  TextEditingController _controllerFor(int index) {
    return _textControllers.putIfAbsent(index, TextEditingController.new);
  }

  List<LampIssueResolutionDecision> _buildDecisions() {
    final decisions = <LampIssueResolutionDecision>[];
    for (var i = 0; i < widget.proposals.length; i++) {
      final option = _selectedOptions[i];
      if (option == null) continue;
      decisions.add(
        LampIssueResolutionDecision(
          proposal: widget.proposals[i],
          option: option,
          textInput: option.requiresTextInput ? _controllerFor(i).text : null,
        ),
      );
    }
    return decisions;
  }
}

class _ManualReviewCard extends StatelessWidget {
  const _ManualReviewCard({
    required this.index,
    required this.proposal,
    required this.selectedOption,
    required this.textController,
    required this.onChanged,
  });

  final int index;
  final LampIssueResolutionProposal proposal;
  final LampIssueResolutionOption? selectedOption;
  final TextEditingController textController;
  final ValueChanged<LampIssueResolutionOption?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedRequiresInput = selectedOption?.requiresTextInput ?? false;
    final rowContextLines = _proposalRowContextLines(proposal);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text('#${index + 1}', style: theme.textTheme.labelLarge),
                Text('Γραμμή: ${proposal.row ?? '-'}'),
                Text('Πεδίο: ${_lampIssueColumnLabelEl(proposal.column)}'),
                Text('Βεβαιότητα: ${proposal.confidence}%'),
              ],
            ),
            const SizedBox(height: 8),
            if (proposal.originalValue != null)
              SelectableText('Αρχική τιμή: ${proposal.originalValue}'),
            if (proposal.proposedMatch != null)
              SelectableText('Πρόταση: ${proposal.proposedMatch}'),
            if (rowContextLines.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Στοιχεία εγγραφής', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final line in rowContextLines)
                SelectableText(line, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            SelectableText(proposal.notes, style: theme.textTheme.bodySmall),
            const Divider(height: 20),
            Text('Ενέργεια', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            RadioGroup<LampIssueResolutionOption?>(
              groupValue: selectedOption,
              onChanged: onChanged,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RadioListTile<LampIssueResolutionOption?>(
                    title: const Text('Παράλειψη / παραμένει ανοικτό'),
                    value: null,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  for (final option in proposal.options)
                    RadioListTile<LampIssueResolutionOption?>(
                      title: Text(_displayResolutionOptionLabel(option.label)),
                      subtitle: option.description != null &&
                              option.description!.trim().isNotEmpty
                          ? Text(
                              option.description!,
                              style: theme.textTheme.bodySmall,
                            )
                          : null,
                      value: option,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
            if (selectedRequiresInput) ...[
              const SizedBox(height: 8),
              TextField(
                controller: textController,
                decoration: InputDecoration(
                  labelText: selectedOption?.inputLabel ?? 'Νέα τιμή',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

List<String> _proposalRowContextLines(LampIssueResolutionProposal proposal) {
  final metadata = proposal.metadata;
  String? text(String key) {
    final value = metadata[key]?.toString().trim();
    if (value == null || value.isEmpty || value == 'null') return null;
    return value;
  }

  final lines = <String>[];
  final code = text('rowContextCode');
  final description = text('rowContextDescription');
  if (code != null || description != null) {
    lines.add('Εξοπλισμός: ${code ?? '-'} · ${description ?? '-'}');
  }
  final stateName = text('rowContextStateName');
  if (stateName != null) {
    lines.add('Κατάσταση: $stateName');
  }
  final assetNo = text('rowContextAssetNo');
  final serialNo = text('rowContextSerialNo');
  if (assetNo != null || serialNo != null) {
    lines.add('Asset: ${assetNo ?? '-'} · Serial: ${serialNo ?? '-'}');
  }
  final officeId = text('rowContextOfficeId');
  final officeLabel = text('rowContextOfficeLabel');
  if (officeId != null || officeLabel != null) {
    lines.add('Τμήμα/Γραφείο: ${officeId ?? '-'} · ${officeLabel ?? '-'}');
  }
  final ownerId = text('rowContextOwnerId');
  final ownerLabel = text('rowContextOwnerLabel');
  if (ownerId != null || ownerLabel != null) {
    lines.add('Υπάλληλος: ${ownerId ?? '-'} · ${ownerLabel ?? '-'}');
  }
  final modelId = text('rowContextModelId');
  final modelLabel = text('rowContextModelLabel');
  if (modelId != null || modelLabel != null) {
    lines.add('Μοντέλο: ${modelId ?? '-'} · ${modelLabel ?? '-'}');
  }
  final contractId = text('rowContextContractId');
  final contractLabel = text('rowContextContractLabel');
  if (contractId != null || contractLabel != null) {
    lines.add('Συμβόλαιο: ${contractId ?? '-'} · ${contractLabel ?? '-'}');
  }
  return lines;
}

String _displayResolutionOptionLabel(String rawLabel) {
  var label = rawLabel.trim();
  label = label.replaceAll('owner', 'υπάλληλος');
  label = label.replaceAll('last_name', 'επώνυμο');
  label = label.replaceAll('first_name', 'μικρό όνομα');
  label = label.replaceAll('Νέος υπάλληλος:', 'Νέος υπάλληλος:');
  label = label.replaceAll('Αλλαγή υπάλληλος', 'Αλλαγή υπαλλήλου');
  return label;
}
