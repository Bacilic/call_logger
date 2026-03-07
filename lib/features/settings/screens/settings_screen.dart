import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../../../core/config/app_config.dart';
import '../../../core/services/settings_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadCurrentPath();
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
      if (mounted) {
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
          ],
        ),
      ),
    );
  }
}
