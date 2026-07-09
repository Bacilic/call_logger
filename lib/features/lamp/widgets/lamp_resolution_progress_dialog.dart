import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/database/old_database/lamp_issue_resolution_service.dart';
import '../../../core/database/old_database/resolution_log_entry.dart';

/// Μορφή εκτιμώμενου χρόνου ολοκλήρωσης ως λεπτά:δευτερόλεπτα.
String lampResolutionEtaText(Duration remaining) {
  final totalSeconds = remaining.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Κείμενο κατάστασης κατά την εκτέλεση της επίλυσης ETL.
String lampResolutionRunningStatusText({
  required int processed,
  required int totalSteps,
  required Duration? estimatedRemaining,
}) {
  final remaining = totalSteps - processed;
  final eta = processed == 0
      ? 'υπολογίζεται…'
      : lampResolutionEtaText(estimatedRemaining!);
  return 'Η επίλυση εκτελείται. Επιλύθηκαν $processed από $totalSteps · '
      'Απομένουν $remaining — Ολοκλήρωση σε $eta';
}

class LampResolutionProgressDialog extends StatefulWidget {
  const LampResolutionProgressDialog({
    super.key,
    required this.title,
    required this.logController,
    required this.cancelToken,
    required this.apply,
    required this.totalSteps,
    required this.progress,
    required this.paused,
  });

  final String title;
  final ResolutionLogController logController;
  final ResolutionCancelToken cancelToken;
  final Future<LampIssueResolutionApplyResult> Function() apply;
  final int totalSteps;
  final ValueNotifier<int> progress;
  final ValueNotifier<bool> paused;

  @override
  State<LampResolutionProgressDialog> createState() =>
      _LampResolutionProgressDialogState();
}

class _LampResolutionProgressDialogState
    extends State<LampResolutionProgressDialog> {
  final _scrollController = ScrollController();
  final _stopwatch = Stopwatch();

  bool _isRunning = true;
  bool _hasCompleted = false;
  bool _cancelRequested = false;
  bool _exporting = false;
  LampIssueResolutionApplyResult? _applyResult;
  Object? _fatalError;

  Timer? _etaTimer;
  Duration _accumulatedPause = Duration.zero;
  DateTime? _pauseStartedAt;

  @override
  void initState() {
    super.initState();
    widget.logController.addListener(_handleLogChanged);
    widget.progress.addListener(_handleProgressChanged);
    widget.paused.addListener(_handlePausedChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startApply();
    });
  }

  @override
  void dispose() {
    _etaTimer?.cancel();
    widget.logController.removeListener(_handleLogChanged);
    widget.progress.removeListener(_handleProgressChanged);
    widget.paused.removeListener(_handlePausedChanged);
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
    final processed = widget.progress.value;
    final progressValue = widget.totalSteps > 0
        ? processed / widget.totalSteps
        : null;

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
                LinearProgressIndicator(value: progressValue),
                const SizedBox(height: 12),
              ],
              Text(
                _statusText(),
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
    _stopwatch.start();
    _startEtaTimer();
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
            _stopEtaTimer();
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
            _stopEtaTimer();
          }),
    );
  }

  void _startEtaTimer() {
    _etaTimer?.cancel();
    _etaTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isRunning || _hasCompleted) {
        _stopEtaTimer();
        return;
      }
      setState(() {});
    });
  }

  void _stopEtaTimer() {
    _etaTimer?.cancel();
    _etaTimer = null;
  }

  void _handleProgressChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handlePausedChanged() {
    if (!mounted) return;
    if (widget.paused.value) {
      _pauseStartedAt = DateTime.now();
    } else if (_pauseStartedAt != null) {
      _accumulatedPause += DateTime.now().difference(_pauseStartedAt!);
      _pauseStartedAt = null;
    }
    setState(() {});
  }

  Duration _effectiveElapsed() {
    var elapsed = _stopwatch.elapsed;
    elapsed -= _accumulatedPause;
    if (_pauseStartedAt != null) {
      elapsed -= DateTime.now().difference(_pauseStartedAt!);
    }
    if (elapsed.isNegative) {
      return Duration.zero;
    }
    return elapsed;
  }

  Duration? _estimatedRemaining() {
    final processed = widget.progress.value;
    if (processed <= 0) return null;
    final remaining = widget.totalSteps - processed;
    if (remaining <= 0) return Duration.zero;
    final elapsed = _effectiveElapsed();
    final perItem = elapsed ~/ processed;
    return perItem * remaining;
  }

  void _handleLogChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      _scheduleScrollToBottom();
    });
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.pixels >= position.maxScrollExtent - 48;
  }

  void _scheduleScrollToBottom() {
    if (!_isNearBottom()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (!_isNearBottom()) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(maxExtent);
    });
  }

  String _statusText() {
    if (_isRunning) {
      return lampResolutionRunningStatusText(
        processed: widget.progress.value,
        totalSteps: widget.totalSteps,
        estimatedRemaining: _estimatedRemaining(),
      );
    }
    final entryCount = widget.logController.entries.length;
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
        bytes: Uint8List(0),
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
