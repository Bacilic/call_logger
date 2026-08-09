import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/settings_service.dart';
import '../models/catalog_validation_rules.dart';
import '../services/catalog_validation_service.dart';

/// Οι κανόνες επικύρωσης της ΕΝΕΡΓΗΣ βάσης.
///
/// Ζουν στο app_settings, άρα η cache είναι database-scoped: ακυρώνεται
/// υποχρεωτικά στην αλλαγή βάσης (invalidateDatabaseScopedCaches) και μετά
/// από κάθε αποθήκευση στην οθόνη ρυθμίσεων.
final catalogValidationRulesProvider = FutureProvider<CatalogValidationRules>((
  ref,
) async {
  final raw = await SettingsService().catalogs.getCatalogValidationRulesRaw();
  return CatalogValidationRules.fromRawJson(raw);
});

/// Έτοιμη υπηρεσία ελέγχου πάνω στους φορτωμένους κανόνες.
///
/// Οι φόρμες τη διαβάζουν με `ref.watch(...).valueOrNull` — όσο φορτώνει,
/// απλώς δεν εμφανίζονται υποδείξεις.
final catalogValidationServiceProvider =
    FutureProvider<CatalogValidationService>((ref) async {
      final rules = await ref.watch(catalogValidationRulesProvider.future);
      return CatalogValidationService(rules);
    });

/// Ξέπλυμα της αλυσίδας επικύρωσης ΕΚΤΟΣ φάσης build.
///
/// Κάθε `ref.invalidate(catalogValidationRulesProvider)` οφείλει να το καλεί
/// αμέσως μετά: ο [catalogValidationServiceProvider] παρακολουθεί τους κανόνες
/// με `watch`, κι αν η αλυσίδα μείνει «dirty» χωρίς listeners (καμία φόρμα
/// ανοιχτή), ξεπλένεται σύγχρονα μέσα στο επόμενο build που θα τη διαβάσει →
/// «setState() called during build».
void flushCatalogValidationProviderChain(WidgetRef ref) {
  void run() {
    if (!ref.context.mounted) return;
    _readCatalogValidationChain(ref);
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
void _readCatalogValidationChain(WidgetRef ref) {
  ref.read(catalogValidationRulesProvider);
  ref.read(catalogValidationServiceProvider);
}
