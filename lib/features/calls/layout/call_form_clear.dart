import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../provider/call_entry_provider.dart';
import '../provider/call_header_provider.dart';
import 'calls_field_groups_provider.dart';

/// Ξεπλένει ρητά την αλυσίδα providers της οθόνης κλήσεων ΕΚΤΟΣ φάσης build.
///
/// Το πρώτο `ref.watch` της οθόνης κλήσεων είναι το [callsScreenIsExpandedProvider]
/// (`calls_screen_layout.dart`), το οποίο εξαρτάται από το [callsFieldGroupsProvider]
/// και εκείνο με τη σειρά του από το [callHeaderProvider]. Όταν η φόρμα μεταλλάσσεται
/// ενώ η οθόνη κλήσεων ΔΕΝ είναι προσαρτημένη, η αλυσίδα μένει «dirty» χωρίς listeners
/// και ξεπλένεται σύγχρονα μέσα στο επόμενο build της οθόνης — τότε το Riverpod καλεί
/// `markNeedsBuild` στο `UncontrolledProviderScope` κατά τη φάση build και η εφαρμογή
/// καταρρέει με «setState() or markNeedsBuild() called during build».
///
/// Οι καλούντες βρίσκονται πάντα εκτός build (callback κουμπιού, μετά από `await`
/// διαλόγου, ή post-frame callback), οπότε το ξέπλυμα γίνεται σύγχρονα εδώ.
void flushCallsScreenProviderChain(WidgetRef ref) {
  _readCallsScreenChain(ref.read);
}

/// Η αλυσίδα σε ΕΝΑ σημείο: αν προστεθεί κρίκος, ενημερώνεται μόνο εδώ.
///
/// Δέχεται το `read` ως συνάρτηση ώστε να μη διπλογράφεται η αλυσίδα αν κάποτε
/// χρειαστεί δεύτερος τρόπος ανάγνωσης.
void _readCallsScreenChain(T Function<T>(Provider<T>) read) {
  read(callsFieldGroupsProvider);
  read(callsScreenIsExpandedProvider);
}

/// Ξέπλυμα της αλυσίδας των Κλήσεων μετά από **μαζική ενέργεια Καταλόγου**.
///
/// Κάθε μαζική διαγραφή ή επεξεργασία ακυρώνει το `lookupServiceProvider`. Όταν
/// η ενέργεια γίνεται από τον Κατάλογο, η οθόνη κλήσεων ΔΕΝ είναι
/// προσαρτημένη: η αλυσίδα `callsScreenIsExpandedProvider` →
/// `callsFieldGroupsProvider` → `lookupServiceProvider` μένει «dirty χωρίς
/// listeners» και ξεπλένεται αργότερα **σύγχρονα μέσα σε build** — όταν αλλάξει
/// το `TickerMode` επειδή άνοιξε ή έκλεισε διάλογος — ρίχνοντας
/// «setState() called during build».
///
/// Γιατί εδώ και όχι μέσα στο `refreshDirectoryCaches`: εκείνο καλείται και από
/// τον `callSmartEntityProvider`, που ανήκει στην ίδια αλυσίδα — ένα `ref.read`
/// από εκεί δίνει `CircularDependencyError`. Από το widget layer δεν υπάρχει
/// κύκλος.
///
/// Το ξέπλυμα γίνεται **τώρα** όταν είμαστε εκτός build, αλλιώς αναβάλλεται στο
/// επόμενο frame — ίδιος έλεγχος φάσης με το [invalidateDatabaseScopedCaches].
/// Οι καλούντες βρίσκονται συνήθως μετά από `await`, δηλαδή σε idle φάση.
void flushCallsChainAfterDirectoryMutation(WidgetRef ref) {
  final phase = SchedulerBinding.instance.schedulerPhase;
  final safeToRunNow =
      phase == SchedulerPhase.idle ||
      phase == SchedulerPhase.postFrameCallbacks;
  if (safeToRunNow) {
    flushCallsScreenProviderChain(ref);
    return;
  }
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (!ref.context.mounted) return;
    flushCallsScreenProviderChain(ref);
  });
}

/// Πλήρης εκκαθάριση της φόρμας κλήσης — η ΜΟΝΑΔΙΚΗ έγκυρη διαδρομή.
///
/// CONTRACT (μην αλλοιωθεί): η εκκαθάριση είναι ΜΙΑ αδιαίρετη ενέργεια τεσσάρων
/// βημάτων. Αν παραλειφθεί έστω ένα, μένουν «κολλημένες» επιβεβαιώσεις πεδίων ή
/// μάνταλο μεγάλης προβολής από ακυρωμένη κλήση. ΚΑΘΕ σημείο που καθαρίζει τη φόρμα
/// (κουμπί «Εκκαθάριση», διάλογος-φρουρός αλλαγής βάσης, μελλοντικές ροές) οφείλει να
/// καλεί αυτή τη συνάρτηση αντί να επαναλαμβάνει τα βήματα.
void clearCallFormCompletely(WidgetRef ref) {
  ref.read(callHeaderProvider.notifier).clearAll();
  ref.read(callEntryProvider.notifier).reset();
  ref.read(callsFieldConfirmationsProvider.notifier).resetAll();
  ref.read(callsScreenExpandedLatchProvider.notifier).release();
  flushCallsScreenProviderChain(ref);
}
