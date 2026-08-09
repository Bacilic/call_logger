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
