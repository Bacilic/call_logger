import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/app_config.dart';
import '../../../core/database/active_database_generation.dart';
import '../../../core/database/backup_pending_changes.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/models/app_permission.dart';
import '../../../core/providers/core_lexicon_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/file_picker_initial_directory.dart';
import '../../../core/utils/file_picker_session.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import '../../operators/services/profile_settings_export.dart';
import '../models/database_backup_settings.dart';
import '../providers/backup_scheduler_provider.dart';
import '../providers/database_backup_settings_provider.dart';
import '../services/database_backup_audit.dart';
import '../services/database_backup_service.dart';
import '../utils/backup_destination_folder_validator.dart';
import '../utils/backup_destination_location_warnings.dart';
import '../utils/backup_location_hints.dart';
import '../utils/backup_restore_tooltip.dart';
import 'backup_int_setting_field.dart';
import '../utils/backup_schedule_status.dart';
import '../utils/portable_backup_availability.dart';
import 'backup_folder_missing_dialog.dart';
import 'settings_panel_info_tooltip.dart';

/// Tooltip δίπλα στον διακόπτη αυτόματων αντιγράφων ασφαλείας.
const _backupSafetyTooltipMessage =
    'Ασφαλές αντίγραφο χωρίς διακοπή λειτουργίας.\n\n'
    'VACUUM INTO (ατομικό): Ολόκληρο αντίγραφο με μία κίνηση — σε διακοπή '
    '(π.χ. ρεύμα) δεν μένει μισοκατεστραμμένο αρχείο.\n\n'
    'WAL / SHM: Γραφή στο παρασκήνιο· η εφαρμογή συνεχίζει κανονικά χωρίς '
    'να «παγώνει».';

/// Καρτέλα «Αντίγραφα»: ρυθμίσεις αυτόματων αντιγράφων ασφαλείας.
///
/// Ο απλός χρήστης (χωρίς δικαίωμα πλήρους αντιγράφου) βλέπει ποιος τα
/// χειρίζεται και το δικό του «αντίγραφο ρυθμίσεων» — όπως πριν από την
/// καρτελοποίηση.
/// Πώς τελείωσε η προσπάθεια δημιουργίας του φακέλου προορισμού.
///
/// Ρητό αποτέλεσμα αντί για `bool`: το «δεν έγινε» έκρυβε δύο πολύ
/// διαφορετικές καταστάσεις — «το ακύρωσε ο χρήστης» και «απέτυχε, και η
/// αιτία γράφτηκε ήδη». Ο καλών τις μπέρδευε και έσβηνε την αιτία.
enum _FolderCreationOutcome {
  created,
  cancelled,

  /// Απέτυχε· το μήνυμα προς τον χρήστη έχει ΗΔΗ γραφτεί.
  failedWithMessage,
}

class DatabaseSettingsBackupTab extends ConsumerStatefulWidget {
  const DatabaseSettingsBackupTab({super.key});

  @override
  ConsumerState<DatabaseSettingsBackupTab> createState() =>
      _DatabaseSettingsBackupTabState();
}

class _DatabaseSettingsBackupTabState
    extends ConsumerState<DatabaseSettingsBackupTab>
    with AutomaticKeepAliveClientMixin {
  final SettingsService _settings = SettingsService();

  late final TextEditingController _destinationController;
  late final TextEditingController _maxCopiesController;
  late final TextEditingController _maxAgeController;
  late final TextEditingController _fullCopiesController;
  late final TextEditingController _thresholdController;
  late final TextEditingController _minSpacingController;
  late final TextEditingController _maxWaitController;
  Future<List<BackupCaptionSegment>> _locationCaptionSegmentsFuture =
      Future.value(const <BackupCaptionSegment>[]);
  Future<({String dbPath, int eligibleWindowsVolumeCount})>
  _backupDestinationWarningContextFuture = Future.value((
    dbPath: '',
    eligibleWindowsVolumeCount: 0,
  ));
  Future<BackupDestinationContentResult> _destinationContentFuture =
      Future.value(
        // Αφετηρία πριν διαβαστούν οι ρυθμίσεις: «δεν έχει οριστεί» είναι η
        // ειλικρινής άγνοια — το «δεν υπάρχει» θα κατηγορούσε φάκελο που
        // κανείς δεν έχει κοιτάξει ακόμη.
        const BackupDestinationContentResult(
          kind: BackupDestinationContentKind.folderNotSet,
        ),
      );

  String _currentDbPath = '';
  Future<int> _pendingChangesFuture = Future.value(0);

  final FocusNode _destinationFocus = FocusNode();
  final FocusNode _maxCopiesFocus = FocusNode();
  final FocusNode _maxAgeFocus = FocusNode();
  final FocusNode _fullCopiesFocus = FocusNode();
  final FocusNode _thresholdFocus = FocusNode();
  final FocusNode _minSpacingFocus = FocusNode();
  final FocusNode _maxWaitFocus = FocusNode();
  String? _destinationFolderError;
  int _destinationValidationGen = 0;
  Timer? _scheduleStatusRefreshTimer;

  // Οι controllers και ο χρονιστής ζουν όσο ζει ο διάλογος — όπως όταν όλα
  // τα τμήματα κατοικούσαν σε ένα ενιαίο πάνελ.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _destinationController = TextEditingController();
    _maxCopiesController = TextEditingController();
    _maxAgeController = TextEditingController();
    _fullCopiesController = TextEditingController();
    _thresholdController = TextEditingController();
    _minSpacingController = TextEditingController();
    _maxWaitController = TextEditingController();
    _reloadLocationAndWarningFutures();
    _reloadPendingChangesFuture();
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
    unawaited(_loadCurrentDbPath());
    _scheduleStatusRefreshTimer = Timer.periodic(const Duration(seconds: 30), (
      _,
    ) {
      if (!mounted) return;
      _reloadDestinationContentFuture();
      _reloadPendingChangesFuture();
      setState(() {});
    });
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
    _fullCopiesController.dispose();
    _thresholdController.dispose();
    _minSpacingController.dispose();
    _maxWaitController.dispose();
    _maxCopiesFocus.dispose();
    _maxAgeFocus.dispose();
    _fullCopiesFocus.dispose();
    _thresholdFocus.dispose();
    _minSpacingFocus.dispose();
    _maxWaitFocus.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentDbPath() async {
    final path = await _settings.getDatabasePath();
    if (!mounted) return;
    setState(() => _currentDbPath = path);
  }

  void _reloadPendingChangesFuture() {
    _pendingChangesFuture = _loadPendingChanges();
  }

  Future<int> _loadPendingChanges() async {
    try {
      final settings = ref.read(databaseBackupSettingsProvider);
      final db = await DatabaseHelper.instance.database;
      return await BackupPendingChangesRepository(db).countPendingSince(
        settings.lastBackupAuditId,
        fallbackSince: settings.lastAnyBackupAt,
      );
    } catch (_) {
      return 0;
    }
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
        kind: BackupDestinationContentKind.folderNotSet,
      );
    }
    try {
      final db = await DatabaseHelper.instance.database;
      final baseName = p.basenameWithoutExtension(db.path);
      return await BackupDestinationFolderValidator.inspectDestinationContent(
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
    final copiesStr = s.retentionQuickMaxCopies.toString();
    if (syncRetentionMaxCopies &&
        !_maxCopiesFocus.hasFocus &&
        _maxCopiesController.text != copiesStr) {
      _maxCopiesController.text = copiesStr;
    }
    final ageStr = s.retentionQuickMaxAgeDays.toString();
    if (syncRetentionMaxAgeDays &&
        !_maxAgeFocus.hasFocus &&
        _maxAgeController.text != ageStr) {
      _maxAgeController.text = ageStr;
    }
    final fullCopiesStr = s.retentionFullMaxCopies.toString();
    if (!_fullCopiesFocus.hasFocus &&
        _fullCopiesController.text != fullCopiesStr) {
      _fullCopiesController.text = fullCopiesStr;
    }
    final thresholdStr = s.changeThreshold.toString();
    if (!_thresholdFocus.hasFocus &&
        _thresholdController.text != thresholdStr) {
      _thresholdController.text = thresholdStr;
    }
    final spacingStr = s.minSpacingMinutes.toString();
    if (!_minSpacingFocus.hasFocus &&
        _minSpacingController.text != spacingStr) {
      _minSpacingController.text = spacingStr;
    }
    final waitStr = s.maxWaitMinutes.toString();
    if (!_maxWaitFocus.hasFocus && _maxWaitController.text != waitStr) {
      _maxWaitController.text = waitStr;
    }
  }

  Future<void> _persistIntField(
    TextEditingController controller,
    int Function(DatabaseBackupSettings s) readValue,
    Future<void> Function(int value) save,
  ) async {
    final raw = controller.text.trim();
    final n = raw.isEmpty ? null : int.tryParse(raw);
    if (n != null) {
      await save(n);
    }
    if (!mounted) return;
    // Η αποθήκευση μπορεί να ψαλίδισε την τιμή (π.χ. ελάχιστο 15΄) — το πεδίο
    // δείχνει ό,τι πραγματικά ισχύει.
    final applied = readValue(
      ref.read(databaseBackupSettingsProvider),
    ).toString();
    if (controller.text != applied) controller.text = applied;
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

  /// Δημιουργεί τον φάκελο, αφού ρωτήσει — **εφόσον έχει νόημα να ρωτήσει**.
  ///
  /// Επιστρέφει `true` μόνο όταν ο φάκελος υπάρχει πλέον. Όταν επιστρέψει
  /// `false` έχοντας γράψει η ίδια μήνυμα (ανύπαρκτος τόμος, αποτυχία
  /// δημιουργίας), το δηλώνει με το [_destinationFolderError] ήδη γεμάτο· ο
  /// καλών δεν πρέπει να το σβήσει.
  Future<_FolderCreationOutcome> _createBackupDestinationFolderIfConfirmed(
    String folderPath,
  ) async {
    // Ο δίσκος πρέπει να υπάρχει ΠΡΙΝ προσφερθεί δημιουργία: σε αποσυνδεδεμένο
    // ή ανύπαρκτο τόμο η δημιουργία είναι αδύνατη, και η ερώτηση «να τον
    // φτιάξω;» δίνει ελπίδα που δεν υπάρχει.
    if (!BackupLocationHints.volumeOfPathExists(folderPath)) {
      if (!mounted) return _FolderCreationOutcome.failedWithMessage;
      setState(() {
        _destinationFolderError = _missingVolumeMessage(folderPath);
      });
      return _FolderCreationOutcome.failedWithMessage;
    }
    if (!await _confirmCreateBackupDestinationFolder(folderPath)) {
      return _FolderCreationOutcome.cancelled;
    }
    try {
      await Directory(folderPath).create(recursive: true);
      return _FolderCreationOutcome.created;
    } catch (e) {
      if (!mounted) return _FolderCreationOutcome.failedWithMessage;
      setState(() {
        _destinationFolderError =
            'Δεν ήταν δυνατή η δημιουργία του φακέλου: ${humanizeUserFacingError(e)}';
      });
      return _FolderCreationOutcome.failedWithMessage;
    }
  }

  /// Το μήνυμα για δίσκο που δεν υπάρχει — με τους δίσκους που υπάρχουν.
  ///
  /// Η εφαρμογή ήδη ξέρει ποιοι τόμοι είναι συνδεδεμένοι· το να τους πει είναι
  /// η διαφορά ανάμεσα σε «κάτι πήγε στραβά» και «ορίστε τι μπορείτε να
  /// διαλέξετε».
  String _missingVolumeMessage(String folderPath) {
    final letter = BackupLocationHints.windowsDriveLetterFromPath(folderPath);
    final drives = BackupLocationHints.eligibleWindowsBackupDriveLabels();
    final head = letter == null
        ? 'Ο δίσκος της διαδρομής δεν είναι διαθέσιμος'
        : 'Ο δίσκος $letter: δεν υπάρχει ή δεν είναι συνδεδεμένος';
    if (drives.isEmpty) {
      return '$head — ο φάκελος δεν μπορεί να δημιουργηθεί εκεί.';
    }
    return '$head — ο φάκελος δεν μπορεί να δημιουργηθεί εκεί. '
        'Διαθέσιμοι δίσκοι: ${drives.join(', ')}.';
  }

  Future<void> _validateAndPersistDestination() async {
    final gen = ++_destinationValidationGen;
    final raw = _destinationController.text;
    var result = await BackupDestinationFolderValidator.validate(raw);
    if (!mounted || gen != _destinationValidationGen) return;

    if (result.kind == BackupDestinationValidationKind.missingDirectory) {
      final trimmed = raw.trim();
      final outcome = await _createBackupDestinationFolderIfConfirmed(trimmed);
      if (!mounted || gen != _destinationValidationGen) return;
      if (outcome != _FolderCreationOutcome.created) {
        // Το γενικό «ο φάκελος δεν υπάρχει» μπαίνει ΜΟΝΟ όταν δεν ειπώθηκε
        // κάτι πιο συγκεκριμένο. Όσο η απάντηση ήταν σκέτο `false`, αυτή η
        // γραμμή έσβηνε την πραγματική αιτία (ανύπαρκτος δίσκος, άρνηση
        // πρόσβασης) που μόλις είχε γραφτεί.
        if (outcome == _FolderCreationOutcome.cancelled) {
          setState(() => _destinationFolderError = result.errorMessage);
        }
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

  Future<void> _persistRetentionMaxCopies() => _persistIntField(
    _maxCopiesController,
    (s) => s.retentionQuickMaxCopies,
    (v) => ref
        .read(databaseBackupSettingsProvider.notifier)
        .setRetentionQuickMaxCopies(v),
  );

  Future<void> _persistRetentionMaxAgeDays() => _persistIntField(
    _maxAgeController,
    (s) => s.retentionQuickMaxAgeDays,
    (v) => ref
        .read(databaseBackupSettingsProvider.notifier)
        .setRetentionQuickMaxAgeDays(v),
  );

  Future<void> _persistRetentionFullMaxCopies() => _persistIntField(
    _fullCopiesController,
    (s) => s.retentionFullMaxCopies,
    (v) => ref
        .read(databaseBackupSettingsProvider.notifier)
        .setRetentionFullMaxCopies(v),
  );

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

  /// Τι βλέπει ο χρήστης χωρίς δικαίωμα πλήρους αντιγράφου: ποιος χειρίζεται
  /// τα αντίγραφα, και το δικό του «αντίγραφο ρυθμίσεων» (κλειδωμένη απόφαση
  /// Φάσης 0: ο απλός χρήστης παίρνει αντίγραφο μόνο του προφίλ του).
  Widget _buildBackupManagedByAdminNotice(ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Τα αντίγραφα ασφαλείας της βάσης τα χειρίζεται ο '
                    'διαχειριστής.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Μπορείτε να αποθηκεύσετε ένα αντίγραφο των δικών σας '
              'προσωπικών ρυθμίσεων και να το επαναφέρετε όποτε χρειαστεί.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _exportMyProfileSettings,
                  icon: const Icon(Icons.save_alt_outlined, size: 18),
                  label: const Text('Αντίγραφο των ρυθμίσεών μου'),
                ),
                OutlinedButton.icon(
                  onPressed: _importMyProfileSettings,
                  icon: const Icon(Icons.settings_backup_restore, size: 18),
                  label: const Text('Επαναφορά ρυθμίσεων'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importMyProfileSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await importActiveOperatorSettings();
    if (result.isRestored) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Επανήλθαν ${result.restoredCount} ρυθμίσεις. Κάποιες οθόνες '
            'δείχνουν τις νέες τιμές όταν ξανανοίξουν.',
          ),
        ),
      );
    } else if (result.error != null) {
      messenger.showSnackBar(SnackBar(content: Text(result.error!)));
    }
  }

  Future<void> _exportMyProfileSettings() async {
    // Ο messenger κρατιέται ΠΡΙΝ το await — μετά το κλείσιμο του επιλογέα το
    // context μπορεί να μην είναι πια ζωντανό.
    final messenger = ScaffoldMessenger.of(context);
    final result = await exportActiveOperatorSettings();
    if (result.isSaved) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Οι ρυθμίσεις αποθηκεύτηκαν στο ${result.path}'),
        ),
      );
    } else if (result.error != null) {
      messenger.showSnackBar(SnackBar(content: Text(result.error!)));
    }
  }

  Widget _buildBackupScheduleStatusSection(
    ThemeData theme,
    DatabaseBackupSettings settings,
  ) {
    ref.watch(backupSchedulerProvider);
    final jobRunning = ref
        .read(backupSchedulerProvider.notifier)
        .isBackupJobRunning;
    return FutureBuilder<int>(
      future: _pendingChangesFuture,
      builder: (context, snapshot) => _buildBackupStatusLines(
        theme,
        settings,
        pendingChanges: snapshot.data ?? 0,
        jobRunning: jobRunning,
      ),
    );
  }

  Widget _buildBackupStatusLines(
    ThemeData theme,
    DatabaseBackupSettings settings, {
    required int pendingChanges,
    required bool jobRunning,
  }) {
    final status = BackupScheduleStatusFormatter.build(
      settings: settings,
      pendingChanges: pendingChanges,
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
                // Η κενή διαδρομή είναι διαπίστωση, όχι συναγερμός: το κόκκινο
                // «Ορίστε φάκελο προορισμού…» από κάτω κουβαλά ήδη την επείγουσα
                // οδηγία, και δύο κόκκινες γραμμές για το ίδιο πράγμα θα
                // αλληλοακυρώνονταν.
                caution:
                    content.kind ==
                        BackupDestinationContentKind.folderEmptyNoFiles ||
                    content.kind == BackupDestinationContentKind.folderNotSet,
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
      // Και το χειροκίνητο αντίγραφο προστατεύει τις αλλαγές: προχωρά το
      // σημάδι του μετρητή, ώστε ο χρονιστής να μην ξαναπάρει τα ίδια.
      final db = await DatabaseHelper.instance.database;
      final markId = await BackupPendingChangesRepository(db).latestAuditId();
      await notifier.markBackupTaken(
        auditId: markId,
        at: DateTime.now(),
        manual: true,
        fullFingerprint: result.portableFingerprint,
        fullAt: result.isFullBackup ? DateTime.now() : null,
      );
      _reloadDestinationContentFuture();
      _reloadPendingChangesFuture();
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final settings = ref.watch(databaseBackupSettingsProvider);
    ref.listen(databaseBackupSettingsProvider, (prev, next) {
      if (prev == next) return;
      final syncDestination =
          prev == null ||
          prev.destinationDirectory != next.destinationDirectory;
      final syncRetentionMaxCopies =
          prev == null ||
          prev.retentionQuickMaxCopies != next.retentionQuickMaxCopies;
      final syncRetentionMaxAgeDays =
          prev == null ||
          prev.retentionQuickMaxAgeDays != next.retentionQuickMaxAgeDays;
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
    // Η βάση μπορεί να αλλάξει από άλλη καρτέλα (διαδρομή, επαναφορά) — οι
    // υποδείξεις τοποθεσίας και το όνομα αρχείου μιλούν πάντα για την ενεργή.
    ref.listen<int>(activeDatabaseGenerationProvider, (_, _) {
      if (!mounted) return;
      unawaited(_loadCurrentDbPath());
      setState(() {
        _reloadLocationAndWarningFutures();
        _reloadPendingChangesFuture();
      });
    });

    final cWarning = settings.destinationLooksLikeWindowsSystemDriveC;
    // Φάση 2: το πλήρες αντίγραφο είναι δουλειά του διαχειριστή. Ο απλός
    // χρήστης δεν βλέπει τις ενότητες — βλέπει ποιος τις χειρίζεται, και το
    // δικό του «αντίγραφο ρυθμίσεων». Χωρίς συνδεδεμένο χρήστη: όλα ως έχουν.
    final canManageFullBackup = PermissionService.instance.can(
      AppPermission.fullBackup,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!canManageFullBackup) _buildBackupManagedByAdminNotice(theme),
        if (canManageFullBackup) ...[
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
              SettingsPanelInfoTooltip(
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
            const SizedBox(height: 12),
            Text(
              'Τι μπαίνει στο πλήρες αντίγραφο',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Η βάση αντιγράφεται κάθε φορά (.db). Τα παρακάτω μπαίνουν σε '
              'πλήρες αντίγραφο (.zip) ΜΟΝΟ όταν κάτι τους αλλάξει — αλλιώς '
              'παίρνεται γρήγορο, μόνο με τη βάση, και ο δίσκος δεν γεμίζει '
              'πανομοιότυπα αρχεία.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            FutureBuilder<PortableBackupAvailability>(
              future: PortableBackupAvailability.load(
                lexiconLoaded: ref.watch(coreLexiconProvider).loaded,
              ),
              builder: (context, snapshot) {
                final avail = snapshot.data;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                      enabled: avail?.hasLampDbInPortableDataBase ?? false,
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
              'Πότε παίρνεται',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Το αντίγραφο πυροδοτείται από τις αλλαγές — μετρούν και οι '
              'αλλαγές των συναδέλφων στην κοινόχρηστη βάση. Χωρίς καμία '
              'αλλαγή δεν παίρνεται ποτέ αντίγραφο.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            BackupIntSettingField(
              leadingText: 'Κάθε ',
              trailingText: ' αλλαγές',
              controller: _thresholdController,
              focusNode: _thresholdFocus,
              min: 1,
              max: 9999,
              onPersist: () => _persistIntField(
                _thresholdController,
                (s) => s.changeThreshold,
                (v) => ref
                    .read(databaseBackupSettingsProvider.notifier)
                    .setChangeThreshold(v),
              ),
            ),
            BackupIntSettingField(
              leadingText: 'Το συντομότερο μετά από ',
              trailingText: ' λεπτά',
              controller: _minSpacingController,
              focusNode: _minSpacingFocus,
              min: DatabaseBackupSettings.minAllowedSpacingMinutes,
              max: 1440,
              limitHint:
                  'ελάχιστο '
                  '${DatabaseBackupSettings.minAllowedSpacingMinutes} λεπτά',
              limitTooltip:
                  'Κάθε αντίγραφο διαβάζει ολόκληρη τη βάση μέσα από το '
                  'δίκτυο· πιο συχνά από αυτό, η δουλειά σας θα το νιώθει.',
              onPersist: () => _persistIntField(
                _minSpacingController,
                (s) => s.minSpacingMinutes,
                (v) => ref
                    .read(databaseBackupSettingsProvider.notifier)
                    .setMinSpacingMinutes(v),
              ),
            ),
            BackupIntSettingField(
              leadingText: 'Το αργότερο μετά από ',
              trailingText: ' λεπτά',
              controller: _maxWaitController,
              focusNode: _maxWaitFocus,
              min: DatabaseBackupSettings.minAllowedSpacingMinutes,
              max: 10080,
              onPersist: () => _persistIntField(
                _maxWaitController,
                (s) => s.maxWaitMinutes,
                (v) => ref
                    .read(databaseBackupSettingsProvider.notifier)
                    .setMaxWaitMinutes(v),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Και στο κλείσιμο της εφαρμογής, αν υπάρχουν αφύλακτες αλλαγές',
              ),
              value: settings.backupOnCloseIfPending,
              onChanged: (v) => ref
                  .read(databaseBackupSettingsProvider.notifier)
                  .setBackupOnCloseIfPending(v),
            ),
            _buildBackupScheduleStatusSection(theme, settings),
            const Divider(height: 24),
            Text(
              'Πολιτική διατήρησης',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Χωριστά όρια για τα γρήγορα (.db) και τα πλήρη (.zip)· '
              'διαγράφεται πάντα το παλαιότερο όταν ξεπεραστεί το όριο.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            _retentionRuleRow(
              theme,
              leadingText: 'Γρήγορα: διατήρηση των τελευταίων ',
              trailingText: ' αντιγράφων',
              controller: _maxCopiesController,
              focusNode: _maxCopiesFocus,
              onPersist: _persistRetentionMaxCopies,
              enabled: settings.retentionQuickMaxCopiesEnabled,
              onToggle: (v) => ref
                  .read(databaseBackupSettingsProvider.notifier)
                  .setRetentionQuickMaxCopiesEnabled(v),
            ),
            _retentionRuleRow(
              theme,
              leadingText: 'Γρήγορα: διαγραφή παλαιότερων από ',
              trailingText: ' ημέρες',
              controller: _maxAgeController,
              focusNode: _maxAgeFocus,
              onPersist: _persistRetentionMaxAgeDays,
              enabled: settings.retentionQuickMaxAgeEnabled,
              onToggle: (v) => ref
                  .read(databaseBackupSettingsProvider.notifier)
                  .setRetentionQuickMaxAgeEnabled(v),
            ),
            _retentionRuleRow(
              theme,
              leadingText: 'Πλήρη: διατήρηση των τελευταίων ',
              trailingText: ' αντιγράφων',
              controller: _fullCopiesController,
              focusNode: _fullCopiesFocus,
              onPersist: _persistRetentionFullMaxCopies,
              enabled: settings.retentionFullMaxCopiesEnabled,
              onToggle: (v) => ref
                  .read(databaseBackupSettingsProvider.notifier)
                  .setRetentionFullMaxCopiesEnabled(v),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Το πιο πρόσφατο πλήρες αντίγραφο δεν διαγράφεται ποτέ, '
                'ό,τι κι αν λένε τα όρια.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
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
      ],
    );
  }

  /// Γραμμή «κείμενο [πεδίο] κείμενο» για τις ρυθμίσεις πυροδότησης — ίδιο
  /// μοτίβο με τα πεδία της πολιτικής διατήρησης.
  /// Γραμμή κανόνα διατήρησης: κείμενο, αριθμητικό πεδίο και διακόπτης.
  Widget _retentionRuleRow(
    ThemeData theme, {
    required String leadingText,
    required String trailingText,
    required TextEditingController controller,
    required FocusNode focusNode,
    required Future<void> Function() onPersist,
    required bool enabled,
    required ValueChanged<bool> onToggle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: BackupIntSettingField(
            leadingText: leadingText,
            trailingText: trailingText,
            controller: controller,
            focusNode: focusNode,
            min: 1,
            max: 9999,
            onPersist: onPersist,
          ),
        ),
        Switch(value: enabled, onChanged: onToggle),
      ],
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
