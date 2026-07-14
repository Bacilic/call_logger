import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/old_database/lamp_data_issue_type_labels.dart';
import '../../../core/database/old_database/lamp_issue_resolution_models.dart';
import '../../../core/database/old_database/lamp_network_issue_resolution_service.dart';
import '../../../core/database/old_database/lamp_network_sheet_importer.dart';
import 'lamp_entity_code_autocomplete.dart';

const _scanBasedNetworkIssueTypes = <String>{
  'network_duplicate_ip',
  'network_duplicate_name',
  'network_invalid_ip',
  'network_name_code_mismatch',
};

/// Αποτέλεσμα του διαλόγου επίλυσης δικτύου.
enum LampNetworkIssueDialogOutcome {
  completed,
  cancelled,
  nothingChanged,
}

Future<LampNetworkIssueDialogOutcome?> showLampNetworkIssueResolutionDialog({
  required BuildContext context,
  required String issueType,
  required List<Map<String, Object?>> issues,
  required LampNetworkIssueResolutionService service,
  required String databasePath,
  Future<List<LampEntityCodeSuggestion>> Function(String query)?
      searchEquipmentSuggestions,
  Future<String?> Function(int code)? equipmentPreview,
}) {
  return showDialog<LampNetworkIssueDialogOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (context) => LampNetworkIssueResolutionDialog(
      issueType: issueType,
      issues: issues,
      service: service,
      databasePath: databasePath,
      searchEquipmentSuggestions: searchEquipmentSuggestions,
      equipmentPreview: equipmentPreview,
    ),
  );
}

class LampNetworkIssueResolutionDialog extends StatefulWidget {
  const LampNetworkIssueResolutionDialog({
    super.key,
    required this.issueType,
    required this.issues,
    required this.service,
    required this.databasePath,
    this.searchEquipmentSuggestions,
    this.equipmentPreview,
  });

  final String issueType;
  final List<Map<String, Object?>> issues;
  final LampNetworkIssueResolutionService service;
  final String databasePath;
  final Future<List<LampEntityCodeSuggestion>> Function(String query)?
      searchEquipmentSuggestions;
  final Future<String?> Function(int code)? equipmentPreview;

  @override
  State<LampNetworkIssueResolutionDialog> createState() =>
      _LampNetworkIssueResolutionDialogState();
}

class _LampNetworkIssueResolutionDialogState
    extends State<LampNetworkIssueResolutionDialog> {
  late List<Map<String, Object?>> _remaining;
  final TextEditingController _equipmentCodeController =
      TextEditingController();
  final TextEditingController _fixValueController = TextEditingController();
  String? _statusMessage;
  bool _busy = false;
  bool _anyChange = false;
  Timer? _previewDebounce;
  String? _previewLabel;
  late final Future<List<LampEntityCodeSuggestion>> Function(String query)
      _searchEquipmentSuggestions;
  late final Future<String?> Function(int code) _equipmentPreview;

  @override
  void initState() {
    super.initState();
    _remaining = List<Map<String, Object?>>.from(widget.issues);
    _searchEquipmentSuggestions = widget.searchEquipmentSuggestions ??
        (query) => widget.service.searchEquipmentSuggestions(
              databasePath: widget.databasePath,
              query: query,
            );
    _equipmentPreview = widget.equipmentPreview ??
        (code) => widget.service.equipmentPreview(
              databasePath: widget.databasePath,
              code: code,
            );
    _equipmentCodeController.addListener(_onEquipmentCodeChanged);
    _syncFixValueController();
  }

  void _syncFixValueController() {
    if (_isScanBasedIssue) {
      _fixValueController.text = _currentRawValue;
    } else {
      _fixValueController.clear();
    }
  }

  bool get _isScanBasedIssue =>
      _scanBasedNetworkIssueTypes.contains(widget.issueType);

  int? get _scanEquipmentCode {
    final raw = _currentIssue['row_number'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  String? get _scanColumn => _currentIssue['column_name']?.toString();

  String? get _scanMessage => _currentIssue['message']?.toString();

  String get _scanFixFieldLabel {
    switch (_scanColumn) {
      case 'ip_address':
        return 'Διόρθωση IP';
      case 'network_name':
        return 'Διόρθωση ονόματος δικτύου';
      default:
        return 'Διόρθωση τιμής';
    }
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _equipmentCodeController
      ..removeListener(_onEquipmentCodeChanged)
      ..dispose();
    _fixValueController.dispose();
    super.dispose();
  }

  Map<String, Object?> get _currentIssue => _remaining.first;

  int? get _currentIssueId {
    final raw = _currentIssue['id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  String get _currentRawValue =>
      _currentIssue['raw_value']?.toString() ?? '';

  ParsedNetworkIssueRow? get _parsed =>
      widget.service.parseNetworkIssueRawValue(_currentRawValue);

  List<int> get _candidateEquipmentCodes {
    final parsed = _parsed;
    if (parsed == null) return const [];

    final codes = <int>[];
    final fromExcel = int.tryParse(parsed.equipmentCode?.trim() ?? '');
    if (fromExcel != null) {
      codes.add(fromExcel);
    }

    final fromHostname = lampNetworkHostnameCode(parsed.hostname);
    if (fromHostname != null && !codes.contains(fromHostname)) {
      codes.add(fromHostname);
    }

    return codes;
  }

  int get _currentIndex => widget.issues.length - _remaining.length + 1;

  void _advanceOrClose() {
    if (_remaining.length <= 1) {
      Navigator.of(context).pop(
        _anyChange
            ? LampNetworkIssueDialogOutcome.completed
            : LampNetworkIssueDialogOutcome.nothingChanged,
      );
      return;
    }
    setState(() {
      _remaining = _remaining.sublist(1);
      _equipmentCodeController.clear();
      _statusMessage = null;
      _previewLabel = null;
    });
    _syncFixValueController();
  }

  void _onEquipmentCodeChanged() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 300), _runPreview);
    if (_previewLabel != null) {
      setState(() => _previewLabel = null);
    }
  }

  Future<void> _runPreview() async {
    final raw = _equipmentCodeController.text.trim();
    final code = int.tryParse(raw);
    if (raw.isEmpty || code == null) {
      if (!mounted) return;
      setState(() => _previewLabel = null);
      return;
    }

    final label = await _equipmentPreview(code);
    if (!mounted) return;
    setState(() => _previewLabel = label);
  }

  void _applyCandidate(int code) {
    final text = code.toString();
    _equipmentCodeController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _runPreview();
  }

  Future<void> _match({required bool overwrite}) async {
    final issueId = _currentIssueId;
    if (issueId == null) {
      setState(() => _statusMessage = 'Μη έγκυρο αναγνωριστικό εγγραφής.');
      return;
    }
    final code = int.tryParse(_equipmentCodeController.text.trim());
    if (code == null) {
      setState(() => _statusMessage = 'Εισάγετε έγκυρο κωδικό εξοπλισμού.');
      return;
    }

    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    final result = await widget.service.matchIssueToEquipment(
      databasePath: widget.databasePath,
      issueId: issueId,
      equipmentCode: code,
      overwrite: overwrite,
    );
    if (!mounted) return;

    if (result.conflict) {
      setState(() => _busy = false);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Σύγκρουση στοιχείων δικτύου'),
          content: SelectableText(
            'Ο εξοπλισμός $code έχει ήδη:\n'
            '• IP: ${result.existingIp ?? '—'}\n'
            '• Όνομα δικτύου: ${result.existingNetworkName ?? '—'}\n\n'
            'Η εγγραφή ουράς προτείνει:\n'
            '• IP: ${result.proposedIp ?? '—'}\n'
            '• Όνομα δικτύου: ${result.proposedNetworkName ?? '—'}\n\n'
            'Θέλετε αντικατάσταση;',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Όχι'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Αντικατάσταση'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await _match(overwrite: true);
      }
      return;
    }

    setState(() => _busy = false);
    if (result.success) {
      _anyChange = true;
      _advanceOrClose();
      return;
    }
    setState(() => _statusMessage = result.message);
  }

  Future<void> _saveScanFix() async {
    final issueId = _currentIssueId;
    if (issueId == null) {
      setState(() => _statusMessage = 'Μη έγκυρο αναγνωριστικό εγγραφής.');
      return;
    }

    final equipmentCode = _scanEquipmentCode;
    if (equipmentCode == null) {
      setState(
        () => _statusMessage = 'Μη έγκυρος κωδικός εξοπλισμού στην εγγραφή.',
      );
      return;
    }

    final column = _scanColumn?.trim();
    if (column == null || column.isEmpty) {
      setState(
        () => _statusMessage = 'Λείπει η στήλη προς διόρθωση στην εγγραφή.',
      );
      return;
    }

    final newValue = _fixValueController.text;

    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    final result = await widget.service.fixEquipmentNetworkField(
      databasePath: widget.databasePath,
      issueId: issueId,
      equipmentCode: equipmentCode,
      column: column,
      newValue: newValue,
    );
    if (!mounted) return;

    setState(() => _busy = false);
    if (result.success) {
      _anyChange = true;
      _advanceOrClose();
      return;
    }
    setState(() => _statusMessage = result.message);
  }

  Future<void> _acceptAsIs() async {
    final issueId = _currentIssueId;
    if (issueId == null) {
      setState(() => _statusMessage = 'Μη έγκυρο αναγνωριστικό εγγραφής.');
      return;
    }

    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => const _AcceptReasonDialog(),
    );

    if (!mounted) return;
    if (reason == null || reason.trim().isEmpty) return;

    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    final accepted = await widget.service.acceptIssue(
      databasePath: widget.databasePath,
      issueId: issueId,
      reason: reason,
    );
    if (!mounted) return;

    setState(() => _busy = false);
    if (accepted) {
      _anyChange = true;
      _advanceOrClose();
      return;
    }
    setState(
      () => _statusMessage =
          'Δεν ενημερώθηκε η εγγραφή στην ουρά προβλημάτων.',
    );
  }

  Future<void> _deleteCurrent() async {
    final issueId = _currentIssueId;
    if (issueId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Οριστική διαγραφή;'),
        content: const SelectableText(
          'Η εγγραφή θα διαγραφεί μόνιμα από την ουρά προβλημάτων '
          'χωρίς δυνατότητα αναίρεσης.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) return;

    setState(() => _busy = true);
    await widget.service.deleteIssue(
      databasePath: widget.databasePath,
      issueId: issueId,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _anyChange = true;
    _advanceOrClose();
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    final categoryLabel = lampDataIssueTypeDisplayLabel(widget.issueType);
    return AlertDialog(
      title: Text('Επίλυση · $categoryLabel'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Text(
              'Εγγραφή $_currentIndex από ${widget.issues.length}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            if (_isScanBasedIssue) ...[
              SelectableText(
                'Κωδικός εξοπλισμού: ${_scanEquipmentCode ?? '—'}',
              ),
              if (_scanMessage != null && _scanMessage!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                SelectableText(_scanMessage!),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _fixValueController,
                autofocus: true,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: _scanFixFieldLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Η «Αποδοχή ως έχει» κλείνει το πρόβλημα μόνιμα με αιτιολογία, '
                'χωρίς αλλαγή δεδομένων· δεν θα ξαναεμφανιστεί στον επόμενο '
                'έλεγχο (σε αντίθεση με τη διαγραφή από την ουρά).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else ...[
              if (parsed != null) ...[
                _infoRow('Κόμβος', parsed.node),
                if (parsed.equipmentCode != null &&
                    parsed.equipmentCode!.trim().isNotEmpty)
                  _infoRow(
                    'Κωδικός εξοπλισμού (Excel)',
                    parsed.equipmentCode!,
                  ),
                _infoRow('IP', parsed.ip),
                _infoRow('Hostname', parsed.hostname),
                _infoRow('MAC', parsed.mac),
                _infoRow('VLAN', parsed.vlan),
                _infoRow('Περιγραφή', parsed.description),
                if (parsed.comments.trim().isNotEmpty)
                  _infoRow('Σχόλια', parsed.comments),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _copyValue(_composeAllCopyText(parsed)),
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Αντιγραφή όλων'),
                  ),
                ),
                if (_candidateEquipmentCodes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Προτεινόμενοι κωδικοί:',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final code in _candidateEquipmentCodes)
                        ActionChip(
                          label: Text('Πρόταση: $code'),
                          onPressed:
                              _busy ? null : () => _applyCandidate(code),
                        ),
                    ],
                  ),
                ],
              ] else
                SelectableText(
                  'raw_value: $_currentRawValue',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 16),
              IgnorePointer(
                ignoring: _busy,
                child: LampEntityCodeAutocomplete(
                  controller: _equipmentCodeController,
                  searchSuggestions: _searchEquipmentSuggestions,
                  onCodeSelected: (_) => _runPreview(),
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Κωδικός ή όνομα εξοπλισμού',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (_previewLabel != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Θα συνδεθεί με: $_previewLabel',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ],
            if (_statusMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _statusMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).pop(
                    LampNetworkIssueDialogOutcome.cancelled,
                  ),
          child: const Text('Ακύρωση όλων'),
        ),
        TextButton.icon(
          onPressed: _busy ? null : _deleteCurrent,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Διαγραφή από την ουρά'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
        ),
        TextButton(
          onPressed: _busy ? null : _advanceOrClose,
          child: const Text('Παράλειψη'),
        ),
        if (_isScanBasedIssue)
          OutlinedButton(
            onPressed: _busy ? null : _acceptAsIs,
            child: const Text('Αποδοχή ως έχει'),
          ),
        FilledButton(
          onPressed: _busy
              ? null
              : (_isScanBasedIssue
                  ? _saveScanFix
                  : () => _match(overwrite: false)),
          child: Text(
            _isScanBasedIssue ? 'Αποθήκευση διόρθωσης' : 'Αντιστοίχιση',
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText('$label: $value'),
          ),
          IconButton(
            tooltip: 'Αντιγραφή',
            icon: const Icon(Icons.copy_outlined, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () => _copyValue(value),
          ),
        ],
      ),
    );
  }

  String _composeAllCopyText(ParsedNetworkIssueRow parsed) {
    final lines = <String>[];
    void add(String label, String value) {
      if (value.trim().isNotEmpty) {
        lines.add('$label: $value');
      }
    }

    add('Κόμβος', parsed.node);
    final equipmentCode = parsed.equipmentCode?.trim() ?? '';
    if (equipmentCode.isNotEmpty) {
      add('Κωδικός εξοπλισμού (Excel)', equipmentCode);
    }
    add('IP', parsed.ip);
    add('Hostname', parsed.hostname);
    add('MAC', parsed.mac);
    add('VLAN', parsed.vlan);
    add('Περιγραφή', parsed.description);
    add('Σχόλια', parsed.comments);
    return lines.join('\n');
  }

  Future<void> _copyValue(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Αντιγράφηκε: $value'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _AcceptReasonDialog extends StatefulWidget {
  const _AcceptReasonDialog();

  @override
  State<_AcceptReasonDialog> createState() => _AcceptReasonDialogState();
}

class _AcceptReasonDialogState extends State<_AcceptReasonDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = _controller.text.trim();
    return AlertDialog(
      title: const Text('Αποδοχή ως έχει'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Αιτιολογία',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: trimmed.isEmpty ? null : () => Navigator.of(context).pop(trimmed),
          child: const Text('Αποδοχή'),
        ),
      ],
    );
  }
}
