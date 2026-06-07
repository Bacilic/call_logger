import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/database/providers/database_backup_settings_provider.dart';
import '../../features/database/services/database_backup_audit.dart';
import '../../features/database/services/database_backup_service.dart';
import '../../features/database/utils/backup_schedule_status.dart';
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
      if (st != BackupScheduleStatus.missed &&
          st != BackupScheduleStatus.failed &&
          st != BackupScheduleStatus.folderMissing) {
        return;
      }
      if (prev?.lastBackupStatus == st) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final settings = ref.read(databaseBackupSettingsProvider);
        if (st == BackupScheduleStatus.missed &&
            !BackupScheduleStatusFormatter.shouldShowBackupMissedAlert(
              settings,
              DateTime.now(),
            )) {
          unawaited(
            ref
                .read(databaseBackupSettingsProvider.notifier)
                .setLastBackupStatus(BackupScheduleStatus.none),
          );
          return;
        }
        if (st == BackupScheduleStatus.folderMissing) {
          final dest =
              ref.read(databaseBackupSettingsProvider).destinationDirectory;
          unawaited(
            showBackupFolderMissingDialog(
              context: context,
              ref: ref,
              folderPath: dest,
            ),
          );
          return;
        }
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            final settings = ref.read(databaseBackupSettingsProvider);
            final manual = settings.lastManualBackupAttempt;
            final manualToday = manual != null &&
                BackupScheduleStatusFormatter.hasManualBackupToday(
                  settings,
                  DateTime.now(),
                );
            final missedMessage = manualToday
                ? 'Παραλήφθηκε προγραμματισμένο αντίγραφο ασφαλείας, '
                    'άλλα έχει γίνει αντίγραφο από τον χρήστη στις '
                    '${BackupScheduleStatusFormatter.formatLocalTimeHm(manual)}.'
                : 'Παραλήφθηκε προγραμματισμένο αντίγραφο ασφαλείας (η εφαρμογή '
                    'δεν ήταν ανοιχτή στη σχετική ημέρα και ώρα ή δεν ολοκληρώθηκε εγκαίρως).';

            return AlertDialog(
              title: const Text('Αυτόματο αντίγραφο ασφαλείας'),
              content: Text(
                st == BackupScheduleStatus.missed
                    ? missedMessage
                    : 'Το προγραμματισμένο αντίγραφο ασφαλείας απέτυχε. Ελέγξτε το φάκελο '
                        'προορισμού και τα δικαιώματα πρόσβασης.',
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
                    final notifier =
                        ref.read(databaseBackupSettingsProvider.notifier);
                    await notifier.setLastBackupAttempt(DateTime.now());
                    await notifier.setLastBackupStatus(
                      result.success
                          ? BackupScheduleStatus.success
                          : BackupScheduleStatus.failed,
                    );
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
}
