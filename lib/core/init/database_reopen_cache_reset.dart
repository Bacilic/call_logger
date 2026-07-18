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
void invalidateDatabaseScopedCaches(WidgetRef ref) {
  ref.invalidate(databaseBrowserStatsProvider);
  ref.invalidate(lookupServiceProvider);
  ref.invalidate(tasksProvider);
  ref.invalidate(totalTasksCountProvider);
  ref.invalidate(orphanCallsProvider);
  ref.read(taskServiceProvider).resetSnoozeHistoryColumnCache();
}
