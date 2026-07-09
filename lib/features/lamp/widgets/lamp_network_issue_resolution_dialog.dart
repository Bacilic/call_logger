import 'package:flutter/material.dart';

import '../../../core/database/old_database/lamp_data_issue_type_labels.dart';
import '../../../core/database/old_database/lamp_network_issue_resolution_service.dart';

/// Αποτέλεσμα του διαλόγου επίλυσης δικτύου.
enum LampNetworkIssueDialogOutcome {
  completed,
  cancelled,
}

Future<LampNetworkIssueDialogOutcome?> showLampNetworkIssueResolutionDialog({
  required BuildContext context,
  required String issueType,
  required List<Map<String, Object?>> issues,
  required LampNetworkIssueResolutionService service,
  required String databasePath,
}) {
  return showDialog<LampNetworkIssueDialogOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (context) => LampNetworkIssueResolutionDialog(
      issueType: issueType,
      issues: issues,
      service: service,
      databasePath: databasePath,
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
  });

  final String issueType;
  final List<Map<String, Object?>> issues;
  final LampNetworkIssueResolutionService service;
  final String databasePath;

  @override
  State<LampNetworkIssueResolutionDialog> createState() =>
      _LampNetworkIssueResolutionDialogState();
}

class _LampNetworkIssueResolutionDialogState
    extends State<LampNetworkIssueResolutionDialog> {
  late List<Map<String, Object?>> _remaining;
  final TextEditingController _equipmentCodeController =
      TextEditingController();
  String? _statusMessage;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _remaining = List<Map<String, Object?>>.from(widget.issues);
  }

  @override
  void dispose() {
    _equipmentCodeController.dispose();
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

  int get _currentIndex => widget.issues.length - _remaining.length + 1;

  void _advanceOrClose({required bool changed}) {
    if (_remaining.length <= 1) {
      Navigator.of(context).pop(
        changed
            ? LampNetworkIssueDialogOutcome.completed
            : LampNetworkIssueDialogOutcome.completed,
      );
      return;
    }
    setState(() {
      _remaining = _remaining.sublist(1);
      _equipmentCodeController.clear();
      _statusMessage = null;
    });
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
      _advanceOrClose(changed: true);
      return;
    }
    setState(() => _statusMessage = result.message);
  }

  Future<void> _deleteCurrent() async {
    final issueId = _currentIssueId;
    if (issueId == null) return;
    setState(() => _busy = true);
    await widget.service.deleteIssue(
      databasePath: widget.databasePath,
      issueId: issueId,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _advanceOrClose(changed: true);
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    final categoryLabel = lampDataIssueTypeDisplayLabel(widget.issueType);
    return AlertDialog(
      title: Text('Επίλυση · $categoryLabel'),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Εγγραφή $_currentIndex από ${widget.issues.length}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            if (parsed != null) ...[
              _infoRow('Κόμβος', parsed.node),
              _infoRow('IP', parsed.ip),
              _infoRow('Hostname', parsed.hostname),
              _infoRow('MAC', parsed.mac),
              _infoRow('VLAN', parsed.vlan),
              _infoRow('Περιγραφή', parsed.description),
              if (parsed.comments.trim().isNotEmpty)
                _infoRow('Σχόλια', parsed.comments),
            ] else
              SelectableText(
                'raw_value: $_currentRawValue',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _equipmentCodeController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Κωδικός εξοπλισμού',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
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
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).pop(
                    LampNetworkIssueDialogOutcome.cancelled,
                  ),
          child: const Text('Ακύρωση όλων'),
        ),
        TextButton(
          onPressed: _busy ? null : _deleteCurrent,
          child: const Text('Διαγραφή από την ουρά'),
        ),
        TextButton(
          onPressed: _busy ? null : () => _advanceOrClose(changed: false),
          child: const Text('Παράλειψη'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _match(overwrite: false),
          child: const Text('Αντιστοίχιση'),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('$label: $value'),
    );
  }
}
