import 'package:call_logger/core/database/old_database/old_excel_importer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Τι κάνει ο χρήστης όταν κλείνει την αναφορά επιτυχίας import.
/// Βοηθητική γραμμή στη φόρμα αποτυχίας εισαγωγής (κλείδωμα vs γενικό).
String lampImportFailureHintMessage(String errorMessage) {
  final lower = errorMessage.toLowerCase();
  if (errorMessage.contains('errno = 32') ||
      errorMessage.contains('PathAccessException') ||
      errorMessage.contains('χρησιμοποιείται') ||
      lower.contains('another process')) {
    return 'Το αρχείο της βάσης εξαγωγής πιθανόν χρησιμοποιείται από την εφαρμογή — '
        'άλλαξε τη βάση εξόδου ή τη βάση ανάγνωσης και δοκίμασε ξανά.';
  }
  return 'Το αρχείο βάσης μπορεί να είναι ημιτελές ή να μην έχει δημιουργηθεί.';
}

enum LampImportReportCloseAction {
  dismiss,
  runIntegrityCheck,
}

/// Αποτέλεσμα κλεισίματος αναφοράς εισαγωγής.
class LampImportReportOutcome {
  const LampImportReportOutcome({
    required this.action,
    this.setAsReadDatabase = false,
  });

  final LampImportReportCloseAction action;
  final bool setAsReadDatabase;
}

/// Πλαίσιο ανάγνωσης για την αναφορά επιτυχίας (ορατότητα διακόπτη).
class LampImportReadPathContext {
  const LampImportReadPathContext({
    required this.readPathEmpty,
    required this.readDiffersFromOutput,
    this.currentReadFileName,
  });

  final bool readPathEmpty;
  final bool readDiffersFromOutput;
  final String? currentReadFileName;
}

/// Κατάσταση Φάσης Α — πρόοδος εισαγωγής.
class LampImportProgressUiState {
  const LampImportProgressUiState({
    this.currentMessage = 'Προετοιμασία',
    this.completedSteps = const <String>[],
    this.done = 0,
    this.total = 0,
  });

  final String currentMessage;
  final List<String> completedSteps;
  final int done;
  final int total;

  double? get fraction => total > 0 ? done / total : null;
}

LampImportProgressUiState lampImportProgressUiStateFromProgress(
  LampImportProgressUiState previous,
  LampImportProgress progress,
) {
  final completed = List<String>.from(previous.completedSteps);
  final current = previous.currentMessage.trim();
  final next = progress.message.trim();
  if (current.isNotEmpty && current != next && !completed.contains(current)) {
    completed.add(current);
  }
  return LampImportProgressUiState(
    currentMessage: next,
    completedSteps: completed,
    done: progress.done,
    total: progress.total,
  );
}

/// Φάση Β — αναφορά (επιτυχία ή αποτυχία).
sealed class LampImportReportUiState {
  const LampImportReportUiState();

  factory LampImportReportUiState.success({
    required String databaseFileName,
    required int durationSeconds,
    required Map<String, int> importedRows,
    required int issueCount,
    required LampImportReadPathContext readPathContext,
  }) = LampImportReportSuccessUiState;

  factory LampImportReportUiState.failure({
    required String errorMessage,
  }) = LampImportReportFailureUiState;
}

class LampImportReportSuccessUiState extends LampImportReportUiState {
  const LampImportReportSuccessUiState({
    required this.databaseFileName,
    required this.durationSeconds,
    required this.importedRows,
    required this.issueCount,
    required this.readPathContext,
  });

  final String databaseFileName;
  final int durationSeconds;
  final Map<String, int> importedRows;
  final int issueCount;
  final LampImportReadPathContext readPathContext;
}

class LampImportReportFailureUiState extends LampImportReportUiState {
  const LampImportReportFailureUiState({required this.errorMessage});

  final String errorMessage;
}

/// Ελληνικές ετικέτες φύλλων Excel στο αποτέλεσμα import.
const Map<String, String> lampImportSheetLabelsGreek = <String, String>{
  'offices': 'Γραφεία / Τμήματα',
  'owners': 'Υπάλληλοι',
  'model': 'Μοντέλα',
  'contracts': 'Συμβάσεις',
  'equipment': 'Εξοπλισμός',
  'network': 'Δίκτυο (ενημερώσεις)',
};

const List<String> lampImportSheetDisplayOrder = <String>[
  'offices',
  'owners',
  'model',
  'contracts',
  'equipment',
  'network',
];

String lampImportSuccessHeadline(String databaseFileName) {
  return 'Η βάση [$databaseFileName] δημιουργήθηκε εκ νέου από το Excel.';
}

String formatLampImportDurationSeconds(int seconds) {
  if (seconds < 60) {
    return '$seconds δευτερόλεπτα';
  }
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (rest == 0) {
    return '$minutes λεπτά';
  }
  return '$minutes λεπτά και $rest δευτερόλεπτα';
}

Future<bool> confirmRecreateExistingOutputDatabase({
  required BuildContext context,
  required String fileName,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Αναδημιουργία υπάρχουσας βάσης'),
        content: SelectableText(
          'Το αρχείο [$fileName] υπάρχει ήδη. Θα διαγραφεί και θα ξαναδημιουργηθεί '
          'από το τρέχον Excel. Τυχόν επιλύσεις προβλημάτων και εκκρεμότητες δικτύου '
          'που έχουν αποθηκευτεί μόνο στη βάση θα χαθούν.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Συνέχεια'),
          ),
        ],
      );
    },
  );
  return result == true;
}

typedef LampImportExecutor = Future<LampImportResult> Function({
  required void Function(LampImportProgress progress) onProgress,
});

/// Εμφανίζει διάλογο προόδου/αναφοράς και εκτελεί το import.
Future<LampImportReportOutcome?> showLampImportReportFlow({
  required BuildContext context,
  required LampImportExecutor importFuture,
  required LampImportReadPathContext readPathContext,
}) async {
  final progressNotifier = ValueNotifier<LampImportProgressUiState>(
    const LampImportProgressUiState(),
  );
  final reportNotifier = ValueNotifier<LampImportReportUiState?>(null);

  final dialogFuture = showDialog<LampImportReportOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => LampImportReportDialog(
      progressListenable: progressNotifier,
      reportListenable: reportNotifier,
    ),
  );

  try {
    final result = await importFuture(
      onProgress: (progress) {
        progressNotifier.value = lampImportProgressUiStateFromProgress(
          progressNotifier.value,
          progress,
        );
      },
    );
    reportNotifier.value = LampImportReportUiState.success(
      databaseFileName: result.databasePath.split(RegExp(r'[/\\]')).last,
      durationSeconds: 0,
      importedRows: result.importedRows,
      issueCount: result.issueCount,
      readPathContext: readPathContext,
    );
  } catch (error) {
    reportNotifier.value = LampImportReportUiState.failure(
      errorMessage: error.toString(),
    );
  }

  return dialogFuture;
}

Future<LampImportReportOutcome?> showLampImportReportFlowWithDuration({
  required BuildContext context,
  required Future<LampImportResult> Function(
    void Function(LampImportProgress progress) onProgress,
  ) importRunner,
  required Stopwatch stopwatch,
  required LampImportReadPathContext readPathContext,
}) async {
  final progressNotifier = ValueNotifier<LampImportProgressUiState>(
    const LampImportProgressUiState(),
  );
  final reportNotifier = ValueNotifier<LampImportReportUiState?>(null);

  final dialogFuture = showDialog<LampImportReportOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => LampImportReportDialog(
      progressListenable: progressNotifier,
      reportListenable: reportNotifier,
    ),
  );

  try {
    final result = await importRunner((progress) {
      progressNotifier.value = lampImportProgressUiStateFromProgress(
        progressNotifier.value,
        progress,
      );
    });
    stopwatch.stop();
    reportNotifier.value = LampImportReportUiState.success(
      databaseFileName: result.databasePath.split(RegExp(r'[/\\]')).last,
      durationSeconds: stopwatch.elapsed.inSeconds,
      importedRows: result.importedRows,
      issueCount: result.issueCount,
      readPathContext: readPathContext,
    );
  } catch (error) {
    stopwatch.stop();
    reportNotifier.value = LampImportReportUiState.failure(
      errorMessage: error.toString(),
    );
  } finally {
    progressNotifier.dispose();
  }

  final action = await dialogFuture;
  reportNotifier.dispose();
  return action;
}

class LampImportReportDialog extends StatelessWidget {
  const LampImportReportDialog({
    super.key,
    required this.progressListenable,
    required this.reportListenable,
  });

  final ValueListenable<LampImportProgressUiState> progressListenable;
  final ValueListenable<LampImportReportUiState?> reportListenable;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LampImportReportUiState?>(
      valueListenable: reportListenable,
      builder: (context, report, _) {
        if (report != null) {
          return switch (report) {
            LampImportReportSuccessUiState success =>
              _LampImportSuccessReportDialog(report: success),
            LampImportReportFailureUiState failure =>
              _LampImportFailureReportDialog(report: failure),
          };
        }
        return ValueListenableBuilder<LampImportProgressUiState>(
          valueListenable: progressListenable,
          builder: (context, progress, _) {
            return AlertDialog(
              title: const Text('Εισαγωγή Excel στη βάση'),
              content: SizedBox(
                width: 640,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(value: progress.fraction),
                    const SizedBox(height: 12),
                    Text(
                      progress.currentMessage,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (progress.total > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Βήμα ${progress.done} από ${progress.total}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (progress.completedSteps.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: progress.completedSteps.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final step = progress.completedSteps[index];
                            return ListTile(
                              dense: true,
                              leading: const Icon(
                                Icons.check_circle_outline,
                                color: Colors.green,
                              ),
                              title: Text(step),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _LampImportSuccessReportDialog extends StatefulWidget {
  const _LampImportSuccessReportDialog({required this.report});

  final LampImportReportSuccessUiState report;

  @override
  State<_LampImportSuccessReportDialog> createState() =>
      _LampImportSuccessReportDialogState();
}

class _LampImportSuccessReportDialogState
    extends State<_LampImportSuccessReportDialog> {
  bool _setAsReadDatabase = false;

  bool get _showReadSwitch {
    final ctx = widget.report.readPathContext;
    return !ctx.readPathEmpty && ctx.readDiffersFromOutput;
  }

  void _close(LampImportReportCloseAction action) {
    Navigator.of(context).pop(
      LampImportReportOutcome(
        action: action,
        setAsReadDatabase: _showReadSwitch && _setAsReadDatabase,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final issueColor = report.issueCount > 0 ? scheme.error : scheme.onSurface;
    final readContext = report.readPathContext;

    return AlertDialog(
      title: const Text('Αναφορά εισαγωγής Excel'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                lampImportSuccessHeadline(report.databaseFileName),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF2E7D32),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                'Διάρκεια: ${formatLampImportDurationSeconds(report.durationSeconds)}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Εγγραφές που εισήχθησαν',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              ..._importedRowsLines(context, report.importedRows),
              const SizedBox(height: 12),
              SelectableText(
                'Προβλήματα ETL: ${report.issueCount} καταγράφηκαν στη βάση',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: issueColor,
                  fontWeight:
                      report.issueCount > 0 ? FontWeight.w600 : null,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                'Τα προβλήματα εμφανίζονται στην καρτέλα «Προβλήματα ETL».',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (readContext.readPathEmpty) ...[
                SelectableText(
                  'Η νέα βάση ορίστηκε ως βάση ανάγνωσης (το πεδίο ανάγνωσης ήταν κενό).',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
              ] else if (_showReadSwitch) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _setAsReadDatabase,
                  onChanged: (value) {
                    setState(() => _setAsReadDatabase = value);
                  },
                  title: Text(
                    'Η βάση [${report.databaseFileName}] δημιουργήθηκε με επιτυχία, '
                    'θέλετε να γίνει η Βάση Δεδομένων που χρησιμοποιεί η Λάμπα',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SelectableText(
                'Ο έλεγχος προβλημάτων της βάσης εκτελείται αυτόματα μετά την εισαγωγή.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _close(LampImportReportCloseAction.dismiss),
          child: const Text('Κλείσιμο'),
        ),
      ],
    );
  }
}

class _LampImportFailureReportDialog extends StatelessWidget {
  const _LampImportFailureReportDialog({required this.report});

  final LampImportReportFailureUiState report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('Αναφορά εισαγωγής Excel'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                'Η εισαγωγή απέτυχε',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                report.errorMessage,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              SelectableText(
                lampImportFailureHintMessage(report.errorMessage),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: report.errorMessage),
            );
          },
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: const Text('Αντιγραφή σφάλματος'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Κλείσιμο'),
        ),
      ],
    );
  }
}

List<Widget> _importedRowsLines(
  BuildContext context,
  Map<String, int> importedRows,
) {
  final widgets = <Widget>[];
  for (final sheet in lampImportSheetDisplayOrder) {
    if (!importedRows.containsKey(sheet)) continue;
    final count = importedRows[sheet] ?? 0;
    final label = lampImportSheetLabelsGreek[sheet] ?? sheet;
    final color = count == 0 ? Colors.orange.shade800 : null;
    final suffix = count == 0 ? ' — 0 — ελέγξτε το φύλλο στο Excel' : ': $count';
    widgets.add(
      SelectableText(
        '• $label$suffix',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
      ),
    );
  }
  for (final entry in importedRows.entries) {
    if (lampImportSheetDisplayOrder.contains(entry.key)) continue;
    widgets.add(
      SelectableText(
        '• ${entry.key}: ${entry.value}',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
  return widgets;
}
