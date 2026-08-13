// Η σκανδάλη από το σφάλμα: το «malformed» ρωτά τον φρουρό αντί να εμφανιστεί
// ως «Άγνωστο σφάλμα εφαρμογής».
//
// Το κρίσιμο ζεύγος: όταν ο φρουρός επιβεβαιώνει αντικατάσταση, ο καθολικός
// χειριστής σιωπά (μιλά εκείνος)· όταν ΔΕΝ επιβεβαιώνει, το σφάλμα οφείλει να
// φτάσει κανονικά στον χρήστη — αλλιώς μια πραγματικά φθαρμένη βάση θα έσβηνε
// σιωπηλά.
//
//   flutter test test/core/database/database_replacement_poke_test.dart

import 'package:call_logger/core/database/database_replacement_notice.dart';
import 'package:call_logger/core/database/database_replacement_watchdog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _containerWith({
  required Future<bool> Function() detect,
  required Future<void> Function() onDetected,
}) {
  return ProviderContainer(
    overrides: [
      databaseReplacementWatchdogProvider.overrideWith((ref) {
        final watchdog = DatabaseReplacementWatchdog(
          interval: const Duration(days: 1), // μόνο χειροκίνητοι έλεγχοι εδώ
          detect: detect,
          onDetected: onDetected,
        );
        registerActiveDatabaseReplacementWatchdog(ref, watchdog);
        return watchdog;
      }),
    ],
  );
}

void main() {
  test('χωρίς ενεργό φρουρό το σφάλμα ΔΕΝ καταπίνεται', () async {
    expect(await pokeDatabaseReplacementWatchdog(), isFalse);
  });

  test('όταν επιβεβαιωθεί αντικατάσταση, ο φρουρός αναλαμβάνει', () async {
    var reacted = 0;
    final container = _containerWith(
      detect: () async => true,
      onDetected: () async => reacted++,
    );
    addTearDown(container.dispose);
    container.read(databaseReplacementWatchdogProvider);

    expect(await pokeDatabaseReplacementWatchdog(), isTrue);
    expect(reacted, 1);
  });

  test('χωρίς αντικατάσταση το σφάλμα προχωρά στον χρήστη', () async {
    final container = _containerWith(
      detect: () async => false,
      onDetected: () async {},
    );
    addTearDown(container.dispose);
    container.read(databaseReplacementWatchdogProvider);

    expect(
      await pokeDatabaseReplacementWatchdog(),
      isFalse,
      reason:
          'Φθαρμένη βάση χωρίς αντικατάσταση: ο χρήστης ΠΡΕΠΕΙ να δει το '
          'σφάλμα, αλλιώς η φθορά περνά σιωπηλά.',
    );
  });

  test('δεύτερο σφάλμα δεν ξαναχτυπά την ίδια αντίδραση', () async {
    var reacted = 0;
    final container = _containerWith(
      detect: () async => true,
      onDetected: () async => reacted++,
    );
    addTearDown(container.dispose);
    container.read(databaseReplacementWatchdogProvider);

    expect(await pokeDatabaseReplacementWatchdog(), isTrue);
    expect(await pokeDatabaseReplacementWatchdog(), isTrue);

    expect(reacted, 1, reason: 'ένα περιστατικό, μία αντίδραση');
  });

  test('ο φρουρός ξηλώνεται μαζί με τον container', () async {
    final container = _containerWith(
      detect: () async => true,
      onDetected: () async {},
    );
    container.read(databaseReplacementWatchdogProvider);
    container.dispose();

    expect(
      await pokeDatabaseReplacementWatchdog(),
      isFalse,
      reason:
          'Ξηλωμένος φρουρός δεν επιτρέπεται να απαντά «το χειρίζομαι εγώ» — '
          'θα κατάπινε σφάλματα χωρίς να τα δείχνει κανείς.',
    );
  });
}
