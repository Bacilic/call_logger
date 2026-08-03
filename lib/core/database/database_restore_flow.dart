import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import '../utils/file_picker_initial_directory.dart';
import '../utils/file_picker_session.dart';
import 'database_file_classifier.dart';
import 'database_helper.dart';
import '../../features/database/services/backup_zip_candidate_selection.dart';
import '../../features/database/services/backup_zip_inventory.dart';
import '../../features/database/services/backup_zip_manifest.dart';
import '../../features/database/services/backup_zip_staging.dart';
import '../../features/database/services/database_backup_service.dart';
import '../../features/database/services/database_file_replacement.dart';
import '../../features/database/services/restore_plan.dart';
import '../../features/database/services/restore_report.dart';
import '../../features/database/widgets/backup_zip_database_choice_dialog.dart';
import '../../features/database/widgets/restore_from_backup_dialog.dart';
import '../../features/database/widgets/restore_report_dialog.dart';

/// Αποτέλεσμα της ενορχηστρωμένης ροής επαναφοράς από `.zip`.
class RestoreFromBackupZipFlowResult {
  const RestoreFromBackupZipFlowResult.cancelled()
    : cancelled = true,
      failed = false,
      restoredPath = null,
      pathToOpen = null,
      errorMessage = null,
      summaryMessage = null,
      warnings = const <String>[],
      preRestoreBackupPath = null;

  const RestoreFromBackupZipFlowResult.failed(this.errorMessage)
    : cancelled = false,
      failed = true,
      restoredPath = null,
      pathToOpen = null,
      summaryMessage = null,
      warnings = const <String>[],
      preRestoreBackupPath = null;

  const RestoreFromBackupZipFlowResult.completed({
    required this.restoredPath,
    this.pathToOpen,
    this.summaryMessage,
    this.warnings = const <String>[],
    this.preRestoreBackupPath,
  }) : cancelled = false,
       failed = false,
       errorMessage = null;

  final bool cancelled;
  final bool failed;
  final String? restoredPath;

  /// Διαδρομή που πρέπει να ανοίξει ο καλών μέσω του κοινού εκτελεστή.
  /// Σε επιτυχία είναι πάντα ο προορισμός — η βάση που επαναφέρθηκε ανοίγει.
  final String? pathToOpen;
  final String? errorMessage;
  final String? summaryMessage;
  final List<String> warnings;
  final String? preRestoreBackupPath;

  bool get isSuccess =>
      !cancelled && !failed && restoredPath != null && restoredPath!.isNotEmpty;
}

/// Ενορχήστρωση επαναφοράς από `.zip`: επιλογή → απογραφή → επιλογή υποψηφίου →
/// εξαγωγή → διάλογος προορισμού → αντικατάσταση. Το φινάλε εναλλαγής ανήκει
/// αποκλειστικά στον καλούντα.
Future<RestoreFromBackupZipFlowResult> runRestoreFromBackupZipFlow({
  required BuildContext context,
  String? backupFolderHint,
  String? currentDatabasePath,
  String? preselectedZipPath,
  RestoreDestinationChoice initialDestination =
      RestoreDestinationChoice.defaultChoice,
}) async {
  final trimmedCurrent = currentDatabasePath?.trim() ?? '';
  final currentPath = trimmedCurrent.isNotEmpty
      ? trimmedCurrent
      : AppConfig.defaultDbPath;

  final zipPath = preselectedZipPath?.trim().isNotEmpty == true
      ? preselectedZipPath!.trim()
      : await _pickZipPath(context, backupFolderHint);
  if (zipPath == null || zipPath.isEmpty) {
    return const RestoreFromBackupZipFlowResult.cancelled();
  }
  if (!context.mounted) {
    return const RestoreFromBackupZipFlowResult.cancelled();
  }

  final progressLabel = ValueNotifier<String>(
    'Έλεγχος περιεχομένου αντιγράφου…',
  );
  _showBusyDialog(context, progressLabel);
  late final BackupZipInventory inventory;
  try {
    inventory = await inspectBackupZip(
      zipPath,
      onProgress: (current, total) {
        progressLabel.value =
            'Έλεγχος περιεχομένου αντιγράφου, $current από $total';
      },
    );
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    progressLabel.dispose();
  }

  final selection = decideBackupZipCandidateSelection(inventory);
  if (selection.kind == BackupZipCandidateSelectionKind.none) {
    final message = selection.failureMessage ?? inventory.summarySentence;
    if (context.mounted) {
      await _showRestoreMessageDialog(
        context,
        title: 'Η επαναφορά δεν είναι δυνατή',
        message: message,
      );
    }
    return RestoreFromBackupZipFlowResult.failed(message);
  }

  BackupZipEligibleCandidate? chosen = selection.selected;
  if (selection.requiresUserChoice) {
    if (!context.mounted) {
      return const RestoreFromBackupZipFlowResult.cancelled();
    }
    chosen = await showBackupZipDatabaseChoiceDialog(
      context: context,
      inventory: inventory,
    );
    if (chosen == null) {
      return const RestoreFromBackupZipFlowResult.cancelled();
    }
  }

  if (chosen == null) {
    return const RestoreFromBackupZipFlowResult.failed(
      'Δεν επιλέχθηκε αρχείο βάσης για επαναφορά.',
    );
  }

  if (!context.mounted) {
    return const RestoreFromBackupZipFlowResult.cancelled();
  }

  final extractLabel = ValueNotifier<String>('Εξαγωγή επιλεγμένης βάσης…');
  _showBusyDialog(context, extractLabel);
  late final BackupZipInspection extraction;
  try {
    extraction = await extractSelectedBackupZipEntry(
      zipPath,
      databaseEntryName: chosen.entryName,
      preferredOutputFileName: chosen.displayName,
    );
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    extractLabel.dispose();
  }

  if (!extraction.success) {
    final message =
        extraction.errorMessage ?? 'Αποτυχία εξαγωγής βάσης από το αντίγραφο.';
    if (context.mounted) {
      await _showRestoreMessageDialog(
        context,
        title: 'Η επαναφορά απέτυχε',
        message: message,
      );
    }
    return RestoreFromBackupZipFlowResult.failed(message);
  }

  final extractedPath = extraction.extractedDatabasePath!;
  final backupProfile = extraction.profile!;
  final manifest = extraction.manifest ?? const BackupZipManifest.unknown();
  final preferredName = chosen.displayName;

  DatabaseFileProfile? currentProfile;
  if (await File(currentPath).exists()) {
    try {
      currentProfile = await profileDatabaseFile(currentPath);
    } catch (_) {
      currentProfile = null;
    }
  }

  final available = availableRestoreDestinations(
    currentDatabasePath: currentPath,
    backupDatabaseFileName: preferredName,
  );
  var backupNameTargetExists = false;
  if (available.contains(RestoreDestinationChoice.backupName)) {
    final backupNameTarget = resolveRestoreTargetPath(
      choice: RestoreDestinationChoice.backupName,
      currentDatabasePath: currentPath,
      backupDatabaseFileName: preferredName,
    );
    backupNameTargetExists = await File(backupNameTarget).exists();
  }

  if (!context.mounted) {
    await cleanupStagedDatabase(extractedPath);
    return const RestoreFromBackupZipFlowResult.cancelled();
  }

  final decision = await showRestoreFromBackupDialog(
    context: context,
    currentProfile: currentProfile,
    backupProfile: backupProfile,
    manifest: manifest,
    currentDatabasePath: currentPath,
    availableDestinations: available,
    initialDestination: initialDestination,
    preferredDatabaseFileName: preferredName,
    backupNameTargetExists: backupNameTargetExists,
    isFullBackupArchive: inventory.isFullBackupArchive,
    fullBackupPortablesDescription: inventory.portablePresence
        .describeFoundPortables(),
  );

  if (decision == null) {
    final cleanupMsg = await cleanupStagedDatabase(extractedPath);
    if (cleanupMsg != null && context.mounted) {
      await _showRestoreMessageDialog(
        context,
        title: 'Προειδοποίηση',
        message: cleanupMsg,
      );
    }
    return const RestoreFromBackupZipFlowResult.cancelled();
  }

  final targetPath = resolveRestoreTargetPath(
    choice: decision,
    currentDatabasePath: currentPath,
    backupDatabaseFileName: preferredName,
  );

  if (!context.mounted) {
    await cleanupStagedDatabase(extractedPath);
    return const RestoreFromBackupZipFlowResult.cancelled();
  }

  final restoreLabel = ValueNotifier<String>('Επαναφορά από zip…');
  _showBusyDialog(context, restoreLabel);
  String? preRestorePath;
  final warnings = <String>[...inventory.cleanupWarnings];
  String? summary;
  var reportItems = const <RestoreReportItem>[];
  String? failureMessage;
  try {
    Object? closeFailure;
    try {
      await DatabaseHelper.instance.closeConnection();
    } catch (e) {
      closeFailure = e;
    }

    final sameAsStaged = _samePath(targetPath, extractedPath);

    if (!sameAsStaged) {
      final replacement = await DatabaseFileReplacement.replaceFromFile(
        targetDatabasePath: targetPath,
        sourceDatabasePath: extractedPath,
      );
      if (!replacement.success) {
        var message = replacement.message ?? 'Αποτυχία αντικατάστασης βάσης.';
        if (closeFailure != null) {
          message =
              '$message\n\nΤο κλείσιμο της σύνδεσης απέτυχε: $closeFailure';
        }
        failureMessage = message;
      } else {
        preRestorePath = replacement.preRestoreBackupPath;
      }
    }

    if (failureMessage == null) {
      final portables =
          await DatabaseBackupService.restorePortablesFromBackupZip(
            zipPath,
            restoredDatabasePath: targetPath,
          );
      warnings.addAll(portables.warnings);
      summary = portables.message;
      reportItems = portables.reportItems;
    }
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    restoreLabel.dispose();
    final keepStaged = _samePath(targetPath, extractedPath);
    if (!keepStaged) {
      final cleanupMsg = await cleanupStagedDatabase(extractedPath);
      if (cleanupMsg != null) {
        warnings.add(cleanupMsg);
      }
    }
  }

  if (failureMessage != null) {
    if (context.mounted) {
      await _showRestoreMessageDialog(
        context,
        title: 'Η επαναφορά απέτυχε',
        message: failureMessage,
      );
    }
    return RestoreFromBackupZipFlowResult.failed(failureMessage);
  }

  if (context.mounted) {
    await showRestoreReportDialog(
      context: context,
      items: reportItems,
      fallbackText: summary ?? 'Η επαναφορά ολοκληρώθηκε.',
      preRestoreBackupPath: preRestorePath,
      warnings: warnings,
    );
  }

  return RestoreFromBackupZipFlowResult.completed(
    restoredPath: targetPath,
    pathToOpen: targetPath,
    summaryMessage: summary,
    warnings: warnings,
    preRestoreBackupPath: preRestorePath,
  );
}

bool _samePath(String a, String b) {
  final na = p.normalize(p.absolute(a)).replaceAll('/', '\\').toLowerCase();
  final nb = p.normalize(p.absolute(b)).replaceAll('/', '\\').toLowerCase();
  return na == nb;
}

Future<String?> _pickZipPath(
  BuildContext context,
  String? backupFolderHint,
) async {
  final folder = backupFolderHint?.trim() ?? '';
  final initialDirectory = initialDirectoryForFilePicker(
    folder.isNotEmpty ? folder : null,
  );
  final session = await FilePickerSession.run(
    () => FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      dialogTitle: 'Επιλογή αρχείου επαναφοράς (.zip)',
      initialDirectory: initialDirectory,
    ),
  );
  if (session.refocusedExisting) return null;
  final picked = session.value;
  if (picked == null ||
      picked.files.isEmpty ||
      picked.files.single.path == null) {
    return null;
  }
  return picked.files.single.path!.trim();
}

void _showBusyDialog(BuildContext context, ValueNotifier<String> label) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: label,
              builder: (_, text, _) => Text(text),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Κεντρικό σημείο ενημέρωσης της ροής επαναφοράς: πάντα κανονικό παράθυρο.
///
/// Snackbar εδώ θα εμφανιζόταν πίσω από τους ανοιχτούς διαλόγους ρυθμίσεων
/// και θα ήταν μη αναγνώσιμο.
Future<void> _showRestoreMessageDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Εντάξει'),
        ),
      ],
    ),
  );
}

