import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database_file_classifier.dart';
import '../services/backup_zip_manifest.dart';
import '../services/database_file_replacement.dart';
import '../services/restore_plan.dart';

/// Απόφαση χρήστη από τον διάλογο επαναφοράς (χωρίς εργασίες αρχείων/βάσης).
class RestoreFromBackupDialogResult {
  const RestoreFromBackupDialogResult({
    required this.destination,
    required this.openRestoredDatabase,
  });

  final RestoreDestinationChoice destination;
  final bool openRestoredDatabase;
}

/// Διεπαφή επιβεβαίωσης επαναφοράς: σύγκριση, προέλευση, προορισμός, άνοιγμα.
///
/// Δεν διαβάζει βάση και δεν γράφει αρχεία — δέχεται έτοιμα δεδομένα.
Future<RestoreFromBackupDialogResult?> showRestoreFromBackupDialog({
  required BuildContext context,
  required DatabaseFileProfile? currentProfile,
  required DatabaseFileProfile backupProfile,
  required BackupZipManifest manifest,
  required String currentDatabasePath,
  required String zipPath,
  required List<RestoreDestinationChoice> availableDestinations,
  RestoreDestinationChoice initialDestination =
      RestoreDestinationChoice.defaultChoice,
  String? preferredDatabaseFileName,
  bool isFullBackupArchive = false,
  String? fullBackupPortablesDescription,
}) {
  assert(availableDestinations.isNotEmpty);
  final initial = availableDestinations.contains(initialDestination)
      ? initialDestination
      : availableDestinations.first;

  return showDialog<RestoreFromBackupDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _RestoreFromBackupDialog(
      currentProfile: currentProfile,
      backupProfile: backupProfile,
      manifest: manifest,
      currentDatabasePath: currentDatabasePath,
      zipPath: zipPath,
      availableDestinations: availableDestinations,
      initialDestination: initial,
      preferredDatabaseFileName: preferredDatabaseFileName,
      isFullBackupArchive: isFullBackupArchive,
      fullBackupPortablesDescription: fullBackupPortablesDescription,
    ),
  );
}

class _RestoreFromBackupDialog extends StatefulWidget {
  const _RestoreFromBackupDialog({
    required this.currentProfile,
    required this.backupProfile,
    required this.manifest,
    required this.currentDatabasePath,
    required this.zipPath,
    required this.availableDestinations,
    required this.initialDestination,
    this.preferredDatabaseFileName,
    this.isFullBackupArchive = false,
    this.fullBackupPortablesDescription,
  });

  final DatabaseFileProfile? currentProfile;
  final DatabaseFileProfile backupProfile;
  final BackupZipManifest manifest;
  final String currentDatabasePath;
  final String zipPath;
  final List<RestoreDestinationChoice> availableDestinations;
  final RestoreDestinationChoice initialDestination;
  final String? preferredDatabaseFileName;
  final bool isFullBackupArchive;
  final String? fullBackupPortablesDescription;

  @override
  State<_RestoreFromBackupDialog> createState() =>
      _RestoreFromBackupDialogState();
}

class _RestoreFromBackupDialogState extends State<_RestoreFromBackupDialog> {
  late RestoreDestinationChoice _destination;
  late bool _openRestored;

  @override
  void initState() {
    super.initState();
    _destination = widget.initialDestination;
    _openRestored = true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetPath = resolveRestoreTargetPath(
      choice: _destination,
      currentDatabasePath: widget.currentDatabasePath,
      zipPath: widget.zipPath,
      manifest: widget.manifest,
      preferredDatabaseFileName: widget.preferredDatabaseFileName,
    );
    final showOpenSwitch = restoreOpenSwitchMeaningful(_destination);
    final preRestoreName = _destination == RestoreDestinationChoice.currentDatabase
        ? DatabaseFileReplacement.previewPreRestoreFileName(
            widget.currentDatabasePath,
          )
        : DatabaseFileReplacement.previewPreRestoreFileName(targetPath);

    return AlertDialog(
      title: const Text('Επαναφορά από αντίγραφο'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isFullBackupArchive) ...[
                Text(
                  'Αυτό είναι πλήρες αντίγραφο ασφαλείας: δεν επαναφέρεται μόνο '
                  'η βάση, αλλά και '
                  '${widget.fullBackupPortablesDescription ?? 'φορητά αρχεία της εφαρμογής'} '
                  'που βρέθηκαν μέσα στο αρχείο.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text('Σύγκριση', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _ComparisonTable(
                current: widget.currentProfile,
                backup: widget.backupProfile,
              ),
              const SizedBox(height: 16),
              Text('Προέλευση αντιγράφου', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(_originText()),
              const SizedBox(height: 16),
              Text('Πού να γίνει η επαναφορά;', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              RadioGroup<RestoreDestinationChoice>(
                groupValue: _destination,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _destination = v);
                },
                child: Column(
                  children: [
                    for (final choice in widget.availableDestinations)
                      RadioListTile<RestoreDestinationChoice>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(_destinationLabel(choice)),
                        subtitle: Text(
                          _destinationSubtitle(choice),
                          style: theme.textTheme.bodySmall,
                        ),
                        value: choice,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Η τρέχουσα βάση στον προορισμό θα φυλαχτεί ως:\n$preRestoreName',
                style: theme.textTheme.bodySmall,
              ),
              if (_destination == RestoreDestinationChoice.besideZip) ...[
                const SizedBox(height: 8),
                Text(
                  'Προσοχή: η εφαρμογή θα λειτουργεί με βάση μέσα στον φάκελο '
                  'αντιγράφων ασφαλείας.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (showOpenSwitch) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Άνοιγμα της βάσης που επαναφέρθηκε'),
                  value: _openRestored,
                  onChanged: (v) => setState(() => _openRestored = v),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            RestoreFromBackupDialogResult(
              destination: _destination,
              openRestoredDatabase: showOpenSwitch ? _openRestored : true,
            ),
          ),
          child: const Text('Επαναφορά'),
        ),
      ],
    );
  }

  String _originText() {
    if (!widget.manifest.isKnown) {
      return 'Άγνωστη προέλευση (παλαιότερο αντίγραφο χωρίς μεταδεδομένα).';
    }
    final original = widget.manifest.originalDatabasePath?.trim() ?? '';
    if (original.isEmpty) {
      return 'Άγνωστη προέλευση.';
    }
    final currentNorm = p.normalize(widget.currentDatabasePath);
    final originalNorm = p.normalize(original);
    final differs = currentNorm.replaceAll('/', '\\').toLowerCase() !=
        originalNorm.replaceAll('/', '\\').toLowerCase();
    final buffer = StringBuffer('Αρχική διαδρομή βάσης:\n$original');
    if (differs) {
      buffer.write(
        '\n\nΗ αρχική διαδρομή διαφέρει από την τρέχουσα βάση '
        '(${widget.currentDatabasePath}).',
      );
    }
    if (widget.manifest.createdAt != null) {
      buffer.write('\nΔημιουργία αντιγράφου: ${widget.manifest.createdAt}');
    }
    if (widget.manifest.appVersion != null) {
      buffer.write('\nΈκδοση εφαρμογής: ${widget.manifest.appVersion}');
    }
    return buffer.toString();
  }

  String _destinationLabel(RestoreDestinationChoice choice) {
    switch (choice) {
      case RestoreDestinationChoice.currentDatabase:
        return 'Τρέχουσα βάση';
      case RestoreDestinationChoice.besideZip:
        return 'Νέο αρχείο δίπλα στο αντίγραφο';
      case RestoreDestinationChoice.originalPathFromManifest:
        return 'Αρχική διαδρομή του αντιγράφου';
    }
  }

  String _destinationSubtitle(RestoreDestinationChoice choice) {
    return resolveRestoreTargetPath(
      choice: choice,
      currentDatabasePath: widget.currentDatabasePath,
      zipPath: widget.zipPath,
      manifest: widget.manifest,
      preferredDatabaseFileName: widget.preferredDatabaseFileName,
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({
    required this.current,
    required this.backup,
  });

  final DatabaseFileProfile? current;
  final DatabaseFileProfile backup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(String text, {bool header = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          child: Text(
            text,
            style: header
                ? theme.textTheme.labelLarge
                : theme.textTheme.bodyMedium,
          ),
        );

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
      },
      children: [
        TableRow(children: [
          cell('', header: true),
          cell('Τρέχουσα', header: true),
          cell('Αντίγραφο', header: true),
        ]),
        _row('Κλήσεις', current?.callCount, backup.callCount, cell),
        _row('Υπάλληλοι', current?.userCount, backup.userCount, cell),
        _row('Εξοπλισμός', current?.equipmentCount, backup.equipmentCount, cell),
        TableRow(children: [
          cell('Τελευταία κλήση'),
          cell(_dateOrDash(current?.latestCallDate)),
          cell(_dateOrDash(backup.latestCallDate)),
        ]),
      ],
    );
  }

  TableRow _row(
    String label,
    int? currentValue,
    int? backupValue,
    Widget Function(String, {bool header}) cell,
  ) {
    return TableRow(children: [
      cell(label),
      cell(_countOrDash(currentValue)),
      cell(_countOrDash(backupValue)),
    ]);
  }

  String _countOrDash(int? value) => value == null ? '—' : '$value';

  String _dateOrDash(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? '—' : trimmed;
  }
}
