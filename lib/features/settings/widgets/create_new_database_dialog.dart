import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../../../core/database/database_helper.dart';
import '../../../core/init/app_init_provider.dart';
import '../../../core/utils/file_picker_initial_directory.dart';
import '../../../core/utils/file_picker_session.dart';
import '../../../core/utils/windows_save_sqlite_database_dialog.dart';
import '../../calls/provider/lookup_provider.dart';
import '../../database/providers/database_browser_stats_provider.dart';
import '../../database/providers/database_maintenance_provider.dart';
import '../../database/widgets/database_rename_failure_dialog.dart';
import '../../tasks/providers/task_service_provider.dart';
import '../../tasks/providers/tasks_provider.dart';

bool _sameResolvedPath(String a, String b) {
  final na = path.normalize(a);
  final nb = path.normalize(b);
  if (Platform.isWindows) {
    return na.toLowerCase() == nb.toLowerCase();
  }
  return na == nb;
}

/// Έλεγχος διαδρομής μετά το σύστημα «Αποθήκευση ως».
String? validateNewDatabaseSavePath(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return 'Δεν επιλέχθηκε διαδρομή αρχείου.';
  }
  final name = path.basename(trimmed);
  if (name.isEmpty) {
    return 'Εισάγετε όνομα αρχείου.';
  }
  if (!name.toLowerCase().endsWith('.db')) {
    return 'Το όνομα αρχείου πρέπει να τελειώνει σε .db';
  }
  if (name.contains(RegExp(r'[/\\]'))) {
    return 'Το όνομα αρχείου δεν πρέπει να περιέχει διαχωριστικά διαδρομής.';
  }
  return null;
}

/// Native «Αποθήκευση ως» (φάκελος + όνομα + `.db` σε ένα βήμα).
Future<String?> pickSqliteDatabaseSavePath({
  String? initialPathHint,
  String dialogTitle = 'Δημιουργία νέου αρχείου βάσης',
  String defaultSuggestedFileName = 'call_logger.db',
}) async {
  final session = await FilePickerSession.run(
    () => _pickSqliteDatabaseSavePathImpl(
      initialPathHint: initialPathHint,
      dialogTitle: dialogTitle,
      defaultSuggestedFileName: defaultSuggestedFileName,
    ),
  );
  if (session.refocusedExisting) return null;
  return session.value;
}

Future<String?> _pickSqliteDatabaseSavePathImpl({
  String? initialPathHint,
  required String dialogTitle,
  required String defaultSuggestedFileName,
}) async {
  final hint = initialPathHint?.trim();
  final initialDir = initialDirectoryForFilePicker(hint);
  var suggested = defaultSuggestedFileName;
  if (hint != null && hint.isNotEmpty) {
    final base = path.basename(hint);
    if (base.toLowerCase().endsWith('.db') && !base.contains(RegExp(r'[/\\]'))) {
      suggested = base;
    }
  }

  final String? picked;
  if (Platform.isWindows) {
    picked = await showWindowsSaveSqliteDatabasePath(
      dialogTitle: dialogTitle,
      fileName: suggested,
      initialDirectory: initialDir,
    );
  } else {
    picked = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: suggested,
      initialDirectory: initialDir,
      type: FileType.custom,
      allowedExtensions: const ['db'],
      bytes: Uint8List(0),
    );
  }
  if (picked == null || picked.trim().isEmpty) return null;

  return path.normalize(path.absolute(picked.trim()));
}

/// Συντομογραφία για τη ροή δημιουργίας νέας βάσης Call Logger.
Future<String?> pickNewDatabaseSavePath({String? initialPathHint}) =>
    pickSqliteDatabaseSavePath(initialPathHint: initialPathHint);

Future<void> showNewDatabasePathValidationDialog(
  BuildContext context,
  String message,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Μη έγκυρη διαδρομή'),
      content: Text(message, style: Theme.of(ctx).textTheme.bodyMedium),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Εντάξει'),
        ),
      ],
    ),
  );
}

/// Κοινή ροή: μετονομασία πάντα της τρέχουσας βάσης (`{όνομα}_old_YYYY-MM-DD.db`), νέο κενό αρχείο,
/// επανασύνδεση μέσω [onDatabaseReopened]. **Δεν** διαγράφεται η παλιά βάση.
class CreateNewDatabaseFlow {
  CreateNewDatabaseFlow._();

  static void _invalidateCaches(WidgetRef ref) {
    ref.invalidate(databaseBrowserStatsProvider);
    ref.invalidate(lookupServiceProvider);
    ref.invalidate(tasksProvider);
    ref.invalidate(totalTasksCountProvider);
    ref.invalidate(orphanCallsProvider);
    ref.read(taskServiceProvider).resetSnoozeHistoryColumnCache();
  }

  /// [onDatabaseReopened]: π.χ. `MainShell` / `AppShortcuts` → [runDatabaseInitChecks].
  /// [onReloadSettingsState]: μόνο από Ρυθμίσεις (ανανέωση τοπικού state διαδρομής).
  /// [onFlowSuccessCloseParent]: π.χ. κλείσιμο διαλόγου συντήρησης.
  static Future<void> run(
    BuildContext context,
    WidgetRef ref, {
    Future<void> Function()? onDatabaseReopened,
    Future<void> Function()? onReloadSettingsState,
    VoidCallback? onFlowSuccessCloseParent,
    bool showSuccessSnackBar = true,
  }) async {
    String? currentDb;
    try {
      currentDb = (await DatabaseHelper.instance.database).path;
    } catch (_) {}

    final picked = await pickNewDatabaseSavePath(initialPathHint: currentDb);
    if (picked == null || !context.mounted) return;

    final validationError = validateNewDatabaseSavePath(picked);
    if (validationError != null) {
      if (!context.mounted) return;
      await showNewDatabasePathValidationDialog(context, validationError);
      return;
    }

    final norm = picked;

    final exists = await File(norm).exists();
    if (!context.mounted) return;

    String? currentDbForCompare;
    try {
      currentDbForCompare = (await DatabaseHelper.instance.database).path;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Δεν ήταν δυνατή η ανάγνωση της τρέχουσας βάσης.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    if (exists && !_sameResolvedPath(norm, currentDbForCompare)) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Υπάρχον αρχείο στον στόχο'),
          content: Text(
            'Στη διαδρομή:\n\n$norm\n\nυπάρχει ήδη αρχείο. '
            'Δεν διαγράφουμε υπάρχοντα αρχεία· μετακινήστε ή μετονομάστε το χειροκίνητα.',
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Εντάξει'),
            ),
          ],
        ),
      );
      return;
    }

    if (!exists) {
      if (!context.mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Δημιουργία νέου αρχείου βάσης'),
          content: Text(
            'Θα δημιουργηθεί νέο κενό αρχείο στη διαδρομή:\n\n$norm\n\n'
            'Η τρέχουσα βάση θα μετονομαστεί στον φάκελό της ως '
            '«όνομα_αρχείου_old_ημερομηνία» (χωρίς διαγραφή) και θα οριστεί ως ενεργή η νέα διαδρομή. '
            'Η εφαρμογή θα επανασυνδεθεί με τη νέα βάση.',
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Ακύρωση'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Δημιουργία'),
            ),
          ],
        ),
      );
      if (confirm != true || !context.mounted) return;
    } else {
      if (!context.mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Νέο κενό αρχείο στη θέση της τρέχουσας βάσης'),
          content: Text(
            'Το τρέχον αρχείο θα μετονομαστεί ως «όνομα_old_ημερομηνία» στον ίδιο φάκελο '
            'και θα δημιουργηθεί νέο κενό στη θέση:\n\n$norm',
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Ακύρωση'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Συνέχεια'),
            ),
          ],
        ),
      );
      if (confirm != true || !context.mounted) return;
    }

    final maintenance = ref.read(databaseMaintenanceServiceProvider);
    final result = await maintenance.createNewDatabaseAtChosenPath(norm);

    if (!context.mounted) return;

    if (result.success) {
      _invalidateCaches(ref);
      await onDatabaseReopened?.call();
      ref.invalidate(appInitProvider);
      await onReloadSettingsState?.call();
      onFlowSuccessCloseParent?.call();
      if (showSuccessSnackBar && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Η νέα βάση δημιουργήθηκε και η εφαρμογή επανασυνδέθηκε.',
            ),
          ),
        );
      }
      return;
    }

    if (result.renameFailedFilePath != null) {
      await showDatabaseRenameFailureDialog(context, result);
      _invalidateCaches(ref);
      await onDatabaseReopened?.call();
      ref.invalidate(appInitProvider);
      await onReloadSettingsState?.call();
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Αποτυχία.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
    _invalidateCaches(ref);
    await onDatabaseReopened?.call();
    ref.invalidate(appInitProvider);
    await onReloadSettingsState?.call();
  }
}
