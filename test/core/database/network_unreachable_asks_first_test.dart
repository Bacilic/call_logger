import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/database/database_path_resolution.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Το συμβόλαιο: **η εφαρμογή δεν αλλάζει βάση χωρίς να ρωτήσει.**
///
/// Παλιότερα, μια δικτυακή διαδρομή που δεν απαντούσε αντικαθιστούσε σιωπηλά
/// τον εαυτό της με την τοπική προεπιλογή. Η τοπική δεν είναι κενή βάση — είναι
/// παλιό, αληθινό αρχείο· ο χρήστης μπορούσε να καταγράφει κλήσεις σε λάθος
/// δεδομένα χωρίς να το ξέρει.
void main() {
  const unreachableUnc = r'\\δεν-υπαρχει-διακομιστης\κοινοχρηστο\call_logger.db';
  const localDb = r'C:\Users\x\Documents\Call Logger\call_logger.db';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocalDatabaseSessionFallback.forget();
    await SettingsService().markDatabaseConfigured();
  });

  tearDown(LocalDatabaseSessionFallback.forget);

  test('δικτυακή διαδρομή που δεν απαντά δεν μεταπίπτει από μόνη της', () async {
    final resolved = await resolveEffectiveDatabasePath(unreachableUnc);

    expect(resolved.outcome, DatabasePathResolution.networkUnreachable);
    expect(resolved.unreachablePath, unreachableUnc);
    expect(resolved.usedUncFallback, isFalse);
  });

  test('χωρίς απόφαση δεν υπάρχει διαδρομή προς άνοιγμα', () async {
    final resolved = await resolveEffectiveDatabasePath(unreachableUnc);

    // Ο καλών δεν μπορεί να πάρει κατά λάθος «κάποια» διαδρομή και να ανοίξει
    // άλλη βάση νομίζοντας ότι άνοιξε τη ζητούμενη.
    expect(() => resolved.pathToOpen, throwsStateError);
  });

  test('μετά την αποδοχή του χρήστη, ανοίγει η τοπική βάση', () async {
    LocalDatabaseSessionFallback.accept(unreachableUnc, localDb);

    final resolved = await resolveEffectiveDatabasePath(unreachableUnc);

    expect(resolved.outcome, DatabasePathResolution.resolved);
    expect(resolved.usedUncFallback, isTrue);
    expect(
      resolved.pathToOpen,
      localDb,
      reason:
          'Άνοιξε άλλη βάση από εκείνη που δέχτηκε ο χρήστης — η '
          'προσφορά και η ενέργεια απέκλιναν.',
    );
  });

  test('η αποδοχή αφορά ΜΟΝΟ τη διαδρομή για την οποία δόθηκε', () async {
    LocalDatabaseSessionFallback.accept(unreachableUnc, localDb);

    const otherUnc = r'\\αλλος-διακομιστης\κοινοχρηστο\call_logger.db';
    final resolved = await resolveEffectiveDatabasePath(otherUnc);

    expect(resolved.outcome, DatabasePathResolution.networkUnreachable);
  });

  test('διαδρομή με γράμμα δίσκου δεν θεωρείται ποτέ «δεν απαντά»', () async {
    const missingLocal = r'Z:\δεν\υπαρχει\call_logger.db';

    final resolved = await resolveEffectiveDatabasePath(missingLocal);

    // Εκεί το μήνυμα «δεν βρέθηκε το αρχείο» είναι ήδη σαφές και το δίνει ο
    // καλών· δεν χρειάζεται ερώτηση για μετάπτωση.
    expect(resolved.outcome, DatabasePathResolution.resolved);
    expect(resolved.pathToOpen, missingLocal);
  });

  test('το σφάλμα προσφέρει τη σωστή διέξοδο στην οθόνη', () {
    final result = DatabaseInitResult.networkUnreachable(unreachableUnc);

    expect(result.recoveryKind, DatabaseInitRecoveryKind.networkUnreachable);
    expect(result.path, unreachableUnc);
    expect(result.message, contains('Δεν υπάρχει πρόσβαση'));
    expect(result.details, contains(unreachableUnc));
  });
}
