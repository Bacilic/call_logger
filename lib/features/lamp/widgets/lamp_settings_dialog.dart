// Διάλογος ρυθμίσεων Λάμπας: η βάση που διαβάζει, ο έλεγχος προβλημάτων, το όριο αναζήτησης.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/old_database/lamp_old_db_validator.dart';
import '../../../core/database/old_database/lamp_settings_store.dart';
import '../controllers/lamp_integrity_controller.dart';
import '../controllers/lamp_path_management.dart';
import '../controllers/lamp_search_controller.dart';

const String _kReadDbInfoTooltip =
    'Εδώ ορίζετε τη βάση δεδομένων που διαβάζει η Λάμπα (αναζήτηση, πίνακες, '
    'έλεγχος προβλημάτων).\n\n'
    'Στην «Επιλογή» θα ερωτηθείτε αν θέλετε αντίγραφο στον φάκελο της εφαρμογής '
    '(ταξιδεύει μαζί της και μπαίνει στα αντίγραφα ασφαλείας) ή ανάγνωση από τη '
    'θέση που ήδη βρίσκεται το αρχείο.';

class LampSettingsDialogController {
  LampSettingsDialogController({
    required this.path,
    required this.search,
    required this.integrityController,
    required this.getReadPathCheck,
    required this.getDialogFeedback,
    required this.getDialogFeedbackIsError,
    required this.onClearDialogFeedback,
    required this.onCopyDialogFeedback,
    required this.onPickReadDatabase,
    required this.onRunIntegrityCheck,
    required this.onClose,
    required this.isIntegrityChecking,
  });

  final LampPathController path;
  final LampSearchController search;
  final LampIntegrityController integrityController;
  final LampOldDbCheckResult? Function() getReadPathCheck;
  final String? Function() getDialogFeedback;
  final bool Function() getDialogFeedbackIsError;
  final VoidCallback onClearDialogFeedback;
  final Future<void> Function(String message) onCopyDialogFeedback;
  final Future<void> Function() onPickReadDatabase;
  final Future<void> Function() onRunIntegrityCheck;
  final Future<void> Function(void Function() pop) onClose;
  final bool Function() isIntegrityChecking;
}

void openLampSettingsDialog({
  required BuildContext context,
  required LampSettingsDialogController controller,
  required ValueChanged<StateSetter> registerDialogSetState,
  required VoidCallback onDialogClosed,
}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Consumer(
        builder: (context, ref, _) {
          return _LampSettingsDialogShell(
            dialogContext: dialogContext,
            controller: controller,
            registerDialogSetState: registerDialogSetState,
          );
        },
      );
    },
  ).then((_) => onDialogClosed());
}

class _LampSettingsDialogShell extends ConsumerStatefulWidget {
  const _LampSettingsDialogShell({
    required this.dialogContext,
    required this.controller,
    required this.registerDialogSetState,
  });

  final BuildContext dialogContext;
  final LampSettingsDialogController controller;
  final ValueChanged<StateSetter> registerDialogSetState;

  @override
  ConsumerState<_LampSettingsDialogShell> createState() =>
      _LampSettingsDialogShellState();
}

class _LampSettingsDialogShellState
    extends ConsumerState<_LampSettingsDialogShell> {
  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setDialogState) {
        // Mounted-guard: οι controllers (integrity/import/path) καλούν αυτό το
        // setState και ΑΦΟΥ κλείσει ο διάλογος· χωρίς τον έλεγχο mounted προκύπτει
        // «setState() called after dispose()» στον StatefulBuilder (κατάρρευση).
        widget.registerDialogSetState((VoidCallback fn) {
          if (mounted) setDialogState(fn);
        });
        final maxDialogBodyHeight = MediaQuery.sizeOf(context).height * 0.55;
        final readPathCheck = widget.controller.getReadPathCheck();
        final dialogFeedback = widget.controller.getDialogFeedback();
        final integrityChecking = widget.controller.isIntegrityChecking();
        return AlertDialog(
          title: const Text('Ρυθμίσεις Λάμπας'),
          content: SizedBox(
            width: 720,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxDialogBodyHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.controller.path.readPathFormatWarning() !=
                        null) ...[
                      LampPathFormatWarningBanner(
                        message: widget.controller.path
                            .readPathFormatWarning()!,
                      ),
                      const SizedBox(height: 6),
                    ],
                    LampPathRow(
                      controller: widget.controller.path.readDbController,
                      label: 'Βάση Δεδομένων που χρησιμοποιεί η Λάμπα',
                      infoTooltip: _kReadDbInfoTooltip,
                      onPick: () => widget.controller.onPickReadDatabase(),
                      onChanged: widget
                          .controller
                          .path
                          .notifySettingsDialogFieldsChanged,
                    ),
                    const SizedBox(height: 6),
                    LampReadPathCheckPanel(
                      readPathCheck: readPathCheck,
                      readDbController: widget.controller.path.readDbController,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: integrityChecking
                            ? null
                            : () async {
                                await widget.controller.onRunIntegrityCheck();
                                if (!context.mounted) return;
                                setDialogState(() {});
                              },
                        icon: integrityChecking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.rule_folder_outlined),
                        label: const Text('Έλεγχος Προβλημάτων'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller:
                          widget.controller.search.maxSearchResultsController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Μέγιστος αριθμός εμφανιζόμενων αποτελεσμάτων αναζήτησης (Ν)',
                        border: const OutlineInputBorder(),
                        helperText:
                            'Εύρος ${LampSettingsStore.minMaxSearchResults}–'
                            '${LampSettingsStore.maxMaxSearchResults} · προεπιλογή '
                            '${LampSettingsStore.defaultMaxSearchResults}',
                      ),
                    ),
                    if (dialogFeedback != null &&
                        dialogFeedback.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      LampSettingsDialogFeedbackPanel(
                        message: dialogFeedback,
                        isError: widget.controller.getDialogFeedbackIsError(),
                        onClear: widget.controller.onClearDialogFeedback,
                        onCopy: () => widget.controller.onCopyDialogFeedback(
                          dialogFeedback,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await widget.controller.onClose(
                  () => Navigator.of(widget.dialogContext).pop(),
                );
              },
              child: const Text('Κλείσιμο'),
            ),
          ],
        );
      },
    );
  }
}

class LampSettingsDialogFeedbackPanel extends StatelessWidget {
  const LampSettingsDialogFeedbackPanel({
    super.key,
    required this.message,
    required this.isError,
    required this.onClear,
    required this.onCopy,
  });

  final String message;
  final bool isError;
  final VoidCallback onClear;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color bg = isError
        ? scheme.errorContainer.withValues(alpha: 0.55)
        : scheme.primaryContainer.withValues(alpha: 0.45);
    final IconData icon = isError ? Icons.error_outline : Icons.info_outline;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.onSurface),
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
                if (isError)
                  IconButton(
                    tooltip: 'Αντιγραφή μηνύματος',
                    visualDensity: VisualDensity.compact,
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_outlined, size: 18),
                  ),
                IconButton(
                  tooltip: 'Απόκρυψη μηνύματος',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
