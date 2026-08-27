import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/database_backup_settings_provider.dart';
import '../services/database_backup_audit.dart';
import '../utils/backup_location_hints.dart';
import '../utils/backup_schedule_utils.dart';
import 'backup_destination_change_flow.dart';

/// Τι διάλεξε ο χρήστης όταν λείπει ο φάκελος προορισμού.
enum BackupFolderMissingChoice {
  /// Το αφήνει για αργότερα.
  ignore,

  /// Φτιάχνει τον φάκελο στην ίδια διαδρομή και παίρνει αντίγραφο.
  createHere,

  /// Ορίζει **άλλη** διαδρομή — η μόνη σωστή απάντηση όταν η αποθηκευμένη
  /// διαδρομή δεν ισχύει πια (άλλη βάση, αλλαγμένος δικτυακός τόμος).
  changeFolder,
}

/// Διάλογος όταν λείπει ο φάκελος προορισμού backup (εκκίνηση ή χειροκίνητη
/// εκτέλεση).
///
/// Το [pickFolder] υπάρχει για τα τεστ — αλλιώς ανοίγει ο πραγματικός
/// επιλογέας φακέλου.
Future<void> showBackupFolderMissingDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String folderPath,
  BackupAuditTrigger auditTrigger = BackupAuditTrigger.scheduledRetry,
  bool dismissSetsStatusNone = true,
  Future<String?> Function()? pickFolder,
}) async {
  final trimmed = folderPath.trim();
  if (trimmed.isEmpty) return;

  // Ο δίσκος πρέπει να υπάρχει ΠΡΙΝ προσφερθεί δημιουργία: σε αποσυνδεδεμένο ή
  // ανύπαρκτο τόμο η δημιουργία είναι αδύνατη, και η προτροπή δίνει ελπίδα που
  // δεν υπάρχει. Η εφαρμογή ξέρει ήδη ποιοι τόμοι είναι συνδεδεμένοι.
  final volumeExists = BackupLocationHints.volumeOfPathExists(trimmed);
  final driveLetter = BackupLocationHints.windowsDriveLetterFromPath(trimmed);
  final availableDrives = volumeExists
      ? const <String>[]
      : BackupLocationHints.eligibleWindowsBackupDriveLabels();
  final missingVolumeText = driveLetter == null
      ? 'Ο δίσκος της διαδρομής δεν είναι διαθέσιμος'
      : 'Ο δίσκος $driveLetter: δεν υπάρχει ή δεν είναι συνδεδεμένος';
  final availableText = availableDrives.isEmpty
      ? ''
      : 'Διαθέσιμοι δίσκοι: ${availableDrives.join(', ')}.';

  final choice = await showDialog<BackupFolderMissingChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Φάκελος αντιγράφων ασφαλείας'),
      content: Text(
        volumeExists
            ? 'Ο φάκελος δεν βρέθηκε:\n\n$trimmed\n\n'
                  'Πιθανή αιτία: αποσυνδεδεμένος εξωτερικός δίσκος, διαγραφή '
                  'ή μετονομασία.\n\n'
                  'Αν η διαδρομή ισχύει ακόμη, δημιουργήστε τον εδώ. Αν '
                  'όχι — άλλη βάση, αλλαγμένος δικτυακός τόμος — ορίστε άλλη '
                  'διαδρομή, αλλιώς τα αντίγραφα θα πάνε σε λάθος σημείο.'
            : 'Ο φάκελος δεν βρέθηκε:\n\n$trimmed\n\n'
                  '$missingVolumeText, οπότε ο φάκελος δεν μπορεί να '
                  'δημιουργηθεί εκεί.\n\n$availableText\n\n'
                  'Πατήστε «Αλλαγή φακέλου» για να ορίσετε άλλη διαδρομή.',
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(BackupFolderMissingChoice.ignore),
          child: const Text('Αγνόηση'),
        ),
        // Πάντα διαθέσιμη: ο φάκελος μπορεί να λείπει επειδή η αποθηκευμένη
        // διαδρομή δεν ισχύει πια. Τότε η δημιουργία του παλιού φακέλου
        // φτιάχνει έναν άχρηστο φάκελο στο λάθος σημείο — και τα αντίγραφα
        // πάνε εκεί.
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(BackupFolderMissingChoice.changeFolder),
          child: const Text('Αλλαγή φακέλου'),
        ),
        if (volumeExists)
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(BackupFolderMissingChoice.createHere),
            child: const Text('Δημιουργία εδώ και εκτέλεση'),
          ),
      ],
    ),
  );

  if (!context.mounted) return;

  switch (choice) {
    case null:
    case BackupFolderMissingChoice.ignore:
      if (dismissSetsStatusNone) {
        await ref
            .read(databaseBackupSettingsProvider.notifier)
            .setLastBackupStatus(BackupScheduleStatus.none);
      }
    case BackupFolderMissingChoice.changeFolder:
      await changeBackupFolderAndRun(
        context: context,
        ref: ref,
        pick: pickFolder,
      );
    case BackupFolderMissingChoice.createHere:
      await runBackupAndReport(
        context: context,
        ref: ref,
        createFolder: true,
        auditTrigger: auditTrigger,
      );
  }
}
