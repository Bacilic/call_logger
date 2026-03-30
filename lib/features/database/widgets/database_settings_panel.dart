import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/settings_service.dart';
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

/// Πάνελ ρυθμίσεων βάσης δεδομένων (προς το παρόν: αντίγραφα ασφαλείας).
class DatabaseSettingsPanel extends ConsumerStatefulWidget {
  const DatabaseSettingsPanel({super.key});

  @override
  ConsumerState<DatabaseSettingsPanel> createState() =>
      _DatabaseSettingsPanelState();
}

class _DatabaseSettingsPanelState extends ConsumerState<DatabaseSettingsPanel> {
  late final TextEditingController _destinationController;
  late final TextEditingController _maxCopiesController;
  late final TextEditingController _maxAgeController;
  late final ScrollController _panelScrollController;
  late final Future<List<BackupCaptionSegment>> _locationCaptionSegmentsFuture;
  late final Future<({String dbPath, int eligibleWindowsVolumeCount})>
      _backupDestinationWarningContextFuture;
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
    _locationCaptionSegmentsFuture = _loadLocationCaptionSegments();
    _backupDestinationWarningContextFuture =
        _loadBackupDestinationWarningContext();
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
    final dbPath = await SettingsService().getDatabasePath();
    return BackupLocationHints.composeLocationCaptionSegments(
      driveLabels: drives,
      configuredDatabasePath: dbPath,
    );
  }

  Future<({String dbPath, int eligibleWindowsVolumeCount})>
      _loadBackupDestinationWarningContext() async {
    final dbPath = await SettingsService().getDatabasePath();
    final eligibleWindowsVolumeCount =
        BackupLocationHints.eligibleWindowsBackupVolumeCount();
    return (
      dbPath: dbPath,
      eligibleWindowsVolumeCount: eligibleWindowsVolumeCount,
    );
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
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
            const SizedBox(height: 4),
            Text(
              'Αντίγραφα ασφαλείας (SQLite VACUUM INTO — ατομικό, με WAL/SHM). '
              'Περισσότερες ρυθμίσεις βάσης θα προστεθούν εδώ.',
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
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ώρα προγράμματος'),
              subtitle: Text(settings.backupTime),
              trailing: TextButton(
                onPressed: settings.backupOnExit
                    ? () async {
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
                      }
                    : null,
                child: const Text('Επιλογή'),
              ),
            ),
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


