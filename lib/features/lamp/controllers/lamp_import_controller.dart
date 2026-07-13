// Εισαγωγή Excel σε βάση .db: έλεγχοι εισόδου, επιβεβαίωση και αναφορά.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/old_database/lamp_database_provider.dart';
import '../../../core/database/old_database/lamp_old_db_validator.dart';
import '../../../core/database/old_database/old_excel_importer.dart';
import '../widgets/lamp_import_report_dialog.dart';
import 'lamp_path_management.dart';
import 'lamp_screen_host.dart';

typedef RecreateConfirmationCallback = Future<bool> Function({
  required String fileName,
});

typedef ImportReportFlowCallback = Future<LampImportReportCloseAction?> Function({
  required Stopwatch stopwatch,
  required Future<LampImportResult> Function(
    void Function(LampImportProgress progress) onProgress,
  ) importRunner,
});

class LampImportRunResult {
  const LampImportRunResult({
    this.failureMessage,
    this.runIntegrityCheck = false,
    this.successMessage,
  });

  final String? failureMessage;
  final bool runIntegrityCheck;
  final String? successMessage;
}

class LampImportController {
  LampImportController({
    required this.host,
    required this.path,
    RecreateConfirmationCallback? confirmRecreateExistingDatabase,
    ImportReportFlowCallback? showImportReportDialog,
  })  : _confirmRecreateExistingDatabase = confirmRecreateExistingDatabase,
        _showImportReportDialog = showImportReportDialog;

  final LampScreenHost host;
  final LampPathController path;
  final RecreateConfirmationCallback? _confirmRecreateExistingDatabase;
  final ImportReportFlowCallback? _showImportReportDialog;

  bool importing = false;

  String? excelImportDisabledReason({LampOldDbCheckResult? outputPathCheck}) {
    final excelEmpty = path.excelController.text.trim().isEmpty;
    final outEmpty = path.outputDbController.text.trim().isEmpty;
    if (excelEmpty && outEmpty) {
      return 'Λείπει το Excel και διαδρομή του αρχείου εξόδου .db';
    }
    if (excelEmpty) {
      return 'Λείπει το αρχείο Excel';
    }
    if (outEmpty) {
      return 'Δεν έχει οριστεί διαδρομή εξόδου';
    }
    final outputFormatError = LampOldDbValidator.validateDbPathFormat(
      path.outputDbController.text,
    );
    if (outputFormatError != null) {
      return outputFormatError;
    }
    if (outputPathCheck != null && lampOutputPathBlocksImport(outputPathCheck)) {
      return outputPathCheck.userMessageGreek;
    }
    return null;
  }

  Widget excelImportButton({
    required VoidCallback onImport,
    required String? message,
    LampOldDbCheckResult? outputPathCheck,
  }) {
    final blockReason = excelImportDisabledReason(
      outputPathCheck: outputPathCheck,
    );
    final enabled = !importing && blockReason == null;
    final button = FilledButton.icon(
      onPressed: enabled ? onImport : null,
      icon: const Icon(Icons.play_arrow),
      label: Text(kLampExcelImportButtonLabel),
    );
    final tooltipMessage =
        importing ? 'Εκτελείται εισαγωγή Excel…' : blockReason;
    if (enabled || tooltipMessage == null) {
      return button;
    }
    return Tooltip(
      waitDuration: const Duration(milliseconds: 400),
      showDuration: const Duration(seconds: 5),
      message: tooltipMessage,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {},
          child: IgnorePointer(child: button),
        ),
      ),
    );
  }

  Future<bool> _askRecreateConfirmation(String fileName) {
    final callback = _confirmRecreateExistingDatabase;
    if (callback != null) {
      return callback(fileName: fileName);
    }
    return confirmRecreateExistingOutputDatabase(
      context: host.context,
      fileName: fileName,
    );
  }

  Future<LampImportReportCloseAction?> _runReportFlow({
    required Stopwatch stopwatch,
    required Future<LampImportResult> Function(
      void Function(LampImportProgress progress) onProgress,
    ) importRunner,
  }) {
    final callback = _showImportReportDialog;
    if (callback != null) {
      return callback(stopwatch: stopwatch, importRunner: importRunner);
    }
    return showLampImportReportFlowWithDuration(
      context: host.context,
      stopwatch: stopwatch,
      importRunner: importRunner,
    );
  }

  Future<LampImportRunResult> runImport({
    required void Function() onImportStart,
    required void Function(String message) onImportSuccess,
    required Future<void> Function() afterImportValidate,
    required Future<void> Function() onImportFailureReload,
  }) async {
    final excelPath = path.excelController.text.trim();
    final outPath = path.outputDbController.text.trim();
    final blockReason = excelImportDisabledReason();
    if (blockReason != null) {
      host.showSnack(blockReason, isError: true);
      return LampImportRunResult(failureMessage: blockReason);
    }

    if (await File(outPath).exists()) {
      final confirmed = await _askRecreateConfirmation(p.basename(outPath));
      if (!confirmed) {
        return const LampImportRunResult();
      }
    }

    final settings = host.shared.settings;
    await settings.setExcelPath(excelPath);
    await settings.setOutputPath(outPath);
    await LampDatabaseProvider.instance.close();
    importing = true;
    onImportStart();
    host.lampSettingsDialogSetState?.call(() {});

    final stopwatch = Stopwatch()..start();
    LampImportResult? importResult;

    try {
      final closeAction = await _runReportFlow(
        stopwatch: stopwatch,
        importRunner: (onProgress) async {
          final result = await host.shared.importer.importExcel(
            excelPath: excelPath,
            databasePath: outPath,
            onProgress: onProgress,
          );
          importResult = result;
          return result;
        },
      );

      if (!host.mounted) {
        return const LampImportRunResult();
      }

      final result = importResult;
      if (result == null) {
        await onImportFailureReload();
        return const LampImportRunResult(
          failureMessage: 'Η εισαγωγή Excel απέτυχε.',
        );
      }

      await settings.setOutputAndReadFromImportResult(result.databasePath);
      path.readDbController.text = result.databasePath;
      path.outputDbController.text = result.databasePath;
      final successMessage = _successMessageFor(result);
      onImportSuccess(successMessage);
      host.lampSettingsDialogSetState?.call(() {});
      await afterImportValidate();

      return LampImportRunResult(
        successMessage: successMessage,
        runIntegrityCheck:
            closeAction == LampImportReportCloseAction.runIntegrityCheck,
      );
    } catch (e) {
      if (!host.mounted) {
        return const LampImportRunResult(
          failureMessage: 'Η εισαγωγή Excel απέτυχε.',
        );
      }
      await onImportFailureReload();
      return const LampImportRunResult(
        failureMessage: 'Η εισαγωγή Excel απέτυχε.',
      );
    } finally {
      stopwatch.stop();
      if (host.mounted) {
        importing = false;
        host.lampSettingsDialogSetState?.call(() {});
        host.notifyState();
      }
    }
  }

  String _successMessageFor(LampImportResult result) {
    return 'Ολοκληρώθηκε η βάση ${p.basename(result.databasePath)}. '
        'Προβλήματα ETL: ${result.issueCount}. '
        'Η αποθηκευμένη διαδρομή «ανάγνωση» ευθυγραμμίστηκε με το .db εξόδου (ίδιο αρχείο).';
  }
}
