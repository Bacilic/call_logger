// Εισαγωγή Excel σε βάση .db: έλεγχοι εισόδου, επιβεβαίωση και αναφορά.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/old_database/lamp_database_provider.dart';
import '../../../core/database/old_database/lamp_excel_validator.dart';
import '../../../core/database/old_database/lamp_old_db_validator.dart';
import '../../../core/database/old_database/old_excel_importer.dart';
import '../../../core/providers/lamp_db_comparison_provider.dart';
import '../widgets/lamp_import_report_dialog.dart';
import 'lamp_path_management.dart';
import 'lamp_screen_host.dart';

typedef RecreateConfirmationCallback = Future<bool> Function({
  required String fileName,
});

typedef ImportReportFlowCallback = Future<LampImportReportOutcome?> Function({
  required Stopwatch stopwatch,
  required LampImportReadPathContext readPathContext,
  required Future<LampImportResult> Function(
    void Function(LampImportProgress progress) onProgress,
  ) importRunner,
});

/// Ανανέωση των ειδοποιήσεων σύγκρισης βάσεων (ανάγνωση έναντι εξόδου).
/// Εγχέεται στα τεστ ώστε το [runImport] να μη χρειάζεται ζωντανό [WidgetRef].
typedef LampDbComparisonRefresh = Future<void> Function({
  required String readPath,
  required String outputPath,
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
    LampDbComparisonRefresh? refreshDbComparison,
  })  : _confirmRecreateExistingDatabase = confirmRecreateExistingDatabase,
        _showImportReportDialog = showImportReportDialog,
        _refreshDbComparison = refreshDbComparison;

  final LampScreenHost host;
  final LampPathController path;
  final RecreateConfirmationCallback? _confirmRecreateExistingDatabase;
  final ImportReportFlowCallback? _showImportReportDialog;
  final LampDbComparisonRefresh? _refreshDbComparison;

  bool importing = false;

  static const _excelValidator = LampExcelValidator();

  String? excelImportDisabledReason({
    LampOldDbCheckResult? outputPathCheck,
    LampExcelCheckResult? excelPathCheck,
  }) {
    final excelEmpty = path.excelController.text.trim().isEmpty;
    final outEmpty = path.outputDbController.text.trim().isEmpty;
    if (excelEmpty && outEmpty) {
      return 'Λείπει το Excel και διαδρομή του αρχείου εξόδου .db';
    }
    if (excelEmpty) {
      return 'Λείπει το αρχείο Excel';
    }
    if (excelPathCheck != null && lampExcelPathBlocksImport(excelPathCheck)) {
      return excelPathCheck.userMessageGreek;
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
    LampExcelCheckResult? excelPathCheck,
  }) {
    final blockReason = excelImportDisabledReason(
      outputPathCheck: outputPathCheck,
      excelPathCheck: excelPathCheck,
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

  Future<LampImportReportOutcome?> _runReportFlow({
    required Stopwatch stopwatch,
    required LampImportReadPathContext readPathContext,
    required Future<LampImportResult> Function(
      void Function(LampImportProgress progress) onProgress,
    ) importRunner,
  }) {
    final callback = _showImportReportDialog;
    if (callback != null) {
      return callback(
        stopwatch: stopwatch,
        readPathContext: readPathContext,
        importRunner: importRunner,
      );
    }
    return showLampImportReportFlowWithDuration(
      context: host.context,
      stopwatch: stopwatch,
      readPathContext: readPathContext,
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

    final excelCheck = await _excelValidator.validateExcelSource(excelPath);
    if (excelCheck.status != LampExcelStatus.ok) {
      final message = excelCheck.userMessageGreek;
      host.showSnack(message, isError: true);
      return LampImportRunResult(failureMessage: message);
    }

    final outputDirError = await _validateOutputDirectoryAccessible(outPath);
    if (outputDirError != null) {
      host.showSnack(outputDirError, isError: true);
      return LampImportRunResult(failureMessage: outputDirError);
    }

    final blockReason = excelImportDisabledReason(excelPathCheck: excelCheck);
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
    final readBeforeImport = path.readDbController.text.trim();
    final readPathEmpty = readBeforeImport.isEmpty;
    final readPathContext = LampImportReadPathContext(
      readPathEmpty: readPathEmpty,
      readDiffersFromOutput: !readPathEmpty &&
          !LampOldDbValidator.pathsReferToSameFile(
            readBeforeImport,
            outPath,
          ),
      currentReadFileName:
          readBeforeImport.isEmpty ? null : p.basename(readBeforeImport),
    );

    try {
      final outcome = await _runReportFlow(
        stopwatch: stopwatch,
        readPathContext: readPathContext,
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

      final outputPath = result.databasePath;
      await settings.setOutputPath(outputPath);
      path.outputDbController.text = outputPath;

      final alignRead = readPathEmpty || (outcome?.setAsReadDatabase ?? false);
      if (alignRead) {
        await settings.setReadPath(outputPath);
        path.readDbController.text = outputPath;
      }

      final successMessage = _successMessageFor(
        result: result,
        readAligned: alignRead,
      );
      onImportSuccess(successMessage);
      host.lampSettingsDialogSetState?.call(() {});
      await afterImportValidate();
      await _refreshComparison();

      return LampImportRunResult(
        successMessage: successMessage,
        runIntegrityCheck: outcome?.action ==
            LampImportReportCloseAction.runIntegrityCheck,
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

  /// Ανανεώνει τις ειδοποιήσεις σύγκρισης. Στην παραγωγή περνά από τον
  /// [lampDbComparisonProvider] μέσω `host.ref`· στα τεστ εγχέεται no-op ώστε
  /// να μη χρειάζεται ζωντανό [WidgetRef] (και άρα ούτε `testWidgets`/FFI).
  Future<void> _refreshComparison() async {
    final readPath = path.readDbController.text.trim();
    final outputPath = path.outputDbController.text.trim();
    final override = _refreshDbComparison;
    if (override != null) {
      await override(readPath: readPath, outputPath: outputPath);
      return;
    }
    await host.ref.read(lampDbComparisonProvider.notifier).refresh(
      readPathOverride: readPath,
      outputPathOverride: outputPath,
    );
  }

  String _successMessageFor({
    required LampImportResult result,
    required bool readAligned,
  }) {
    final alignmentText = readAligned
        ? 'Η αποθηκευμένη διαδρομή «ανάγνωση» ευθυγραμμίστηκε με το .db εξόδου (ίδιο αρχείο).'
        : 'Η βάση ανάγνωσης παρέμεινε ξεχωριστή από τη νέα έξοδο.';
    return 'Ολοκληρώθηκε η βάση ${p.basename(result.databasePath)}. '
        'Προβλήματα ETL: ${result.issueCount}. '
        '$alignmentText';
  }

  /// Έλεγχος ότι ο φάκελος εξόδου υπάρχει ή μπορεί να δημιουργηθεί.
  Future<String?> _validateOutputDirectoryAccessible(String outputPath) async {
    final trimmed = outputPath.trim();
    if (trimmed.isEmpty) {
      return 'Δεν έχει οριστεί διαδρομή εξόδου';
    }
    final parent = Directory(p.dirname(trimmed));
    if (await parent.exists()) {
      return null;
    }
    try {
      await parent.create(recursive: true);
      return null;
    } on FileSystemException catch (e) {
      return 'Ο φάκελος εξόδου δεν είναι προσβάσιμος '
          '(${p.basename(parent.path)}). Ελέγξτε δίσκο δικτύου/USB ή τη διαδρομή. '
          '${e.message}'.trim();
    }
  }
}
