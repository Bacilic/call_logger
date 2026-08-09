import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/spell_check_service.dart';
import 'core_lexicon_provider.dart';
import 'greek_dictionary_provider.dart';

/// Ορθογραφικό λεξικό: πυρήνας (αν φορτωμένος) + `user_dictionary` στη βάση.
final spellCheckServiceProvider = FutureProvider<LexiconSpellCheckService>((
  ref,
) async {
  ref.watch(coreLexiconProvider);
  final dict = ref.watch(greekDictionaryServiceProvider);
  final svc = LexiconSpellCheckService();
  await svc.init(lexiconVariants: dict.stripKeyToVariantsMap);
  return svc;
});

/// Ξέπλυμα της αλυσίδας λεξικού ΕΚΤΟΣ φάσης build.
///
/// Κάθε `ref.invalidate(coreLexiconProvider)` (ή του ορθογράφου) οφείλει να το
/// καλεί αμέσως μετά: ο [greekDictionaryServiceProvider] και ο
/// [spellCheckServiceProvider] παρακολουθούν τον πυρήνα με `watch`. Αν οι
/// συνδρομές τους είναι σε παύση (η οθόνη Κλήσεων δεν είναι ορατή), μένουν
/// «dirty» και ξεπλένονται σύγχρονα μέσα στο επόμενο build που τους διαβάζει
/// (πεδία με ορθογράφο, φόρμες καταλόγου) → «setState() called during build».
void flushLexiconProviderChain(WidgetRef ref) {
  void run() {
    if (!ref.context.mounted) return;
    _readLexiconChain(ref);
  }

  final phase = SchedulerBinding.instance.schedulerPhase;
  final safeToRunNow =
      phase == SchedulerPhase.idle ||
      phase == SchedulerPhase.postFrameCallbacks;
  if (safeToRunNow) {
    run();
    return;
  }
  SchedulerBinding.instance.addPostFrameCallback((_) => run());
}

// Η αλυσίδα σε ΕΝΑ σημείο: αν προστεθεί κρίκος, ενημερώνεται μόνο εδώ.
void _readLexiconChain(WidgetRef ref) {
  ref.read(coreLexiconProvider);
  ref.read(greekDictionaryServiceProvider);
  ref.read(spellCheckServiceProvider);
}
