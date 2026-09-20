import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ai_model_cooldown_registry.dart';
import '../services/ai_model_health_store.dart';

/// Η υγεία των μοντέλων ΤΝ — επιβιώνει και του κλεισίματος της εφαρμογής.
///
/// Η γνώση φορτώνεται από τον υπολογιστή στο παρασκήνιο και ξαναγράφεται σε
/// κάθε μεταβολή. Μια κλήση που προλαβαίνει τη φόρτωση απλώς δεν ξέρει ακόμη —
/// κοστίζει μία δοκιμή, μία φορά ανά εκκίνηση.
///
/// **Ζει στο core, όχι σε ένα feature:** το κλειδί της μνήμης είναι το όνομα του
/// μοντέλου, άρα ό,τι μαθαίνει μια οθόνη ισχύει αυτούσιο για κάθε άλλη που
/// μιλά στο ίδιο μοντέλο. Αν ο πάροχος ζούσε μέσα στο Ιστορικό, κάθε νέα χρήση
/// της ΤΝ θα έπρεπε να δανειστεί κάτι από εκεί — ή, χειρότερα, να ξεκινήσει
/// χωρίς μνήμη.
final aiModelCooldownRegistryProvider = Provider<AiModelCooldownRegistry>((
  ref,
) {
  late final AiModelCooldownRegistry registry;
  registry = AiModelCooldownRegistry(
    onChanged: () =>
        unawaited(AiModelHealthStore.save(registry.activeDowntimes)),
  );
  unawaited(AiModelHealthStore.load().then(registry.restore));
  return registry;
});
