import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_helper.dart';
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
Future<AppInitRetryOutcome> runAppInitRetry({required WidgetRef ref}) async {
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
    await completeDatabaseSwitch(ref: ref, path: path);
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
