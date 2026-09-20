import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/active_database_generation.dart';
import '../../../core/database/backup_pending_changes.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/models/app_permission.dart';
import '../../../core/providers/core_lexicon_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/file_picker_initial_directory.dart';
import '../../../core/utils/file_picker_session.dart';
import '../models/database_backup_settings.dart';
import '../providers/backup_scheduler_provider.dart';
import '../providers/database_backup_settings_provider.dart';
import '../services/backup_destination_resolver.dart';
import '../services/database_backup_audit.dart';
import '../services/manual_backup_runner.dart';
import '../utils/backup_destination_folder_validator.dart';
import '../utils/backup_location_hints.dart';
import '../utils/backup_restore_tooltip.dart';
import '../utils/portable_backup_availability.dart';
import 'backup_folder_missing_dialog.dart';
import 'backup_tab_contents_section.dart';
import 'backup_tab_destination_section.dart';
import 'backup_tab_form_controllers.dart';
import 'backup_tab_retention_section.dart';
import 'backup_tab_schedule_section.dart';
import 'broken_backup_dialog.dart';
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
/// Ενορχηστρώνει — δεν χτίζει. Κρατά την κατάσταση (πεδία, φορτώσεις,
/// χρονιστής), και κάθε ενότητα της οθόνης ζει στο δικό της widget. Ο απλός
/// χρήστης (χωρίς δικαίωμα πλήρους αντιγράφου) βλέπει μόνο ποιος τα
/// χειρίζεται.
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
  final BackupTabFormControllers _fields = BackupTabFormControllers();

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

  /// Τι υπάρχει διαθέσιμο για πλήρες αντίγραφο, ελεγμένο **μία φορά** ανά
  /// κατάσταση λεξικού.
  ///
  /// Ο έλεγχος σαρώνει τρεις φακέλους (κατόψεις, εικόνες εργαλείων, βάση
  /// Λάμπας). Όσο το αίτημα φτιαχνόταν μέσα στο χτίσιμο της καρτέλας, κάθε
  /// πάτημα διακόπτη τους ξανασάρωνε όλους — και ο φάκελος της βάσης είναι
  /// συχνά δικτυακός.
  bool? _availabilityForLexiconLoaded;
  Future<PortableBackupAvailability>? _portableAvailabilityFuture;

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
    _reloadLocationAndWarningFutures();
    _reloadPendingChangesFuture();
    _fields.destinationFocus.addListener(_onDestinationFocusChanged);
    _fields.destination.addListener(_onDestinationTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fields.syncFromSettings(ref.read(databaseBackupSettingsProvider));
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
    _fields.destinationFocus.removeListener(_onDestinationFocusChanged);
    _fields.destination.removeListener(_onDestinationTextChanged);
    _fields.dispose();
    super.dispose();
  }

  // ── Φορτώσεις ──────────────────────────────────────────────────────────

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
    return (
      dbPath: dbPath,
      eligibleWindowsVolumeCount:
          BackupLocationHints.eligibleWindowsBackupVolumeCount(),
    );
  }

  Future<PortableBackupAvailability> _portableAvailability({
    required bool lexiconLoaded,
  }) {
    if (_availabilityForLexiconLoaded != lexiconLoaded ||
        _portableAvailabilityFuture == null) {
      _availabilityForLexiconLoaded = lexiconLoaded;
      _portableAvailabilityFuture = PortableBackupAvailability.load(
        lexiconLoaded: lexiconLoaded,
      );
    }
    return _portableAvailabilityFuture!;
  }

  // ── Φάκελος προορισμού ─────────────────────────────────────────────────

  void _onDestinationFocusChanged() {
    if (!_fields.destinationFocus.hasFocus) {
      unawaited(_validateAndPersistDestination());
    }
  }

  /// Κάθε πληκτρολόγηση ξαναχτίζει — και αυτό ΔΕΝ είναι σπατάλη.
  ///
  /// Οι προειδοποιήσεις συστέγασης κρίνουν το κείμενο που γράφεται τώρα, όχι
  /// την αποθηκευμένη ρύθμιση· χωρίς το χτίσιμο θα έμεναν παγωμένες στην
  /// προηγούμενη διαδρομή. Το μήνυμα σφάλματος σβήνεται στην ίδια κίνηση.
  void _onDestinationTextChanged() {
    if (!mounted) return;
    setState(() => _destinationFolderError = null);
  }

  Future<bool> _confirmCreateBackupDestinationFolder(String folderPath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Δημιουργία φακέλου'),
        content: Text(
          'Ο φάκελος δεν υπάρχει:\n\n$folderPath\n\nΘέλετε να δημιουργηθεί;',
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

  /// Ο μετρητής γενιάς κόβει απαντήσεις που άργησαν: όσο ο χρήστης
  /// πληκτρολογεί, μια παλιά επικύρωση δεν επιτρέπεται να γράψει το μήνυμά
  /// της πάνω από τη νεότερη.
  Future<void> _validateAndPersistDestination() async {
    final gen = ++_destinationValidationGen;
    final raw = _fields.destination.text;

    final resolution = await resolveBackupDestination(
      raw,
      confirmCreate: _confirmCreateBackupDestinationFolder,
    );
    if (!mounted || gen != _destinationValidationGen) return;

    if (resolution.isValid) {
      setState(() => _destinationFolderError = null);
      await ref
          .read(databaseBackupSettingsProvider.notifier)
          .setDestinationDirectory(raw.trim());
      if (!mounted) return;
      _reloadDestinationContentFuture();
      return;
    }
    setState(() => _destinationFolderError = resolution.errorMessage);
  }

  Future<void> _pickFolder() async {
    final initialDirectory = initialDirectoryForFilePicker(
      _fields.destination.text,
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
    _fields.destination.text = path;
    await _validateAndPersistDestination();
  }

  // ── Αποθήκευση αριθμητικών πεδίων ──────────────────────────────────────

  Future<void> _persist(
    TextEditingController controller,
    int Function(DatabaseBackupSettings s) read,
    Future<void> Function(int value) save,
  ) {
    return persistIntField(
      controller: controller,
      save: save,
      readApplied: () =>
          read(ref.read(databaseBackupSettingsProvider)).toString(),
      stillMounted: () => mounted,
    );
  }

  DatabaseBackupSettingsNotifier get _notifier =>
      ref.read(databaseBackupSettingsProvider.notifier);

  // ── Χειροκίνητο αντίγραφο ──────────────────────────────────────────────

  Future<void> _runBackupNow() async {
    final settings = ref.read(databaseBackupSettingsProvider);
    final destination = settings.destinationDirectory.trim();
    final messenger = ScaffoldMessenger.of(context);

    final result = await runManualBackup(
      settings: settings,
      inspectDestination: _loadDestinationContent,
      markBackupTaken:
          ({
            required int auditId,
            required DateTime at,
            required String? fullFingerprint,
            required DateTime? fullAt,
          }) => _notifier.markBackupTaken(
            auditId: auditId,
            at: at,
            manual: true,
            fullFingerprint: fullFingerprint,
            fullAt: fullAt,
          ),
    );
    if (!mounted) return;

    switch (result.outcome) {
      case ManualBackupOutcome.folderMissing:
        await showBackupFolderMissingDialog(
          context: context,
          ref: ref,
          folderPath: destination,
          auditTrigger: BackupAuditTrigger.manual,
          dismissSetsStatusNone: false,
        );
        if (mounted) setState(_reloadDestinationContentFuture);
      case ManualBackupOutcome.success:
        setState(() {
          _reloadDestinationContentFuture();
          _reloadPendingChangesFuture();
        });
        ref.invalidate(backupRestoreTooltipProvider);
        messenger.showSnackBar(SnackBar(content: Text(result.message!)));
      case ManualBackupOutcome.verificationFailed:
        // Ο φάκελος ξαναδιαβάζεται ούτως ή άλλως: το αρχείο άλλαξε όνομα, και
        // η λίστα αντιγράφων δείχνει ακόμη το παλιό.
        setState(_reloadDestinationContentFuture);
        ref.invalidate(backupRestoreTooltipProvider);
        await showBrokenBackupDialog(
          context: context,
          brokenFilePath: result.brokenFilePath!,
          reason: result.message ?? 'Το αντίγραφο δεν άνοιξε για έλεγχο.',
        );
        if (mounted) setState(_reloadDestinationContentFuture);
      case ManualBackupOutcome.failure:
        messenger.showSnackBar(
          SnackBar(
            content: Text(result.message!),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
    }
  }

  // ── Χτίσιμο ────────────────────────────────────────────────────────────

  /// Τα πεδία ακολουθούν τις ρυθμίσεις όταν αυτές αλλάξουν από αλλού.
  ///
  /// Η ενημέρωση controller μέσα στο `listen` (συγχρονά) προκαλεί «Build
  /// scheduled during frame» — γι' αυτό μετατίθεται στο επόμενο καρέ.
  void _listenForSettingsChanges() {
    ref.listen(databaseBackupSettingsProvider, (prev, next) {
      if (prev == next) return;
      final syncDestination =
          prev == null ||
          prev.destinationDirectory != next.destinationDirectory;
      final syncQuickMaxCopies =
          prev == null ||
          prev.retentionQuickMaxCopies != next.retentionQuickMaxCopies;
      final syncQuickMaxAge =
          prev == null ||
          prev.retentionQuickMaxAgeDays != next.retentionQuickMaxAgeDays;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (syncDestination && !_fields.destinationFocus.hasFocus) {
          setState(() => _destinationFolderError = null);
        }
        _fields.syncFromSettings(
          ref.read(databaseBackupSettingsProvider),
          syncDestination: syncDestination,
          syncRetentionMaxCopies: syncQuickMaxCopies,
          syncRetentionMaxAgeDays: syncQuickMaxAge,
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
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final settings = ref.watch(databaseBackupSettingsProvider);
    _listenForSettingsChanges();

    // Φάση 2: το πλήρες αντίγραφο είναι δουλειά του διαχειριστή. Ο απλός
    // χρήστης δεν βλέπει τις ενότητες — βλέπει ποιος τις χειρίζεται.
    // Χωρίς συνδεδεμένο χρήστη: όλα ως έχουν.
    final canManageFullBackup = PermissionService.instance.can(
      AppPermission.fullBackup,
    );
    if (!canManageFullBackup) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [BackupManagedByAdminNotice()],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAutoBackupSwitch(theme, settings),
        if (!settings.backupOnExit) ...[
          const SizedBox(height: 8),
          Text(
            'Ενεργοποιήστε το διακόπτη για να εμφανιστούν όλες οι σχετικές '
            'ρυθμίσεις.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (settings.backupOnExit) ...[
          BackupTabDestinationSection(
            controller: _fields.destination,
            focusNode: _fields.destinationFocus,
            errorText: _destinationFolderError,
            onPickFolder: _pickFolder,
            onCommit: () => unawaited(_validateAndPersistDestination()),
            locationCaptionsFuture: _locationCaptionSegmentsFuture,
            destinationContentFuture: _destinationContentFuture,
            warningContextFuture: _backupDestinationWarningContextFuture,
            configuredDestination: settings.destinationDirectory,
            showSystemDriveWarning:
                settings.destinationLooksLikeWindowsSystemDriveC,
          ),
          const SizedBox(height: 12),
          _buildNamingFormatField(settings),
          const SizedBox(height: 12),
          BackupTabContentsSection(
            settings: settings,
            availabilityFuture: _portableAvailability(
              lexiconLoaded: ref.watch(coreLexiconProvider).loaded,
            ),
            onToggleMapImages: _notifier.setIncludeMapImagesInBackup,
            onToggleToolImages: _notifier.setIncludeToolImages,
            onToggleLexicon: _notifier.setIncludeLexicon,
            onToggleLampDb: _notifier.setIncludeLampDb,
          ),
          const Divider(height: 24),
          const SizedBox(height: 12),
          BackupTabTriggerSection(
            settings: settings,
            thresholdController: _fields.threshold,
            thresholdFocus: _fields.thresholdFocus,
            onPersistThreshold: () => _persist(
              _fields.threshold,
              (s) => s.changeThreshold,
              _notifier.setChangeThreshold,
            ),
            minSpacingController: _fields.minSpacing,
            minSpacingFocus: _fields.minSpacingFocus,
            onPersistMinSpacing: () => _persist(
              _fields.minSpacing,
              (s) => s.minSpacingMinutes,
              _notifier.setMinSpacingMinutes,
            ),
            maxWaitController: _fields.maxWait,
            maxWaitFocus: _fields.maxWaitFocus,
            onPersistMaxWait: () => _persist(
              _fields.maxWait,
              (s) => s.maxWaitMinutes,
              _notifier.setMaxWaitMinutes,
            ),
            onToggleBackupOnClose: _notifier.setBackupOnCloseIfPending,
          ),
          _buildScheduleStatus(settings),
          const Divider(height: 24),
          BackupTabRetentionSection(
            settings: settings,
            quickMaxCopiesController: _fields.maxCopies,
            quickMaxCopiesFocus: _fields.maxCopiesFocus,
            onPersistQuickMaxCopies: () => _persist(
              _fields.maxCopies,
              (s) => s.retentionQuickMaxCopies,
              _notifier.setRetentionQuickMaxCopies,
            ),
            onToggleQuickMaxCopies: _notifier.setRetentionQuickMaxCopiesEnabled,
            quickMaxAgeController: _fields.maxAge,
            quickMaxAgeFocus: _fields.maxAgeFocus,
            onPersistQuickMaxAge: () => _persist(
              _fields.maxAge,
              (s) => s.retentionQuickMaxAgeDays,
              _notifier.setRetentionQuickMaxAgeDays,
            ),
            onToggleQuickMaxAge: _notifier.setRetentionQuickMaxAgeEnabled,
            fullMaxCopiesController: _fields.fullCopies,
            fullMaxCopiesFocus: _fields.fullCopiesFocus,
            onPersistFullMaxCopies: () => _persist(
              _fields.fullCopies,
              (s) => s.retentionFullMaxCopies,
              _notifier.setRetentionFullMaxCopies,
            ),
            onToggleFullMaxCopies: _notifier.setRetentionFullMaxCopiesEnabled,
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
    );
  }

  Widget _buildAutoBackupSwitch(
    ThemeData theme,
    DatabaseBackupSettings settings,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Αυτόματα αντίγραφα ασφαλείας'),
            subtitle: const Text(
              'Ενεργοποίηση\\Απενεργοποίηση Αυτόματων Αντιγράφων ασφαλείας '
              'της εφαρμογής.',
            ),
            value: settings.backupOnExit,
            onChanged: _notifier.setBackupOnExit,
          ),
        ),
        SettingsPanelInfoTooltip(
          message: _backupSafetyTooltipMessage,
          iconColor: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }

  Widget _buildNamingFormatField(DatabaseBackupSettings settings) {
    return DropdownButtonFormField<DatabaseBackupNamingFormat>(
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
        _notifier.setNamingFormat(v);
      },
    );
  }

  Widget _buildScheduleStatus(DatabaseBackupSettings settings) {
    ref.watch(backupSchedulerProvider);
    final jobRunning = ref
        .read(backupSchedulerProvider.notifier)
        .isBackupJobRunning;
    return FutureBuilder<int>(
      future: _pendingChangesFuture,
      builder: (context, snapshot) => BackupTabScheduleStatus(
        settings: settings,
        pendingChanges: snapshot.data ?? 0,
        jobRunning: jobRunning,
        destinationContentFuture: _destinationContentFuture,
        databaseBaseName: _currentDbPath.trim().isEmpty
            ? null
            : p.basenameWithoutExtension(_currentDbPath),
      ),
    );
  }
}
