import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import '../database/backup_destination_hint.dart';
import '../database/database_helper.dart';
import '../database/database_init_result.dart';
import '../database/database_init_runner.dart';
import '../database/database_path_pick_flow.dart';
import '../database/database_restore_flow.dart';
import '../services/settings_service.dart';
import '../updates/update_manifest.dart';
import '../updates/update_providers.dart';
import '../utils/database_path_identity.dart';
import '../utils/user_facing_error_messages.dart';
import 'compact_tooltip.dart';
import '../../features/database/widgets/schema_upgrade_consent_dialog.dart';
import '../../features/settings/widgets/create_new_database_dialog.dart';

/// Οθόνη σφάλματος βάσης / γενικού σφάλματος.
/// Λεπτομερή ελληνικά μηνύματα, επιλέξιμο κείμενο, αντιγραφή πλήρους αναφοράς.
class DatabaseErrorScreen extends ConsumerStatefulWidget {
  const DatabaseErrorScreen({
    super.key,
    required this.result,
    required this.dbPath,
    required this.onRetry,
    @visibleForTesting this.probeAvailableInstallerForTest,
  });

  final DatabaseInitResult result;
  final String? dbPath;
  final Future<void> Function() onRetry;

  /// Παράκαμψη ελέγχου διαθέσιμου installer (μόνο για τεστ).
  final Future<UpdateManifest?> Function()? probeAvailableInstallerForTest;

  @override
  ConsumerState<DatabaseErrorScreen> createState() =>
      _DatabaseErrorScreenState();
}

class _DatabaseErrorScreenState extends ConsumerState<DatabaseErrorScreen> {
  late final ScrollController _detailsScrollController;
  List<String> _recentExistingPaths = const <String>[];
  UpdateManifest? _availableInstaller;

  /// Εφεδρεία για παλιά αποτελέσματα χωρίς [DatabaseInitResult.recoveryKind].
  bool get _isSchemaMigrationRecoveryMessage {
    if (_shouldOfferRestartFromText) return false;
    if (widget.result.status != DatabaseStatus.applicationError) return false;
    final msg = widget.result.message ?? '';
    if (msg.contains('Προέκυψε πρόβλημα κατά την πρόσβαση ή την ενημέρωση') &&
        msg.contains('SQLite')) {
      return false;
    }
    if (msg.contains('Λείπει ο πίνακας') ||
        msg.contains('Λείπει αναμενόμενος πίνακας') ||
        msg.contains('Λείπει η στήλη') ||
        msg.contains('Λείπει αναμενόμενη στήλη')) {
      return true;
    }
    if (msg.contains('κατεστραμμένη ή βρίσκεται σε παλιά μορφή') ||
        msg.contains('κατεστραμμένη ή σε ασύμβατη μορφή')) {
      return true;
    }
    if (msg.contains('αναβάθμιση της βάσης δεδομένων') ||
        msg.contains('αναβάθμιση του σχήματος της βάσης δεδομένων')) {
      return true;
    }
    final det = widget.result.details ?? '';
    if (det.contains('Δοκιμάστε να διαγράψετε') &&
        det.contains('Data Base') &&
        det.contains('Εντολή SQL (Causing statement)')) {
      return true;
    }
    return false;
  }

  bool get _shouldOfferRestartFromText {
    final original = widget.result.originalExceptionText?.toLowerCase() ?? '';
    final details = widget.result.details?.toLowerCase() ?? '';
    return original.contains('timed out') ||
        original.contains('timeoutexception') ||
        details.contains('δεν απάντησε έγκαιρα');
  }

  DatabaseInitRecoveryKind get _effectiveRecoveryKind {
    final explicit = widget.result.recoveryKind;
    if (explicit != null) return explicit;

    if (_shouldOfferRestartFromText) {
      return DatabaseInitRecoveryKind.timeout;
    }
    final msg = widget.result.message ?? '';
    if (msg.contains('είναι η βάση δεδομένων της Λάμπας')) {
      return DatabaseInitRecoveryKind.wrongDatabaseLamp;
    }
    if (msg.contains('δεν είναι βάση της Καταγραφής Κλήσεων')) {
      return DatabaseInitRecoveryKind.wrongDatabaseUnknown;
    }
    if (_isSchemaMigrationRecoveryMessage) {
      return DatabaseInitRecoveryKind.corruptedOrMigration;
    }
    if (widget.result.status == DatabaseStatus.accessDenied &&
        (msg.contains('κλειδωμένο') ||
            msg.contains('database is locked') ||
            msg.contains('κοινή χρήση αρχείου'))) {
      return DatabaseInitRecoveryKind.locked;
    }
    if (widget.result.status == DatabaseStatus.corruptedOrInvalid) {
      return DatabaseInitRecoveryKind.corruptedOrMigration;
    }
    return DatabaseInitRecoveryKind.generic;
  }

  /// Λείπει αρχείο της ΕΓΚΑΤΑΣΤΑΣΗΣ (π.χ. `sqlite3.dll`) — όχι της βάσης.
  bool get _isMissingApplicationFile =>
      _effectiveRecoveryKind == DatabaseInitRecoveryKind.missingApplicationFile;

  /// Κάθε σφάλμα προσφέρει ΜΟΝΟ τη δική του διέξοδο: όταν λείπει αρχείο της
  /// εγκατάστασης, η βάση είναι μια χαρά και κάθε ενέργεια πάνω της αποτυγχάνει
  /// — η «Δημιουργία νέας βάσης» θα έσκαγε με το ίδιο ακριβώς σφάλμα.
  bool get _shouldOfferDatabaseActions => !_isMissingApplicationFile;

  /// Η «Επαναδοκιμή» ξαναπροσπαθεί μόνο το άνοιγμα της βάσης· η μηχανή SQLite
  /// φορτώνεται μία φορά στην εκκίνηση, οπότε χωρίς επανεκκίνηση το σφάλμα
  /// επαναλαμβάνεται αυτούσιο.
  bool get _shouldOfferRestart =>
      _effectiveRecoveryKind == DatabaseInitRecoveryKind.timeout ||
      _isMissingApplicationFile;

  bool get _isFileNotFound =>
      widget.result.status == DatabaseStatus.fileNotFound;

  bool get _shouldOfferLocateDatabase {
    final kind = _effectiveRecoveryKind;
    return kind == DatabaseInitRecoveryKind.wrongDatabaseLamp ||
        kind == DatabaseInitRecoveryKind.wrongDatabaseUnknown ||
        kind == DatabaseInitRecoveryKind.corruptedOrMigration;
  }

  bool get _shouldOfferRestoreFromBackup {
    if (_shouldOfferRestart) return false;
    final kind = _effectiveRecoveryKind;
    if (kind == DatabaseInitRecoveryKind.locked ||
        kind == DatabaseInitRecoveryKind.timeout) {
      return false;
    }
    if (_isFileNotFound) return true;
    return kind == DatabaseInitRecoveryKind.wrongDatabaseLamp ||
        kind == DatabaseInitRecoveryKind.wrongDatabaseUnknown ||
        kind == DatabaseInitRecoveryKind.corruptedOrMigration;
  }

  String? get _databaseFilePath =>
      (widget.result.path ?? widget.dbPath)?.trim();

  static const Color _solutionPhraseBlue = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    _detailsScrollController = ScrollController();
    _loadRecentExistingPaths();
    if (_isMissingApplicationFile) {
      unawaited(_probeAvailableInstaller());
    }
    if (_effectiveRecoveryKind ==
        DatabaseInitRecoveryKind.schemaUpgradeConsent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_offerSchemaUpgradeConsent());
      });
    }
  }

  Future<void> _probeAvailableInstaller() async {
    final probe =
        widget.probeAvailableInstallerForTest ??
        () => ref.read(updateServiceProvider).probeAvailableInstaller();
    final manifest = await probe();
    if (!mounted) return;
    setState(() => _availableInstaller = manifest);
  }

  Future<void> _offerSchemaUpgradeConsent() async {
    await runSchemaUpgradeConsentRecovery(
      context: context,
      result: widget.result,
      onSuccess: widget.onRetry,
    );
  }

  @override
  void dispose() {
    _detailsScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentExistingPaths() async {
    final recent = await SettingsService().getRecentDatabasePaths();
    final current = _databaseFilePath;
    final existing = <String>[];
    for (final raw in recent) {
      final path = raw.trim();
      if (path.isEmpty) continue;
      if (current != null &&
          current.isNotEmpty &&
          databasePathsReferToSameFile(path, current)) {
        continue;
      }
      try {
        // Σύγχρονος έλεγχος: αποφεύγει κρέμασμα FakeAsync/timers στα widget tests
        // και δεν αφήνει εκκρεμή timeout timers.
        if (File(path).existsSync()) {
          existing.add(path);
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _recentExistingPaths = existing);
  }

  Future<void> _openSettingsForCreateDatabase() async {
    // Από την οθόνη σφάλματος δεν ανοίγουμε ολόκληρες Ρυθμίσεις.
    // Δείχνουμε μόνο τον διάλογο δημιουργίας νέου αρχείου βάσης και,
    // αν ολοκληρωθεί, δημιουργούμε το αρχείο, ορίζουμε τη διαδρομή
    // και επαναδοκιμάζουμε την αρχικοποίηση.
    final picked = await pickNewDatabaseSavePath(
      initialPathHint: _databaseFilePath,
    );
    if (!mounted) return;
    if (picked == null) {
      return;
    }

    final validationError = validateNewDatabaseSavePath(picked);
    if (validationError != null) {
      await showNewDatabasePathValidationDialog(context, validationError);
      return;
    }

    final norm = picked;

    // Αν υπάρχει ήδη αρχείο στον στόχο, ζητάμε χειροκίνητη παρέμβαση.
    if (await File(norm).exists()) {
      if (!mounted) return;
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

    // Δημιουργία νέου κενού αρχείου με πλήρες schema.
    try {
      await DatabaseHelper.instance.createNewDatabaseFile(norm);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Αποτυχία δημιουργίας νέας βάσης: ${humanizeUserFacingError(e)}',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    // Έλεγχος / αποθήκευση διαδρομής και επανασύνδεση.
    final outcome = await setAndVerifyDatabasePath(norm);
    if (!mounted) return;

    if (!outcome.ok) {
      await _showVerifyFailureDialog(outcome);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Η νέα βάση δημιουργήθηκε και η εφαρμογή επανασυνδέθηκε.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await widget.onRetry();
  }

  /// Άμεσο άνοιγμα διαλόγου αρχείου/φακέλου· αποθήκευση διαδρομής μέσω [SettingsService] και επανασύνδεση.
  Future<void> _findDatabaseViaPicker() async {
    final picked = await pickDatabasePathWithSystemPicker();
    if (!mounted) return;
    // Ακύρωση επιλογέα = έγκυρη πράξη· κανένα μήνυμα.
    if (picked == null || picked.path.isEmpty) return;
    if (picked.isBackupArchive) {
      await _restoreFromBackup(preselectedZipPath: picked.path);
      return;
    }
    await _verifyPathAndRetry(picked.path);
  }

  Future<void> _applyRecentDatabasePath(String path) async {
    await _verifyPathAndRetry(path);
  }

  Future<void> _verifyPathAndRetry(String path) async {
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

    final outcome = await setAndVerifyDatabasePath(path);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (!outcome.ok) {
      await _showVerifyFailureDialog(outcome);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Η διαδρομή αποθηκεύτηκε. Γίνεται επανασύνδεση…'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await widget.onRetry();
  }

  Future<void> _showVerifyFailureDialog(
    ({bool ok, DatabaseInitRunnerResult runner}) outcome,
  ) async {
    // Αποτυχία που ζητά συγκατάθεση αναβάθμισης ΔΕΝ είναι αδιέξοδο: ο χρήστης
    // πρέπει να πάρει τις ίδιες επιλογές με την αλλαγή βάσης (αντίγραφο /
    // πρωτότυπο / άκυρο), όχι ένα σκέτο «Εντάξει».
    if (outcome.runner.result.recoveryKind ==
        DatabaseInitRecoveryKind.schemaUpgradeConsent) {
      await runSchemaUpgradeConsentRecovery(
        context: context,
        result: outcome.runner.result,
        onSuccess: widget.onRetry,
      );
      return;
    }
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
  }

  Future<void> _restoreFromBackup({String? preselectedZipPath}) async {
    final target = _databaseFilePath;
    final backupFolder = await resolveValidBackupDestinationHint(
      container: ProviderScope.containerOf(context),
      candidateDatabasePaths: <String>[
        ..._recentExistingPaths,
        if (target != null && target.isNotEmpty) target,
      ],
    );
    if (!mounted) return;
    final result = await runRestoreFromBackupZipFlow(
      context: context,
      backupFolderHint: backupFolder,
      currentDatabasePath: (target != null && target.isNotEmpty)
          ? target
          : AppConfig.defaultDbPath,
      preselectedZipPath: preselectedZipPath,
    );
    if (!mounted || result.cancelled) return;
    if (result.failed) return;
    if (!result.isSuccess) return;

    final toOpen = result.pathToOpen?.trim();
    if (toOpen != null && toOpen.isNotEmpty) {
      await _verifyPathAndRetry(toOpen);
    }
  }

  Widget _buildMissingDatabaseGuidance(ThemeData theme) {
    final baseStyle = theme.textTheme.bodyLarge?.copyWith(
      height: 1.45,
      color: theme.colorScheme.onSurface,
    );
    final boldLabel = baseStyle?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface,
    );
    final bluePhrase = baseStyle?.copyWith(
      color: _solutionPhraseBlue,
      fontWeight: FontWeight.w600,
    );

    return SelectableText.rich(
      TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(text: 'Η βάση έχει αλλάξει τοποθεσία. Μπορείτε να '),
          TextSpan(text: 'αναζητήσετε τη βάση', style: bluePhrase),
          const TextSpan(text: ' σας με το κουμπί '),
          TextSpan(text: 'Επιλογή αρχείου βάσης', style: boldLabel),
          const TextSpan(text: ' ή να '),
          TextSpan(text: 'δημιουργήσετε μία νέα βάση', style: bluePhrase),
          const TextSpan(text: ', ΧΩΡΙΣ δεδομένα με το κουμπί '),
          TextSpan(text: 'Δημιουργία νέας βάσης', style: boldLabel),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }

  /// Καθησυχασμός όταν έσπασε η εγκατάσταση, όχι η βάση.
  Widget _buildMissingApplicationFileReassurance(ThemeData theme) {
    final baseStyle = theme.textTheme.bodyLarge?.copyWith(
      height: 1.45,
      color: theme.colorScheme.onSurface,
    );
    final bluePhrase = baseStyle?.copyWith(
      color: _solutionPhraseBlue,
      fontWeight: FontWeight.w600,
    );

    return SelectableText.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: 'Τα δεδομένα σας είναι ασφαλή', style: bluePhrase),
          const TextSpan(
            text:
                ': η βάση αποθηκεύεται έξω από τον φάκελο της εφαρμογής. '
                'Έσπασε η εγκατάσταση, όχι η βάση — η επανεγκατάσταση '
                'ξαναγράφει μόνο τα αρχεία της εφαρμογής και δεν προκαλεί '
                'καμία απώλεια δεδομένων.',
          ),
        ],
      ),
    );
  }

  Future<void> _repairInstallation() async {
    final manifest = _availableInstaller;
    if (manifest == null) return;
    try {
      final result = await repairInstallationFromPackage(
        ref.read(updateInstallerServiceProvider),
        manifest: manifest,
      );
      if (result.success || !mounted) return;
      final detail = result.failedStep == null
          ? (result.message ?? 'Άγνωστο σφάλμα')
          : 'Στο βήμα «${result.failedStep}»: ${result.message ?? ''}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Η επιδιόρθωση εγκατάστασης απέτυχε. $detail'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Η επιδιόρθωση εγκατάστασης απέτυχε. '
            '${humanizeUserFacingError(e)}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String get _fallbackShortTitle {
    switch (widget.result.status) {
      case DatabaseStatus.fileNotFound:
        return 'Δεν βρέθηκε βάση δεδομένων.';
      case DatabaseStatus.accessDenied:
        return 'Πρόβλημα πρόσβασης στο αρχείο βάσης.';
      case DatabaseStatus.corruptedOrInvalid:
        return 'Μη έγκυρο ή κατεστραμμένο αρχείο βάσης.';
      case DatabaseStatus.applicationError:
        return 'Σφάλμα εφαρμογής ή υποσυστήματος.';
      case DatabaseStatus.success:
        return widget.result.message ?? 'Η σύνδεση πέτυχε.';
    }
  }

  String get _primaryMessage {
    final m = widget.result.message?.trim();
    if (m != null && m.isNotEmpty) return m;
    return _fallbackShortTitle;
  }

  Future<void> _copyFullReport(BuildContext context) async {
    final text = widget.result.buildClipboardReport(
      dbPathFallback: widget.dbPath,
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Αντιγράφηκε πλήρης αναφορά σφάλματος στο πρόχειρο.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Άνοιγμα του Windows Explorer στο προβληματικό αρχείο .db (`/select,`).
  Future<void> _openFolderContainingDatabaseFile() async {
    final full = _databaseFilePath;
    if (full == null || full.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Δεν υπάρχει γνωστή διαδρομή αρχείου βάσης για εμφάνιση φακέλου.',
          ),
        ),
      );
      return;
    }
    if (!Platform.isWindows) {
      try {
        final dir = Directory(full).parent.path;
        await Process.run('explorer', [dir]);
      } catch (_) {}
      return;
    }
    try {
      final normalized = full.replaceAll('/', r'\');
      await Process.run('explorer.exe', ['/select,', normalized]);
    } catch (_) {
      try {
        await Process.run('explorer.exe', [Directory(full).parent.path]);
      } catch (_) {}
    }
  }

  Future<void> _restartApplication(BuildContext context) async {
    try {
      await Process.start(
        Platform.resolvedExecutable,
        Platform.executableArguments,
        mode: ProcessStartMode.detached,
      );
      exit(0);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Η αυτόματη επανεκκίνηση δεν ήταν δυνατή. Κλείστε και ανοίξτε ξανά την εφαρμογή.',
          ),
        ),
      );
    }
  }

  Widget _buildRecentDatabasesSection(ThemeData theme) {
    if (!_shouldOfferDatabaseActions) return const SizedBox.shrink();
    if (_recentExistingPaths.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Πρόσφατες έγκυρες βάσεις',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < _recentExistingPaths.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: CompactTooltip(
                  message:
                      'Γρήγορη επιστροφή σε προηγούμενη έγκυρη βάση.\n\n'
                      'Πατήστε για να συνδέσετε ξανά αυτό το αρχείο '
                      '(χωρίς να ανοίξετε τον επιλογέα αρχείων).\n\n'
                      'Πλήρης διαδρομή:\n${_recentExistingPaths[i]}',
                  waitDuration: const Duration(milliseconds: 350),
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _applyRecentDatabasePath(_recentExistingPaths[i]),
                    icon: const Icon(Icons.history, size: 18),
                    label: Text(
                      p.basename(_recentExistingPaths[i]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _tooltipActionButton({
    required String label,
    required String message,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: CompactTooltip(
        message: message,
        waitDuration: const Duration(milliseconds: 350),
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          ),
          label: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryActionsRow() {
    // Κάθε κουμπί μπαίνει μόνο αν η διέξοδός του έχει νόημα για ΑΥΤΟ το σφάλμα·
    // τα κενά ανάμεσά τους παρεμβάλλονται στο τέλος, ώστε ένα κρυμμένο κουμπί
    // να μην αφήνει πίσω του αδέσποτο διάστημα.
    final repairInstaller = _availableInstaller;
    final buttons = <Widget>[
      if (_isMissingApplicationFile && repairInstaller != null)
        _tooltipActionButton(
          label: repairInstaller.version.isNotEmpty
              ? 'Επιδιόρθωση εγκατάστασης (${repairInstaller.version})'
              : 'Επιδιόρθωση εγκατάστασης',
          message:
              'Ξαναγράφει τα αρχεία της εφαρμογής από το διαθέσιμο πακέτο '
              'ενημερώσεων'
              '${repairInstaller.version.isNotEmpty ? ' — θα εγκατασταθεί η έκδοση ${repairInstaller.version}' : ''}.\n\n'
              'Δεν αγγίζει τη βάση δεδομένων ούτε τα δεδομένα σας.\n\n'
              'Χρησιμοποιήστε το όταν λείπει αρχείο της εγκατάστασης '
              '(π.χ. sqlite3.dll) και υπάρχει έτοιμος installer στον φάκελο '
              'ενημερώσεων.',
          icon: Icons.system_update_alt,
          onPressed: _repairInstallation,
        ),
      if (_shouldOfferDatabaseActions)
        _tooltipActionButton(
          label: 'Επιλογή αρχείου βάσης',
          message:
              'Ανοίγει το παράθυρο των Windows για να διαλέξετε ένα υπάρχον '
              'αρχείο βάσης (.db).\n\n'
              'Χρησιμοποιήστε το όταν ξέρετε πού βρίσκεται η σωστή βάση '
              '(π.χ. call_logger.db) και θέλετε να τη συνδέσετε στην εφαρμογή.',
          icon: Icons.folder_open_outlined,
          onPressed: _findDatabaseViaPicker,
        ),
      if (_shouldOfferRestoreFromBackup)
        _tooltipActionButton(
          label: 'Επαναφορά από αντίγραφο ασφαλείας',
          message:
              'Ανοίγει επιλογέα για αρχείο .zip αντιγράφου ασφαλείας και '
              'επαναφέρει τη βάση (και σχετικά αρχεία) από αυτό.\n\n'
              'Αν έχετε ορίσει φάκελο αντιγράφων στις ρυθμίσεις και ο '
              'φάκελος υπάρχει, ο επιλογέας ανοίγει εκεί.\n\n'
              'Χρησιμοποιήστε το όταν το τρέχον αρχείο είναι λάθος ή '
              'κατεστραμμένο και έχετε πρόσφατο αντίγραφο ασφαλείας.',
          icon: Icons.settings_backup_restore,
          onPressed: _restoreFromBackup,
        ),
      if (_shouldOfferDatabaseActions)
        _tooltipActionButton(
          label: 'Δημιουργία νέας βάσης',
          message:
              'Δημιουργεί ένα ολοκαίνουργιο, κενό αρχείο βάσης (χωρίς παλιά '
              'δεδομένα) και το ορίζει ως ενεργό.\n\n'
              'Χρησιμοποιήστε το μόνο αν θέλετε να ξεκινήσετε από την αρχή. '
              'Τα παλιά δεδομένα δεν μεταφέρονται αυτόματα.',
          icon: Icons.add_circle_outline,
          onPressed: _openSettingsForCreateDatabase,
        ),
      if (_shouldOfferLocateDatabase)
        _tooltipActionButton(
          label: 'Εμφάνιση φακέλου βάσης',
          message:
              'Ανοίγει τον Εξερευνητή αρχείων των Windows στον φάκελο του '
              'τρέχοντος (προβληματικού) αρχείου .db.\n\n'
              'Δεν αλλάζει τη ρύθμιση της εφαρμογής· χρησιμεύει για να '
              'δείτε, μετονομάσετε ή μετακινήσετε χειροκίνητα το αρχείο.',
          icon: Icons.folder_outlined,
          onPressed: _openFolderContainingDatabaseFile,
        ),
    ];

    if (buttons.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < buttons.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 8));
      children.add(buttons[i]);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = widget.result.path ?? widget.dbPath;
    final details = widget.result.details?.trim();
    final original = widget.result.originalExceptionText?.trim();
    final stack = widget.result.stackTraceText?.trim();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.error_outline,
                size: 56,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Σφάλμα',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Scrollbar(
                  controller: _detailsScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _detailsScrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SelectableText(
                          _primaryMessage,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        if (_isMissingApplicationFile) ...[
                          const SizedBox(height: 18),
                          _buildMissingApplicationFileReassurance(theme),
                        ],
                        if (_isFileNotFound && !_shouldOfferRestart) ...[
                          const SizedBox(height: 18),
                          _buildMissingDatabaseGuidance(theme),
                        ],
                        if (details != null && details.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          SelectableText(
                            details,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (path != null && path.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Διαδρομή',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            path,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (widget.result.technicalCode != null &&
                            widget.result.technicalCode!.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Κωδικός / αναγνωριστικό',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            widget.result.technicalCode!.trim(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (original != null && original.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Αρχικό μήνυμα σφάλματος (runtime)',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            original,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (stack != null && stack.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Stack trace',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            stack,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              CompactTooltip(
                message:
                    'Αντιγράφει στο πρόχειρο ολόκληρη την τεχνική αναφορά '
                    '(μήνυμα, διαδρομή, runtime σφάλμα, stack trace).\n\n'
                    'Χρήσιμο όταν χρειάζεται να στείλετε το πρόβλημα για '
                    'διάγνωση ή υποστήριξη.',
                waitDuration: const Duration(milliseconds: 350),
                child: FilledButton.tonalIcon(
                  onPressed: () => _copyFullReport(context),
                  icon: const Icon(Icons.copy),
                  label: const Text('Αντιγραφή πλήρους σφάλματος'),
                ),
              ),
              const SizedBox(height: 12),
              _buildRecentDatabasesSection(theme),
              _buildPrimaryActionsRow(),
              const SizedBox(height: 12),
              CompactTooltip(
                message: _isMissingApplicationFile
                    ? 'Κλείνει την εφαρμογή και την ανοίγει ξανά από την αρχή.\n\n'
                          'Λείπει αρχείο της εγκατάστασης. Η επαναδοκιμή δεν '
                          'βοηθά εδώ: το αρχείο φορτώνεται μία φορά στο ξεκίνημα '
                          'της εφαρμογής.\n\n'
                          'Αν έχετε ήδη επαναφέρει το αρχείο (π.χ. από την '
                          'καραντίνα του antivirus), η επανεκκίνηση θα το βρει.'
                    : _shouldOfferRestart
                    ? 'Κλείνει την εφαρμογή και την ανοίγει ξανά από την αρχή.\n\n'
                          'Χρησιμοποιήστε το όταν η βάση δεν απάντησε εγκαίρως '
                          '(timeout) και μια απλή επαναδοκιμή δεν αρκεί.'
                    : 'Ξαναδοκιμάζει το άνοιγμα της τρέχουσας βάσης χωρίς '
                          'να αλλάξει διαδρομή.\n\n'
                          'Χρήσιμο αν το πρόβλημα ήταν προσωρινό (δίκτυο, '
                          'κλείδωμα που λύθηκε). Αν το αρχείο είναι λάθος, '
                          'επιλέξτε άλλο αρχείο ή πρόσφατη βάση.',
                waitDuration: const Duration(milliseconds: 350),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    if (_shouldOfferRestart) {
                      await _restartApplication(context);
                      return;
                    }
                    await widget.onRetry();
                  },
                  icon: Icon(
                    _shouldOfferRestart ? Icons.restart_alt : Icons.refresh,
                  ),
                  label: Text(
                    _shouldOfferRestart
                        ? 'Επανεκκίνηση εφαρμογής'
                        : 'Επαναδοκιμή',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
