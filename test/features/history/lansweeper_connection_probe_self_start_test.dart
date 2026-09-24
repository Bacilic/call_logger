// Ο φρουρός σύνδεσης Lansweeper: ξεκινά μόνος του και δεν κολλά στο «ελέγχω».
//
//   flutter test test/features/history/lansweeper_connection_probe_self_start_test.dart

import 'package:call_logger/features/history/models/lansweeper_connection_status.dart';
import 'package:call_logger/features/history/providers/lansweeper_connection_probe_provider.dart';
import 'package:call_logger/features/history/providers/lansweeper_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';
import 'lansweeper_report_test_doubles.dart';

/// Φρουρός με αργό, ελεγχόμενο probe — χωρίς δίκτυο.
///
/// Κρατά **ολόκληρη** την πραγματική λογική (αρχική κατάσταση, αυτόματη
/// εκκίνηση, γενιές, καθαρισμός) και αντικαθιστά μόνο το σημείο που μιλά στο
/// δίκτυο. Αλλιώς το τεστ θα φύλαγε αντίγραφο του κώδικα, όχι τον κώδικα.
class _SlowProbeNotifier extends LansweeperConnectionProbeNotifier {
  static int runs = 0;

  @override
  Future<LansweeperConnectionStatus> runProbe({
    required String apiUrl,
    required String ticketFormUrl,
    required String apiKey,
    required String agentUsername,
  }) async {
    runs++;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return const LansweeperConnectionAvailable();
  }
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        ...callLoggerTestProviderOverrides(),
        lansweeperApiUrlProvider.overrideWith(
          FixedLansweeperApiUrlNotifier.new,
        ),
        lansweeperTicketFormUrlProvider.overrideWith(
          FixedLansweeperTicketFormUrlNotifier.new,
        ),
        lansweeperApiKeyProvider.overrideWith(
          FixedLansweeperApiKeyNotifier.new,
        ),
        lansweeperAgentUsernameProvider.overrideWith(
          FixedLansweeperAgentUsernameNotifier.new,
        ),
        lansweeperConnectionProbeProvider.overrideWith(_SlowProbeNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    _SlowProbeNotifier.runs = 0;
  });

  group('φρουρός σύνδεσης Lansweeper', () {
    test(
      'μια οθόνη που απλώς παρακολουθεί την κατάσταση παίρνει απάντηση, χωρίς να ζητήσει έλεγχο',
      () async {
        final container = makeContainer();

        // Ό,τι ακριβώς κάνει κάθε οθόνη που κρίνει από τη σύνδεση: ένα watch.
        // Πριν από τη διόρθωση, αυτό γεννούσε φρουρό στο «ελέγχω» που δεν τον
        // ξυπνούσε ποτέ κανείς — και η Άμεση Καταχώρηση έμενε κλειδωμένη.
        container.listen(
          lansweeperConnectionProbeProvider,
          (_, _) {},
          fireImmediately: true,
        );

        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(
          container.read(lansweeperConnectionProbeProvider),
          isA<LansweeperConnectionAvailable>(),
        );
        expect(_SlowProbeNotifier.runs, 1);
      },
    );

    test('δεύτερος ακροατής δεν ξεκινά δεύτερο έλεγχο', () async {
      final container = makeContainer();
      container.listen(
        lansweeperConnectionProbeProvider,
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        lansweeperConnectionProbeProvider,
        (_, _) {},
        fireImmediately: true,
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(_SlowProbeNotifier.runs, 1);
    });

    test(
      'απόδειξη από τον έλεγχο πράκτορα κερδίζει τον έλεγχο που τρέχει',
      () async {
        final container = makeContainer();
        container.listen(
          lansweeperConnectionProbeProvider,
          (_, _) {},
          fireImmediately: true,
        );
        final notifier = container.read(
          lansweeperConnectionProbeProvider.notifier,
        );

        // Όσο το ping είναι ακόμη στον αέρα, ο έλεγχος πράκτορα αποδεικνύει τη
        // σύνδεση. Η δήλωση πρέπει να ισχύσει αμέσως ΚΑΙ να μην ακυρωθεί από
        // το ping που θα απαντήσει μετά.
        notifier.markAvailable();
        expect(
          container.read(lansweeperConnectionProbeProvider),
          isA<LansweeperConnectionAvailable>(),
        );

        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(
          container.read(lansweeperConnectionProbeProvider),
          isA<LansweeperConnectionAvailable>(),
        );
      },
    );
  });
}
