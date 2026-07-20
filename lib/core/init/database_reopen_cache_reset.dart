import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/calls/provider/lookup_provider.dart';
import '../../features/database/providers/database_browser_stats_provider.dart';
import '../../features/tasks/providers/task_service_provider.dart';
import '../../features/tasks/providers/tasks_provider.dart';

/// Εκκαθάριση Riverpod caches που κρατούν δεδομένα της προηγούμενης βάσης.
///
/// ΚΑΘΕ νέα ροή που ξανανοίγει βάση (αλλαγή διαδρομής, δημιουργία νέας βάσης,
/// επαναδοκιμή αρχικοποίησης κ.λπ.) οφείλει να καλεί αυτή τη συνάρτηση, ώστε
/// providers χωρίς autoDispose (π.χ. [tasksProvider]) να μην εμφανίζουν /
/// μεταλλάσσουν εγγραφές της παλιάς βάσης πάνω στη νέα.
///
/// Η ακύρωση αναβάλλεται στο ΕΠΟΜΕΝΟ frame (όπως το [deferTasksProviderInvalidate])
/// ώστε το flush των providers να μη συμπέσει ποτέ με build που τρέχει την ίδια
/// στιγμή (π.χ. το rebuild του δέντρου από `ref.invalidate(appInitProvider)`).
/// Επιπλέον, το [lookupServiceProvider] ξαναδιαβάζεται ρητά αμέσως μετά την
/// ακύρωση: βρίσκεται στην αλυσίδα εξαρτήσεων του πρώτου `ref.watch` της οθόνης
/// κλήσεων (`callsScreenIsExpandedProvider` → `callsFieldGroupsProvider` →
/// `lookupServiceProvider`), οπότε αν έμενε «dirty» θα ξεπλενόταν σύγχρονα μέσα
/// στο επόμενο build της οθόνης κλήσεων και θα προκαλούσε «setState during build».
void invalidateDatabaseScopedCaches(WidgetRef ref) {
  void run() {
    if (!ref.context.mounted) return;
    ref.invalidate(databaseBrowserStatsProvider);
    ref.invalidate(lookupServiceProvider);
    ref.invalidate(tasksProvider);
    ref.invalidate(totalTasksCountProvider);
    ref.invalidate(orphanCallsProvider);
    ref.read(taskServiceProvider).resetSnoozeHistoryColumnCache();
    // Άμεσο flush του lookup ΕΚΤΟΣ φάσης build: το single-flight lock της
    // αρχικοποίησης ([runDatabaseInitChecks]) σειριοποιεί τυχόν παράλληλο άνοιγμα.
    ref.read(lookupServiceProvider);
  }

  final phase = SchedulerBinding.instance.schedulerPhase;
  final safeToRunNow = phase == SchedulerPhase.idle ||
      phase == SchedulerPhase.postFrameCallbacks;
  if (safeToRunNow) {
    run();
  } else {
    SchedulerBinding.instance.addPostFrameCallback((_) => run());
  }
}
