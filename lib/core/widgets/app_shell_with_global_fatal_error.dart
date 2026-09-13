import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/database/providers/database_backup_settings_provider.dart';
import '../../features/database/utils/backup_schedule_utils.dart';
import '../../features/database/widgets/backup_failed_dialog.dart';
import '../../features/database/widgets/backup_folder_missing_dialog.dart';
import '../errors/fatal_error_routing.dart';
import '../init/app_init_retry_runner.dart';
import 'database_error_screen.dart';
import 'fatal_error_screen.dart';
import 'global_fatal_error_notifier.dart';

/// Ποια οθόνη ανήκει σε κάθε κατάσταση μοιραίου σφάλματος.
///
/// Χωριστή από το widget ώστε η **απόφαση** να ελέγχεται χωρίς να χτιστεί η
/// οθόνη: η οθόνη σφάλματος βάσης διαβάζει δίσκο μόλις εμφανιστεί, και ένα
/// τεστ που την έχτιζε θα κρεμούσε στον εικονικό χρόνο.
Widget screenForFatalError(
  FatalErrorState? state, {
  required Widget child,
  required Future<void> Function() onRetryDatabase,
}) {
  return switch (state) {
    null => child,
    DatabaseFatalError(:final result) => DatabaseErrorScreen(
      result: result,
      dbPath: result.path,
      onRetry: onRetryDatabase,
    ),
    GeneralFatalError(:final result) => FatalErrorScreen(
      result: result,
      onRetry: () async {
        globalFatalErrorNotifier.value = null;
      },
    ),
  };
}

/// Εμφανίζει πλήρη οθόνη σφάλματος όταν το [globalFatalErrorNotifier] έχει
/// τιμή, αλλιώς το [child].
///
/// **Ποια** οθόνη εξαρτάται από το είδος του σφάλματος. Μια βάση που δεν
/// ανοίγει παίρνει την οθόνη σφάλματος βάσης — εκείνη που ξέρει να προσφέρει
/// άλλο αρχείο, επαναφορά από αντίγραφο και αναβάθμιση σχήματος. Μέχρι σήμερα
/// έπαιρνε τη γενική, της οποίας η μόνη διέξοδος ήταν μια «Επαναδοκιμή» που
/// ξαναβρίσκει το ίδιο πρόβλημα: ο χρήστης έμενε με επανεκκίνηση ως μόνη
/// επιλογή.
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

    return ValueListenableBuilder<FatalErrorState?>(
      valueListenable: globalFatalErrorNotifier,
      builder: (context, fatal, _) =>
          screenForFatalError(fatal, child: child, onRetryDatabase: () =>
              _retryDatabase(context, ref)),
    );
  }

  /// Ξανανοίγει τη βάση και, **μόνο σε επιτυχία**, κατεβάζει την οθόνη.
  ///
  /// Η αποτυχία αφήνει την οθόνη στη θέση της με το μήνυμα από κάτω: το να
  /// επέστρεφε στην εφαρμογή θα την ξανάριχνε αμέσως στο ίδιο σφάλμα.
  static Future<void> _retryDatabase(
    BuildContext context,
    WidgetRef ref,
  ) async {
    // Ο messenger και το χρώμα κρατιούνται ΠΡΙΝ το await: η επαναδοκιμή
    // ξαναχτίζει την οθόνη, και το context μπορεί να μην είναι πια το ίδιο.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final outcome = await runAppInitRetry(ref: ref);
    if (outcome.succeeded) {
      globalFatalErrorNotifier.value = null;
      return;
    }
    messenger?.showSnackBar(
      SnackBar(
        content: Text(outcome.errorMessage!),
        backgroundColor: errorColor,
      ),
    );
  }
}
