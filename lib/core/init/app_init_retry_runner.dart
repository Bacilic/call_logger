import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_helper.dart';
import '../utils/file_path_identity.dart';
import '../providers/application_reset_provider.dart';
import '../services/settings_service.dart';
import '../utils/user_facing_error_messages.dart';
import 'database_switch_completion.dart';

/// Αποτέλεσμα επαναδοκιμής αρχικοποίησης: πέτυχε, ή κρατά έτοιμο το ελληνικό
/// μήνυμα που πρέπει να δει ο χρήστης.
class AppInitRetryOutcome {
  const AppInitRetryOutcome.success() : errorMessage = null;
  const AppInitRetryOutcome.failure(String message) : errorMessage = message;

  final String? errorMessage;

  bool get succeeded => errorMessage == null;
}

/// Συνθέτει το μήνυμα αποτυχίας, προσθέτοντας —μόνο όταν συνέβη— και την
/// αποτυχία κλεισίματος της προηγούμενης σύνδεσης.
///
/// Το κλείσιμο αποτυγχάνει τυπικά όταν το αρχείο βάσης είναι κλειδωμένο από
/// δεύτερο ανοιχτό αντίγραφο της εφαρμογής, οπότε ο χρήστης χρειάζεται και τις
/// δύο πληροφορίες μαζί για να καταλάβει τι να κάνει.
@visibleForTesting
String composeAppInitRetryFailureMessage({
  required String base,
  required Object? closeFailure,
}) {
  if (closeFailure == null) return base;
  return '$base\n\n'
      'Το κλείσιμο της τρέχουσας σύνδεσης απέτυχε: '
      '${humanizeUserFacingError(closeFailure)}\n'
      'Αν το αρχείο είναι κλειδωμένο, κλείστε τυχόν άλλο ανοιχτό αντίγραφο '
      'της εφαρμογής και δοκιμάστε ξανά.';
}

/// Ξαναδοκιμάζει την αρχικοποίηση μετά από αποτυχία εκκίνησης: κλείνει την
/// τρέχουσα σύνδεση, διαβάζει τη ρυθμισμένη διαδρομή και ξαναπερνά ολόκληρη τη
/// [completeDatabaseSwitch].
///
/// Δεν δέχεται [BuildContext] και δεν εμφανίζει μηνύματα — η προβολή του
/// αποτελέσματος είναι δουλειά του καλούντος widget.
///
/// Το [failedDatabasePath] είναι η βάση της αποτυχίας που οδήγησε εδώ — `null`
/// όταν δεν είναι γνωστή. Από αυτήν κρίνεται αν η επαναδοκιμή είναι αλλαγή
/// βάσης ή απλώς η ίδια βάση ξανά.
Future<AppInitRetryOutcome> runAppInitRetry({
  required WidgetRef ref,
  required String? failedDatabasePath,
}) async {
  Object? closeFailure;
  try {
    await DatabaseHelper.instance.closeConnection();
  } catch (e) {
    closeFailure = e;
  }

  final String path;
  try {
    path = await SettingsService().getDatabasePath();
  } catch (e) {
    return AppInitRetryOutcome.failure(
      composeAppInitRetryFailureMessage(
        base: 'Αποτυχία επαναδοκιμής: ${humanizeUserFacingError(e)}',
        closeFailure: closeFailure,
      ),
    );
  }

  ref.invalidate(applicationResetPendingProvider);

  try {
    await completeDatabaseSwitch(
      ref: ref,
      path: path,
      showSuccessNotice: _isDatabaseChange(
        failedPath: failedDatabasePath,
        configuredPath: path,
      ),
    );
  } catch (e) {
    return AppInitRetryOutcome.failure(
      composeAppInitRetryFailureMessage(
        base: humanizeUserFacingError(e),
        closeFailure: closeFailure,
      ),
    );
  }

  return const AppInitRetryOutcome.success();
}

/// Η πράσινη «αλλαγή βάσης» βγαίνει μόνο όταν η ρυθμισμένη βάση είναι **άλλη**
/// από εκείνη που απέτυχε.
///
/// Η απλή «Επαναδοκιμή» και η «Χρήση τοπικής βάσης» αφήνουν τη ρυθμισμένη
/// διαδρομή ίδια — η πρώτη απλώς ξεκινά την εφαρμογή, η δεύτερη ανοίγει την
/// τοπική, που την ανακοινώνει η κίτρινη λωρίδα. Μόνο η επιλογή άλλης βάσης
/// από την οθόνη σφάλματος είναι αλλαγή. Χωρίς γνωστή βάση αποτυχίας,
/// σιωπή: προτιμότερη από μια ανακοίνωση που μπορεί να είναι ψέμα.
bool _isDatabaseChange({
  required String? failedPath,
  required String configuredPath,
}) {
  final failed = failedPath?.trim() ?? '';
  if (failed.isEmpty) return false;
  return !pathsReferToSameFile(failed, configuredPath);
}
