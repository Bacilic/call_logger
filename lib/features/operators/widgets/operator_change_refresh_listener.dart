import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/init/operator_scoped_cache_reset.dart';
import '../../../core/services/current_operator.dart';

/// Αόρατος ακροατής: μόλις αλλάξει ο συνδεδεμένος χρήστης, ανανεώνει **κάθε
/// οθόνη που δείχνει προσωπική ρύθμιση** — χωρίς να χρειάζεται ο χρήστης να
/// μπει και να βγει από τις Ρυθμίσεις.
///
/// Ζει στο κύριο κέλυφος όσο η εφαρμογή, ώστε η ανανέωση να συμβαίνει
/// **οπουδήποτε κι αν βρίσκεται ο χρήστης τη στιγμή της αλλαγής**: στην
/// πλευρική μπάρα, στον Κατάλογο (στήλες και πλάτη), στην οθόνη Κλήσεων
/// (χρονόμετρο, κάρτες), στα Στατιστικά (φίλτρα).
///
/// Είναι widget και όχι provider επίτηδες: η ακύρωση caches πρέπει να ξεκινά
/// από το widget layer, αλλιώς η αλυσίδα ξεπλένεται σύγχρονα μέσα σε build
/// άλλης οθόνης.
class OperatorChangeRefreshListener extends ConsumerStatefulWidget {
  const OperatorChangeRefreshListener({super.key});

  @override
  ConsumerState<OperatorChangeRefreshListener> createState() =>
      _OperatorChangeRefreshListenerState();
}

class _OperatorChangeRefreshListenerState
    extends ConsumerState<OperatorChangeRefreshListener> {
  @override
  void initState() {
    super.initState();
    CurrentOperator.listenable.addListener(_onOperatorChanged);
  }

  @override
  void dispose() {
    CurrentOperator.listenable.removeListener(_onOperatorChanged);
    super.dispose();
  }

  void _onOperatorChanged() {
    if (!mounted) return;
    invalidateOperatorScopedCaches(ref);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
