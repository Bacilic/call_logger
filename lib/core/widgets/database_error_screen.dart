import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';

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
import '../utils/user_facing_error_messages.dart';
import '../../features/settings/widgets/create_new_database_dialog.dart';

/// Οθόνη σφάλματος βάσης / γενικού σφάλματος.
/// Λεπτομερή ελληνικά μηνύματα, επιλέξιμο κείμενο, αντιγραφή πλήρους αναφοράς.
class DatabaseErrorScreen extends ConsumerStatefulWidget {
  const DatabaseErrorScreen({
    super.key,
    required this.result,
    required this.dbPath,
    required this.onRetry,
  });

  final DatabaseInitResult result;
  final String? dbPath;
  final Future<void> Function() onRetry;

  @override
  ConsumerState<DatabaseErrorScreen> createState() =>
      _DatabaseErrorScreenState();
}

class _DatabaseErrorScreenState extends ConsumerState<DatabaseErrorScreen> {
  late final ScrollController _detailsScrollController;
  List<String> _recentExistingPaths = const <String>[];

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

  bool get _shouldOfferRestart =>
      _effectiveRecoveryKind == DatabaseInitRecoveryKind.timeout;

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
          _pathsReferToSameFile(path, current)) {
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

  bool _pathsReferToSameFile(String a, String b) {
    final na = p.normalize(a);
    final nb = p.normalize(b);
    if (Platform.isWindows) {
      return na.toLowerCase() == nb.toLowerCase();
    }
    return na == nb;
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
        content: Text('Η νέα βάση δημιουργήθηκε και η εφαρμογή επανασυνδέθηκε.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await widget.onRetry();
  }

  /// Άμεσο άνοιγμα διαλόγου αρχείου/φακέλου· αποθήκευση διαδρομής μέσω [SettingsService] και επανασύνδεση.
  Future<void> _findDatabaseViaPicker() async {
    final picked = await pickDatabasePathWithSystemPicker();
    if (!mounted) return;
    if (picked == null || picked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν επιλέχθηκε αρχείο ή φάκελος.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await _verifyPathAndRetry(picked);
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
    final msg =
        outcome.runner.result.message ?? 'Η βάση δεν πέρασε τον έλεγχο.';
    final det = outcome.runner.result.details?.trim();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Η βάση δεν είναι έγκυρη'),
        content: SingleChildScrollView(
          child: Text(
            det != null && det.isNotEmpty ? '$msg\n\n$det' : msg,
          ),
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

  Future<void> _restoreFromBackup() async {
    final target = _databaseFilePath;
    final backupFolder = await resolveValidBackupDestinationHint(
      container: ProviderScope.containerOf(context),
      candidateDatabasePaths: <String>[
        ..._recentExistingPaths,
        if (target != null && target.isNotEmpty) target,
      ],
    );
    if (!mounted) return;
    await runRestoreFromBackupZipFlow(
      context: context,
      backupFolderHint: backupFolder,
      currentDatabasePath:
          (target != null && target.isNotEmpty) ? target : AppConfig.defaultDbPath,
      onVerifiedSuccess: () async {
        await widget.onRetry();
      },
    );
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
          const TextSpan(
            text: 'Η βάση έχει αλλάξει τοποθεσία. Μπορείτε να ',
          ),
          TextSpan(text: 'αναζητήσετε τη βάση', style: bluePhrase),
          const TextSpan(text: ' σας με το κουμπί '),
          TextSpan(text: 'Επιλογή αρχείου βάσης', style: boldLabel),
          const TextSpan(text: ' ή να '),
          TextSpan(text: 'δημιουργήσετε μία νέα βάση', style: bluePhrase),
          const TextSpan(
            text: ', ΧΩΡΙΣ δεδομένα με το κουμπί ',
          ),
          TextSpan(text: 'Δημιουργία νέας βάσης', style: boldLabel),
          const TextSpan(text: '.'),
        ],
      ),
    );
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
    final text = widget.result.buildClipboardReport(dbPathFallback: widget.dbPath);
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
                child: Tooltip(
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
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
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
    final children = <Widget>[
      _tooltipActionButton(
        label: 'Επιλογή αρχείου βάσης',
        tooltip:
            'Ανοίγει το παράθυρο των Windows για να διαλέξετε ένα υπάρχον '
            'αρχείο βάσης (.db).\n\n'
            'Χρησιμοποιήστε το όταν ξέρετε πού βρίσκεται η σωστή βάση '
            '(π.χ. call_logger.db) και θέλετε να τη συνδέσετε στην εφαρμογή.',
        icon: Icons.folder_open_outlined,
        onPressed: _findDatabaseViaPicker,
      ),
    ];

    if (_shouldOfferRestoreFromBackup) {
      children
        ..add(const SizedBox(width: 8))
        ..add(
          _tooltipActionButton(
            label: 'Επαναφορά από αντίγραφο ασφαλείας',
            tooltip:
                'Ανοίγει επιλογέα για αρχείο .zip αντιγράφου ασφαλείας και '
                'επαναφέρει τη βάση (και σχετικά αρχεία) από αυτό.\n\n'
                'Αν έχετε ορίσει φάκελο αντιγράφων στις ρυθμίσεις και ο '
                'φάκελος υπάρχει, ο επιλογέας ανοίγει εκεί.\n\n'
                'Χρησιμοποιήστε το όταν το τρέχον αρχείο είναι λάθος ή '
                'κατεστραμμένο και έχετε πρόσφατο αντίγραφο ασφαλείας.',
            icon: Icons.settings_backup_restore,
            onPressed: _restoreFromBackup,
          ),
        );
    }

    children
      ..add(const SizedBox(width: 8))
      ..add(
        _tooltipActionButton(
          label: 'Δημιουργία νέας βάσης',
          tooltip:
              'Δημιουργεί ένα ολοκαίνουργιο, κενό αρχείο βάσης (χωρίς παλιά '
              'δεδομένα) και το ορίζει ως ενεργό.\n\n'
              'Χρησιμοποιήστε το μόνο αν θέλετε να ξεκινήσετε από την αρχή. '
              'Τα παλιά δεδομένα δεν μεταφέρονται αυτόματα.',
          icon: Icons.add_circle_outline,
          onPressed: _openSettingsForCreateDatabase,
        ),
      );

    if (_shouldOfferLocateDatabase) {
      children
        ..add(const SizedBox(width: 8))
        ..add(
          _tooltipActionButton(
            label: 'Εμφάνιση φακέλου βάσης',
            tooltip:
                'Ανοίγει τον Εξερευνητή αρχείων των Windows στον φάκελο του '
                'τρέχοντος (προβληματικού) αρχείου .db.\n\n'
                'Δεν αλλάζει τη ρύθμιση της εφαρμογής· χρησιμεύει για να '
                'δείτε, μετονομάσετε ή μετακινήσετε χειροκίνητα το αρχείο.',
            icon: Icons.folder_outlined,
            onPressed: _openFolderContainingDatabaseFile,
          ),
        );
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
              Tooltip(
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
              Tooltip(
                message: _shouldOfferRestart
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
