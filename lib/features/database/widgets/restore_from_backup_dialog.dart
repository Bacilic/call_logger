import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database_file_classifier.dart';
import '../services/backup_zip_manifest.dart';
import '../services/database_file_replacement.dart';
import '../services/restore_plan.dart';

/// Διεπαφή επιβεβαίωσης επαναφοράς: σύγκριση, προέλευση, όνομα προορισμού.
///
/// Η επαναφορά γίνεται πάντα στον φάκελο της τρέχουσας βάσης — ο χρήστης
/// επιλέγει μόνο το όνομα. Δεν διαβάζει βάση και δεν γράφει αρχεία — δέχεται
/// έτοιμα δεδομένα. Επιστρέφει την επιλογή ονόματος ή `null` σε ακύρωση.
Future<RestoreDestinationChoice?> showRestoreFromBackupDialog({
  required BuildContext context,
  required DatabaseFileProfile? currentProfile,
  required DatabaseFileProfile backupProfile,
  required BackupZipManifest manifest,
  required String currentDatabasePath,
  required List<RestoreDestinationChoice> availableDestinations,
  RestoreDestinationChoice initialDestination =
      RestoreDestinationChoice.defaultChoice,
  String? preferredDatabaseFileName,
  bool backupNameTargetExists = false,
  bool isFullBackupArchive = false,
  String? fullBackupPortablesDescription,
}) {
  assert(availableDestinations.isNotEmpty);
  final initial = availableDestinations.contains(initialDestination)
      ? initialDestination
      : availableDestinations.first;

  return showDialog<RestoreDestinationChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _RestoreFromBackupDialog(
      currentProfile: currentProfile,
      backupProfile: backupProfile,
      manifest: manifest,
      currentDatabasePath: currentDatabasePath,
      availableDestinations: availableDestinations,
      initialDestination: initial,
      preferredDatabaseFileName: preferredDatabaseFileName,
      backupNameTargetExists: backupNameTargetExists,
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
    required this.availableDestinations,
    required this.initialDestination,
    this.preferredDatabaseFileName,
    this.backupNameTargetExists = false,
    this.isFullBackupArchive = false,
    this.fullBackupPortablesDescription,
  });

  final DatabaseFileProfile? currentProfile;
  final DatabaseFileProfile backupProfile;
  final BackupZipManifest manifest;
  final String currentDatabasePath;
  final List<RestoreDestinationChoice> availableDestinations;
  final RestoreDestinationChoice initialDestination;
  final String? preferredDatabaseFileName;
  final bool backupNameTargetExists;
  final bool isFullBackupArchive;
  final String? fullBackupPortablesDescription;

  @override
  State<_RestoreFromBackupDialog> createState() =>
      _RestoreFromBackupDialogState();
}

class _RestoreFromBackupDialogState extends State<_RestoreFromBackupDialog> {
  late RestoreDestinationChoice _destination;

  @override
  void initState() {
    super.initState();
    _destination = widget.initialDestination;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              Text(
                'Με ποιο όνομα να γίνει η επαναφορά;',
                style: theme.textTheme.titleSmall,
              ),
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
                          _targetPathFor(choice),
                          style: theme.textTheme.bodySmall,
                        ),
                        value: choice,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _preservationText(),
                style: theme.textTheme.bodySmall,
              ),
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
          onPressed: () => Navigator.pop(context, _destination),
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
    final differs =
        currentNorm.replaceAll('/', '\\').toLowerCase() !=
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
        return 'Με το τρέχον όνομα '
            '(${p.basename(widget.currentDatabasePath)})';
      case RestoreDestinationChoice.backupName:
        return 'Με το όνομα του αντιγράφου '
            '(${p.basename(_targetPathFor(choice))})';
    }
  }

  String _targetPathFor(RestoreDestinationChoice choice) {
    return resolveRestoreTargetPath(
      choice: choice,
      currentDatabasePath: widget.currentDatabasePath,
      backupDatabaseFileName: widget.preferredDatabaseFileName,
    );
  }

  String _preservationText() {
    switch (_destination) {
      case RestoreDestinationChoice.currentDatabase:
        final preRestoreName = DatabaseFileReplacement.previewPreRestoreFileName(
          widget.currentDatabasePath,
        );
        return 'Η τρέχουσα βάση θα φυλαχτεί ως:\n$preRestoreName';
      case RestoreDestinationChoice.backupName:
        final currentName = p.basename(widget.currentDatabasePath);
        final target = _targetPathFor(RestoreDestinationChoice.backupName);
        if (!widget.backupNameTargetExists) {
          return 'Η τρέχουσα βάση ($currentName) παραμένει στη θέση της.';
        }
        final preRestoreName = DatabaseFileReplacement.previewPreRestoreFileName(
          target,
        );
        return 'Η τρέχουσα βάση ($currentName) παραμένει στη θέση της.\n'
            'Το υπάρχον αρχείο «${p.basename(target)}» θα φυλαχτεί ως:\n'
            '$preRestoreName';
    }
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.current, required this.backup});

  final DatabaseFileProfile? current;
  final DatabaseFileProfile backup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(String text, {bool header = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      child: Text(
        text,
        style: header ? theme.textTheme.labelLarge : theme.textTheme.bodyMedium,
      ),
    );

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
      },
      children: [
        TableRow(
          children: [
            cell('', header: true),
            cell('Τρέχουσα', header: true),
            cell('Αντίγραφο', header: true),
          ],
        ),
        _row('Κλήσεις', current?.callCount, backup.callCount, cell),
        _row('Υπάλληλοι', current?.userCount, backup.userCount, cell),
        _row(
          'Εξοπλισμός',
          current?.equipmentCount,
          backup.equipmentCount,
          cell,
        ),
        TableRow(
          children: [
            cell('Τελευταία κλήση'),
            cell(_dateOrDash(current?.latestCallDate)),
            cell(_dateOrDash(backup.latestCallDate)),
          ],
        ),
      ],
    );
  }

  TableRow _row(
    String label,
    int? currentValue,
    int? backupValue,
    Widget Function(String, {bool header}) cell,
  ) {
    return TableRow(
      children: [
        cell(label),
        cell(_countOrDash(currentValue)),
        cell(_countOrDash(backupValue)),
      ],
    );
  }

  String _countOrDash(int? value) => value == null ? '—' : '$value';

  String _dateOrDash(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? '—' : trimmed;
  }
}
