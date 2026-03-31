import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../../../core/database/database_helper.dart';
import '../../../core/init/app_init_provider.dart';
import '../../calls/provider/lookup_provider.dart';
import '../../database/providers/database_browser_stats_provider.dart';
import '../../database/providers/database_maintenance_provider.dart';
import '../../database/widgets/database_rename_failure_dialog.dart';
import '../../tasks/providers/tasks_provider.dart';

bool _sameResolvedPath(String a, String b) {
  final na = path.normalize(a);
  final nb = path.normalize(b);
  if (Platform.isWindows) {
    return na.toLowerCase() == nb.toLowerCase();
  }
  return na == nb;
}

/// Διάλογος επιλογής φακέλου και ονόματος αρχείου για δημιουργία νέου `.db`.
class CreateNewDatabaseDialog extends StatefulWidget {
  const CreateNewDatabaseDialog({super.key});

  @override
  State<CreateNewDatabaseDialog> createState() => _CreateNewDatabaseDialogState();
}

class _CreateNewDatabaseDialogState extends State<CreateNewDatabaseDialog> {
  String? _selectedFolder;
  final TextEditingController _filenameController =
      TextEditingController(text: 'call_logger.db');
  String? _validationError;

  @override
  void dispose() {
    _filenameController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Επιλογή φακέλου για νέο αρχείο βάσης',
    );
    if (dirPath != null && dirPath.trim().isNotEmpty && mounted) {
      setState(() {
        _selectedFolder = dirPath;
        _validationError = null;
      });
    }
  }

  void _submit() {
    final folder = _selectedFolder?.trim();
    final name = _filenameController.text.trim();
    if (folder == null || folder.isEmpty) {
      setState(() => _validationError = 'Επιλέξτε φάκελο.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _validationError = 'Εισάγετε όνομα αρχείου.');
      return;
    }
    if (!name.toLowerCase().endsWith('.db')) {
      setState(
        () => _validationError =
            'Το όνομα αρχείου πρέπει να τελειώνει σε .db',
      );
      return;
    }
    if (name.contains(RegExp(r'[/\\]'))) {
      setState(
        () => _validationError =
            'Το όνομα αρχείου δεν πρέπει να περιέχει διαχωριστικά διαδρομής.',
      );
      return;
    }
    final fullPath = path.join(folder, name);
    Navigator.of(context).pop(fullPath);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFolder = _selectedFolder?.trim().isNotEmpty ?? false;
    return AlertDialog(
      title: const Text('Δημιουργία νέου αρχείου βάσης'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Επιλέξτε φάκελο και δώστε όνομα αρχείου (π.χ. new_base.db).',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedFolder ?? 'Δεν έχει επιλεγεί φάκελος',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: hasFolder
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.error,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _pickFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Φάκελος'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _filenameController,
              decoration: const InputDecoration(
                labelText: 'Όνομα αρχείου',
                hintText: 'π.χ. new_base.db',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _validationError = null),
            ),
            if (_validationError != null) ...[
              const SizedBox(height: 8),
              Text(
                _validationError!,
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: hasFolder ? _submit : null,
          child: const Text('Δημιουργία'),
        ),
      ],
    );
  }
}

/// Κοινή ροή: μετονομασία πάντα της τρέχουσας βάσης (`{όνομα}_old_YYYY-MM-DD.db`), νέο κενό αρχείο,
/// επανασύνδεση μέσω [onDatabaseReopened]. **Δεν** διαγράφεται η παλιά βάση.
class CreateNewDatabaseFlow {
  CreateNewDatabaseFlow._();

  static void _invalidateCaches(WidgetRef ref) {
    ref.invalidate(databaseBrowserStatsProvider);
    ref.invalidate(lookupServiceProvider);
    ref.invalidate(tasksProvider);
    ref.invalidate(orphanCallsProvider);
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
    final fullPath = await showDialog<String>(
      context: context,
      builder: (ctx) => const CreateNewDatabaseDialog(),
    );
    if (fullPath == null || !context.mounted) return;

    final norm = path.normalize(path.absolute(fullPath.trim()));
    final exists = await File(norm).exists();
    String? currentDb;
    try {
      currentDb = (await DatabaseHelper.instance.database).path;
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

    if (exists && !_sameResolvedPath(norm, currentDb)) {
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
