import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/old_database/lamp_issue_resolution_service.dart';
import '../../../core/database/old_database/lamp_scientific_serial.dart';

/// Έλεγχος ύπαρξης σειριακού σε άλλον εξοπλισμό (πιθανό barcode).
typedef LampSerialExistsChecker = Future<bool> Function(
  String serial,
  int? exceptCode,
);

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
  bool groupedIdenticalValues = false,
  LampSerialExistsChecker? serialExistsChecker,
}) {
  return showDialog<List<LampIssueResolutionDecision>>(
    context: context,
    barrierDismissible: false,
    builder: (context) => LampIssueManualReviewDialog(
      issueType: issueType,
      proposals: proposals,
      groupedIdenticalValues: groupedIdenticalValues,
      serialExistsChecker: serialExistsChecker,
    ),
  );
}

class LampIssueManualReviewDialog extends StatefulWidget {
  const LampIssueManualReviewDialog({
    super.key,
    required this.issueType,
    required this.proposals,
    this.groupedIdenticalValues = false,
    this.serialExistsChecker,
  });

  final LampIssueType issueType;
  final List<LampIssueResolutionProposal> proposals;
  final bool groupedIdenticalValues;
  final LampSerialExistsChecker? serialExistsChecker;

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
    final grouped = widget.groupedIdenticalValues && widget.proposals.length > 1;
    final selectedCount = grouped
        ? (_selectedOptions[0] != null ? 1 : 0)
        : _selectedOptions.values
            .whereType<LampIssueResolutionOption>()
            .length;
    final displayProposals = grouped
        ? <LampIssueResolutionProposal>[widget.proposals.first]
        : widget.proposals;
    return AlertDialog(
      title: Text('${widget.issueType.label} · χειροκίνητος έλεγχος'),
      content: SizedBox(
        width: 860,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (grouped) ...[
              Text(
                'Η απόφαση θα εφαρμοστεί σε ${widget.proposals.length} εγγραφές '
                'με την ίδια τιμή.',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Γραμμές: ${widget.proposals.map((p) => p.row ?? '-').join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            Text(
              grouped
                  ? 'Επιλέξτε ενέργεια που θα εφαρμοστεί σε όλες τις εγγραφές.'
                  : 'Επιλέξτε ενέργεια για όσα θέλετε να εφαρμοστούν τώρα. '
                      'Όσα μείνουν χωρίς επιλογή παραμένουν ανοικτά.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: displayProposals.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final proposal = displayProposals[index];
                  final sourceIndex = grouped ? 0 : index;
                  return _ManualReviewCard(
                    index: index,
                    proposal: proposal,
                    selectedOption: _selectedOptions[sourceIndex],
                    textController: _controllerFor(sourceIndex),
                    serialExistsChecker: widget.serialExistsChecker,
                    onChanged: (option) {
                      setState(() => _selectedOptions[sourceIndex] = option);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              grouped
                  ? 'Επιλεγμένη ενέργεια: $selectedCount/1'
                  : 'Επιλεγμένες ενέργειες: $selectedCount/${widget.proposals.length}',
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
    final grouped = widget.groupedIdenticalValues && widget.proposals.length > 1;
    if (grouped) {
      final option = _selectedOptions[0];
      if (option == null) return const <LampIssueResolutionDecision>[];
      final textInput = option.requiresTextInput ? _controllerFor(0).text : null;
      return <LampIssueResolutionDecision>[
        for (final proposal in widget.proposals)
          LampIssueResolutionDecision(
            proposal: proposal,
            option: option,
            textInput: textInput,
          ),
      ];
    }

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

class _ManualReviewCard extends StatefulWidget {
  const _ManualReviewCard({
    required this.index,
    required this.proposal,
    required this.selectedOption,
    required this.textController,
    required this.onChanged,
    this.serialExistsChecker,
  });

  final int index;
  final LampIssueResolutionProposal proposal;
  final LampIssueResolutionOption? selectedOption;
  final TextEditingController textController;
  final ValueChanged<LampIssueResolutionOption?> onChanged;
  final LampSerialExistsChecker? serialExistsChecker;

  @override
  State<_ManualReviewCard> createState() => _ManualReviewCardState();
}

class _ManualReviewCardState extends State<_ManualReviewCard> {
  Timer? _serialCheckDebounce;
  bool? _serialExistsElsewhere;
  bool _serialCheckInFlight = false;

  bool get _isScientificSerialContext {
    if (widget.proposal.issueType == LampIssueType.scientificSerial) {
      return true;
    }
    final clean = widget.proposal.metadata['cleanDigits']?.toString().trim();
    return clean != null && clean.isNotEmpty;
  }

  String? get _cleanDigits {
    final fromMeta = widget.proposal.metadata['cleanDigits']?.toString().trim();
    if (fromMeta != null && fromMeta.isNotEmpty) return fromMeta;
    final fromOption =
        widget.selectedOption?.metadata['cleanDigits']?.toString().trim();
    if (fromOption != null && fromOption.isNotEmpty) return fromOption;
    return null;
  }

  int? get _expectedLength {
    final fromMeta = widget.proposal.metadata['expectedLength'];
    if (fromMeta is int) return fromMeta;
    if (fromMeta != null) return int.tryParse(fromMeta.toString());
    final fromOption = widget.selectedOption?.metadata['expectedLength'];
    if (fromOption is int) return fromOption;
    if (fromOption != null) return int.tryParse(fromOption.toString());
    return null;
  }

  String? get _rawSerial {
    final fromMeta = widget.proposal.metadata['rawSerial']?.toString();
    if (fromMeta != null && fromMeta.trim().isNotEmpty) return fromMeta.trim();
    return widget.proposal.originalValue?.trim();
  }

  int? get _exceptCode {
    final fromOption = widget.selectedOption?.metadata['targetCode'];
    if (fromOption is int) return fromOption;
    if (fromOption != null) return int.tryParse(fromOption.toString());
    return widget.proposal.row;
  }

  @override
  void initState() {
    super.initState();
    widget.textController.addListener(_onSerialInputChanged);
  }

  @override
  void didUpdateWidget(covariant _ManualReviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textController != widget.textController) {
      oldWidget.textController.removeListener(_onSerialInputChanged);
      widget.textController.addListener(_onSerialInputChanged);
    }
    if (oldWidget.selectedOption != widget.selectedOption) {
      _scheduleSerialExistsCheck(widget.textController.text);
    }
  }

  @override
  void dispose() {
    _serialCheckDebounce?.cancel();
    widget.textController.removeListener(_onSerialInputChanged);
    super.dispose();
  }

  void _onSerialInputChanged() {
    if (!_isScientificSerialContext ||
        !(widget.selectedOption?.requiresTextInput ?? false)) {
      return;
    }
    setState(() {});
    _scheduleSerialExistsCheck(widget.textController.text);
  }

  void _scheduleSerialExistsCheck(String value) {
    _serialCheckDebounce?.cancel();
    final checker = widget.serialExistsChecker;
    if (checker == null) {
      if (_serialExistsElsewhere != null || _serialCheckInFlight) {
        setState(() {
          _serialExistsElsewhere = null;
          _serialCheckInFlight = false;
        });
      }
      return;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _serialExistsElsewhere = null;
        _serialCheckInFlight = false;
      });
      return;
    }
    _serialCheckDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _serialCheckInFlight = true);
      try {
        final exists = await checker(trimmed, _exceptCode);
        if (!mounted) return;
        setState(() {
          _serialExistsElsewhere = exists;
          _serialCheckInFlight = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _serialExistsElsewhere = null;
          _serialCheckInFlight = false;
        });
      }
    });
  }

  List<String> _warningMessages() {
    if (!_isScientificSerialContext ||
        !(widget.selectedOption?.requiresTextInput ?? false)) {
      return const <String>[];
    }
    final cleanDigits = _cleanDigits ?? '';
    final warnings = scientificSerialLocalWarnings(
      newSerial: widget.textController.text,
      cleanDigits: cleanDigits,
      expectedLength: _expectedLength,
      rawSerial: _rawSerial ?? '',
    );
    if (_serialExistsElsewhere == true) {
      warnings.add(scientificSerialDuplicateWarning);
    }
    return warnings;
  }

  Future<void> _copyCleanDigits(String cleanDigits) async {
    await Clipboard.setData(ClipboardData(text: cleanDigits));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Αντιγράφηκαν τα ψηφία: $cleanDigits'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final proposal = widget.proposal;
    final selectedOption = widget.selectedOption;
    final selectedRequiresInput = selectedOption?.requiresTextInput ?? false;
    final rowContextLines = _proposalRowContextLines(proposal);
    final cleanDigits = _cleanDigits;
    final showCleanDigitsLine =
        _isScientificSerialContext && cleanDigits != null && cleanDigits.isNotEmpty;
    final warnings = _warningMessages();
    const warningColor = Color(0xFFE65100);

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
                Text('#${widget.index + 1}', style: theme.textTheme.labelLarge),
                Text('Κωδικός εξοπλισμού: ${proposal.row ?? '-'}'),
                Text('Πεδίο: ${_lampIssueColumnLabelEl(proposal.column)}'),
                Text('Βεβαιότητα: ${proposal.confidence}%'),
              ],
            ),
            const SizedBox(height: 8),
            if (proposal.originalValue != null)
              SelectableText(
                'Αρχική τιμή: ${_proposalOriginalDisplay(proposal)}',
              ),
            if (proposal.proposedMatch != null ||
                proposal.proposedId != null)
              SelectableText(
                'Πρόταση: ${_proposalProposedDisplay(proposal)}',
              ),
            if (rowContextLines.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Στοιχεία εγγραφής', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final line in rowContextLines)
                SelectableText(line, style: theme.textTheme.bodySmall),
            ],
            if (showCleanDigitsLine) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SelectableText(
                      'Ψηφία για αναζήτηση: $cleanDigits',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Αντιγραφή ψηφίων',
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _copyCleanDigits(cleanDigits),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            SelectableText(proposal.notes, style: theme.textTheme.bodySmall),
            const Divider(height: 20),
            Text('Ενέργεια', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            RadioGroup<LampIssueResolutionOption?>(
              groupValue: selectedOption,
              onChanged: widget.onChanged,
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
                      title: Text(_displayResolutionOptionLabel(option)),
                      subtitle: _resolutionOptionSubtitle(theme, option),
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
                controller: widget.textController,
                decoration: InputDecoration(
                  labelText: selectedOption?.inputLabel ?? 'Νέα τιμή',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (warnings.isNotEmpty || _serialCheckInFlight) ...[
                const SizedBox(height: 8),
                for (final warning in warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_outlined,
                          size: 16,
                          color: warningColor,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            warning,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: warningColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_serialCheckInFlight)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Έλεγχος διπλότυπου σειριακού…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
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

Widget? _resolutionOptionSubtitle(
  ThemeData theme,
  LampIssueResolutionOption option,
) {
  final description = option.description?.trim();
  if (description == null || description.isEmpty) return null;
  return Text(
    description,
    style: theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
    ),
  );
}

String? _metadataDisplayLabel(
  LampIssueResolutionProposal proposal,
  String key,
) {
  final value = proposal.metadata[key]?.toString().trim();
  if (value == null || value.isEmpty || value == 'null') return null;
  return value;
}

String _proposalOriginalDisplay(LampIssueResolutionProposal proposal) {
  return _metadataDisplayLabel(proposal, 'originalDisplayLabel') ??
      _formatIdWithName(
        raw: proposal.originalValue ?? '',
        id: int.tryParse((proposal.originalValue ?? '').trim()),
      );
}

String _proposalProposedDisplay(LampIssueResolutionProposal proposal) {
  return _metadataDisplayLabel(proposal, 'proposedDisplayLabel') ??
      _formatIdWithName(
        raw: proposal.proposedMatch ?? '',
        id: proposal.proposedId,
      );
}

String _formatIdWithName({required String raw, int? id}) {
  final trimmed = raw.trim();
  final parsedId = id ?? int.tryParse(trimmed);
  if (parsedId != null &&
      trimmed.isNotEmpty &&
      trimmed != parsedId.toString()) {
    return '$parsedId · $trimmed';
  }
  if (parsedId != null) return parsedId.toString();
  return trimmed.isEmpty ? '-' : trimmed;
}

String _displayResolutionOptionLabel(LampIssueResolutionOption option) {
  if (option.proposedId != null) {
    return option.label.trim();
  }
  var label = option.label.trim();
  label = label.replaceAll('owner', 'υπάλληλος');
  label = label.replaceAll('last_name', 'επώνυμο');
  label = label.replaceAll('first_name', 'μικρό όνομα');
  label = label.replaceAll('Νέος υπάλληλος:', 'Νέος υπάλληλος:');
  label = label.replaceAll('Αλλαγή υπάλληλος', 'Αλλαγή υπαλλήλου');
  return label;
}
