import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/database/old_database/lamp_issue_resolution_service.dart';
import '../../../core/database/old_database/resolution_log_entry.dart';

class LampResolutionProgressDialog extends StatefulWidget {
  const LampResolutionProgressDialog({
    super.key,
    required this.title,
    required this.logController,
    required this.cancelToken,
    required this.apply,
  });

  final String title;
  final ResolutionLogController logController;
  final ResolutionCancelToken cancelToken;
  final Future<LampIssueResolutionApplyResult> Function() apply;

  @override
  State<LampResolutionProgressDialog> createState() =>
      _LampResolutionProgressDialogState();
}

class _LampResolutionProgressDialogState
    extends State<LampResolutionProgressDialog> {
  final _scrollController = ScrollController();

  bool _isRunning = true;
  bool _hasCompleted = false;
  bool _cancelRequested = false;
  bool _exporting = false;
  LampIssueResolutionApplyResult? _applyResult;
  Object? _fatalError;

  @override
  void initState() {
    super.initState();
    widget.logController.addListener(_handleLogChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startApply();
    });
  }

  @override
  void dispose() {
    widget.logController.removeListener(_handleLogChanged);
    _scrollController.dispose();
    widget.logController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.logController.entries;
    final reportText = _reportText;
    final canCancel = _isRunning && !_hasCompleted && !_cancelRequested;
    final canExport =
        !_isRunning && _hasCompleted && entries.isNotEmpty && !_exporting;
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text('${widget.title} · αναφορά εκτέλεσης'),
        content: SizedBox(
          width: 860,
          height: 620,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isRunning) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
              ],
              Text(
                _statusText(entries.length),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectionArea(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        reportText.isEmpty
                            ? 'Αναμονή για τις πρώτες εγγραφές log...'
                            : reportText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_fatalError != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Η διαδικασία ολοκληρώθηκε με σφάλμα. '
                  'Η αναφορά παραμένει διαθέσιμη για εξαγωγή.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: canCancel ? _cancel : null,
            child: const Text('Ακύρωση'),
          ),
          TextButton(
            onPressed: canExport ? _exportLog : null,
            child: Text(_exporting ? 'Εξαγωγή...' : 'Εξαγωγή ως .txt'),
          ),
          FilledButton(
            onPressed: _hasCompleted
                ? () => Navigator.of(context).pop(_applyResult)
                : null,
            child: const Text('Κλείσιμο'),
          ),
        ],
      ),
    );
  }

  String get _reportText {
    return widget.logController.entries
        .map((entry) {
          return entry.formatLine();
        })
        .join('\n');
  }

  void _startApply() {
    unawaited(
      widget
          .apply()
          .then<void>((result) {
            if (!mounted) return;
            widget.logController.add(
              ResolutionLogEntry.success(
                'Η διαδικασία ολοκληρώθηκε. Εφαρμόστηκαν ${result.totalChanged} ενέργειες, σφάλματα: ${result.errors.length}.',
              ),
            );
            setState(() {
              _isRunning = false;
              _hasCompleted = true;
              _applyResult = result;
            });
          })
          .catchError((Object error, StackTrace stackTrace) {
            if (!mounted) return;
            widget.logController.add(
              ResolutionLogEntry.error(
                'Η διαδικασία απέτυχε πριν ολοκληρωθεί: $error',
              ),
            );
            setState(() {
              _isRunning = false;
              _hasCompleted = true;
              _fatalError = error;
            });
          }),
    );
  }

  void _handleLogChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      _scheduleScrollToBottom();
    });
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(maxExtent);
    });
  }

  String _statusText(int entryCount) {
    if (_isRunning) {
      return 'Η επίλυση εκτελείται. Γραμμές αναφοράς: $entryCount.';
    }
    if (_fatalError != null) {
      return 'Η επίλυση σταμάτησε λόγω σφάλματος. Γραμμές αναφοράς: $entryCount.';
    }
    final result = _applyResult;
    if (result == null) {
      return 'Η επίλυση ολοκληρώθηκε. Γραμμές αναφοράς: $entryCount.';
    }
    return 'Ολοκληρώθηκε: ${result.totalChanged} ενέργειες, '
        'ανεπίλυτα: ${result.unresolved}, σφάλματα: ${result.errors.length}.';
  }

  void _cancel() {
    widget.cancelToken.cancel();
    _cancelRequested = true;
    widget.logController.add(
      ResolutionLogEntry.warning(
        'Ζητήθηκε ακύρωση. Η τρέχουσα συναλλαγή θα ολοκληρωθεί πριν σταματήσει η διαδικασία.',
      ),
    );
    setState(() {});
  }

  Future<void> _exportLog() async {
    final report = _reportText;
    if (report.isEmpty) return;

    setState(() => _exporting = true);
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Εξαγωγή αναφοράς επίλυσης',
        fileName: 'resolution_log_${_timestampForFileName()}.txt',
        type: FileType.custom,
        allowedExtensions: const <String>['txt'],
      );
      if (!mounted) return;
      if (path == null) {
        setState(() => _exporting = false);
        return;
      }

      await File(path).writeAsString(report, encoding: utf8);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Η αναφορά αποθηκεύτηκε στο $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Αποτυχία εξαγωγής αναφοράς: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  String _timestampForFileName() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
