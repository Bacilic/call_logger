import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/widgets/compact_tooltip.dart';
import 'package:flutter/services.dart';

import '../../../core/database/old_database/lamp_data_issue_type_labels.dart';
import '../../../core/database/old_database/lamp_issue_resolution_service.dart';
import '../../../core/database/old_database/lamp_scientific_serial.dart';
import '../controllers/lamp_manual_review_progress.dart';
import 'lamp_contract_fields.dart';
import 'lamp_issue_row_context.dart';
import 'lamp_placement_fields.dart';
import 'lamp_serial_series_fields.dart';

/// Ρητή παράλειψη στον χειροκίνητο έλεγχο (διακριτή από «καμία επιλογή»).
final LampIssueResolutionOption kLampManualSkipOption =
    const LampIssueResolutionOption(
      id: '__skip_open__',
      label: 'Παράλειψη / παραμένει ανοικτό',
      action: LampIssueResolutionAction.unresolved,
    );

/// Έλεγχος ύπαρξης σειριακού σε άλλον εξοπλισμό (πιθανό barcode).
typedef LampSerialExistsChecker =
    Future<bool> Function(String serial, int? exceptCode);

Future<List<LampIssueResolutionDecision>?> showLampIssueManualReviewDialog({
  required BuildContext context,
  required LampIssueType issueType,
  required List<LampIssueResolutionProposal> proposals,
  bool groupedIdenticalValues = false,
  LampSerialExistsChecker? serialExistsChecker,
  LampManualReviewProgress? progress,
  LampPlacementCatalog placementCatalog = LampPlacementCatalog.empty,
}) {
  return showDialog<List<LampIssueResolutionDecision>>(
    context: context,
    barrierDismissible: false,
    builder: (context) => LampIssueManualReviewDialog(
      issueType: issueType,
      proposals: proposals,
      groupedIdenticalValues: groupedIdenticalValues,
      serialExistsChecker: serialExistsChecker,
      progress: progress,
      placementCatalog: placementCatalog,
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
    this.progress,
    this.placementCatalog = LampPlacementCatalog.empty,
  });

  final LampIssueType issueType;
  final List<LampIssueResolutionProposal> proposals;
  final bool groupedIdenticalValues;
  final LampSerialExistsChecker? serialExistsChecker;

  /// Γραφεία και υπάλληλοι για τα πεδία τοποθέτησης — φορτώνονται μία φορά
  /// από τον ενορχηστρωτή και μοιράζονται σε όλα τα βήματα.
  final LampPlacementCatalog placementCatalog;

  /// Θέση στη σειρά χειροκίνητων βημάτων· `null` όταν ο διάλογος ανοίγει
  /// μεμονωμένα (π.χ. σε τεστ ή από μελλοντικό σημείο χωρίς ορχήστρωση).
  final LampManualReviewProgress? progress;

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

  /// Τι διάλεξε ο χρήστης στα δύο πεδία τοποθέτησης, ανά πρόταση.
  final Map<int, ({int? officeId, int? ownerId})> _placements =
      <int, ({int? officeId, int? ownerId})>{};

  /// Προμηθευτής και κατηγορία για τη δημιουργία σύμβασης, ανά πρόταση.
  final Map<int, ({int? supplierId, int? categoryId})> _contracts =
      <int, ({int? supplierId, int? categoryId})>{};

  /// Προσαρμοσμένο πρότυπο αρίθμησης ανά πρόταση· κενό σημαίνει «προεπιλογή».
  ///
  /// Ανά πρόταση και όχι ανά διάλογο: το πρότυπο περιέχει τον σειριακό ή το
  /// μοντέλο της συγκεκριμένης ομάδας, οπότε δεν μεταφέρεται στην επόμενη.
  final Map<int, TextEditingController> _seriesTemplates =
      <int, TextEditingController>{};

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    for (final controller in _seriesTemplates.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grouped =
        widget.groupedIdenticalValues && widget.proposals.length > 1;
    final selectedCount = grouped
        ? (_isReadyDecision(0) ? 1 : 0)
        : _selectedOptions.keys.where(_isReadyDecision).length;
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
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
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
                    placementCatalog: widget.placementCatalog,
                    placement: _placements[sourceIndex],
                    onPlacementChanged: ({officeId, ownerId}) {
                      setState(
                        () => _placements[sourceIndex] = (
                          officeId: officeId,
                          ownerId: ownerId,
                        ),
                      );
                    },
                    contractSelection: _contracts[sourceIndex],
                    onContractChanged: ({supplierId, categoryId}) {
                      setState(
                        () => _contracts[sourceIndex] = (
                          supplierId: supplierId,
                          categoryId: categoryId,
                        ),
                      );
                    },
                    seriesTemplateController: _seriesTemplateFor(sourceIndex),
                    onSeriesTemplateChanged: () => setState(() {}),
                    onChanged: (option) {
                      setState(() {
                        _selectedOptions[sourceIndex] = option;
                        _prefillContractName(sourceIndex, option);
                      });
                    },
                  );
                },
              ),
            ),
            // Ο μετρητής έχει νόημα μόνο ως πρόοδος σε πολλαπλές αποφάσεις·
            // με μία μοναδική πρόταση το «1/1» δεν λέει τίποτα.
            if (!grouped && widget.proposals.length > 1) ...[
              const SizedBox(height: 12),
              Text(
                'Αποφασισμένες: $selectedCount/${widget.proposals.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (widget.progress case final progress?) ...[
              const SizedBox(height: 12),
              _ManualReviewProgressBar(progress: progress),
            ],
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
          // Παραλείπει **το τρέχον βήμα** και προχωρά στο επόμενο — δεν
          // ακυρώνει τη σειρά. Το «όλων» έχει νόημα μόνο όταν το βήμα καλύπτει
          // πολλές εγγραφές· με μία, ήταν απλώς λάθος.
          child: Text(
            widget.proposals.length > 1
                ? 'Παράλειψη και των ${widget.proposals.length}'
                : 'Παράλειψη',
          ),
        ),
        FilledButton(
          onPressed: selectedCount == 0
              ? null
              : () => Navigator.of(context).pop(_buildDecisions()),
          // Το κουμπί μετρά **επιλογές**, όχι εγγραφές: στην ομαδοποιημένη
          // μορφή μία επιλογή εφαρμόζεται σε πολλές εγγραφές, και ο
          // πληθυντικός θα υπονοούσε ότι έχεις πάρει πολλές αποφάσεις.
          child: Text(
            displayProposals.length > 1
                ? 'Εφαρμογή επιλεγμένων'
                : 'Εφαρμογή επιλογής',
          ),
        ),
      ],
    );
  }

  TextEditingController _controllerFor(int index) {
    return _textControllers.putIfAbsent(index, TextEditingController.new);
  }

  TextEditingController _seriesTemplateFor(int index) {
    return _seriesTemplates.putIfAbsent(index, TextEditingController.new);
  }

  /// Το πρότυπο που ισχύει: το προσαρμοσμένο αν γράφτηκε, αλλιώς η πρόταση
  /// του αναλυτή.
  String _seriesTemplateValue(int index, LampIssueResolutionOption option) {
    final custom = _seriesTemplateFor(index).text.trim();
    if (custom.isNotEmpty) return custom;
    return option.metadata['suggestedTemplate']?.toString() ?? '';
  }

  /// Το όνομα της νέας σύμβασης ξεκινά από την ωμή τιμή — «30236» είναι το
  /// μόνο που ξέρει η βάση γι' αυτήν. Ό,τι έχει ήδη γράψει ο χρήστης μένει.
  void _prefillContractName(int index, LampIssueResolutionOption? option) {
    if (option == null || !option.requiresContractInput) return;
    final controller = _controllerFor(index);
    if (controller.text.trim().isNotEmpty) return;
    final suggested = option.metadata['createContractName']?.toString().trim();
    if (suggested == null || suggested.isEmpty) return;
    controller.text = suggested;
  }

  /// Αποφασισμένη εγγραφή: πραγματική επιλογή ή ρητή παράλειψη (όχι απουσία).
  bool _isDecidedOption(LampIssueResolutionOption? option) => option != null;

  /// Έτοιμη προς εφαρμογή: αποφασισμένη **και** συμπληρωμένη.
  ///
  /// Ο ορισμός τοποθέτησης χωρίς γραφείο δεν είναι απόφαση — αλλιώς το κουμπί
  /// θα ενεργοποιούνταν σε μια επιλογή που δεν έχει τι να γράψει.
  bool _isReadyDecision(int index) {
    final option = _selectedOptions[index];
    if (!_isDecidedOption(option)) return false;
    if (option!.requiresPlacementInput) {
      return _placements[index]?.officeId != null;
    }
    // Η σύμβαση χρειάζεται τουλάχιστον όνομα· ο προμηθευτής και η κατηγορία
    // μπορούν να συμπληρωθούν αργότερα.
    if (option.requiresContractInput) {
      return _controllerFor(index).text.trim().isNotEmpty;
    }
    // Πρότυπο χωρίς τον τελεστή θα έδινε την ίδια τιμή σε όλες τις εγγραφές:
    // το κουμπί μένει κλειστό αντί να σκάσει η ενέργεια.
    if (option.requiresSerialSeriesInput) {
      return lampSeriesTemplateIsValid(_seriesTemplateValue(index, option));
    }
    return true;
  }

  /// Ρητή παράλειψη — δεν γράφει απόφαση στη βάση.
  bool _isExplicitSkip(LampIssueResolutionOption? option) =>
      identical(option, kLampManualSkipOption);

  List<LampIssueResolutionDecision> _buildDecisions() {
    final grouped =
        widget.groupedIdenticalValues && widget.proposals.length > 1;
    if (grouped) {
      final option = _selectedOptions[0];
      if (option == null || _isExplicitSkip(option)) {
        return const <LampIssueResolutionDecision>[];
      }
      final textInput = option.requiresTextInput
          ? _controllerFor(0).text
          : null;
      final placement = _placementInputFor(0, option);
      final contract = _contractInputFor(0, option);
      return <LampIssueResolutionDecision>[
        for (final proposal in widget.proposals)
          LampIssueResolutionDecision(
            proposal: proposal,
            option: option,
            textInput: textInput,
            placementInput: placement,
            contractInput: contract,
            serialSeriesTemplate: option.requiresSerialSeriesInput
                ? _seriesTemplateValue(0, option)
                : null,
          ),
      ];
    }

    final decisions = <LampIssueResolutionDecision>[];
    for (var i = 0; i < widget.proposals.length; i++) {
      final option = _selectedOptions[i];
      if (option == null || _isExplicitSkip(option)) continue;
      // Ημιτελής τοποθέτηση δεν στέλνεται: θα έσκαγε στον applier αντί να
      // μείνει απλώς ανοιχτή.
      if ((option.requiresPlacementInput || option.requiresContractInput) &&
          !_isReadyDecision(i)) {
        continue;
      }
      decisions.add(
        LampIssueResolutionDecision(
          proposal: widget.proposals[i],
          option: option,
          textInput: option.requiresTextInput ? _controllerFor(i).text : null,
          placementInput: _placementInputFor(i, option),
          contractInput: _contractInputFor(i, option),
          serialSeriesTemplate: option.requiresSerialSeriesInput
              ? _seriesTemplateValue(i, option)
              : null,
        ),
      );
    }
    return decisions;
  }

  LampPlacementInput? _placementInputFor(
    int index,
    LampIssueResolutionOption option,
  ) {
    if (!option.requiresPlacementInput) return null;
    final placement = _placements[index];
    final officeId = placement?.officeId;
    if (officeId == null) return null;
    return LampPlacementInput(
      officeId: officeId,
      ownerId: placement?.ownerId,
    );
  }

  LampContractInput? _contractInputFor(
    int index,
    LampIssueResolutionOption option,
  ) {
    if (!option.requiresContractInput) return null;
    final name = _controllerFor(index).text.trim();
    if (name.isEmpty) return null;
    final selection = _contracts[index];
    return LampContractInput(
      name: name,
      supplierId: selection?.supplierId,
      categoryId: selection?.categoryId,
    );
  }
}

class _ManualReviewCard extends StatefulWidget {
  const _ManualReviewCard({
    required this.index,
    required this.proposal,
    required this.selectedOption,
    required this.textController,
    required this.onChanged,
    required this.onPlacementChanged,
    required this.onContractChanged,
    required this.seriesTemplateController,
    required this.onSeriesTemplateChanged,
    this.serialExistsChecker,
    this.placementCatalog = LampPlacementCatalog.empty,
    this.placement,
    this.contractSelection,
  });

  final int index;
  final LampIssueResolutionProposal proposal;
  final LampIssueResolutionOption? selectedOption;
  final TextEditingController textController;
  final ValueChanged<LampIssueResolutionOption?> onChanged;
  final LampSerialExistsChecker? serialExistsChecker;
  final LampPlacementCatalog placementCatalog;
  final ({int? officeId, int? ownerId})? placement;
  final void Function({int? officeId, int? ownerId}) onPlacementChanged;
  final ({int? supplierId, int? categoryId})? contractSelection;
  final void Function({int? supplierId, int? categoryId}) onContractChanged;
  final TextEditingController seriesTemplateController;
  final VoidCallback onSeriesTemplateChanged;

  @override
  State<_ManualReviewCard> createState() => _ManualReviewCardState();
}

class _ManualReviewCardState extends State<_ManualReviewCard> {
  Timer? _serialCheckDebounce;
  bool? _serialExistsElsewhere;
  bool _serialCheckInFlight = false;
  int? _selectedDuplicateCode;
  String? _selectedDuplicateActionKind;

  /// Η αρίθμηση ξαναϋπολογίζεται σε κάθε build με την τρέχουσα μορφή, ώστε η
  /// προεπισκόπηση να δείχνει **ακριβώς** ό,τι θα γραφτεί. Η ίδια συνάρτηση
  /// τρέχει και στην εφαρμογή — μία πηγή αλήθειας, καμία απόκλιση.
  String _defaultTemplateFor(LampIssueResolutionOption option) =>
      option.metadata['suggestedTemplate']?.toString() ?? '';

  LampSerialSeriesPlan _seriesPlanFor(
    LampIssueResolutionOption option,
    String template,
  ) {
    final metadata = option.metadata;
    return lampBuildSerialSeries(
      template: template,
      equipmentCodes: <int>[
        for (final value in (metadata['codes'] as List<Object?>? ?? const []))
          if (value is int) value,
      ],
      takenSerials: <String>[
        for (final value
            in (metadata['takenSerials'] as List<Object?>? ?? const []))
          if (value != null) value.toString(),
      ],
    );
  }

  Map<int, String> _descriptionByCode(LampIssueResolutionProposal proposal) {
    final rows = proposal.metadata['rows'];
    if (rows is! List) return const <int, String>{};
    return <int, String>{
      for (final row in rows)
        if (row is Map && row['code'] is int)
          row['code'] as int: (row['description']?.toString().trim() ?? ''),
    }..removeWhere((_, value) => value.isEmpty);
  }

  bool get _isDuplicateGroupLayout {
    if (widget.proposal.options.isEmpty) return false;
    final rows = widget.proposal.metadata['rows'];
    if (rows is! List || rows.isEmpty) return false;
    return widget.proposal.options.every(
      (option) => option.metadata['duplicateActionKind'] != null,
    );
  }

  List<Map<String, Object?>> get _duplicateRows {
    final rows = widget.proposal.metadata['rows'];
    if (rows is! List) return const <Map<String, Object?>>[];
    return <Map<String, Object?>>[
      for (final row in rows)
        if (row is Map<String, Object?>)
          row
        else if (row is Map)
          Map<String, Object?>.from(row),
    ];
  }

  int? _codeFromDuplicateRow(Map<String, Object?> row) {
    final code = row['code'];
    if (code is int) return code;
    if (code is num) return code.toInt();
    return int.tryParse(code?.toString() ?? '');
  }

  String _duplicateRowDropdownLabel(Map<String, Object?> row) {
    final code = _codeFromDuplicateRow(row);
    final description = row['description']?.toString().trim();
    if (description != null && description.isNotEmpty) {
      return '$code ($description)';
    }
    return '$code';
  }

  LampIssueResolutionOption? _duplicateOptionFor(
    String? actionKind,
    int? code,
  ) {
    if (actionKind == null || code == null) return null;
    for (final option in widget.proposal.options) {
      if (option.metadata['duplicateActionKind']?.toString() != actionKind) {
        continue;
      }
      final keepCode = option.metadata['keepCode'];
      final targetCode = option.metadata['targetCode'];
      final keep = keepCode is int
          ? keepCode
          : int.tryParse(keepCode?.toString() ?? '');
      final target = targetCode is int
          ? targetCode
          : int.tryParse(targetCode?.toString() ?? '');
      if (keep == code || target == code) return option;
    }
    return null;
  }

  void _syncDuplicateSelection() {
    widget.onChanged(
      _duplicateOptionFor(_selectedDuplicateActionKind, _selectedDuplicateCode),
    );
  }

  void _onDuplicateCodeChanged(int? code) {
    setState(() => _selectedDuplicateCode = code);
    _syncDuplicateSelection();
  }

  void _onDuplicateActionKindChanged(String? actionKind) {
    setState(() => _selectedDuplicateActionKind = actionKind);
    _syncDuplicateSelection();
  }

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
    final fromOption = widget.selectedOption?.metadata['cleanDigits']
        ?.toString()
        .trim();
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
    if (_isDuplicateGroupLayout) {
      final rows = _duplicateRows;
      if (rows.isNotEmpty) {
        _selectedDuplicateCode = _codeFromDuplicateRow(rows.first);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncDuplicateSelection();
      });
    }
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
    final rowContextLines = lampProposalRowContextLines(proposal);
    final confidenceText = lampConfidenceDisplay(proposal);
    final cleanDigits = _cleanDigits;
    final showCleanDigitsLine =
        _isScientificSerialContext &&
        cleanDigits != null &&
        cleanDigits.isNotEmpty;
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
                SelectableText('Κωδικός εξοπλισμού: ${proposal.row ?? '-'}'),
                SelectableText(
                  'Πεδίο: ${lampDataIssueColumnDisplayLabel(proposal.column)}',
                ),
                if (confidenceText != null)
                  Tooltip(
                    message: lampConfidenceTooltip,
                    child: SelectableText(confidenceText),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (proposal.originalValue != null)
              SelectableText(
                'Αρχική τιμή: ${_proposalOriginalDisplay(proposal)}',
              ),
            if (proposal.proposedMatch != null || proposal.proposedId != null)
              SelectableText('Πρόταση: ${_proposalProposedDisplay(proposal)}'),
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
            if (_isDuplicateGroupLayout) ...[
              DropdownButtonFormField<int>(
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Εγγραφή:',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                initialValue: _selectedDuplicateCode,
                items: [
                  for (final row in _duplicateRows)
                    if (_codeFromDuplicateRow(row) != null)
                      DropdownMenuItem<int>(
                        value: _codeFromDuplicateRow(row),
                        child: Text(_duplicateRowDropdownLabel(row)),
                      ),
                ],
                onChanged: _onDuplicateCodeChanged,
              ),
              const SizedBox(height: 8),
              RadioGroup<String?>(
                groupValue: _selectedDuplicateActionKind,
                onChanged: _onDuplicateActionKindChanged,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RadioListTile<String?>(
                      title: const Text('Παράλειψη / παραμένει ανοικτό'),
                      value: null,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    RadioListTile<String?>(
                      title: const Text(
                        'Κράτα την και καθάρισε την τιμή στις άλλες εγγραφές',
                      ),
                      value: 'clear',
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    RadioListTile<String?>(
                      title: const Text(
                        'Κράτα την και διέγραψε τις άλλες εγγραφές',
                      ),
                      value: 'delete',
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    RadioListTile<String?>(
                      title: const Text('Δώσε νέα τιμή σε αυτή την εγγραφή'),
                      value: 'reassign',
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ] else
              RadioGroup<LampIssueResolutionOption?>(
                groupValue: selectedOption,
                onChanged: widget.onChanged,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RadioListTile<LampIssueResolutionOption?>(
                      title: const Text('Παράλειψη / παραμένει ανοικτό'),
                      value: kLampManualSkipOption,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    for (final option in proposal.options) ...[
                      RadioListTile<LampIssueResolutionOption?>(
                        title: _resolutionOptionTitle(theme, option),
                        subtitle: _resolutionOptionSubtitle(theme, option),
                        value: option,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      // Τα πεδία ανοίγουν κάτω από τη δική τους επιλογή, όχι
                      // στο τέλος της κάρτας: αλλιώς δεν φαίνεται σε ποια
                      // ενέργεια ανήκουν.
                      if (option.requiresPlacementInput &&
                          identical(selectedOption, option))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(32, 4, 0, 8),
                          child: LampPlacementFields(
                            key: Key('lamp_placement_${widget.index}'),
                            catalog: widget.placementCatalog,
                            officeId: widget.placement?.officeId,
                            ownerId: widget.placement?.ownerId,
                            onChanged: widget.onPlacementChanged,
                          ),
                        ),
                      if (option.requiresSerialSeriesInput &&
                          identical(selectedOption, option))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(32, 4, 0, 8),
                          child: LampSerialSeriesFields(
                            buildPlan: (template) =>
                                _seriesPlanFor(option, template),
                            defaultTemplate: _defaultTemplateFor(option),
                            controller: widget.seriesTemplateController,
                            descriptionByCode: _descriptionByCode(proposal),
                            onUseDefault: () {
                              widget.seriesTemplateController.clear();
                              widget.onSeriesTemplateChanged();
                            },
                          ),
                        ),
                      if (option.requiresContractInput &&
                          identical(selectedOption, option))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(32, 4, 0, 8),
                          child: LampContractFields(
                            key: Key('lamp_contract_${widget.index}'),
                            catalog: widget.placementCatalog,
                            nameController: widget.textController,
                            supplierId: widget.contractSelection?.supplierId,
                            categoryId: widget.contractSelection?.categoryId,
                            onChanged: widget.onContractChanged,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ListenableBuilder(
              listenable: widget.textController,
              builder: (context, _) {
                final consequence = lampResolutionConsequenceLine(
                  proposal,
                  selectedOption,
                  textInput: selectedRequiresInput
                      ? widget.textController.text
                      : null,
                );
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    consequence,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                );
              },
            ),
            if (selectedRequiresInput) ...[
              const SizedBox(height: 8),
              TextField(
                controller: widget.textController,
                autofocus: true,
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

/// Πρόοδος στη σειρά χειροκίνητων βημάτων: θέση, μπάρα, εναπομείναντα.
///
/// Η μπάρα οδηγείται από τις **προτάσεις**, όχι τα βήματα: ένα βήμα που
/// καλύπτει 30 όμοιες εγγραφές είναι πολύ μεγαλύτερη πρόοδος από ένα που
/// καλύπτει μία, και η μπάρα πρέπει να το δείχνει.
class _ManualReviewProgressBar extends StatelessWidget {
  const _ManualReviewProgressBar({required this.progress});

  final LampManualReviewProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              progress.stepLabel,
              key: const Key('lamp_manual_step_label'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  key: const Key('lamp_manual_progress_bar'),
                  value: progress.fraction,
                  minHeight: 4,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              progress.remainingLabel,
              key: const Key('lamp_manual_remaining_label'),
              style: labelStyle,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          progress.proposalsLabel,
          key: const Key('lamp_manual_proposals_label'),
          style: labelStyle,
        ),
      ],
    );
  }
}

/// Τίτλος επιλογής, με σπασμένο σύνδεσμο όταν ο υποψήφιος δεν έχει κανέναν
/// συνδεδεμένο εξοπλισμό.
///
/// Η ένδειξη ζει **μόνο εδώ**, στον οδηγό επίλυσης: εκεί αλλάζει απόφαση —
/// τέτοιοι υποψήφιοι συνήθως απορρίπτονται. Στην αναζήτηση θα ήταν θόρυβος,
/// αφού η ίδια η ενότητα «Χωρίς συνδεδεμένο εξοπλισμό» το λέει ήδη.
Widget _resolutionOptionTitle(
  ThemeData theme,
  LampIssueResolutionOption option,
) {
  final label = _displayResolutionOptionLabel(option);
  if (option.metadata[kLampOptionUnlinkedFlag] != true) return Text(label);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CompactTooltip(
        message:
            'Καμία εγγραφή εξοπλισμού δεν χρησιμοποιεί αυτή την οντότητα — '
            'πιθανό κατάλοιπο της παλιάς βάσης.',
        child: Icon(
          Icons.link_off,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(width: 6),
      Flexible(child: Text(label)),
    ],
  );
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
  return option.label.trim();
}
