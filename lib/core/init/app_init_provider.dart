import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_init_progress_provider.dart';
import '../database/department_floor_migration.dart';
import '../database/department_name_key_migration.dart';
import '../services/audit_retention_runner.dart';
import '../updates/update_providers.dart';
import 'app_initializer.dart';
import 'startup_journal.dart';
import 'startup_journal_writer.dart';
import 'startup_notices.dart';
import 'startup_update_check.dart';

/// Provider αρχικοποίησης εφαρμογής. Τρέχει μία φορά στην εκκίνηση.
/// Με `--profile` η προεπιλεγμένη βάση είναι ήδη στο [AppConfig.defaultDbPath].
final appInitProvider = FutureProvider<AppInitResult>((ref) async {
  // Μην τροποποιείς άλλους providers συγχρονισμένα κατά το mount του FutureProvider
  // (Riverpod: «Providers are not allowed to modify other providers during their initialization»).
  await Future<void>.delayed(Duration.zero);
  // Η επαναδοκιμή ξαναχτίζει το ημερολόγιο από το προοίμιο και πέρα, ώστε τα
  // βήματα να μη διπλογράφονται σε κάθε πάτημα του «Επανάληψη».
  StartupJournal.instance.rewindToBootPrefix();
  // Ο γραφέας του αρχείου μαθαίνει το ίδιο: το αρχείο δεν γυρίζει πίσω όπως η
  // οθόνη, οπότε η δεύτερη προσπάθεια πρέπει να δηλωθεί ρητά.
  StartupJournalWriter.instanceOrNull?.beginAttempt();
  final progressNotifier = ref.read(databaseInitProgressProvider.notifier);
  progressNotifier.reset();
  final result = await _runInitialization(ref, progressNotifier);
  StartupJournalWriter.instanceOrNull?.sealAttempt(success: result.success);
  return result;
});

/// Η καθαυτό αρχικοποίηση, χωρισμένη ώστε η σφράγιση του ημερολογίου να έχει
/// **ένα** σημείο: κάθε έξοδος από εδώ περνά από τον καλούντα.
Future<AppInitResult> _runInitialization(
  Ref ref,
  DatabaseInitProgressNotifier progressNotifier,
) async {
  final AppInitResult result;
  try {
    result = await AppInitializer.initialize(
      progressNotifier: progressNotifier,
    );
  } catch (_) {
    // Η αποτυχία ανεβαίνει κανονικά στην οθόνη σφάλματος — αλλά το αρχείο
    // κλείνει πρώτα, αλλιώς η συνεδρία μένει για πάντα μισοτελειωμένη.
    StartupJournalWriter.instanceOrNull?.sealAttempt(success: false);
    rethrow;
  }
  if (result.success) {
    // Μέσω του provider, όχι κατευθείαν στο service: εδώ ζει η λογική «η
    // νεότερη υπερισχύει», και το αποτέλεσμα μένει στην κρυφή μνήμη ώστε το
    // κέλυφος να μην ξαναρωτήσει το δίκτυο μόλις ανοίξει.
    await runStartupUpdateCheck(() => ref.read(updateCheckProvider.future));
    await AppInitializer.activateBackupSchedulingAfterDatabaseReady(ref);
    // Soft-fail και τα τρία: κανένα βήμα νοικοκυριού δεν μπλοκάρει την εκκίνηση.
    await runStartupHousekeeping(
      'Εκκαθάριση παλαιού ιστορικού ελέγχου',
      AuditRetentionRunner.applyIfConfiguredOnStartup,
    );
    await runStartupHousekeeping(
      'Μεταφορά ορόφων τμημάτων',
      DepartmentFloorMigrationRunner.runIfNeeded,
    );
    await runStartupHousekeeping(
      'Επαναϋπολογισμός κλειδιών ονομάτων',
      DepartmentNameKeyMigrationRunner.runIfNeeded,
    );
    await runStartupHousekeeping(
      'Καθαρισμός υπολειμμάτων εγκατάστασης',
      cleanAssetResidue,
    );
  }
  return result;
}
