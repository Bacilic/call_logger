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
  ref.read(callsFieldGroupsProvider);
  ref.read(callsScreenIsExpandedProvider);
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
