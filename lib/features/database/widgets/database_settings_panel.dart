import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/database/database_init_runner.dart';
import '../../../core/database/database_path_pick_flow.dart';
import '../../../core/init/app_init_provider.dart';
import '../../../core/services/settings_service.dart';
import '../../settings/widgets/create_new_database_dialog.dart';
import '../models/database_backup_settings.dart';
import '../providers/database_backup_settings_provider.dart';
import '../services/database_backup_service.dart';
import '../utils/backup_destination_folder_validator.dart';
import '../utils/backup_destination_location_warnings.dart';
import '../utils/backup_location_hints.dart';
import '../utils/backup_schedule_utils.dart';

String _weekdayChipLabel(int weekday) {
  const labels = ['Δε', 'Τρ', 'Τε', 'Πε', 'Πα', 'Σα', 'Κυ'];
  return labels[weekday - 1];
}

/// Πάνελ ρυθμίσεων βάσης δεδομένων: αρχείο βάσης, δημιουργία νέου `.db`, αντίγραφα ασφαλείας.
class DatabaseSettingsPanel extends ConsumerStatefulWidget {
  const DatabaseSettingsPanel({
    super.key,
    this.onDatabaseLifecycleChanged,
  });

  /// Μετά από επιτυχή αλλαγή διαδρομής (επαλήθευση) ή δημιουργία νέου αρχείου βάσης.
  final Future<void> Function()? onDatabaseLifecycleChanged;

  @override
  ConsumerState<DatabaseSettingsPanel> createState() =>
      _DatabaseSettingsPanelState();
}

class _DatabaseSettingsPanelState extends ConsumerState<DatabaseSettingsPanel> {
  final SettingsService _settings = SettingsService();

  late final TextEditingController _destinationController;
  late final TextEditingController _maxCopiesController;
  late final TextEditingController _maxAgeController;
  late final ScrollController _panelScrollController;
  Future<List<BackupCaptionSegment>> _locationCaptionSegmentsFuture =
      Future.value(const <BackupCaptionSegment>[]);
  Future<({String dbPath, int eligibleWindowsVolumeCount})>
      _backupDestinationWarningContextFuture = Future.value(
    (dbPath: '', eligibleWindowsVolumeCount: 0),
  );

  String _currentDbPath = '';
  List<String> _recentDbPaths = [];
  bool _currentDbPathExists = false;
  String? _selectedNewDbPath;
  bool _isLoadingDbPath = true;
  String? _dbPathErrorMessage;

  final FocusNode _destinationFocus = FocusNode();
  final FocusNode _maxCopiesFocus = FocusNode();
  final FocusNode _maxAgeFocus = FocusNode();
  String? _destinationFolderError;
  int _destinationValidationGen = 0;

  @override
  void initState() {
    super.initState();
    _destinationController = TextEditingController();
    _maxCopiesController = TextEditingController();
    _maxAgeController = TextEditingController();
    _panelScrollController = ScrollController();
    _reloadLocationAndWarningFutures();
    _destinationFocus.addListener(_onDestinationFocusChanged);
    _destinationController.addListener(_onDestinationTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncControllersFromState(
        ref.read(databaseBackupSettingsProvider),
        syncDestination: true,
        syncRetentionMaxCopies: true,
        syncRetentionMaxAgeDays: true,
      );
    });
    unawaited(_loadDatabasePathSection());
  }

  void _reloadLocationAndWarningFutures() {
    _locationCaptionSegmentsFuture = _loadLocationCaptionSegments();
    _backupDestinationWarningContextFuture =
        _loadBackupDestinationWarningContext();
  }

  Future<void> _loadDatabasePathSection() async {
    setState(() {
      _isLoadingDbPath = true;
      _dbPathErrorMessage = null;
    });
    try {
      final p = await _settings.getDatabasePath();
      final recent = await _settings.getRecentDatabasePaths();
      var exists = false;
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
      if (mounted) {
        setState(() {
          _currentDbPath = p;
          _recentDbPaths = paths;
          _currentDbPathExists = exists;
          _isLoadingDbPath = false;
          _locationCaptionSegmentsFuture = _loadLocationCaptionSegments();
          _backupDestinationWarningContextFuture =
              _loadBackupDestinationWarningContext();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _dbPathErrorMessage = 'Σφάλμα ανάγνωσης διαδρομής: $e';
          _isLoadingDbPath = false;
        });
      }
    }
  }

  Future<void> _pickDatabasePath() async {
    setState(() {
      _dbPathErrorMessage = null;
      _selectedNewDbPath = null;
    });

    final picked = await pickDatabasePathWithSystemPicker();
    if (picked != null && picked.isNotEmpty) {
      await _validateApplyAndFinishPick(picked);
    } else {
      if (mounted) {
        setState(() => _dbPathErrorMessage = 'Δεν επιλέχθηκε αρχείο ή φάκελος.');
      }
    }
  }

  Future<void> _validateApplyAndFinishPick(String newPath) async {
    final trimmed = newPath.trim();
    if (trimmed.isEmpty || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              height: 48,
              width: 48,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 24),
            Expanded(
              child: Text(
                'Έλεγχος βάσης δεδομένων…',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );

    late ({bool ok, DatabaseInitRunnerResult runner}) outcome;
    try {
      outcome = await setAndVerifyDatabasePath(trimmed);
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!mounted) return;

    if (!outcome.ok) {
      final msg =
          outcome.runner.result.message ?? 'Η βάση δεν πέρασε τον έλεγχο.';
      final det = outcome.runner.result.details?.trim();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Η βάση δεν είναι έγκυρη'),
          content: SingleChildScrollView(
            child: Text(det != null && det.isNotEmpty ? '$msg\n\n$det' : msg),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Εντάξει'),
            ),
          ],
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Βάση έτοιμη'),
        content: const Text(
          'Η διαδρομή αποθηκεύτηκε και η βάση επαληθεύτηκε.\n\n'
          'Για πλήρη εφαρμογή αλλαγών, κλείστε την εφαρμογή (π.χ. Alt+F4) και ανοίξτε την ξανά.',
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
      _currentDbPath = trimmed;
      _selectedNewDbPath = null;
      _dbPathErrorMessage = null;
    });
    await _loadDatabasePathSection();

    if (!mounted) return;
    ref.invalidate(appInitProvider);
    await widget.onDatabaseLifecycleChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Η νέα βάση ορίστηκε και επαληθεύτηκε.')),
      );
    }
  }

  Future<void> _saveNewDatabasePathSetting() async {
    final newPath = _selectedNewDbPath?.trim();
    if (newPath == null || newPath.isEmpty) {
      setState(() => _dbPathErrorMessage = 'Επιλέξτε πρώτα νέα διαδρομή.');
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
            content: Text(
              'Προειδοποίηση: ο φάκελος δεν υπάρχει. Η διαδρομή θα αποθηκευτεί αλλά η βάση θα δημιουργηθεί στην πρώτη εκκίνηση.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (_) {}

    try {
      await _settings.setDatabasePath(newPath);
    } catch (e) {
      if (mounted) {
        setState(() => _dbPathErrorMessage = 'Σφάλμα αποθήκευσης: $e');
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
      _currentDbPath = newPath;
      _selectedNewDbPath = null;
      _dbPathErrorMessage = null;
    });
    await _loadDatabasePathSection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Η διαδρομή αποθηκεύτηκε επιτυχώς')),
    );
  }

  Future<void> _runCreateNewDatabaseFlow() async {
    setState(() => _dbPathErrorMessage = null);
    await CreateNewDatabaseFlow.run(
      context,
      ref,
      onDatabaseReopened: widget.onDatabaseLifecycleChanged,
      onReloadSettingsState: () async {
        if (!mounted) return;
        await _loadDatabasePathSection();
        if (!mounted) return;
        setState(() {
          _selectedNewDbPath = null;
          _dbPathErrorMessage = null;
        });
      },
    );
  }

  List<Widget> _buildDatabaseFilePathSection(ThemeData theme) {
    return [
      Text(
        'Διαδρομή βάσης δεδομένων',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      if (_isLoadingDbPath)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()),
        )
      else
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _recentDbPaths.contains(_currentDbPath)
                        ? _currentDbPath
                        : _recentDbPaths.isNotEmpty
                            ? _recentDbPaths.first
                            : _currentDbPath,
                    isExpanded: true,
                    items: _recentDbPaths.map((path) {
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
                      if (value == null || value == _currentDbPath) return;
                      await _settings.setDatabasePath(value);
                      await _loadDatabasePathSection();
                    },
                  ),
                ),
              ),
            ),
            if (_currentDbPath.isNotEmpty && !_currentDbPathExists) ...[
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
              message: 'Επιλέξτε τη διαδρομή που είναι η βάση δεδομένων.',
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
      if (_selectedNewDbPath != null) ...[
        const SizedBox(height: 16),
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
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
          child: SelectableText(
            _selectedNewDbPath!,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saveNewDatabasePathSetting,
          icon: const Icon(Icons.save),
          label: const Text('Αποθήκευση ρύθμισης'),
        ),
      ],
      if (_dbPathErrorMessage != null) ...[
        const SizedBox(height: 12),
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
                  _dbPathErrorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text(
        'Δημιουργία νέου αρχείου βάσης',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Η τρέχουσα βάση μετονομάζεται πάντα ως «όνομα_old_ημερομηνία» στον φάκελό της (χωρίς διαγραφή). '
        'Δημιουργείται νέο κενό αρχείο και ορίζεται ενεργό· επανασύνδεση χωρίς επανεκκίνηση.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      FilledButton.tonalIcon(
        onPressed: _currentDbPath.trim().isEmpty
            ? null
            : _runCreateNewDatabaseFlow,
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('Δημιουργία νέου αρχείου βάσης'),
      ),
      const SizedBox(height: 16),
      const Divider(height: 1),
      const SizedBox(height: 12),
    ];
  }

  @override
  void dispose() {
    _destinationFocus.removeListener(_onDestinationFocusChanged);
    _destinationController.removeListener(_onDestinationTextChanged);
    _destinationFocus.dispose();
    _destinationController.dispose();
    _maxCopiesController.dispose();
    _maxAgeController.dispose();
    _panelScrollController.dispose();
    _maxCopiesFocus.dispose();
    _maxAgeFocus.dispose();
    super.dispose();
  }

  void _syncControllersFromState(
    DatabaseBackupSettings s, {
    bool syncDestination = true,
    bool syncRetentionMaxCopies = true,
    bool syncRetentionMaxAgeDays = true,
  }) {
    if (syncDestination &&
        !_destinationFocus.hasFocus &&
        _destinationController.text != s.destinationDirectory) {
      _destinationController.text = s.destinationDirectory;
    }
    final copiesStr = s.retentionMaxCopies.toString();
    if (syncRetentionMaxCopies &&
        !_maxCopiesFocus.hasFocus &&
        _maxCopiesController.text != copiesStr) {
      _maxCopiesController.text = copiesStr;
    }
    final ageStr = s.retentionMaxAgeDays.toString();
    if (syncRetentionMaxAgeDays &&
        !_maxAgeFocus.hasFocus &&
        _maxAgeController.text != ageStr) {
      _maxAgeController.text = ageStr;
    }
  }

  void _onDestinationFocusChanged() {
    if (!_destinationFocus.hasFocus) {
      unawaited(_validateAndPersistDestination());
    }
  }

  void _onDestinationTextChanged() {
    if (!mounted) return;
    setState(() {
      if (_destinationFolderError != null) {
        _destinationFolderError = null;
      }
    });
  }

  Future<void> _validateAndPersistDestination() async {
    final gen = ++_destinationValidationGen;
    final raw = _destinationController.text;
    final result = await BackupDestinationFolderValidator.validate(raw);
    if (!mounted || gen != _destinationValidationGen) return;
    if (result.kind == BackupDestinationValidationKind.ok) {
      setState(() => _destinationFolderError = null);
      await ref.read(databaseBackupSettingsProvider.notifier).setDestinationDirectory(
            raw.trim(),
          );
    } else {
      setState(() => _destinationFolderError = result.errorMessage);
    }
  }

  Future<void> _persistRetentionMaxCopies() async {
    final raw = _maxCopiesController.text.trim();
    if (raw.isEmpty) {
      final s = ref.read(databaseBackupSettingsProvider);
      _maxCopiesController.text = s.retentionMaxCopies.toString();
      return;
    }
    final n = int.tryParse(raw);
    if (n == null) return;
    await ref
        .read(databaseBackupSettingsProvider.notifier)
        .setRetentionMaxCopies(n);
  }

  Future<void> _persistRetentionMaxAgeDays() async {
    final raw = _maxAgeController.text.trim();
    if (raw.isEmpty) {
      final s = ref.read(databaseBackupSettingsProvider);
      _maxAgeController.text = s.retentionMaxAgeDays.toString();
      return;
    }
    final n = int.tryParse(raw);
    if (n == null) return;
    await ref
        .read(databaseBackupSettingsProvider.notifier)
        .setRetentionMaxAgeDays(n);
  }

  Future<List<BackupCaptionSegment>> _loadLocationCaptionSegments() async {
    final drives = BackupLocationHints.eligibleWindowsBackupDriveLabels();
    final dbPath = await _settings.getDatabasePath();
    return BackupLocationHints.composeLocationCaptionSegments(
      driveLabels: drives,
      configuredDatabasePath: dbPath,
    );
  }

  Future<({String dbPath, int eligibleWindowsVolumeCount})>
      _loadBackupDestinationWarningContext() async {
    final dbPath = await _settings.getDatabasePath();
    final eligibleWindowsVolumeCount =
        BackupLocationHints.eligibleWindowsBackupVolumeCount();
    return (
      dbPath: dbPath,
      eligibleWindowsVolumeCount: eligibleWindowsVolumeCount,
    );
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null || !mounted) return;
    setState(() => _destinationFolderError = null);
    _destinationController.text = path;
    await _validateAndPersistDestination();
  }

  Future<void> _runBackupNow() async {
    final settings = ref.read(databaseBackupSettingsProvider);
    final messenger = ScaffoldMessenger.of(context);
    final result = await DatabaseBackupService.runBackup(settings);
    if (!mounted) return;
    if (result.success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.outputPath != null
                ? 'Αντίγραφο: ${result.outputPath}'
                : (result.message ?? 'Επιτυχία'),
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Αποτυχία αντιγράφου'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(databaseBackupSettingsProvider);
    ref.listen(databaseBackupSettingsProvider, (prev, next) {
      if (prev == next) return;
      final syncDestination = prev == null ||
          prev.destinationDirectory != next.destinationDirectory;
      final syncRetentionMaxCopies = prev == null ||
          prev.retentionMaxCopies != next.retentionMaxCopies;
      final syncRetentionMaxAgeDays = prev == null ||
          prev.retentionMaxAgeDays != next.retentionMaxAgeDays;
      // Η ενημέρωση controller μέσα στο listen (συγχρονά) προκαλεί «Build scheduled during frame».
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (syncDestination && !_destinationFocus.hasFocus) {
          setState(() => _destinationFolderError = null);
        }
        _syncControllersFromState(
          ref.read(databaseBackupSettingsProvider),
          syncDestination: syncDestination,
          syncRetentionMaxCopies: syncRetentionMaxCopies,
          syncRetentionMaxAgeDays: syncRetentionMaxAgeDays,
        );
      });
    });

    final cWarning = settings.destinationLooksLikeWindowsSystemDriveC;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Scrollbar(
          controller: _panelScrollController,
          thumbVisibility: true,
          thickness: 6,
          radius: const Radius.circular(3),
          child: SingleChildScrollView(
            controller: _panelScrollController,
            // Κενό δεξιά ώστε η μπάρα να μην επικαλύπτει switches/dropdowns.
            padding: const EdgeInsetsDirectional.only(end: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            Row(
              children: [
                Icon(
                  Icons.settings_suggest_outlined,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Ρυθμίσεις βάσης δεδομένων',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._buildDatabaseFilePathSection(theme),
            Text(
              'Αντίγραφα ασφαλείας (SQLite VACUUM INTO — ατομικό, με WAL/SHM).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Αυτόματα αντίγραφα ασφαλείας'),
              subtitle: const Text(
                'Ενεργοποίηση\\Απενεργοποίηση Αυτόματων Αντιγράφων ασφαλείας της εφαρμογής.',
              ),
              value: settings.backupOnExit,
              onChanged: (v) => ref
                  .read(databaseBackupSettingsProvider.notifier)
                  .setBackupOnExit(v),
            ),
            if (!settings.backupOnExit) ...[
              const SizedBox(height: 8),
              Text(
                'Ενεργοποιήστε το διακόπτη για να εμφανιστούν όλες οι σχετικές ρυθμίσεις.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (settings.backupOnExit) ...[
            FutureBuilder<List<BackupCaptionSegment>>(
              future: _locationCaptionSegmentsFuture,
              builder: (context, snapshot) {
                final color = snapshot.hasError
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant;
                if (snapshot.hasError) {
                  return Text(
                    'Δεν ήταν δυνατή η φόρτωση υποδείξεων τοποθεσίας.',
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                  );
                }
                if (!snapshot.hasData) {
                  return Text(
                    'Φόρτωση υποδείξεων τοποθεσίας…',
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                  );
                }
                final baseStyle = theme.textTheme.bodySmall?.copyWith(
                  color: color,
                );
                return Text.rich(
                  TextSpan(
                    style: baseStyle,
                    children: [
                      for (final s in snapshot.data!)
                        TextSpan(
                          text: s.text,
                          style: s.bold
                              ? const TextStyle(fontWeight: FontWeight.bold)
                              : null,
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    focusNode: _destinationFocus,
                    controller: _destinationController,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      labelText: 'Φάκελος προορισμού',
                      floatingLabelBehavior: FloatingLabelBehavior.auto,
                      isDense: true,
                      errorText: _destinationFolderError,
                      errorMaxLines: 2,
                      errorStyle: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          width: 1,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          width: 1,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          width: 1,
                          color: theme.colorScheme.error,
                        ),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          width: 1,
                          color: theme.colorScheme.error,
                        ),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          width: 1,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                    maxLines: 1,
                    onEditingComplete: () =>
                        unawaited(_validateAndPersistDestination()),
                    onSubmitted: (_) =>
                        unawaited(_validateAndPersistDestination()),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 38,
                  child: FilledButton.tonalIcon(
                    onPressed: _pickFolder,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Αναζήτηση'),
                  ),
                ),
              ],
            ),
            FutureBuilder<({String dbPath, int eligibleWindowsVolumeCount})>(
              future: _backupDestinationWarningContextFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox.shrink();
                }
                final dest = _destinationController.text.trim();
                if (dest.isEmpty || _destinationFolderError != null) {
                  return const SizedBox.shrink();
                }
                final ctx = snapshot.data!;
                final colocated =
                    BackupDestinationLocationWarnings.colocatedWithDatabase(
                  databaseFilePath: ctx.dbPath,
                  destinationDirectory: dest,
                );
                final sameVolume =
                    BackupDestinationLocationWarnings.sameWindowsVolume(
                  databasePath: ctx.dbPath,
                  destinationDirectory: dest,
                );
                final showSameVolume =
                    sameVolume && ctx.eligibleWindowsVolumeCount >= 2;
                if (!colocated && !showSameVolume) {
                  return const SizedBox.shrink();
                }
                final orange = Colors.deepOrange.shade800;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (colocated) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 20,
                            color: orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ο φάκελος προορισμού του αντιγράφου ασφαλείας '
                              '(backup) βρίσκεται στον ίδιο χώρο με τα αρχεία '
                              'της βάσης (ίδιος φάκελος ή υποφάκελός του). Σε '
                              'απώλεια, διαγραφή ή βλάβη του μέσου ενδέχεται '
                              'να χαθούν μαζί τα δεδομένα και το αντίγραφο.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: orange,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (showSameVolume) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 20,
                            color: orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Το αντίγραφο αποθηκεύεται στον ίδιο τόμο '
                              '(volume) με τη βάση. Σε βλάβη δίσκου '
                              'ενδέχεται να επηρεαστούν και τα δύο.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: orange,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
            if (cWarning) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ο φάκελος είναι στον τόμο C: (συστήματος). '
                      'Σε βλάβη δίσκου ή επανεγκατάσταση Windows το αντίγραφο μπορεί να χαθεί μαζί με τα δεδομένα.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<DatabaseBackupNamingFormat>(
              key: ValueKey(settings.namingFormat),
              initialValue: settings.namingFormat,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Μορφή ονόματος αρχείου',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: DatabaseBackupNamingFormat.dateTimeThenBase,
                  child: Text('Ημερομηνία-Ώρα_Όνομα βάσης (.db)'),
                ),
                DropdownMenuItem(
                  value: DatabaseBackupNamingFormat.baseThenDateTime,
                  child: Text('Όνομα βάσης_Ημερομηνία-Ώρα (.db)'),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                ref
                    .read(databaseBackupSettingsProvider.notifier)
                    .setNamingFormat(v);
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Αποθήκευση σε μορφή .zip'),
              subtitle: const Text('Συμπίεση μετά το VACUUM INTO'),
              value: settings.zipOutput,
              onChanged: (v) => ref
                  .read(databaseBackupSettingsProvider.notifier)
                  .setZipOutput(v),
            ),
            const Divider(height: 24),
            const SizedBox(height: 12),
            Text(
              'Πρόγραμμα ημερών & ώρας',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Επιλέξτε ημέρες και ώρα για αυτόματο αντίγραφο ασφαλείας όσο η εφαρμογή είναι ανοιχτή.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < 7; i++)
                  FilterChip(
                    label: Text(_weekdayChipLabel(i + 1)),
                    selected: settings.backupDays.contains(i + 1),
                    onSelected: settings.backupOnExit
                        ? (selected) {
                            final wd = i + 1;
                            final next = List<int>.from(settings.backupDays);
                            if (selected) {
                              if (!next.contains(wd)) next.add(wd);
                            } else {
                              next.remove(wd);
                            }
                            unawaited(
                              ref
                                  .read(databaseBackupSettingsProvider.notifier)
                                  .setBackupScheduleDays(next),
                            );
                          }
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (settings.backupDays.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(
                  'Επιλέξτε τουλάχιστον μία ημέρα για τη λειτουργία των '
                  'προγραμματισμένων αντιγράφων ασφαλείας.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Προγραμματισμένη Ώρα:'),
                subtitle: Text(settings.backupTime),
                trailing: TextButton.icon(
                  onPressed: () async {
                    final p =
                        BackupScheduleUtils.parseTime(settings.backupTime);
                    final initial = TimeOfDay(
                      hour: p?.hour ?? 9,
                      minute: p?.minute ?? 0,
                    );
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: initial,
                    );
                    if (picked == null || !mounted) return;
                    final h = picked.hour.toString().padLeft(2, '0');
                    final m = picked.minute.toString().padLeft(2, '0');
                    await ref
                        .read(databaseBackupSettingsProvider.notifier)
                        .setBackupTime('$h:$m');
                  },
                  icon: const Icon(Icons.access_time, size: 20),
                  label: const Text('Επιλογή'),
                ),
              ),
            ],
            const Divider(height: 24),
            Text(
              'Πολιτική διατήρησης',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Διατήρηση μόνο των τελευταίων ',
                        style: theme.textTheme.bodyLarge,
                      ),
                      SizedBox(
                        width: 64,
                        child: TextField(
                          focusNode: _maxCopiesFocus,
                          controller: _maxCopiesController,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                          ),
                          onEditingComplete: _persistRetentionMaxCopies,
                          onSubmitted: (_) => _persistRetentionMaxCopies(),
                        ),
                      ),
                      Text(
                        ' αντιγράφων ασφαλείας',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: settings.retentionMaxCopiesEnabled,
                  onChanged: (v) => ref
                      .read(databaseBackupSettingsProvider.notifier)
                      .setRetentionMaxCopiesEnabled(v),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Text(
                'Διαγράφεται το παλαιότερο όταν ξεπεραστεί το όριο.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Διαγραφή αντιγράφων παλαιότερων από ',
                        style: theme.textTheme.bodyLarge,
                      ),
                      SizedBox(
                        width: 64,
                        child: TextField(
                          focusNode: _maxAgeFocus,
                          controller: _maxAgeController,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                          ),
                          onEditingComplete: _persistRetentionMaxAgeDays,
                          onSubmitted: (_) => _persistRetentionMaxAgeDays(),
                        ),
                      ),
                      Text(
                        ' ημέρες',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: settings.retentionMaxAgeEnabled,
                  onChanged: (v) => ref
                      .read(databaseBackupSettingsProvider.notifier)
                      .setRetentionMaxAgeEnabled(v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: settings.destinationDirectory.trim().isEmpty
                  ? null
                  : _runBackupNow,
              icon: const Icon(Icons.save_alt_outlined),
              label: const Text('Δημιουργία αντιγράφου τώρα'),
            ),
            ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}


