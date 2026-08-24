import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../database/backup_pending_changes.dart';
import '../database/database_helper.dart';
import '../../features/database/providers/database_backup_settings_provider.dart';
import '../../features/database/services/database_backup_audit.dart';
import '../../features/database/services/database_backup_service.dart';
import '../../features/database/utils/backup_schedule_utils.dart';
import '../../features/database/widgets/backup_folder_missing_dialog.dart';
import '../errors/app_error_result.dart';
import 'fatal_error_screen.dart';
import 'global_fatal_error_notifier.dart';

/// Εμφανίζει πλήρη οθόνη σφάλματος όταν το [globalFatalErrorNotifier] έχει τιμή, αλλιώς το [child].
class AppShellWithGlobalFatalError extends ConsumerWidget {
  const AppShellWithGlobalFatalError({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(databaseBackupSettingsProvider, (prev, next) {
      final st = next.lastBackupStatus;
      if (st != BackupScheduleStatus.failed &&
          st != BackupScheduleStatus.folderMissing) {
        return;
      }
      if (prev?.lastBackupStatus == st) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (st == BackupScheduleStatus.folderMissing) {
          final dest = ref
              .read(databaseBackupSettingsProvider)
              .destinationDirectory;
          unawaited(
            showBackupFolderMissingDialog(
              context: context,
              ref: ref,
              folderPath: dest,
            ),
          );
          return;
        }
        unawaited(_showFailedBackupDialog(context, ref));
      });
    });

    return ValueListenableBuilder<AppErrorResult?>(
      valueListenable: globalFatalErrorNotifier,
      builder: (context, fatal, _) {
        if (fatal != null) {
          return FatalErrorScreen(
            result: fatal,
            onRetry: () async {
              globalFatalErrorNotifier.value = null;
            },
          );
        }
        return child;
      },
    );
  }

  /// Οι ρυθμίσεις/ιστορικό αντιγράφων ζουν μέσα σε κάθε βάση — το μήνυμα
  /// δηλώνει ρητά ποια βάση αφορά, αλλιώς μετά από αλλαγή βάσης ο χρήστης δεν
  /// ξέρει για ποιο αρχείο μιλάμε.
  Future<void> _showFailedBackupDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    String dbScope = '';
    try {
      final db = await DatabaseHelper.instance.database;
      final base = p.basenameWithoutExtension(db.path).trim();
      if (base.isNotEmpty) dbScope = ' της βάσης «$base»';
    } catch (_) {}
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Αυτόματο αντίγραφο ασφαλείας'),
          content: Text(
            'Το αυτόματο αντίγραφο ασφαλείας$dbScope απέτυχε. '
            'Ελέγξτε το φάκελο προορισμού και τα δικαιώματα πρόσβασης.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await ref
                    .read(databaseBackupSettingsProvider.notifier)
                    .setLastBackupStatus(BackupScheduleStatus.none);
              },
              child: const Text('Παράβλεψη'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                final settings = ref.read(databaseBackupSettingsProvider);
                final result = await DatabaseBackupFileOperation.run(
                  settings,
                  auditTrigger: BackupAuditTrigger.scheduledRetry,
                );
                final notifier = ref.read(
                  databaseBackupSettingsProvider.notifier,
                );
                if (result.success) {
                  final db = await DatabaseHelper.instance.database;
                  final markId = await BackupPendingChangesRepository(
                    db,
                  ).latestAuditId();
                  await notifier.markBackupTaken(
                    auditId: markId,
                    at: DateTime.now(),
                  );
                } else {
                  await notifier.setLastBackupAttempt(DateTime.now());
                  await notifier.setLastBackupStatus(
                    BackupScheduleStatus.failed,
                  );
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        result.success
                            ? (result.outputPath != null
                                  ? 'Αντίγραφο: ${result.outputPath}'
                                  : 'Το αντίγραφο ολοκληρώθηκε.')
                            : (result.message ??
                                  'Η δημιουργία αντιγράφου απέτυχε.'),
                      ),
                    ),
                  );
                }
              },
              child: const Text('Εκτέλεση τώρα'),
            ),
          ],
        );
      },
    );
  }
}
