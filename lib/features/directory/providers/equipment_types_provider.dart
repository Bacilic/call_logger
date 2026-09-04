import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/settings_service.dart';

/// Οι τύποι εξοπλισμού της ΕΝΕΡΓΗΣ βάσης, για τα πεδία επιλογής.
///
/// **Γιατί provider και όχι κλήση μέσα στη φόρμα:** η λίστα ζει στο
/// `app_settings`, δηλαδή μέσα στη βάση. Όταν το αίτημα ανάγνωσης φτιαχνόταν
/// μέσα στο χτίσιμο της οθόνης, κάθε πλήκτρο στο διπλανό πεδίο «Κωδικός»
/// ξεκινούσε καινούριο ερώτημα — τέσσερις χαρακτήρες, τέσσερα ερωτήματα, και
/// σε κοινόχρηστη βάση σε δικτυακό φάκελο άλλοι τόσοι γύροι δικτύου.
///
/// Η cache είναι database-scoped: ακυρώνεται στην αλλαγή βάσης
/// (`invalidateDatabaseScopedCaches`) και μετά από κάθε αποθήκευση της λίστας
/// στις ρυθμίσεις εξοπλισμού.
final equipmentTypesProvider = FutureProvider<List<String>>((ref) async {
  return SettingsService().catalogs.getEquipmentTypesList();
});
