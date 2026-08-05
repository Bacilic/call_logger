import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/settings_repository.dart';
import '../../../core/init/database_switch_completion.dart';
import '../providers/database_integrity_provider.dart';
import 'integrity_debug_seeder_service.dart';

/// Provider για τον debug seeder (μόνο debug/desktop — το UI ελέγχει [IntegrityDebugSeederService.isEnabled]).
final integrityDebugSeederServiceProvider =
    Provider<IntegrityDebugSeederService>(
      (ref) => IntegrityDebugSeederService(),
    );

/// `true` όταν η **ενεργή** βάση φέρει την υπογραφή του σπορέα σεναρίων.
///
/// Τα σενάρια είναι ιδιότητα της βάσης, όχι της επίσκεψης στην οθόνη: όσο η
/// δοκιμαστική βάση είναι ανοιχτή, οι κάρτες πρέπει να φαίνονται — ακόμη κι αν
/// η εφαρμογή ξεκίνησε ξανά ή ο χρήστης πήγε αλλού και γύρισε. Με τοπική σημαία
/// «μόλις έτρεξε ο σπορέας» ο μόνος τρόπος να ξαναδεί κανείς τις κάρτες ήταν να
/// ξαναφτιάξει τη βάση από την αρχή.
///
/// Ακυρώνεται από την [invalidateDatabaseScopedCaches], δηλαδή από **κάθε**
/// αλλαγή βάσης — αλλιώς η απάντηση θα αφορούσε τη βάση που έκλεισε.
final activeDatabaseHasDebugScenariosProvider = FutureProvider<bool>((
  ref,
) async {
  try {
    final db = await DatabaseHelper.instance.database;
    final signature = await SettingsRepository(
      db,
    ).getSetting(kDebugScenarioSignatureSettingKey);
    return (signature?.trim().isNotEmpty ?? false);
  } catch (_) {
    // Βάση που δεν ανοίγει δεν είναι δοκιμαστική· το σφάλμα το αναφέρει ήδη η
    // αρχικοποίηση, εδώ θα ήταν διπλή — και η οθόνη χρειάζεται ναι/όχι.
    return false;
  }
});

/// Ανανέωση κατάστασης μετά την ενεργοποίηση της δοκιμαστικής βάσης.
///
/// Η ενεργοποίηση ΕΙΝΑΙ αλλαγή βάσης, οπότε περνά ολόκληρη από την
/// [completeDatabaseSwitch] — όχι μόνο από την εκκαθάριση caches.
///
/// Δύο πράγματα ξεχάστηκαν διαδοχικά εδώ και φαίνονταν στην οθόνη ως ψέματα:
/// πρώτα ένας δικός της, μικρότερος κατάλογος providers (έλειπαν οι καρτέλες
/// Καταλόγου και οι φόρμες κλήσης), και μετά το `invalidate(appInitProvider)`
/// — που είναι το ΜΟΝΟ σημείο απ' όπου ανανεώνονται το `DatabaseInitResult`
/// και το προφίλ αρχείου. Χωρίς αυτό, η λωρίδα κατάστασης και το μήνυμα
/// σύνδεσης έμεναν παγωμένα στην προηγούμενη βάση, ενώ διαδρομή και στατιστικά
/// έδειχναν τη νέα.
Future<void> refreshProvidersAfterIntegrityDebugSwitch(
  WidgetRef ref, {
  required String activatedPath,
}) async {
  ref.read(databaseIntegrityProvider.notifier).reset();
  await completeDatabaseSwitch(ref: ref, path: activatedPath);
  await ref.read(databaseIntegrityProvider.notifier).runCheck(force: true);
}
