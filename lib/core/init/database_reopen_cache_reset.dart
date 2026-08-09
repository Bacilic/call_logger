import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/calls/layout/call_form_clear.dart';
import '../../features/calls/layout/calls_field_groups_provider.dart';
import '../../features/calls/provider/call_entry_provider.dart';
import '../../features/calls/provider/lookup_provider.dart';
import '../../features/calls/provider/smart_entity_selector_provider.dart';
import '../../features/database/debug/integrity_debug_provider_refresh.dart';
import '../../features/database/providers/database_browser_stats_provider.dart';
import '../../features/directory/providers/catalog_validation_provider.dart';
import '../../features/directory/providers/category_directory_provider.dart';
import '../../features/directory/providers/department_directory_provider.dart';
import '../../features/directory/providers/directory_provider.dart';
import '../../features/directory/providers/equipment_directory_provider.dart';
import '../../features/tasks/providers/task_service_provider.dart';
import '../../features/tasks/providers/tasks_provider.dart';

/// Εκκαθάριση Riverpod caches που κρατούν δεδομένα της προηγούμενης βάσης.
///
/// ΚΑΘΕ νέα ροή που ξανανοίγει βάση (αλλαγή διαδρομής, δημιουργία νέας βάσης,
/// επαναδοκιμή αρχικοποίησης κ.λπ.) οφείλει να καλεί αυτή τη συνάρτηση, ώστε
/// providers χωρίς autoDispose (π.χ. [tasksProvider]) να μην εμφανίζουν /
/// μεταλλάσσουν εγγραφές της παλιάς βάσης πάνω στη νέα.
///
/// Καθαρίζει επίσης την κατάσταση των φορμών εισαγωγής ([callSmartEntityProvider],
/// [taskSmartEntityProvider], [historyEditSmartEntityProvider], [callEntryProvider])
/// — καλούντα/εξοπλισμό/τμήμα και [CallEntryState.categoryId] — ώστε η αποθήκευση
/// να μη γράφει ταυτότητες της προηγούμενης βάσης στη νέα.
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
    // Η υπογραφή του σπορέα ζει ΜΕΣΑ στη βάση: μετά την αλλαγή, η οθόνη
    // σεναρίων πρέπει να ξαναρωτήσει τη νέα και όχι να θυμάται την παλιά.
    ref.invalidate(activeDatabaseHasDebugScenariosProvider);
    ref.invalidate(lookupServiceProvider);
    ref.invalidate(tasksProvider);
    ref.invalidate(totalTasksCountProvider);
    ref.invalidate(orphanCallsProvider);
    ref.invalidate(callSmartEntityProvider);
    ref.invalidate(taskSmartEntityProvider);
    ref.invalidate(historyEditSmartEntityProvider);
    ref.invalidate(callEntryProvider);
    // Οι επιβεβαιώσεις πεδίων και το μάνταλο μεγάλης προβολής ανήκουν στην ίδια
    // αδιαίρετη εκκαθάριση φόρμας — αλλιώς μένουν «κολλημένα» από την παλιά βάση.
    ref.invalidate(callsFieldConfirmationsProvider);
    ref.invalidate(callsScreenExpandedLatchProvider);
    // Καρτέλες Καταλόγου: κρατούν φορτωμένες γραμμές ΚΑΙ τη λίστα `lastDeleted`
    // για την αναίρεση — και τα δύο με ids της προηγούμενης βάσης. Το `build()`
    // τους είναι σύγχρονο (κενή κατάσταση), οπότε το invalidate είναι ασφαλές:
    // η κάθε καρτέλα ξαναφορτώνει όταν ανοίξει.
    ref.invalidate(directoryProvider);
    ref.invalidate(departmentDirectoryProvider);
    ref.invalidate(equipmentDirectoryProvider);
    ref.invalidate(categoryDirectoryProvider);
    // Οι κανόνες επικύρωσης ζουν στο app_settings της βάσης — η νέα βάση
    // έχει τους δικούς της.
    ref.invalidate(catalogValidationRulesProvider);
    ref.read(taskServiceProvider).resetSnoozeHistoryColumnCache();
    // Άμεσο flush του lookup ΕΚΤΟΣ φάσης build: το single-flight lock της
    // αρχικοποίησης ([runDatabaseInitChecks]) σειριοποιεί τυχόν παράλληλο άνοιγμα.
    ref.read(lookupServiceProvider);
    // Ξέπλυμα ΟΛΗΣ της αλυσίδας της οθόνης κλήσεων, όχι μόνο του lookup: το
    // [callsFieldGroupsProvider] εξαρτάται και από το [callSmartEntityProvider]
    // που μόλις ακυρώθηκε παραπάνω.
    flushCallsScreenProviderChain(ref);
  }

  final phase = SchedulerBinding.instance.schedulerPhase;
  final safeToRunNow =
      phase == SchedulerPhase.idle ||
      phase == SchedulerPhase.postFrameCallbacks;
  if (safeToRunNow) {
    run();
  } else {
    SchedulerBinding.instance.addPostFrameCallback((_) => run());
  }
}
