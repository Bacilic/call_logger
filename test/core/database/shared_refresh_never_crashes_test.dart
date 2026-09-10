// Το συμβόλαιο: **το ξαναφόρτωμα των κοινών όψεων είναι νοικοκυριό — η
// αποτυχία του δεν ρίχνει ποτέ την εφαρμογή.**
//
// Πραγματικό περιστατικό 10/09/2026: με τη βάση σε δικτυακό φάκελο, η
// επαναφόρτωση μετά την επιστροφή του δικτύου έπεσε πάνω σε `disk I/O error`
// και ο χειριστής είδε διάλογο «Άγνωστο σφάλμα εφαρμογής». Η κλήση έτρεχε
// χωρίς δίχτυ (`unawaited` χωρίς `try`), οπότε το σφάλμα κατέληξε στον
// καθολικό χειριστή ως μοιραίο.
//
//   flutter test test/core/database/shared_refresh_never_crashes_test.dart

import 'package:call_logger/core/database/database_reachability.dart';
import 'package:call_logger/core/database/shared_database_refresh.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Ref? _capturedRef;

final _refCaptureProvider = Provider<int>((ref) {
  _capturedRef = ref;
  return 0;
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() {
    _capturedRef = null;
    // Χωρίς δεμένη βάση δοκιμών: κάθε ερώτημα του ξαναφορτώματος αποτυγχάνει —
    // ακριβώς όπως όταν χάνεται ο κοινόχρηστος φάκελος.
    container = ProviderContainer(retry: (_, _) => null);
    addTearDown(container.dispose);
    container.read(_refCaptureProvider);
  });

  test('η αποτυχία ΔΕΝ βγαίνει έξω — η εφαρμογή δεν πέφτει', () async {
    await expectLater(
      refreshSharedDatabaseViewsSafely(_capturedRef!),
      completes,
      reason:
          'Το ξαναφόρτωμα άφησε το σφάλμα να διαφύγει: σε fire-and-forget '
          'κλήση καταλήγει στον καθολικό χειριστή και ο χειριστής βλέπει '
          '«Άγνωστο σφάλμα εφαρμογής».',
    );
  });

  test('η επιστροφή του δικτύου δεν ρίχνει την εφαρμογή', () async {
    // Ο δρόμος που έσπασε στην πράξη: ο φύλακας βλέπει τη βάση να επανέρχεται
    // και πυροδοτεί ξαναφόρτωμα «στα τυφλά». Αν εκείνο αφήσει σφάλμα να
    // διαφύγει, καταλήγει στον καθολικό χειριστή ως μοιραίο.
    container.read(sharedDatabaseChangeWatcherProvider);
    final guard = container.read(databaseReachabilityProvider.notifier);

    guard.recordProbeResult(succeeded: false);
    guard.recordProbeResult(succeeded: false);
    guard.recordProbeResult(succeeded: true);

    // Χρόνος για να τρέξει και να αποτύχει το ξαναφόρτωμα.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  test('η γυμνή εκδοχή ΟΝΤΩΣ πετάει — το δίχτυ δεν είναι διακοσμητικό',
      () async {
    // Χωρίς αυτόν τον έλεγχο, ο παραπάνω θα περνούσε ακόμη κι αν το
    // ξαναφόρτωμα δεν είχε τίποτα να αποτύχει.
    await expectLater(
      refreshSharedDatabaseViews(_capturedRef!),
      throwsA(anything),
    );
  });
}
