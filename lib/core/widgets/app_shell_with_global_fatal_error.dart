import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/database/providers/database_backup_settings_provider.dart';
import '../../features/database/services/database_backup_service.dart';
import '../../features/database/utils/backup_schedule_utils.dart';
import '../database/database_init_result.dart';
import 'database_error_screen.dart';
import 'global_fatal_error_notifier.dart';

/// Εμφανίζει πλήρη οθόνη σφάλματος όταν το [globalFatalErrorNotifier] έχει τιμή, αλλιώς το [child].
class AppShellWithGlobalFatalError extends ConsumerWidget {
  const AppShellWithGlobalFatalError({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(databaseBackupSettingsProvider, (prev, next) {
      final st = next.lastBackupStatus;
      if (st != BackupScheduleStatus.missed && st != BackupScheduleStatus.failed) {
        return;
      }
      if (prev?.lastBackupStatus == st) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('Αυτόματο αντίγραφο ασφαλείας'),
              content: Text(
                st == BackupScheduleStatus.missed
                    ? 'Παραλήφθηκε προγραμματισμένο αντίγραφο ασφαλείας (η εφαρμογή '
                        'δεν ήταν ανοιχτή στη σχετική ημέρα και ώρα ή δεν ολοκληρώθηκε εγκαίρως).'
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
                  child: const Text('OK'),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final settings = ref.read(databaseBackupSettingsProvider);
                    final result =
                        await DatabaseBackupFileOperation.run(settings);
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

    return ValueListenableBuilder<DatabaseInitResult?>(
      valueListenable: globalFatalErrorNotifier,
      builder: (context, fatal, _) {
        if (fatal != null) {
          return DatabaseErrorScreen(
            result: fatal,
            dbPath: fatal.path,
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
