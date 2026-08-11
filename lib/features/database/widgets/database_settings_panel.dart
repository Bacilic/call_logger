import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/app_config.dart';
import '../../../core/utils/file_picker_initial_directory.dart';
import '../../../core/utils/file_picker_session.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import '../../../core/providers/core_lexicon_provider.dart';
import '../../../core/database/database_file_bundle.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_init_runner.dart';
import '../../../core/database/database_path_pick_flow.dart';
import '../../../core/database/database_restore_flow.dart';
import '../../../core/init/database_switch_completion.dart';
import '../../../core/init/database_switch_guard.dart';
import '../../../core/providers/active_critical_operations_provider.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/new_database_suggested_file_name.dart';
import '../../../core/widgets/compact_tooltip.dart';
import '../../settings/widgets/create_new_database_dialog.dart';
import '../models/database_backup_settings.dart';
import '../providers/backup_scheduler_provider.dart';
import '../providers/database_backup_settings_provider.dart';
import '../providers/database_integrity_provider.dart';
import '../services/create_new_database_texts.dart';
import '../services/database_backup_audit.dart';
import '../services/database_backup_service.dart';
import '../services/database_path_switch_runner.dart';
import '../services/restore_plan.dart';
import 'backup_folder_missing_dialog.dart';
import '../utils/backup_destination_folder_validator.dart';
import '../utils/database_path_dropdown_options.dart';
import '../utils/backup_destination_location_warnings.dart';
import '../utils/backup_location_hints.dart';
import '../utils/backup_schedule_status.dart';
import '../utils/backup_schedule_utils.dart';
import '../utils/backup_restore_tooltip.dart';
import '../utils/portable_backup_availability.dart';
import 'database_check_failed_dialog.dart';
import 'database_integrity_panel.dart';
import 'database_rename_notice_text.dart';

String _weekdayChipLabel(int weekday) {
  const labels = ['Δε', 'Τρ', 'Τε', 'Πε', 'Πα', 'Σα', 'Κυ'];
  return labels[weekday - 1];
}

/// Tooltip δίπλα στον διακόπτη αυτόματων αντιγράφων ασφαλείας.
const _backupSafetyTooltipMessage =
    'Ασφαλές αντίγραφο χωρίς διακοπή λειτουργίας.\n\n'
    'VACUUM INTO (ατομικό): Ολόκληρο αντίγραφο με μία κίνηση — σε διακοπή '
    '(π.χ. ρεύμα) δεν μένει μισοκατεστραμμένο αρχείο.\n\n'
    'WAL / SHM: Γραφή στο παρασκήνιο· η εφαρμογή συνεχίζει κανονικά χωρίς '
    'να «παγώνει».';

/// Πάνελ ρυθμίσεων βάσης δεδομένων: αρχείο βάσης, δημιουργία νέου `.db`, αντίγραφα ασφαλείας.
class DatabaseSettingsPanel extends ConsumerStatefulWidget {
  const DatabaseSettingsPanel({super.key, this.onDatabaseLifecycleChanged});

  /// Μετά από επιτυχή αλλαγή διαδρομής (επαλήθευση) ή δημιουργία νέου αρχείου βάσης.
  final Future<void> Function()? onDatabaseLifecycleChanged;

  @override
  ConsumerState<DatabaseSettingsPanel> createState() =>
      _DatabaseSettingsPanelState();
}

class _DatabaseSettingsPanelState extends ConsumerState<DatabaseSettingsPanel>
    implements DatabasePathSwitchHooks {
  final SettingsService _settings = SettingsService();

  late final TextEditingController _destinationController;
  late final TextEditingController _maxCopiesController;
  late final TextEditingController _maxAgeController;
  late final ScrollController _panelScrollController;
  Future<List<BackupCaptionSegment>> _locationCaptionSegmentsFuture =
      Future.value(const <BackupCaptionSegment>[]);
  Future<({String dbPath, int eligibleWindowsVolumeCount})>
  _backupDestinationWarningContextFuture = Future.value((
    dbPath: '',
    eligibleWindowsVolumeCount: 0,
  ));
  Future<BackupDestinationContentResult> _destinationContentFuture =
      Future.value(
        const BackupDestinationContentResult(
          kind: BackupDestinationContentKind.folderMissing,
        ),
      );

  String _currentDbPath = '';
  List<String> _recentDbPaths = [];
  bool _currentDbPathExists = false;
  bool _isLoadingDbPath = true;
  String? _dbPathErrorMessage;

  final FocusNode _destinationFocus = FocusNode();
  final FocusNode _maxCopiesFocus = FocusNode();
  final FocusNode _maxAgeFocus = FocusNode();
  String? _destinationFolderError;
  int _destinationValidationGen = 0;
  Timer? _scheduleStatusRefreshTimer;

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
    _scheduleStatusRefreshTimer = Timer.periodic(const Duration(seconds: 30), (
      _,
    ) {
      if (!mounted) return;
      _reloadDestinationContentFuture();
      setState(() {});
    });
  }

  void _reloadLocationAndWarningFutures() {
    _locationCaptionSegmentsFuture = _loadLocationCaptionSegments();
    _backupDestinationWarningContextFuture =
        _loadBackupDestinationWarningContext();
    _reloadDestinationContentFuture();
  }

  void _reloadDestinationContentFuture() {
    _destinationContentFuture = _loadDestinationContent();
  }

  Future<BackupDestinationContentResult> _loadDestinationContent() async {
    final dest = ref
        .read(databaseBackupSettingsProvider)
        .destinationDirectory
        .trim();
    if (dest.isEmpty) {
      return const BackupDestinationContentResult(
        kind: BackupDestinationContentKind.folderMissing,
      );
    }
    try {
      final db = await DatabaseHelper.instance.database;
      final baseName = p.basenameWithoutExtension(db.path);
      return BackupDestinationFolderValidator.inspectDestinationContent(
        destinationDirectory: dest,
        dbBaseName: baseName,
      );
    } catch (_) {
      // Σκόπιμη υποβάθμιση, όχι απόκρυψη σφάλματος: χωρίς ανοιχτή βάση δεν
      // γνωρίζουμε το όνομα του αρχείου, άρα δεν μπορούμε να πούμε τι περιέχει
      // ο φάκελος προορισμού. Η ένδειξη είναι διακοσμητική (προειδοποίηση στο
      // πάνελ αντιγράφων) — το πραγματικό σφάλμα βάσης αναφέρεται από τη ροή
      // αρχικοποίησης, που είναι ο ιδιοκτήτης του μηνύματος.
      return const BackupDestinationContentResult(
        kind: BackupDestinationContentKind.folderMissing,
      );
    }
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
          // Η αδυναμία ΕΛΕΓΧΟΥ είναι η απάντηση: σε νεκρή δικτυακή διαδρομή ή
          // άρνηση πρόσβασης δεν μπορούμε να επιβεβαιώσουμε το αρχείο, οπότε το
          // εικονίδιο «δεν υπάρχει αυτή η βάση» είναι η σωστή ένδειξη. Το
          // ονομαστικό σφάλμα το δίνει η επόμενη απόπειρα ανοίγματος.
          exists = false;
        }
      }
      var paths = List<String>.from(recent);
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
          _dbPathErrorMessage =
              'Σφάλμα ανάγνωσης διαδρομής: ${humanizeUserFacingError(e)}';
          _isLoadingDbPath = false;
        });
      }
    }
  }

  Future<void> _pickDatabasePath() async {
    if (!await ensureDatabaseSwitchAllowed(context, ref)) return;

    setState(() {
      _dbPathErrorMessage = null;
    });

    final picked = await pickDatabasePathWithSystemPicker();
    if (FilePickerSession.takeLastRefocusedExisting()) return;
    // Ακύρωση επιλογέα = έγκυρη πράξη· κανένα μήνυμα (η κενή διαδρομή
    // αποκλείεται πλέον κεντρικά στο SettingsService.setDatabasePath).
    if (picked == null || picked.path.isEmpty) return;
    if (picked.isBackupArchive) {
      await _restoreFromBackupZip(preselectedZipPath: picked.path);
    } else {
      await _switchToPickedDatabasePath(picked.path);
    }
  }

  /// Αλλαγή στη διαδρομή βάσης που επέλεξε ο χρήστης (επιλογέας ή πρόσφατη).
  Future<void> _switchToPickedDatabasePath(String newPath) async {
    final trimmed = newPath.trim();
    if (trimmed.isEmpty || !mounted) return;
    if (!await ensureDatabaseSwitchAllowed(context, ref)) return;
    if (!mounted) return;

    await runDatabasePathSwitch(path: trimmed, hooks: this);
  }

  @override
  Future<void> showVerifyingIndicator() async {
    if (!mounted) return;
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
  }

  @override
  Future<void> hideVerifyingIndicator() async {
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _applySwitchAfterSchemaRecovery() async {
    if (!mounted) return;
    final activePath = await SettingsService().getDatabasePath();
    if (!mounted) return;
    await applySwitchToSession(activePath);
  }

  @override
  Future<void> reportVerificationFailure(
    DatabaseInitRunnerResult runner,
  ) async {
    if (!mounted) return;
    final recovered = await showDatabaseCheckFailedDialog(
      context: context,
      result: runner.result,
      onSuccess: _applySwitchAfterSchemaRecovery,
    );
    if (recovered && mounted) {
      // Η διαδρομή μπορεί να είναι αντίγραφο (αναβαθμισμένο ή υποβαθμισμένο)
      // — ανανέωση ετικετών.
      await _loadDatabasePathSection();
    }
  }

  @override
  Future<void> applySwitchToSession(String path) async {
    if (!mounted) return;
    await completeDatabaseSwitch(
      ref: ref,
      path: path,
      hooks: DatabaseSwitchCompletionHooks(
        onSessionStateUpdated: (switchedPath) async {
          if (!mounted) return;
          setState(() {
            _currentDbPath = switchedPath;
            _dbPathErrorMessage = null;
          });
          await _loadDatabasePathSection();
        },
        onLifecycleChanged: () async {
          await widget.onDatabaseLifecycleChanged?.call();
        },
      ),
    );
  }

  @override
  void declareSwitchBegin() {
    ref
        .read(activeCriticalOperationsProvider.notifier)
        .begin(CriticalOperation.databaseSwitch);
  }

  @override
  void declareSwitchEnd() {
    ref
        .read(activeCriticalOperationsProvider.notifier)
        .end(CriticalOperation.databaseSwitch);
  }

  Future<void> _runCreateNewDatabaseFlow() async {
    await runGuardedDatabaseSwitch(context, ref, () async {
      if (!mounted) return;
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
            _dbPathErrorMessage = null;
          });
        },
      );
    });
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
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    // Η τιμή είναι ΠΑΝΤΑ η ενεργή διαδρομή: οι επιλογές την
                    // περιλαμβάνουν εξ ορισμού, οπότε δεν υπάρχει εφεδρική τιμή
                    // που θα εμφάνιζε ως ενεργή μια βάση που δεν είναι ανοιχτή.
                    value: _currentDbPath,
                    isExpanded: true,
                    items:
                        databasePathDropdownOptions(
                          currentPath: _currentDbPath,
                          recentPaths: _recentDbPaths,
                        ).map((path) {
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
                      await _switchToPickedDatabasePath(value);
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
      DatabaseRenameNoticeText(
        // Το όνομα ξαναϋπολογίζεται σε κάθε χτίσιμο: μετά από αλλαγή βάσης η
        // οδηγία πρέπει να μιλά για τη ΝΕΑ ενεργή βάση, όχι για την παλιά.
        parts: currentDatabaseRenameNotice(
          renamedFileName: _currentDbPath.trim().isEmpty
              ? ''
              : resolveRenamedOldDatabaseFileName(
                  currentDatabasePath: _currentDbPath.trim(),
                ),
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      CompactTooltip(
        message: createNewDatabaseButtonTooltip(
          suggestedFileName: suggestNewCallLoggerDatabaseFileName(
            directory: _currentDbPath.trim().isEmpty
                ? ''
                : p.dirname(_currentDbPath.trim()),
          ),
        ),
        child: FilledButton.tonalIcon(
          onPressed: _currentDbPath.trim().isEmpty
              ? null
              : _runCreateNewDatabaseFlow,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Δημιουργία νέου αρχείου βάσης'),
        ),
      ),
      const SizedBox(height: 16),
      const Divider(height: 1),
      const SizedBox(height: 12),
    ];
  }

  @override
  void dispose() {
    _scheduleStatusRefreshTimer?.cancel();
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

  Future<bool> _confirmCreateBackupDestinationFolder(String folderPath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Δημιουργία φακέλου'),
        content: Text(
          'Ο φάκελος δεν υπάρχει:\n\n$folderPath\n\n'
          'Θέλετε να δημιουργηθεί;',
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Δημιουργία'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<bool> _createBackupDestinationFolderIfConfirmed(
    String folderPath,
  ) async {
    if (!await _confirmCreateBackupDestinationFolder(folderPath)) {
      return false;
    }
    try {
      await Directory(folderPath).create(recursive: true);
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _destinationFolderError =
            'Δεν ήταν δυνατή η δημιουργία του φακέλου: ${humanizeUserFacingError(e)}';
      });
      return false;
    }
  }

  Future<void> _validateAndPersistDestination() async {
    final gen = ++_destinationValidationGen;
    final raw = _destinationController.text;
    var result = await BackupDestinationFolderValidator.validate(raw);
    if (!mounted || gen != _destinationValidationGen) return;

    if (result.kind == BackupDestinationValidationKind.missingDirectory) {
      final trimmed = raw.trim();
      final created = await _createBackupDestinationFolderIfConfirmed(trimmed);
      if (!mounted || gen != _destinationValidationGen) return;
      if (!created) {
        setState(() => _destinationFolderError = result.errorMessage);
        return;
      }
      result = await BackupDestinationFolderValidator.validate(raw);
      if (!mounted || gen != _destinationValidationGen) return;
    }

    if (result.kind == BackupDestinationValidationKind.ok) {
      setState(() => _destinationFolderError = null);
      await ref
          .read(databaseBackupSettingsProvider.notifier)
          .setDestinationDirectory(raw.trim());
      _reloadDestinationContentFuture();
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
    final initialDirectory = initialDirectoryForFilePicker(
      _destinationController.text,
    );
    final session = await FilePickerSession.run(
      () => FilePicker.getDirectoryPath(
        dialogTitle: 'Φάκελος προορισμού αντιγράφων ασφαλείας',
        initialDirectory: initialDirectory,
      ),
    );
    if (session.refocusedExisting) return;
    final path = session.value;
    if (path == null || !mounted) return;
    setState(() => _destinationFolderError = null);
    _destinationController.text = path;
    await _validateAndPersistDestination();
  }

  Widget _buildBackupScheduleStatusSection(
    ThemeData theme,
    DatabaseBackupSettings settings,
  ) {
    ref.watch(backupSchedulerProvider);
    final jobRunning = ref
        .read(backupSchedulerProvider.notifier)
        .isBackupJobRunning;
    final status = BackupScheduleStatusFormatter.build(
      settings: settings,
      backupJobRunning: jobRunning,
      dbBaseName: _currentDbPath.trim().isEmpty
          ? null
          : p.basenameWithoutExtension(_currentDbPath),
    );

    Color? severityColor({required bool warning, required bool caution}) {
      if (warning) return theme.colorScheme.error;
      if (caution) return theme.colorScheme.tertiary;
      return theme.colorScheme.onSurfaceVariant;
    }

    Widget line(
      String text, {
      bool warning = false,
      bool caution = false,
      bool emphasize = false,
    }) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: severityColor(warning: warning, caution: caution),
            fontWeight: emphasize ? FontWeight.w600 : null,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (status.nextBackupText != null)
            line(status.nextBackupText!, emphasize: status.nextIsImminent),
          if (status.lastBackupText != null)
            ...status.lastBackupText!.split('\n').map((row) => line(row)),
          FutureBuilder<BackupDestinationContentResult>(
            future: _destinationContentFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return line('Έλεγχος φακέλου…');
              }
              final content = snapshot.data!;
              final label =
                  BackupScheduleStatusFormatter.destinationContentLabelEl(
                    content,
                  );
              return line(
                label,
                warning:
                    content.kind == BackupDestinationContentKind.folderMissing,
                caution:
                    content.kind ==
                    BackupDestinationContentKind.folderEmptyNoFiles,
              );
            },
          ),
          if (status.hintText != null)
            line(status.hintText!, warning: status.hintIsWarning),
        ],
      ),
    );
  }

  Widget _buildDestinationFolderMissingBanner(ThemeData theme) {
    return FutureBuilder<BackupDestinationContentResult>(
      future: _destinationContentFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        if (snapshot.data!.kind != BackupDestinationContentKind.folderMissing) {
          return const SizedBox.shrink();
        }
        final dest = ref
            .read(databaseBackupSettingsProvider)
            .destinationDirectory;
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Material(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                'Ο φάκελος προορισμού δεν βρέθηκε:\n$dest\n'
                'Πιθανή αιτία: αποσυνδεδεμένος δίσκος ή διαγραφή. '
                'Τα αρχεία αντιγράφου στον δίσκο μπορεί να μην είναι διαθέσιμα.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _runBackupNow() async {
    final settings = ref.read(databaseBackupSettingsProvider);
    final dest = settings.destinationDirectory.trim();
    if (dest.isNotEmpty) {
      final content = await _loadDestinationContent();
      if (!mounted) return;
      if (content.kind == BackupDestinationContentKind.folderMissing) {
        await showBackupFolderMissingDialog(
          context: context,
          ref: ref,
          folderPath: dest,
          auditTrigger: BackupAuditTrigger.manual,
          dismissSetsStatusNone: false,
        );
        if (mounted) _reloadDestinationContentFuture();
        return;
      }
    }

    final messenger = ScaffoldMessenger.of(context);
    final result = await DatabaseBackupService.runBackup(
      settings,
      auditTrigger: BackupAuditTrigger.manual,
    );
    if (!mounted) return;
    if (result.success) {
      final notifier = ref.read(databaseBackupSettingsProvider.notifier);
      await notifier.setLastManualBackupAttempt(DateTime.now());
      final current = ref.read(databaseBackupSettingsProvider);
      if (current.lastBackupStatus == BackupScheduleStatus.missed ||
          current.lastBackupStatus == BackupScheduleStatus.folderMissing) {
        await notifier.setLastBackupAttempt(null);
        await notifier.setLastBackupStatus(BackupScheduleStatus.none);
      }
      _reloadDestinationContentFuture();
      ref.invalidate(backupRestoreTooltipProvider);
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
      if (result.failureCode == DatabaseBackupFailureCode.folderMissing &&
          dest.isNotEmpty) {
        await showBackupFolderMissingDialog(
          context: context,
          ref: ref,
          folderPath: dest,
          auditTrigger: BackupAuditTrigger.manual,
          dismissSetsStatusNone: false,
        );
        if (mounted) _reloadDestinationContentFuture();
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Αποτυχία αντιγράφου'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _restoreFromBackupZip({String? preselectedZipPath}) async {
    await runGuardedDatabaseSwitch(context, ref, () async {
      if (!mounted) return;
      final backupFolder = _destinationController.text.trim().isNotEmpty
          ? _destinationController.text.trim()
          : ref
                .read(databaseBackupSettingsProvider)
                .destinationDirectory
                .trim();
      final defaultTarget = _currentDbPath.trim().isNotEmpty
          ? _currentDbPath
          : AppConfig.defaultDbPath;
      final result = await runRestoreFromBackupZipFlow(
        context: context,
        backupFolderHint: backupFolder.isNotEmpty ? backupFolder : null,
        currentDatabasePath: defaultTarget,
        preselectedZipPath: preselectedZipPath,
        initialDestination: RestoreDestinationChoice.currentDatabase,
      );
      if (!mounted || !result.isSuccess) return;
      final toOpen = result.pathToOpen?.trim();
      if (toOpen != null && toOpen.isNotEmpty) {
        await runDatabasePathSwitch(path: toOpen, hooks: this);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(databaseBackupSettingsProvider);
    ref.listen(databaseBackupSettingsProvider, (prev, next) {
      if (prev == next) return;
      final syncDestination =
          prev == null ||
          prev.destinationDirectory != next.destinationDirectory;
      final syncRetentionMaxCopies =
          prev == null || prev.retentionMaxCopies != next.retentionMaxCopies;
      final syncRetentionMaxAgeDays =
          prev == null || prev.retentionMaxAgeDays != next.retentionMaxAgeDays;
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
                const SizedBox(height: 12),
                _RestoreFromBackupZipButton(onPressed: _restoreFromBackupZip),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: SwitchListTile(
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
                    ),
                    _SettingsPanelInfoTooltip(
                      message: _backupSafetyTooltipMessage,
                      iconColor: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
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
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: color,
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return Text(
                          'Φόρτωση υποδείξεων τοποθεσίας…',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: color,
                          ),
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
                                    ? const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      )
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
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.12,
                                ),
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
                  if (settings.destinationDirectory.trim().isNotEmpty)
                    _buildDestinationFolderMissingBanner(theme),
                  if (Platform.isWindows) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Στον διάλογο επιλογής (Windows) χρησιμοποιήστε «Νέος φάκελος» '
                      'για δημιουργία φακέλου (π.χ. backups σε εξωτερικό δίσκο). '
                      'Μπορείτε επίσης να πληκτρολογήσετε διαδρομή και να επιβεβαιώσετε '
                      'με Enter — αν λείπει ο φάκελος, θα σας ζητηθεί δημιουργία.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  FutureBuilder<
                    ({String dbPath, int eligibleWindowsVolumeCount})
                  >(
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
                  FutureBuilder<PortableBackupAvailability>(
                    future: PortableBackupAvailability.load(
                      lexiconLoaded: ref.watch(coreLexiconProvider).loaded,
                    ),
                    builder: (context, snapshot) {
                      final avail = snapshot.data;
                      final bundleLocksZip =
                          avail != null &&
                          settings.effectiveIncludesPortableBundleInZip(avail);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Αποθήκευση σε μορφή .zip'),
                            subtitle: const Text(
                              'Αναδιοργάνωση και εκκαθάριση κενών χώρων της βάσης και εξαγωγή σε νέο αρχείο (VACUUM INTO). Έπιτα συμπίεση σε αρχείο .zip.',
                            ),
                            value: settings.zipOutput,
                            onChanged: bundleLocksZip
                                ? null
                                : (v) => ref
                                      .read(
                                        databaseBackupSettingsProvider.notifier,
                                      )
                                      .setZipOutput(v),
                          ),
                          _portableBackupSwitch(
                            title: 'Συμπερίληψη εικόνων χαρτών',
                            subtitle: Text(
                              PortableBackupAvailability.mapsImagesSubtitle(),
                            ),
                            value: settings.includeMapImagesInBackup,
                            enabled: avail?.hasMapImages ?? false,
                            disabledTooltip:
                                'Δεν υπάρχουν αποθηκευμένες εικόνες χαρτών',
                            onChanged: (v) => ref
                                .read(databaseBackupSettingsProvider.notifier)
                                .setIncludeMapImagesInBackup(v),
                          ),
                          _portableBackupSwitch(
                            title: 'Εικονίδια εργαλείων',
                            subtitle: Text(
                              'Zip με φάκελο ${AppConfig.portableImagesDirName} '
                              '(στη ρίζα εφαρμογής)',
                            ),
                            value: settings.includeToolImages,
                            enabled: avail?.hasToolImages ?? false,
                            disabledTooltip:
                                'Δεν υπάρχουν αποθηκευμένα εικονίδια εργαλείων',
                            onChanged: (v) => ref
                                .read(databaseBackupSettingsProvider.notifier)
                                .setIncludeToolImages(v),
                          ),
                          _portableBackupSwitch(
                            title: 'Λεξικό',
                            subtitle: Text(
                              'Zip με φάκελο ${AppConfig.portableDictionariesDirName}',
                            ),
                            value: settings.includeLexicon,
                            enabled: avail?.hasLoadedLexicon ?? false,
                            disabledTooltip: 'Δεν υπάρχει φορτωμένο λεξικό',
                            onChanged: (v) => ref
                                .read(databaseBackupSettingsProvider.notifier)
                                .setIncludeLexicon(v),
                          ),
                          _portableBackupSwitch(
                            title: 'Βάση Λάμπας',
                            subtitle: Text(
                              'Zip με αρχείο .db από ${AppConfig.portableDataBaseDirName}',
                            ),
                            value: settings.includeLampDb,
                            enabled:
                                avail?.hasLampDbInPortableDataBase ?? false,
                            disabledTooltip:
                                'Δεν υπάρχει βάση Λάμπας στον φάκελο της εφαρμογής',
                            onChanged: (v) => ref
                                .read(databaseBackupSettingsProvider.notifier)
                                .setIncludeLampDb(v),
                          ),
                        ],
                      );
                    },
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
                    'Επιλέξτε ημέρες και ώρα για αυτόματο αντίγραφο ασφαλείας όσο η εφαρμογή είναι ανοιχτή. '
                    'Εκτελείται το πολύ ένα προγραμματισμένο αντίγραφο ανά ημερολογιακή ημέρα.',
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
                          onSelected: (selected) {
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
                          },
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
                    Row(
                      children: [
                        Text(
                          'Προγραμματισμένη Ώρα:',
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          settings.backupTime,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () async {
                            final p = BackupScheduleUtils.parseTime(
                              settings.backupTime,
                            );
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
                      ],
                    ),
                    _buildBackupScheduleStatusSection(theme, settings),
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
                                onSubmitted: (_) =>
                                    _persistRetentionMaxCopies(),
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
                                onSubmitted: (_) =>
                                    _persistRetentionMaxAgeDays(),
                              ),
                            ),
                            Text(' ημέρες', style: theme.textTheme.bodyLarge),
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
                const Divider(height: 24),
                Text(
                  'Έλεγχος ακεραιότητας',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Διάγνωση ορφανών συσχετίσεων, ευρετηρίων αναζήτησης και βηματική '
                  'επιδιόρθωση με επιβεβαίωση.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                _IntegrityLaunchSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _portableBackupSwitch({
    required String title,
    required Widget subtitle,
    required bool value,
    required bool enabled,
    required String disabledTooltip,
    required ValueChanged<bool> onChanged,
  }) {
    final tile = SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: subtitle,
      value: value,
      onChanged: enabled ? onChanged : null,
    );
    if (!enabled) {
      return Tooltip(
        message: disabledTooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: tile,
      );
    }
    return tile;
  }
}

/// Στενό tooltip (i) που μένει εντός του διαλόγου ρυθμίσεων βάσης.
class _SettingsPanelInfoTooltip extends StatelessWidget {
  const _SettingsPanelInfoTooltip({
    required this.message,
    required this.iconColor,
    this.maxWidth = 280,
  });

  final String message;
  final Color iconColor;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: message,
      constraints: BoxConstraints(maxWidth: maxWidth),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      preferBelow: false,
      verticalOffset: 10,
      waitDuration: const Duration(milliseconds: 350),
      showDuration: const Duration(seconds: 8),
      textStyle: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onInverseSurface,
        height: 1.4,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(Icons.info_outline, size: 18, color: iconColor),
      ),
    );
  }
}

class _RestoreFromBackupZipButton extends ConsumerWidget {
  const _RestoreFromBackupZipButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tooltipAsync = ref.watch(backupRestoreTooltipProvider);
    final message = tooltipAsync.when(
      data: (value) => value,
      loading: () => 'Φόρτωση πληροφοριών αντιγράφου…',
      error: (_, _) => BackupRestoreTooltipBuilder.fallbackMessage,
    );

    return Tooltip(
      message: message,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 400),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.unarchive_outlined),
        label: const Text('Επαναφορά από Αντίγραφο Ασφαλείας'),
      ),
    );
  }
}

class _IntegrityLaunchSection extends ConsumerWidget {
  const _IntegrityLaunchSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final integrityState = ref.watch(databaseIntegrityProvider);

    String? statusHint;
    if (integrityState is DatabaseIntegritySuccess) {
      if (!integrityState.report.hasFindings) {
        statusHint = 'Τελευταίος έλεγχος: δεν εντοπίστηκαν προβλήματα.';
      } else {
        statusHint =
            'Τελευταίος έλεγχος: ${integrityState.report.findings.length} ευρήματα '
            '(${integrityState.report.criticalCount} κρίσιμα).';
      }
    } else if (integrityState is DatabaseIntegrityError) {
      statusHint = 'Τελευταίος έλεγχος απέτυχε.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => DatabaseIntegrityDialog.show(context),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('Έλεγχος ακεραιότητας…'),
              ),
            ),
            _SettingsPanelInfoTooltip(
              message: integrityChecksTooltipMessage,
              iconColor: theme.colorScheme.onSurfaceVariant,
              maxWidth: 560,
            ),
          ],
        ),
        if (statusHint != null) ...[
          const SizedBox(height: 6),
          Text(
            statusHint,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
