import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../../../core/config/app_config.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/services/settings_service.dart';
import '../../directory/providers/directory_provider.dart';

/// Οθόνη ρυθμίσεων: διαδρομή βάσης δεδομένων και άλλες επιλογές.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final SettingsService _settings = SettingsService();

  String _currentPath = '';
  List<String> _recentPaths = [];
  bool _currentPathExists = false;
  String? _selectedNewPath;
  bool _isLoadingPath = true;
  String? _errorMessage;
  bool _showImportExcelButton = false;

  final TextEditingController _vncPathsController = TextEditingController();
  final TextEditingController _vncPasswordController = TextEditingController();
  final TextEditingController _anydeskPathController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCurrentPath();
  }

  @override
  void dispose() {
    _vncPathsController.dispose();
    _vncPasswordController.dispose();
    _anydeskPathController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentPath() async {
    setState(() {
      _isLoadingPath = true;
      _errorMessage = null;
    });
    try {
      final p = await _settings.getDatabasePath();
      final recent = await _settings.getRecentDatabasePaths();
      bool exists = false;
      if (p.trim().isNotEmpty) {
        try {
          exists = await File(p).exists();
        } catch (_) {
          exists = false;
        }
      }
      var paths = List<String>.from(recent);
      if (!paths.contains(p)) {
        paths.insert(0, p);
        paths = paths.take(3).toList();
      }
      final showImport = await _settings.getShowImportExcelButton();
      final vncPaths = await _settings.getVncPaths();
      final vncPassword = await _settings.getVncPassword();
      final anydeskPath = await _settings.getAnydeskPath();
      if (mounted) {
        _vncPathsController.text = vncPaths.join('\n');
        _vncPasswordController.text = vncPassword;
        _anydeskPathController.text = anydeskPath;
        setState(() {
          _currentPath = p;
          _recentPaths = paths;
          _currentPathExists = exists;
          _showImportExcelButton = showImport;
          _isLoadingPath = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Σφάλμα ανάγνωσης διαδρομής: $e';
          _isLoadingPath = false;
        });
      }
    }
  }

  /// Επιλογή αρχείου .db (προτίμηση) ή φακέλου.
  Future<void> _pickDatabasePath() async {
    setState(() {
      _errorMessage = null;
      _selectedNewPath = null;
    });

    // Πρώτα προσπάθεια επιλογής αρχείου .db
    final fileResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
      dialogTitle: 'Επιλογή αρχείου βάσης δεδομένων (.db)',
    );

    if (fileResult != null &&
        fileResult.files.isNotEmpty &&
        fileResult.files.single.path != null) {
      final p = fileResult.files.single.path!;
      if (mounted) {
        setState(() => _selectedNewPath = p);
      }
      return;
    }

    // Εναλλακτικά: επιλογή φακέλου (θα χρησιμοποιηθεί call_logger.db μέσα)
    final dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Επιλογή φακέλου βάσης δεδομένων',
    );

    if (dirPath != null && dirPath.trim().isNotEmpty) {
      final fullDbPath = path.join(dirPath, 'call_logger.db');
      if (mounted) {
        setState(() => _selectedNewPath = fullDbPath);
      }
    } else {
      if (mounted) {
        setState(() => _errorMessage = 'Δεν επιλέχθηκε αρχείο ή φάκελος.');
      }
    }
  }

  Future<void> _showCreateNewDatabaseDialog() async {
    setState(() => _errorMessage = null);
    final fullPath = await showDialog<String>(
      context: context,
      builder: (ctx) => const _CreateNewDatabaseDialog(),
    );
    if (fullPath == null || !mounted) return;

    final file = File(fullPath);
    final exists = await file.exists();

    if (exists) {
      if (!mounted) return;
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Υπάρχον αρχείο'),
          content: const Text(
            'Στη διαδρομή που επιλέξατε υπάρχει ήδη αρχείο. Αν συνεχίσετε, θα δημιουργηθεί νέα κενή βάση και το υπάρχον αρχείο θα αντικατασταθεί. Όλα τα δεδομένα του υπάρχοντος αρχείου θα χαθούν οριστικά.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Ακύρωση'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Αντικατάσταση'),
            ),
          ],
        ),
      );
      if (overwrite != true || !mounted) return;
      try {
        await file.delete();
      } catch (e) {
        if (mounted) {
          setState(() => _errorMessage = 'Δεν ήταν δυνατή η αντικατάσταση: $e');
        }
        return;
      }
    } else {
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Δημιουργία νέου αρχείου βάσης'),
          content: Text(
            'Θα δημιουργηθεί νέο κενό αρχείο βάσης στη διαδρομή:\n\n$fullPath\n\nΗ νέα διαδρομή θα οριστεί ως ενεργή και θα ισχύσει μετά την επανεκκίνηση της εφαρμογής.',
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
      if (confirm != true || !mounted) return;
    }

    try {
      await DatabaseHelper.instance.createNewDatabaseFile(fullPath);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage =
            'Δεν ήταν δυνατή η δημιουργία του αρχείου. Ελέγξτε δικαιώματα και ότι η διαδρομή είναι έγκυρη.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Σφάλμα: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    try {
      await _settings.setDatabasePath(fullPath);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Σφάλμα αποθήκευσης ρύθμισης: $e');
      }
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Ρυθμίσεις αποθηκεύτηκαν'),
        content: const Text(
          'Το νέο αρχείο βάσης δημιουργήθηκε. Η νέα διαδρομή θα ισχύσει στην επόμενη εκκίνηση της εφαρμογής. Παρακαλώ κλείστε την εφαρμογή χειροκίνητα (π.χ. Alt+F4 ή κουμπί κλεισίματος) και ανοίξτε την ξανά.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Εντάξει'),
          ),
        ],
      ),
    );
    setState(() {
      _currentPath = fullPath;
      _selectedNewPath = null;
      _errorMessage = null;
    });
    await _loadCurrentPath();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Το νέο αρχείο βάσης δημιουργήθηκε. Κλείστε και ξανανοίξτε την εφαρμογή.')),
    );
  }

  Future<void> _saveSettings() async {
    final newPath = _selectedNewPath?.trim();
    if (newPath == null || newPath.isEmpty) {
      setState(() => _errorMessage = 'Επιλέξτε πρώτα νέα διαδρομή.');
      return;
    }

    if (!newPath.toLowerCase().endsWith('.db')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Προειδοποίηση: η διαδρομή δεν τελειώνει σε .db. Βεβαιωθείτε ότι δείχνει σε αρχείο βάσης δεδομένων.',
            ),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    }

    final newFile = File(newPath);
    try {
      final parentExists = await newFile.parent.exists();
      if (!parentExists && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Προειδοποίηση: ο φάκελος δεν υπάρχει. Η διαδρομή θα αποθηκευτεί αλλά η βάση θα δημιουργηθεί στην πρώτη εκκίνηση.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (_) {}

    try {
      await _settings.setDatabasePath(newPath);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Σφάλμα αποθήκευσης: $e');
      }
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Ρυθμίσεις αποθηκεύτηκαν'),
        content: const Text(
          'Η νέα διαδρομή θα ισχύσει στην επόμενη εκκίνηση της εφαρμογής.\n\n'
          'Παρακαλώ κλείστε την εφαρμογή χειροκίνητα (Alt+F4 ή κουμπί κλεισίματος) και ανοίξτε την ξανά.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Εντάξει'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    setState(() {
      _currentPath = newPath;
      _selectedNewPath = null;
      _errorMessage = null;
    });
    await _loadCurrentPath();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Η διαδρομή αποθηκεύτηκε επιτυχώς')),
    );
  }

  /// Αποθήκευση ρυθμίσεων VNC/AnyDesk από τα πεδία στη βάση (app_settings).
  Future<void> _saveRemoteConnectionSettings() async {
    try {
      final vncPathsText = _vncPathsController.text;
      final paths = vncPathsText
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      await _settings.setVncPaths(paths);
      await _settings.setVncPassword(_vncPasswordController.text);
      await _settings.setAnydeskPath(_anydeskPathController.text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Σφάλμα αποθήκευσης: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Οι ρυθμίσεις απομακρυσμένης σύνδεσης αποθηκεύτηκαν.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ρυθμίσεις'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Διαδρομή βάσης δεδομένων',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (_isLoadingPath)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outline
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _recentPaths.contains(_currentPath)
                              ? _currentPath
                              : _recentPaths.isNotEmpty
                                  ? _recentPaths.first
                                  : _currentPath,
                          isExpanded: true,
                          items: _recentPaths.map((path) {
                            final isDefault = path == AppConfig.defaultDbPath;
                            return DropdownMenuItem<String>(
                              value: path,
                              child: Text(
                                path.isEmpty
                                    ? '(προεπιλογή)'
                                    : isDefault
                                        ? '$path (προεπιλογή)'
                                        : path,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (String? value) async {
                            if (value == null || value == _currentPath) return;
                            await _settings.setDatabasePath(value);
                            await _loadCurrentPath();
                          },
                        ),
                      ),
                    ),
                  ),
                  if (_currentPath.isNotEmpty && !_currentPathExists) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Δεν υπάρχει αυτή η βάση δεδομένων.',
                      child: Icon(
                        Icons.error,
                        color: theme.colorScheme.error,
                        size: 28,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Tooltip(
                    message:
                        'Επιλέξτε τη διαδρομή που είναι η βάση δεδομένων.',
                    child: IconButton.filled(
                      onPressed: _pickDatabasePath,
                      icon: const Icon(Icons.storage),
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            if (_selectedNewPath != null) ...[
              const SizedBox(height: 20),
              Text(
                'Νέα διαδρομή (προεπισκόπηση)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
                child: SelectableText(
                  _selectedNewPath!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saveSettings,
                icon: const Icon(Icons.save),
                label: const Text('Αποθήκευση ρύθμισης'),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            Text(
              'Δημιουργία νέου αρχείου βάσης',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Δημιουργεί νέο κενό αρχείο βάσης και το ορίζει ως ενεργό. Η τρέχουσα διαδρομή στις ρυθμίσεις θα αντικατασταθεί.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _showCreateNewDatabaseDialog,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Δημιουργία νέου αρχείου βάσης'),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Ρυθμίσεις Απομακρυσμένης Σύνδεσης (VNC & AnyDesk)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _vncPathsController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Διαδρομές VNC (Μία ανά γραμμή)',
                hintText: 'π.χ. C:\\Program Files\\TightVNC\\tvnviewer.exe',
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _vncPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Κωδικός VNC',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _anydeskPathController,
              decoration: const InputDecoration(
                labelText: 'Διαδρομή AnyDesk.exe',
                hintText: 'π.χ. C:\\Program Files (x86)\\AnyDesk\\AnyDesk.exe',
                border: OutlineInputBorder(),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _saveRemoteConnectionSettings,
              icon: const Icon(Icons.save),
              label: const Text('Αποθήκευση ρυθμίσεων απομακρυσμένης σύνδεσης'),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Άλλες επιλογές',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _showImportExcelButton,
              onChanged: (value) async {
                await _settings.setShowImportExcelButton(value);
                if (mounted) setState(() => _showImportExcelButton = value);
              },
              title: const Text('Εμφάνιση κουμπιού Import Excel'),
              subtitle: const Text(
                'Ενεργοποίηση για να εμφανίζεται το κουμπί εισαγωγής Excel στην κύρια οθόνη.',
              ),
            ),
            SwitchListTile(
              value: ref.watch(catalogContinuousScrollProvider).value ?? true,
              onChanged: (bool val) async {
                await DatabaseHelper.instance.setSetting(
                  'catalog_continuous_scroll',
                  val.toString(),
                );
                ref.invalidate(catalogContinuousScrollProvider);
              },
              title: const Text('Συνεχής κύλιση πίνακα Καταλόγου'),
              subtitle: const Text(
                'Mouse wheel γραμμή-γραμμή αντί για αλλαγή σελίδας.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Διάλογος επιλογής φακέλου και ονόματος αρχείου για δημιουργία νέου .db.
class _CreateNewDatabaseDialog extends StatefulWidget {
  const _CreateNewDatabaseDialog();

  @override
  State<_CreateNewDatabaseDialog> createState() => _CreateNewDatabaseDialogState();
}

class _CreateNewDatabaseDialogState extends State<_CreateNewDatabaseDialog> {
  String? _selectedFolder;
  final TextEditingController _filenameController = TextEditingController(text: 'call_logger.db');
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
      setState(() => _validationError = 'Το όνομα αρχείου πρέπει να τελειώνει σε .db');
      return;
    }
    if (name.contains(RegExp(r'[/\\]'))) {
      setState(() => _validationError = 'Το όνομα αρχείου δεν πρέπει να περιέχει διαχωριστικά διαδρομής.');
      return;
    }
    final fullPath = path.join(folder, name);
    Navigator.of(context).pop(fullPath);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                      color: _selectedFolder != null
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
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
          onPressed: _submit,
          child: const Text('Δημιουργία'),
        ),
      ],
    );
  }
}
