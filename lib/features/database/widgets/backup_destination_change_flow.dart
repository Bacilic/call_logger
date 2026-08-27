import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/backup_pending_changes.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/utils/file_picker_initial_directory.dart';
import '../../../core/utils/file_picker_session.dart';
import '../providers/database_backup_settings_provider.dart';
import '../services/database_backup_audit.dart';
import '../services/database_backup_service.dart';
import '../utils/backup_schedule_utils.dart';

/// Η κοινή ροή «άλλαξε φάκελο προορισμού και πάρε αντίγραφο τώρα».
///
/// Ζει σε ένα σημείο επειδή τη χρειάζονται **δύο** διάλογοι — η αποτυχία
/// αντιγράφου και ο φάκελος που λείπει — και δύο αντίγραφα της ίδιας ροής θα
/// απέκλιναν με την πρώτη διόρθωση: ο ένας διάλογος θα σημάδευε την κατάσταση
/// σωστά και ο άλλος όχι, ή ο ένας θα έλεγε το σφάλμα και ο άλλος θα σιωπούσε.

/// Επιλογή νέας διαδρομής και **άμεση** εκτέλεση του αντιγράφου.
///
/// Η αποθήκευση χωρίς εκτέλεση θα άφηνε τον χρήστη να αναρωτιέται αν έπιασε·
/// εδώ η απάντηση έρχεται αμέσως, με το αποτέλεσμα στο μήνυμα.
///
/// Το [pick] υπάρχει για τα τεστ — αλλιώς χρησιμοποιείται ο πραγματικός
/// επιλογέας φακέλου των Windows.
Future<void> changeBackupFolderAndRun({
  required BuildContext context,
  required WidgetRef ref,
  Future<String?> Function()? pick,
}) async {
  final picked = (await (pick ?? pickBackupDestinationFolder(ref))())?.trim();
  if (picked == null || picked.isEmpty || !context.mounted) return;

  await ref
      .read(databaseBackupSettingsProvider.notifier)
      .setDestinationDirectory(picked);
  if (!context.mounted) return;
  await runBackupAndReport(context: context, ref: ref, createFolder: true);
}

/// Ο πραγματικός επιλογέας φακέλου, με το ίδιο μοτίβο που χρησιμοποιεί η
/// καρτέλα ρυθμίσεων — ώστε ο επιλογέας να μην ανοίγει δεύτερη φορά όταν ένας
/// είναι ήδη ανοιχτός.
Future<String?> Function() pickBackupDestinationFolder(WidgetRef ref) {
  return () async {
    final current = ref
        .read(databaseBackupSettingsProvider)
        .destinationDirectory;
    final session = await FilePickerSession.run(
      () => FilePicker.getDirectoryPath(
        dialogTitle: 'Φάκελος προορισμού αντιγράφων ασφαλείας',
        initialDirectory: initialDirectoryForFilePicker(current),
      ),
    );
    return session.refocusedExisting ? null : session.value;
  };
}

/// Τρέχει το αντίγραφο, ενημερώνει την κατάσταση και **λέει τι έγινε**.
Future<void> runBackupAndReport({
  required BuildContext context,
  required WidgetRef ref,
  required bool createFolder,
  BackupAuditTrigger auditTrigger = BackupAuditTrigger.scheduledRetry,
}) async {
  final settings = ref.read(databaseBackupSettingsProvider);
  final result = createFolder
      ? await DatabaseBackupFileOperation.runCreatingFolderIfNeeded(
          settings,
          auditTrigger: auditTrigger,
        )
      : await DatabaseBackupFileOperation.run(
          settings,
          auditTrigger: auditTrigger,
        );

  final notifier = ref.read(databaseBackupSettingsProvider.notifier);
  if (result.success) {
    final db = await DatabaseHelper.instance.database;
    final markId = await BackupPendingChangesRepository(db).latestAuditId();
    await notifier.markBackupTaken(auditId: markId, at: DateTime.now());
  } else {
    await notifier.setLastBackupAttempt(DateTime.now());
    await notifier.setLastBackupStatus(
      result.failureCode == DatabaseBackupFailureCode.folderMissing
          ? BackupScheduleStatus.folderMissing
          : BackupScheduleStatus.failed,
    );
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        result.success
            ? (result.outputPath != null
                  ? 'Το αντίγραφο ολοκληρώθηκε: ${result.outputPath}'
                  : 'Το αντίγραφο ολοκληρώθηκε.')
            // Η αιτία που κατέγραψε η ίδια η αποτυχία — όχι γενικόλογο «απέτυχε».
            : (result.message ?? 'Το αντίγραφο απέτυχε ξανά.'),
      ),
      duration: Duration(seconds: result.success ? 4 : 8),
      backgroundColor: result.success
          ? null
          : Theme.of(context).colorScheme.error,
    ),
  );
}
