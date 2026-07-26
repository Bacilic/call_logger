import '../../../core/database/database_init_runner.dart';
import '../../../core/database/database_path_pick_flow.dart';

/// Επαληθευτής διαδρομής βάσης (προεπιλογή: [setAndVerifyDatabasePath]).
typedef DatabasePathVerifier =
    Future<({bool ok, DatabaseInitRunnerResult runner})> Function(String path);

/// Σημεία σύνδεσης UI/συνεδρίας για την εναλλαγή διαδρομής βάσης.
abstract interface class DatabasePathSwitchHooks {
  Future<void> showVerifyingIndicator();
  Future<void> hideVerifyingIndicator();
  Future<void> reportVerificationFailure(DatabaseInitRunnerResult runner);
  Future<void> applySwitchToSession(String path);
  void declareSwitchBegin();
  void declareSwitchEnd();
}

/// Ενορχήστρωση εναλλαγής διαδρομής βάσης χωρίς UI και χωρίς πραγματική βάση.
///
/// Απαράβατος κανόνας: μετά από αποτυχημένη επαλήθευση η [DatabasePathSwitchHooks.applySwitchToSession]
/// δεν καλείται ΠΟΤΕ, και μετά από επιτυχημένη καλείται ΠΑΝΤΑ ακριβώς μία φορά.
Future<bool> runDatabasePathSwitch({
  required String path,
  required DatabasePathSwitchHooks hooks,
  DatabasePathVerifier verify = setAndVerifyDatabasePath,
}) async {
  hooks.declareSwitchBegin();
  try {
    await hooks.showVerifyingIndicator();
    late final ({bool ok, DatabaseInitRunnerResult runner}) outcome;
    try {
      outcome = await verify(path);
    } finally {
      await hooks.hideVerifyingIndicator();
    }
    if (outcome.ok) {
      await hooks.applySwitchToSession(path);
      return true;
    }
    await hooks.reportVerificationFailure(outcome.runner);
    return false;
  } finally {
    hooks.declareSwitchEnd();
  }
}
