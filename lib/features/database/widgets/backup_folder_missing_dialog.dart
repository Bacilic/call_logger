import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/database_backup_settings_provider.dart';
import '../services/database_backup_audit.dart';
import '../services/database_backup_service.dart';
import '../utils/backup_schedule_utils.dart';

/// Διάλογος όταν λείπει ο φάκελος προορισμού backup (εκκίνηση ή χειροκίνητη εκτέλεση).
Future<void> showBackupFolderMissingDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String folderPath,
  BackupAuditTrigger auditTrigger = BackupAuditTrigger.scheduledRetry,
  bool dismissSetsStatusNone = true,
}) async {
  final trimmed = folderPath.trim();
  if (trimmed.isEmpty) return;

  final create = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Φάκελος αντιγράφων ασφαλείας'),
      content: Text(
        'Ο φάκελος δεν βρέθηκε:\n\n$trimmed\n\n'
        'Πιθανή αιτία: αποσυνδεδεμένος εξωτερικός δίσκος, διαγραφή ή μετονομασία.\n\n'
        'Θέλετε να δημιουργηθεί ο φάκελος και να εκτελεστεί αντίγραφο ασφαλείας τώρα;',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Αγνόηση'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Δημιουργία φακέλου και εκτέλεση αντιγράφου'),
        ),
      ],
    ),
  );

  if (!context.mounted) return;

  if (create != true) {
    if (dismissSetsStatusNone) {
      await ref
          .read(databaseBackupSettingsProvider.notifier)
          .setLastBackupStatus(BackupScheduleStatus.none);
    }
    return;
  }

  final settings = ref.read(databaseBackupSettingsProvider);
  final result = await DatabaseBackupFileOperation.runCreatingFolderIfNeeded(
    settings,
    auditTrigger: auditTrigger,
  );
  final notifier = ref.read(databaseBackupSettingsProvider.notifier);
  if (auditTrigger == BackupAuditTrigger.manual) {
    if (result.success) {
      await notifier.setLastManualBackupAttempt(DateTime.now());
    }
  } else {
    await notifier.setLastBackupAttempt(DateTime.now());
  }
  await notifier.setLastBackupStatus(
    result.success
        ? BackupScheduleStatus.success
        : (result.failureCode == DatabaseBackupFailureCode.folderMissing
            ? BackupScheduleStatus.folderMissing
            : BackupScheduleStatus.failed),
  );

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        result.success
            ? (result.outputPath != null
                ? 'Αντίγραφο: ${result.outputPath}'
                : 'Το αντίγραφο ολοκληρώθηκε.')
            : (result.message ?? 'Η δημιουργία αντιγράφου απέτυχε.'),
      ),
      backgroundColor: result.success
          ? null
          : Theme.of(context).colorScheme.error,
    ),
  );
}
