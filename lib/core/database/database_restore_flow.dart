import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../utils/file_picker_initial_directory.dart';
import '../utils/file_picker_session.dart';
import '../../features/database/services/database_backup_service.dart';
import 'database_helper.dart';
import 'database_path_pick_flow.dart';

/// Κοινή ροή επαναφοράς βάσης από αρχείο `.zip` αντιγράφου ασφαλείας.
///
/// Επιστρέφει `true` όταν η επαναφορά και η επαλήθευση διαδρομής πέτυχαν.
Future<bool> runRestoreFromBackupZipFlow({
  required BuildContext context,
  String? backupFolderHint,
  String? currentDatabasePath,
  Future<void> Function()? onVerifiedSuccess,
}) async {
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
  if (session.refocusedExisting) return false;
  final picked = session.value;
  if (picked == null ||
      picked.files.isEmpty ||
      picked.files.single.path == null) {
    return false;
  }
  final zipPath = picked.files.single.path!.trim();
  if (!context.mounted) return false;

  final trimmedCurrent = currentDatabasePath?.trim() ?? '';
  final defaultTarget = trimmedCurrent.isNotEmpty
      ? trimmedCurrent
      : AppConfig.defaultDbPath;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Επαναφορά από zip'),
      content: Text(
        'Η βάση θα αντικατασταθεί στο:\n$defaultTarget\n\n'
        'Οι εικόνες χαρτών (${AppConfig.portableMapsDirName}), εικονίδια '
        '(${AppConfig.portableImagesDirName}), λεξικό (${AppConfig.portableDictionariesDirName}) '
        'και βάση Λάμπας (${AppConfig.portableDataBaseDirName}) θα επαναφερθούν στη '
        'ρίζα της εφαρμογής. Συνέχεια;',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Επαναφορά'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const AlertDialog(
      content: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(width: 24),
          Expanded(child: Text('Επαναφορά από zip…')),
        ],
      ),
    ),
  );

  DatabaseRestoreResult result;
  try {
    try {
      await DatabaseHelper.instance.closeConnection();
    } catch (_) {}
    result = await DatabaseBackupService.restoreFromBackupZip(
      zipPath,
      targetDatabasePath: defaultTarget,
    );
  } catch (e) {
    result = DatabaseRestoreResult(
      success: false,
      message: e.toString(),
    );
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  if (!context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  if (!result.success) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(result.message ?? 'Αποτυχία επαναφοράς'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
    return false;
  }

  if (result.databasePath == null) {
    return false;
  }

  final outcome = await setAndVerifyDatabasePath(result.databasePath!);
  if (!context.mounted) return false;
  if (outcome.ok) {
    await onVerifiedSuccess?.call();
    if (!context.mounted) return true;
    messenger.showSnackBar(
      SnackBar(content: Text(result.message ?? 'Η επαναφορά ολοκληρώθηκε.')),
    );
    return true;
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        outcome.runner.result.message ??
            'Η επαναφορά ολοκληρώθηκε αλλά η βάση δεν πέρασε έλεγχο.',
      ),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
  return false;
}
