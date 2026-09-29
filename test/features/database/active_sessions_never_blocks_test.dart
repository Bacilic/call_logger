import 'package:call_logger/core/services/known_schema_ceilings.dart';
import 'package:call_logger/features/database/providers/active_sessions_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Η φόρτωση των ανοιχτών συνεδριών **ολοκληρώνεται πάντα** μέσα σε έλεγχο.
///
/// **Γιατί υπάρχει αυτό το αρχείο (μάθημα 28/09):** προστέθηκε στη διαδρομή μια
/// ανάγνωση τοπικών ρυθμίσεων, για να βρεθεί έως ποιο σχήμα διαβάζει κάθε
/// έκδοση. Η ανάγνωση περνά από κανάλι του συστήματος, που μέσα σε
/// `testWidgets` **δεν απαντά ποτέ**. Το αποτέλεσμα δεν ήταν κόκκινος έλεγχος
/// αλλά κάτι χειρότερο: ένα αρχείο πέντε ελέγχων που κρεμούσε και έκλεινε με
/// «No tests were found» — δηλαδή **περνούσε ως επιτυχία χωρίς να τρέξει**.
///
/// Η διαδρομή τρέχει και σε οθόνες όπου η βάση απέτυχε να ανοίξει (φρουρός
/// αναβάθμισης σχήματος, διάλογος συντήρησης). Εκεί ακριβώς μια αναμονή που δεν
/// τελειώνει είναι παγωμένο παράθυρο χωρίς διέξοδο.
///
/// **Ο έλεγχος τρέχει με πραγματικό χρόνο** (`runAsync`), ώστε το όριο να
/// μετρήσει στ' αλήθεια: με το πλαστό ρολόι του `testWidgets` μια αναμονή που
/// δεν τελειώνει δεν θα χτυπούσε ποτέ το όριο — θα κρεμούσε ξανά.
void main() {
  setUp(KnownSchemaCeilings.resetForTest);
  tearDown(KnownSchemaCeilings.resetForTest);

  testWidgets('η φόρτωση συνεδριών δεν περιμένει κανάλι συστήματος', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final sessions = await loadActiveSessions(now: DateTime(2026, 9, 28, 20))
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw StateError(
              'Η φόρτωση συνεδριών δεν ολοκληρώθηκε. Κάποια κλήση στη διαδρομή '
              'περιμένει κανάλι συστήματος ή βάση — και στα τεστ δεν απαντά ποτέ.',
            ),
          );

      // Χωρίς ανοιχτή βάση και χωρίς φάκελο ιχνών, η τίμια απάντηση είναι
      // «κανείς» — αλλά το ζητούμενο εδώ είναι ότι **απαντά**.
      expect(sessions, isEmpty);
    });
  });

  testWidgets('δεύτερη κλήση στη σειρά επίσης ολοκληρώνεται', (tester) async {
    // Ο κύκλος ανανέωσης κοινόχρηστης βάσης την καλεί επαναλαμβανόμενα· μια
    // κλήση που κρατά κάτι από την προηγούμενη θα φαινόταν μόνο τη δεύτερη φορά.
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await loadActiveSessions(now: DateTime(2026, 9, 28, 20)).timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw StateError('Η κλήση #${i + 1} δεν ολοκληρώθηκε.'),
        );
      }
    });
  });

  test('το ταβάνι εκδόσεων απαντά χωρίς καμία αναμονή', () {
    // Σύγχρονη κλήση: αν γινόταν ποτέ ασύγχρονη, θα ξαναγύριζε το πρόβλημα.
    expect(KnownSchemaCeilings.forVersion('0.57.1'), isNull);
    expect(KnownSchemaCeilings.forVersion(null), isNull);
  });
}
