import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/database/providers/database_backup_settings_provider.dart';
import '../../features/database/utils/backup_schedule_utils.dart';
import '../../features/database/widgets/backup_failed_dialog.dart';
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
      final st = BackupScheduleStatus.normalize(next.lastBackupStatus);
      if (!BackupScheduleStatus.shouldAnnounce(
        previous: prev?.lastBackupStatus,
        current: st,
      )) {
        return;
      }

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
        unawaited(showBackupFailedDialog(context: context, ref: ref));
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
