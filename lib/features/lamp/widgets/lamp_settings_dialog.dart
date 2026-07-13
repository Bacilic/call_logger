// Διάλογος ρυθμίσεων διαδρομών Λάμπας: Excel, read/output DB, import, έλεγχος.
import 'package:flutter/material.dart';

import '../../../core/database/old_database/lamp_old_db_validator.dart';
import '../../../core/database/old_database/lamp_settings_store.dart';
import '../controllers/lamp_import_controller.dart';
import '../controllers/lamp_integrity_controller.dart';
import '../controllers/lamp_path_management.dart';
import '../controllers/lamp_search_controller.dart';

const String _kExcelInfoTooltip =
    'Ορίστε το αρχείο Excel από το οποίο θα αντληθούν τα δεδομένα. '
    'Το αρχείο πρέπει να έχει τη συγκεκριμένη δομή που εξάγει το πρόγραμμα της Λάμπας, '
    'μαζί με την καρτέλα "network".';

const String _kOutputDbInfoTooltip =
    'Ορίστε το αρχείο βάσης δεδομένων στο οποίο θα μετατραπεί το Excel. '
    'Η μετατροπή σε αρχείο .db γίνεται για πιο εύχρηστη διαχείριση. '
    'Αν το αρχείο υπάρχει ήδη, θα διαγραφεί και θα ξαναδημιουργηθεί από το τρέχον περιεχόμενο του Excel. '
    'Προσοχή: ΔΕΝ είναι αυτό το αρχείο που διαβάζει η Λάμπα.';

const String _kReadDbInfoTooltip =
    'Εδώ ορίζετε τη βάση δεδομένων που διαβάζει η Λάμπα (αναζήτηση, πίνακες, '
    'έλεγχος προβλημάτων). Είναι ξεχωριστή από το αρχείο που δημιουργεί το Excel, '
    'ώστε να μπορούν να γίνονται εύκολα δοκιμές. Φυσικά μπορεί να είναι το ίδιο αρχείο.';

class LampSettingsDialogController {
  LampSettingsDialogController({
    required this.path,
    required this.search,
    required this.importController,
    required this.integrityController,
    required this.getReadPathCheck,
    required this.getOutputPathCheck,
    required this.getDialogFeedback,
    required this.getDialogFeedbackIsError,
    required this.onClearDialogFeedback,
    required this.onCopyDialogFeedback,
    required this.onPickExcel,
    required this.onPickReadDatabase,
    required this.onPickDatabaseOutput,
    required this.onMatchReadToOutput,
    required this.onRunIntegrityCheck,
    required this.onRunImport,
    required this.onClose,
    required this.isImporting,
    required this.isIntegrityChecking,
  });

  final LampPathController path;
  final LampSearchController search;
  final LampImportController importController;
  final LampIntegrityController integrityController;
  final LampOldDbCheckResult? Function() getReadPathCheck;
  final LampOldDbCheckResult? Function() getOutputPathCheck;
  final String? Function() getDialogFeedback;
  final bool Function() getDialogFeedbackIsError;
  final VoidCallback onClearDialogFeedback;
  final Future<void> Function(String message) onCopyDialogFeedback;
  final Future<void> Function() onPickExcel;
  final Future<void> Function() onPickReadDatabase;
  final Future<void> Function() onPickDatabaseOutput;
  final Future<void> Function() onMatchReadToOutput;
  final Future<void> Function() onRunIntegrityCheck;
  final Future<void> Function() onRunImport;
  final Future<void> Function(void Function() pop) onClose;
  final bool Function() isImporting;
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
      return StatefulBuilder(
        builder: (context, setDialogState) {
          registerDialogSetState(setDialogState);
          final maxDialogBodyHeight = MediaQuery.sizeOf(context).height * 0.55;
          final readPathCheck = controller.getReadPathCheck();
          final outputPathCheck = controller.getOutputPathCheck();
          final dialogFeedback = controller.getDialogFeedback();
          final importing = controller.isImporting();
          final integrityChecking = controller.isIntegrityChecking();
          final matchButtonState = computeMatchReadToOutputButtonState(
            outputPath: controller.path.outputDbController.text,
            readPath: controller.path.readDbController.text,
          );
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
                      LampPathRow(
                        controller: controller.path.excelController,
                        label: 'Αρχείο Excel (πηγή δεδομένων)',
                        infoTooltip: _kExcelInfoTooltip,
                        onPick: () => controller.onPickExcel(),
                        onChanged: controller.path.notifySettingsDialogFieldsChanged,
                      ),
                      const SizedBox(height: 12),
                      if (controller.path.outputPathFormatWarning() != null) ...[
                        LampPathFormatWarningBanner(
                          message: controller.path.outputPathFormatWarning()!,
                        ),
                        const SizedBox(height: 6),
                      ],
                      LampPathRow(
                        controller: controller.path.outputDbController,
                        label: 'Βάση δεδομένων που δημιουργεί το Excel',
                        infoTooltip: _kOutputDbInfoTooltip,
                        onPick: () => controller.onPickDatabaseOutput(),
                        onChanged: controller.path.notifySettingsDialogFieldsChanged,
                      ),
                      const SizedBox(height: 6),
                      LampPathCheckPanel(
                        pathCheck: outputPathCheck,
                        pathController: controller.path.outputDbController,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: controller.importController.excelImportButton(
                          onImport: () => controller.onRunImport(),
                          message: null,
                          outputPathCheck: outputPathCheck,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (controller.path.readPathFormatWarning() != null) ...[
                        LampPathFormatWarningBanner(
                          message: controller.path.readPathFormatWarning()!,
                        ),
                        const SizedBox(height: 6),
                      ],
                      LampPathRow(
                        controller: controller.path.readDbController,
                        label: 'Βάση Δεδομένων που χρησιμοποιεί η Λάμπα',
                        infoTooltip: _kReadDbInfoTooltip,
                        onPick: () => controller.onPickReadDatabase(),
                        onChanged: controller.path.notifySettingsDialogFieldsChanged,
                        trailing: Tooltip(
                          waitDuration: const Duration(milliseconds: 300),
                          showDuration: const Duration(seconds: 6),
                          message: matchButtonState.tooltip,
                          child: IconButton(
                            onPressed: matchButtonState.enabled &&
                                    !importing &&
                                    !integrityChecking
                                ? () async {
                                    await controller.onMatchReadToOutput();
                                    if (!context.mounted) return;
                                    setDialogState(() {});
                                  }
                                : null,
                            icon: const Icon(Icons.arrow_downward),
                            tooltip: '',
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      LampReadPathCheckPanel(
                        readPathCheck: readPathCheck,
                        readDbController: controller.path.readDbController,
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          onPressed: (importing || integrityChecking)
                              ? null
                              : () async {
                                  await controller.onRunIntegrityCheck();
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
                        controller: controller.search.maxSearchResultsController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText:
                              'Μέγιστος αριθμός εμφανιζόμενων αποτελεσμάτων αναζήτησης (Ν)',
                          border: const OutlineInputBorder(),
                          helperText:
                              'Εύρος ${LampSettingsStore.minMaxSearchResults}–'
                              '${LampSettingsStore.maxMaxSearchResults} · προεπιλογή '
                              '${LampSettingsStore.defaultMaxSearchResults}',
                        ),
                      ),
                      if (dialogFeedback != null && dialogFeedback.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        LampSettingsDialogFeedbackPanel(
                          message: dialogFeedback,
                          isError: controller.getDialogFeedbackIsError(),
                          onClear: controller.onClearDialogFeedback,
                          onCopy: () => controller.onCopyDialogFeedback(
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
                onPressed: importing
                    ? null
                    : () async {
                        await controller.onClose(
                          () => Navigator.of(dialogContext).pop(),
                        );
                      },
                child: const Text('Κλείσιμο'),
              ),
            ],
          );
        },
      );
    },
  ).then((_) => onDialogClosed());
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
