import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/about/providers/app_version_provider.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/updates/network_folder_classifier.dart';
import '../../../core/updates/update_folder_status.dart';
import '../../../core/utils/elapsed_stopwatch_format.dart';
import '../../../core/utils/file_picker_initial_directory.dart';
import '../../../core/utils/file_picker_session.dart';
import '../../../core/utils/search_debouncer.dart';
import '../../../core/widgets/compact_tooltip.dart';
import '../../../core/widgets/draggable_dialog_shell.dart';
import '../utils/backup_destination_folder_validator.dart';
import 'build_output_log.dart';
import 'publish_cli.dart';
import 'publish_reminder_provider.dart';
import 'release_process_runner.dart';
import 'release_publisher_service.dart';

/// Κάρτα «Δημοσίευση έκδοσης» — μόνο στα Σενάρια σφαλμάτων (debug).
class ReleasePublisherCard extends ConsumerStatefulWidget {
  const ReleasePublisherCard({
    super.key,
    this.networkFolderClassifier,
    this.networkClassifyDebounce = const Duration(milliseconds: 400),
    this.serviceFactory,
  });

  /// Προαιρετικός classifier (τεστ / έγχυση)· αλλιώς [NetworkFolderClassifier.system].
  final NetworkFolderClassifier? networkFolderClassifier;

  /// Καθυστέρηση debounce πριν τον έλεγχο δικτυακής διαδρομής.
  final Duration networkClassifyDebounce;

  /// Προαιρετική κατασκευή service (τεστ)· αλλιώς πραγματικό flutter build.
  final ReleasePublisherService Function({
    required String updateFolderPath,
    void Function(String message)? onProgress,
  })?
  serviceFactory;

  @override
  ConsumerState<ReleasePublisherCard> createState() =>
      _ReleasePublisherCardState();
}

class _ReleasePublisherCardState extends ConsumerState<ReleasePublisherCard> {
  final _folderController = TextEditingController();
  final _buildOutputLog = BuildOutputLog();
  late final SearchDebouncer _networkClassifyDebouncer;
  bool _running = false;
  String? _statusMessage;
  bool _statusIsError = false;
  String? _folderError;
  bool _folderValid = false;
  int _validationGen = 0;
  bool _showLocalOnlyWarning = false;
  UpdateFolderStatus? _folderStatus;
  final Stopwatch _actionStopwatch = Stopwatch();
  Timer? _elapsedTimer;
  String _elapsedLabel = _initialElapsedLabel;

  static final String _initialElapsedLabel = formatElapsedWithMillis(
    Duration.zero,
  );

  static const _publishDescription =
      'Πλήρης δημοσίευση νέας έκδοσης: σφραγίζει το ιστορικό αλλαγών, '
      'αυξάνει τον αριθμό έκδοσης, χτίζει την εφαρμογή από την αρχή και '
      'αντιγράφει το συμπιεσμένο πακέτο μαζί με τον εγκαταστάτη στον φάκελο '
      'ενημερώσεων. Διαρκεί αρκετά λεπτά.';

  static const _installerDescription =
      'Γράφει ΜΟΝΟ το αρχείο εγκατάστασης (install_call_logger.bat) στον '
      'φάκελο ενημερώσεων. Δεν χτίζει την εφαρμογή, δεν αλλάζει έκδοση και '
      'δεν αγγίζει το ιστορικό.';

  static const _folderRequirement =
      'Ορίστε έγκυρο εγγράψιμο φάκελο ενημερώσεων';

  /// Η υπόδειξη λέει πάντα **τι κάνει** το κουμπί· όταν είναι ανενεργό λόγω
  /// φακέλου, προστίθεται και η αιτία. Όσο τρέχει μια ενέργεια δεν προστίθεται
  /// τίποτα — το κουμπί είναι ανενεργό επειδή δουλεύει, όχι επειδή λείπει κάτι.
  String _actionTooltip(String description) => (_canPublish || _running)
      ? description
      : '$description\n\n$_folderRequirement';

  NetworkFolderClassifier get _classifier =>
      widget.networkFolderClassifier ?? NetworkFolderClassifier.system();

  @override
  void initState() {
    super.initState();
    _networkClassifyDebouncer = SearchDebouncer(
      delay: widget.networkClassifyDebounce,
    );
    _folderController.addListener(_onFolderTextChanged);
    _loadFolder();
  }

  Future<void> _loadFolder() async {
    final path = await SettingsService().catalogs.getUpdateFolderPath();
    if (!mounted) return;
    if (path != null && path.isNotEmpty) {
      _folderController.text = path;
      await _validateAndPersistFolder(offerCreateIfMissing: false);
    }
  }

  @override
  void dispose() {
    _folderController.removeListener(_onFolderTextChanged);
    _stopActionTimer(freezeLabel: false);
    _networkClassifyDebouncer.dispose();
    _folderController.dispose();
    _buildOutputLog.dispose();
    super.dispose();
  }

  void _onFolderTextChanged() {
    unawaited(_validateAndPersistFolder(offerCreateIfMissing: false));
    _scheduleNetworkFolderClassify();
  }

  void _scheduleNetworkFolderClassify() {
    final text = _folderController.text;
    _networkClassifyDebouncer.run(text, (q, isCurrent) async {
      final trimmed = q.trim();
      if (trimmed.isEmpty) {
        if (!isCurrent() || !mounted) return;
        setState(() => _showLocalOnlyWarning = false);
        return;
      }
      final kind = await _classifier.classify(trimmed);
      if (!isCurrent() || !mounted) return;
      setState(() {
        _showLocalOnlyWarning = kind == NetworkFolderKind.localOnly;
      });
    });
  }

  void _startActionTimer() {
    _elapsedTimer?.cancel();
    _actionStopwatch
      ..reset()
      ..start();
    _elapsedLabel = _initialElapsedLabel;
    // Ρυθμός ανανέωσης πυκνότερος από τα χιλιοστά που δείχνει: χωρίς αυτό ο
    // αριθμός θα «κολλούσε» ανά δευτερόλεπτο και τα χιλιοστά θα ήταν διακοσμητικά.
    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedLabel = formatElapsedWithMillis(_actionStopwatch.elapsed);
      });
    });
  }

  void _stopActionTimer({bool freezeLabel = true}) {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    if (_actionStopwatch.isRunning) {
      _actionStopwatch.stop();
    }
    if (freezeLabel) {
      _elapsedLabel = formatElapsedWithMillis(_actionStopwatch.elapsed);
    }
  }

  void _appendLog(String line) {
    final stamp = formatElapsedWithMillis(_actionStopwatch.elapsed);
    _buildOutputLog.append('[$stamp] $line');
  }

  bool get _canPublish =>
      !_running && _folderValid && _folderController.text.trim().isNotEmpty;

  Future<bool> _confirmCreateFolder(String folderPath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => DraggableDialogShell(
        title: const Text('Δημιουργία φακέλου'),
        builder: (titleHandle) => AlertDialog(
          title: titleHandle,
          content: const Text('Ο φάκελος δεν υπάρχει. Να δημιουργηθεί;'),
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
      ),
    );
    return confirmed == true;
  }

  Future<bool> _createFolderIfConfirmed(String folderPath) async {
    if (!await _confirmCreateFolder(folderPath)) {
      return false;
    }
    try {
      await Directory(folderPath).create(recursive: true);
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _folderError = 'Δεν ήταν δυνατή η δημιουργία του φακέλου: $e';
        _folderValid = false;
      });
      return false;
    }
  }

  Future<void> _validateAndPersistFolder({
    bool offerCreateIfMissing = false,
  }) async {
    final gen = ++_validationGen;
    final raw = _folderController.text;
    final trimmed = raw.trim();

    if (trimmed.isEmpty) {
      if (!mounted || gen != _validationGen) return;
      setState(() {
        _folderError = null;
        _folderValid = false;
        _folderStatus = null;
      });
      return;
    }

    var result = await BackupDestinationFolderValidator.validate(raw);
    if (!mounted || gen != _validationGen) return;

    if (result.kind == BackupDestinationValidationKind.missingDirectory) {
      if (offerCreateIfMissing) {
        final created = await _createFolderIfConfirmed(trimmed);
        if (!mounted || gen != _validationGen) return;
        if (!created) {
          setState(() {
            _folderError = result.errorMessage;
            _folderValid = false;
          });
          return;
        }
        result = await BackupDestinationFolderValidator.validate(raw);
        if (!mounted || gen != _validationGen) return;
      } else {
        setState(() {
          _folderError = result.errorMessage;
          _folderValid = false;
        });
        return;
      }
    }

    if (result.kind == BackupDestinationValidationKind.ok) {
      setState(() {
        _folderError = null;
        _folderValid = true;
      });
      await SettingsService().catalogs.setUpdateFolderPath(trimmed);
      await _refreshFolderStatus(trimmed, gen: gen);
    } else {
      setState(() {
        _folderError = result.errorMessage;
        _folderValid = false;
        _folderStatus = null;
      });
    }
  }

  /// Ανανεώνει την ένδειξη «τι περιέχει ο φάκελος» (δημοσιευμένη έκδοση ή τι
  /// λείπει). Το [gen] κόβει αποτελέσματα που πρόλαβε να ξεπεράσει νεότερη
  /// πληκτρολόγηση.
  Future<void> _refreshFolderStatus(String folder, {int? gen}) async {
    final status = await inspectUpdateFolder(folder);
    if (!mounted || (gen != null && gen != _validationGen)) return;
    setState(() => _folderStatus = status);
  }

  Future<void> _pickFolder() async {
    if (FilePickerSession.takeLastRefocusedExisting()) return;
    final initialDirectory = initialDirectoryForFilePicker(
      _folderController.text,
    );
    final session = await FilePickerSession.run(
      () => FilePicker.getDirectoryPath(
        dialogTitle: 'Φάκελος ενημερώσεων',
        initialDirectory: initialDirectory,
      ),
    );
    if (session.refocusedExisting) return;
    final path = session.value;
    if (path == null || !mounted) return;
    setState(() => _folderError = null);
    _folderController.text = path;
    await _validateAndPersistFolder(offerCreateIfMissing: true);
  }

  Future<void> _publish() =>
      _runPublisherAction((service) => service.publish());

  Future<void> _writeInstallerOnly() =>
      _runPublisherAction((service) => service.writeInstallerOnly());

  Future<void> _rebuildCurrentVersion() =>
      _runPublisherAction((service) => service.rebuildCurrentVersion());

  /// Κοινή ροή για κάθε ενέργεια της κάρτας: κλείδωμα κουμπιών, χρονόμετρο,
  /// αποθήκευση φακέλου, εκτέλεση, μήνυμα αποτελέσματος.
  ///
  /// Η [action] λέει **τι** εκτελείται· τα υπόλοιπα βήματα είναι ίδια για όλες
  /// τις ενέργειες, ώστε μια αλλαγή στο φινάλε να γίνεται σε ένα σημείο.
  Future<void> _runPublisherAction(
    Future<ReleasePublishResult> Function(ReleasePublisherService service)
    action,
  ) async {
    if (!_canPublish) return;
    final folder = _folderController.text.trim();

    setState(() {
      _running = true;
      _statusMessage = null;
      _statusIsError = false;
      _elapsedLabel = _initialElapsedLabel;
    });
    _buildOutputLog.clear();
    _startActionTimer();

    await SettingsService().catalogs.setUpdateFolderPath(folder);
    final result = await action(_createService(folder));

    if (!mounted) {
      _stopActionTimer();
      return;
    }

    _stopActionTimer();
    final elapsed = _elapsedLabel;
    setState(() {
      _running = false;
      _statusIsError = result.status == ReleasePublishStatus.failure;
      _statusMessage = _statusMessageFor(result, elapsed);
    });

    // Το Unreleased άδειασε: η υπενθύμιση δημοσίευσης πρέπει να σβήσει τώρα,
    // όχι στην επόμενη εκκίνηση.
    if (result.status == ReleasePublishStatus.success) {
      ref.invalidate(publishReminderProvider);
    }

    // Κάθε ενέργεια αλλάζει το περιεχόμενο του φακέλου — η ένδειξη κατάστασης
    // πρέπει να δείχνει το ΝΕΟ περιεχόμενο, όχι αυτό πριν την ενέργεια.
    await _refreshFolderStatus(folder);
  }

  static String? _statusMessageFor(
    ReleasePublishResult result,
    String elapsed,
  ) {
    switch (result.status) {
      case ReleasePublishStatus.success:
        final base = result.message ?? 'Επιτυχία.';
        return '$base (συνολικός χρόνος: $elapsed)';
      case ReleasePublishStatus.emptyUnreleasedWarning:
        return result.message;
      case ReleasePublishStatus.failure:
        final step = result.failedStep ?? 'άγνωστο';
        return 'Αποτυχία στο βήμα «$step»: ${result.message ?? ''}';
    }
  }

  ReleasePublisherService _createService(String folder) {
    // Χωρίς setState: το log ειδοποιεί μόνο του την προβολή του, ώστε μια
    // γραμμή εξόδου να μην ξαναχτίζει ολόκληρη την κάρτα.
    void reportProgress(String message) {
      if (!mounted) return;
      _appendLog(message);
    }

    final factory = widget.serviceFactory;
    if (factory != null) {
      return factory(updateFolderPath: folder, onProgress: reportProgress);
    }

    final projectRoot = Directory.current.path;
    final releaseDir = [
      projectRoot,
      'build',
      'windows',
      'x64',
      'runner',
      'Release',
    ].join(Platform.pathSeparator);

    return ReleasePublisherService(
      projectRoot: projectRoot,
      buildReleaseDirectory: releaseDir,
      updateFolderPath: folder,
      clock: DateTime.now,
      onProgress: reportProgress,
      processRunner: runReleaseProcess,
    );
  }

  static String _bumpKindLabel(VersionBumpKind kind) => switch (kind) {
    VersionBumpKind.patch => 'patch',
    VersionBumpKind.minor => 'minor',
  };

  Future<void> _onPublishPressed() async {
    if (!_canPublish) return;
    final folder = _folderController.text.trim();
    final service = _createService(folder);

    late final ReleasePublishPreview preview;
    try {
      preview = await service.preparePreview();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Αποτυχία προεπισκόπησης: $e';
      });
      return;
    }
    if (!mounted) return;

    if (!preview.hasUnreleasedEntries) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => DraggableDialogShell(
          title: const Text('Κενό ιστορικό'),
          builder: (titleHandle) => AlertDialog(
            key: const Key('release_empty_unreleased_dialog'),
            title: titleHandle,
            content: Text(
              'Το ιστορικό (Unreleased) είναι κενό, οπότε δεν προκύπτει νέος '
              'αριθμός έκδοσης.\n\n'
              '• Μόνο εγκαταστάτης: ξαναγράφει μόνο το '
              'install_call_logger.bat.\n'
              '• Δημιουργία πάραυτα: ξαναχτίζει και ξαναδημοσιεύει την '
              '${preview.currentVersion} χωρίς αλλαγή του αριθμού έκδοσης. '
              'Ο αριθμός κτισίματος πάει ${preview.currentBuild} → '
              '${preview.currentBuild + 1}, ώστε οι εγκατεστημένες εφαρμογές '
              'να δουν την ενημέρωση.',
            ),
            actions: [
              TextButton(
                key: const Key('release_empty_cancel'),
                autofocus: true,
                onPressed: () => Navigator.of(ctx).pop('cancel'),
                child: const Text('Ακύρωση'),
              ),
              TextButton(
                key: const Key('release_empty_installer_only'),
                onPressed: () => Navigator.of(ctx).pop('installer'),
                child: const Text('Μόνο εγκαταστάτης'),
              ),
              FilledButton(
                key: const Key('release_empty_rebuild'),
                onPressed: () => Navigator.of(ctx).pop('rebuild'),
                child: const Text('Δημιουργία πάραυτα'),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      if (choice == 'installer') {
        await _writeInstallerOnly();
      } else if (choice == 'rebuild') {
        await _rebuildCurrentVersion();
      }
      return;
    }

    final bumpLabel = _bumpKindLabel(preview.bumpKind);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => DraggableDialogShell(
        title: const Text('Επιβεβαίωση δημοσίευσης'),
        builder: (titleHandle) => AlertDialog(
          key: const Key('release_confirm_dialog'),
          title: titleHandle,
          content: Text(
            'Δημοσίευση: ${preview.currentVersion}+${preview.currentBuild} → '
            '${preview.nextVersion}+${preview.nextBuild}, με '
            '${preview.unreleasedEntryCount} καταχωρήσεις ιστορικού.\n\n'
            'Θα δημοσιευτεί ως $bumpLabel → ${preview.nextVersion}\n\n'
            'Συνέχεια;',
          ),
          actions: [
            TextButton(
              key: const Key('release_confirm_cancel'),
              autofocus: true,
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Ακύρωση'),
            ),
            FilledButton(
              key: const Key('release_confirm_publish'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Δημοσίευση'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      await _publish();
    }
  }

  Future<void> _copyCliCommand() async {
    if (!_canPublish) return;
    final folder = _folderController.text.trim();
    final template = await SettingsService().catalogs
        .getPublishCliCommandTemplate();
    final command = buildPublishCliCommand(template, folder);
    await Clipboard.setData(ClipboardData(text: command));
    if (!mounted) return;
    setState(() {
      _statusIsError = false;
      _statusMessage = 'Η εντολή αντιγράφηκε στο πρόχειρο:\n$command';
    });
  }

  Future<void> _openCliSettingsDialog() async {
    final initial = await SettingsService().catalogs
        .getPublishCliCommandTemplate();
    if (!mounted) return;
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => _PublishCliSettingsDialog(initialTemplate: initial),
    );
    if (saved == null || !mounted) return;
    final text = saved.trim();
    await SettingsService().catalogs.setPublishCliCommandTemplate(
      text.isEmpty ? null : text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Διατηρείται για συμβατότητα με overrides τεστ (appVersionProvider).
    ref.watch(appVersionProvider);

    final publishButton = FilledButton.icon(
      key: const Key('release_publish_button'),
      onPressed: _canPublish ? () => unawaited(_onPublishPressed()) : null,
      icon: _running
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onPrimary,
              ),
            )
          : const Icon(Icons.publish_outlined),
      label: Text(_running ? 'Δημοσίευση…' : 'Δημοσίευση'),
    );

    final installerButton = OutlinedButton.icon(
      key: const Key('release_installer_only_button'),
      onPressed: _canPublish ? () => unawaited(_writeInstallerOnly()) : null,
      icon: const Icon(Icons.description_outlined),
      label: const Text('Ανανέωση εγκαταστάτη'),
    );

    return Material(
      color: scheme.tertiaryContainer.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Δημοσίευση έκδοσης',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Σφραγίζει το Ιστορικό Έκδοσης, αυξάνει την έκδοση, '
              'χτίζει τη Κυκλοφορία της εφαρμογής και δημοσιεύει στο '
              'κοινόχρηστο φάκελο ενημερώσεων '
              '(μαζί με τον εγκαταστάτη: install_call_logger.bat). '
              'Ο τύπος αύξησης (patch/minor) προκύπτει αυτόματα από το '
              'περιεχόμενο του Unreleased.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('release_update_folder_field'),
                    controller: _folderController,
                    decoration: InputDecoration(
                      labelText: 'Φάκελος ενημερώσεων',
                      hintText: r'\\server\share\call_logger_updates',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText: _folderError,
                    ),
                    enabled: !_running,
                    onEditingComplete: () => unawaited(
                      _validateAndPersistFolder(offerCreateIfMissing: true),
                    ),
                    onSubmitted: (_) => unawaited(
                      _validateAndPersistFolder(offerCreateIfMissing: true),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Επιλογή φακέλου',
                  onPressed: _running ? null : _pickFolder,
                  icon: const Icon(Icons.folder_open),
                ),
              ],
            ),
            if (_folderStatus case final status?
                when status.state != UpdateFolderState.unavailable) ...[
              const SizedBox(height: 8),
              Row(
                key: const Key('release_update_folder_status'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    status.isReady
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: 16,
                    color: status.isReady ? scheme.primary : scheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      status.isReady
                          ? status.describe()
                          : '${status.describe()} Η «Δημοσίευση» τον '
                                'ξαναγεμίζει.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: status.isReady
                            ? scheme.onSurfaceVariant
                            : scheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_showLocalOnlyWarning) ...[
              const SizedBox(height: 8),
              Row(
                key: const Key('release_update_folder_local_only_warning'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 16,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Αυτή φαίνεται τοπική διαδρομή — οι συνάδελφοι δεν θα '
                      'έχουν πρόσβαση. Προτιμήστε κοινόχρηστο φάκελο δικτύου '
                      '(\\διακομιστής\\...) ή μοιραστείτε αυτόν τον φάκελο '
                      'στο δίκτυο.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                CompactTooltip(
                  message: _actionTooltip(_publishDescription),
                  waitDuration: const Duration(milliseconds: 400),
                  child: publishButton,
                ),
                CompactTooltip(
                  message: _actionTooltip(_installerDescription),
                  waitDuration: const Duration(milliseconds: 400),
                  child: installerButton,
                ),
                CompactTooltip(
                  message:
                      'Λόγω περιορισμών ασφαλείας στο εργασιακό περιβάλλον '
                      '(antivirus), η μεταγλώττιση από την εφαρμογή ενδέχεται '
                      'να μπλοκάρεται. Αντιγράφει την εντολή δημοσίευσης για '
                      'εκτέλεση από τερματικό (π.χ. Cursor), όπου το build '
                      'ολοκληρώνεται κανονικά με το ίδιο ακριβώς αποτέλεσμα.',
                  child: IconButton(
                    key: const Key('release_copy_cli_button'),
                    onPressed: _canPublish
                        ? () => unawaited(_copyCliCommand())
                        : null,
                    icon: const Icon(Icons.code),
                  ),
                ),
                IconButton(
                  key: const Key('release_cli_settings_button'),
                  tooltip: 'Ρυθμίσεις εντολής τερματικού',
                  onPressed: _running
                      ? null
                      : () => unawaited(_openCliSettingsDialog()),
                  icon: const Icon(Icons.settings_outlined),
                ),
                if (_running || _actionStopwatch.elapsedMilliseconds > 0)
                  Text(
                    key: const Key('release_elapsed_timer'),
                    'Χρόνος: $_elapsedLabel',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _BuildOutputView(log: _buildOutputLog),
            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Material(
                color:
                    (_statusIsError
                            ? scheme.errorContainer
                            : scheme.primaryContainer)
                        .withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _statusMessage!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _statusIsError
                          ? scheme.onErrorContainer
                          : scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Προβολή της εξόδου μεταγλώττισης: ζωγραφίζει **μόνο τις ορατές γραμμές**.
///
/// Ακούει το ίδιο το [BuildOutputLog], οπότε μια νέα γραμμή ξαναχτίζει αυτό το
/// widget και όχι ολόκληρη την κάρτα.
class _BuildOutputView extends StatefulWidget {
  const _BuildOutputView({required this.log});

  final BuildOutputLog log;

  @override
  State<_BuildOutputView> createState() => _BuildOutputViewState();
}

class _BuildOutputViewState extends State<_BuildOutputView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.log.addListener(_handleLogChanged);
  }

  @override
  void dispose() {
    widget.log.removeListener(_handleLogChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleLogChanged() {
    if (!mounted) return;
    final shouldFollowTail = _isNearBottom();
    setState(() {});
    if (!shouldFollowTail) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  /// Μακριά από το τέλος σημαίνει ότι ο χρήστης διαβάζει παλιότερη γραμμή —
  /// δεν του αρπάζουμε τη θέση με αυτόματη κύλιση.
  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.pixels >= position.maxScrollExtent - 48;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'Consolas',
    );
    final lines = widget.log.lines;

    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Πρόοδος / έξοδος Μεταγλώττισης',
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      isEmpty: false,
      child: SizedBox(
        height: 190,
        child: SelectionArea(
          child: ListView.builder(
            key: const Key('release_build_output'),
            controller: _scrollController,
            primary: false,
            itemCount: lines.length,
            itemBuilder: (context, index) =>
                Text(lines[index], style: lineStyle),
          ),
        ),
      ),
    );
  }
}

/// Διάλογος επεξεργασίας προτύπου εντολής δημοσίευσης μέσω τερματικού.
class _PublishCliSettingsDialog extends StatefulWidget {
  const _PublishCliSettingsDialog({required this.initialTemplate});

  final String initialTemplate;

  @override
  State<_PublishCliSettingsDialog> createState() =>
      _PublishCliSettingsDialogState();
}

class _PublishCliSettingsDialogState extends State<_PublishCliSettingsDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTemplate);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableDialogShell(
      title: const Text('Πρότυπο εντολής τερματικού'),
      builder: (titleHandle) => AlertDialog(
        key: const Key('release_cli_settings_dialog'),
        title: titleHandle,
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Η εντολή χρησιμοποιεί το placeholder {folder} '
                  '(φάκελος ενημερώσεων).\n\n'
                  'Παράμετροι εντολής:\n'
                  '$kPublishCliParametersHelp',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('release_cli_template_field'),
                  controller: _controller,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Πρότυπο εντολής',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('release_cli_reset_default_button'),
            onPressed: () {
              setState(() {
                _controller.text = kDefaultPublishCliCommandTemplate;
              });
            },
            child: const Text('Επαναφορά προεπιλογής'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            key: const Key('release_cli_save_button'),
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: const Text('Αποθήκευση'),
          ),
        ],
      ),
    );
  }
}
