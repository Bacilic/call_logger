import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_init_result.dart';
import '../database/database_init_runner.dart';
import '../database/database_path_pick_flow.dart';
import '../database/database_path_resolution.dart';
import '../database/database_reachability.dart';
import '../utils/one_shot_periodic_detector.dart';
import 'database_switch_completion.dart';

/// Ρωτά «απαντά πάλι η δικτυακή βάση;». Εγχύσιμο για τεστ.
///
/// **Η ίδια ερώτηση με του φύλακα προσβασιμότητας** ([probeDatabaseFile]):
/// μέγεθος αρχείου και όχι ύπαρξη, γιατί η ύπαρξη απαντιέται από τη μνήμη των
/// Windows για αρχείο που δεν διαβάζεται πια· και όριο πέντε δευτερολέπτων,
/// γιατί η επανασύνδεση με κοινόχρηστο φάκελο αργεί. Μία απάντηση στο
/// «απαντά αυτό το αρχείο βάσης;» για όλη την εφαρμογή.
final networkDatabaseProbeProvider = Provider<Future<bool> Function(String)>(
  (ref) => probeDatabaseFile,
);

/// Πόσο συχνά ρωτά ο φρουρός επανόδου. Εγχύσιμο για τεστ.
final networkDatabaseReturnIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 30),
);

/// `true` μόλις η δικτυακή βάση, που δεν απάντησε στην εκκίνηση, ξαναπαντήσει.
///
/// Ζει μόνο όσο κάποιος τον παρακολουθεί — δηλαδή όσο φαίνεται η λωρίδα της
/// τοπικής βάσης. Κανένας υπάρχων κύκλος δεν ρωτά τη δικτυακή σε αυτή την
/// κατάσταση (όλοι ακολουθούν την ανοιχτή, τοπική βάση), γι' αυτό έχει δικό
/// του χρονόμετρο. Ο μηχανισμός είναι ο [OneShotPeriodicDetector]: ένας
/// έλεγχος τη φορά, φωνάζει μία φορά και σταματά, και η αποτυχία της
/// ερώτησης είναι σιωπή.
///
/// **Ο φρουρός μόνο ειδοποιεί.** Η μετάβαση είναι απόφαση του χρήστη: μια
/// αλλαγή βάσης στη μέση μιας κλήσης θα την αποθήκευε σε άλλη βάση από εκείνη
/// όπου ξεκίνησε.
final networkDatabaseReturnedProvider = StreamProvider.autoDispose
    .family<bool, String>((ref, networkPath) {
      final probe = ref.watch(networkDatabaseProbeProvider);
      final controller = StreamController<bool>();
      final detector = OneShotPeriodicDetector(
        detect: () => probe(networkPath),
        onDetected: () async => controller.add(true),
        interval: ref.watch(networkDatabaseReturnIntervalProvider),
      )..start();
      ref.onDispose(() {
        detector.dispose();
        unawaited(controller.close());
      });
      return controller.stream;
    });

/// Αποτέλεσμα της «Μετάβασης στη δικτυακή βάση».
class NetworkDatabaseReturnOutcome {
  const NetworkDatabaseReturnOutcome.switched() : errorMessage = null;
  const NetworkDatabaseReturnOutcome.stayedLocal(String message)
    : errorMessage = message;

  /// Γιατί η εφαρμογή έμεινε στην τοπική — `null` όταν η μετάβαση πέτυχε.
  final String? errorMessage;

  bool get switched => errorMessage == null;
}

/// Περνά από την τοπική βάση «γι' αυτή τη φορά» στη ρυθμισμένη δικτυακή.
///
/// **Πρώτα ανοίγει, μετά ανακοινώνει.** Η δικτυακή μπορεί να ξαναχαθεί ανάμεσα
/// στην ειδοποίηση και στο κλικ: τότε η απόφαση «τοπική» αποκαθίσταται, η
/// τοπική ξανανοίγει, και δεν εμφανίζεται ποτέ πράσινη λωρίδα επιτυχίας για
/// βάση που δεν άνοιξε. Η ρυθμισμένη διαδρομή δεν αλλάζει σε καμία περίπτωση —
/// ήταν πάντα η δικτυακή.
///
/// Το [onDatabaseReopened] είναι ο ξανα-έλεγχος του κελύφους· συγχρονίζει τη
/// λωρίδα με τη βάση που όντως άνοιξε, σε επιτυχία και σε αποτυχία.
Future<NetworkDatabaseReturnOutcome> returnToNetworkDatabase({
  required WidgetRef ref,
  Future<void> Function()? onDatabaseReopened,
  DatabaseInitChecksRunner runInitChecks = runDatabaseInitChecks,
}) async {
  final networkPath = LocalDatabaseSessionFallback.acceptedNetworkPath;
  final localPath = networkPath == null
      ? null
      : LocalDatabaseSessionFallback.acceptedLocalPathFor(networkPath);
  if (networkPath == null || localPath == null) {
    return const NetworkDatabaseReturnOutcome.stayedLocal(
      'Η εφαρμογή δεν δουλεύει σε τοπική βάση.',
    );
  }

  LocalDatabaseSessionFallback.forget();
  final result = await _runChecks(runInitChecks, networkPath);
  if (!result.isSuccess) {
    LocalDatabaseSessionFallback.accept(networkPath, localPath);
    await _runChecks(runInitChecks, localPath);
    await onDatabaseReopened?.call();
    // Η ειδοποίηση «επανήλθε» αποδείχθηκε πρόωρη: ο φρουρός ξεκινά από την
    // αρχή, ώστε η λωρίδα να ξαναπεί «δεν απαντά» αντί να προσφέρει ξανά
    // μετάβαση που μόλις απέτυχε.
    ref.invalidate(networkDatabaseReturnedProvider(networkPath));
    return NetworkDatabaseReturnOutcome.stayedLocal(
      result.message ?? 'Η δικτυακή βάση δεν άνοιξε.',
    );
  }

  await completeDatabaseSwitch(
    ref: ref,
    path: networkPath,
    hooks: DatabaseSwitchCompletionHooks(
      onLifecycleChanged: onDatabaseReopened,
    ),
  );
  return const NetworkDatabaseReturnOutcome.switched();
}

Future<DatabaseInitResult> _runChecks(
  DatabaseInitChecksRunner runInitChecks,
  String path,
) async {
  try {
    return (await runInitChecks(closeConnectionFirst: true)).result;
  } catch (e, st) {
    return DatabaseInitResult.fromException(e, path, st);
  }
}
