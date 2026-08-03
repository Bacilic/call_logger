import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/init/database_switch_completion.dart';
import '../providers/database_integrity_provider.dart';
import 'integrity_debug_seeder_service.dart';

/// Provider για τον debug seeder (μόνο debug/desktop — το UI ελέγχει [IntegrityDebugSeederService.isEnabled]).
final integrityDebugSeederServiceProvider =
    Provider<IntegrityDebugSeederService>(
      (ref) => IntegrityDebugSeederService(),
    );

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
