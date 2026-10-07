// Η λωρίδα της τοπικής βάσης: λέει πώς φεύγει, μικραίνει σε σημάδι με το
// «Χ», και μόλις επανέλθει η δικτυακή το λέει και προσφέρει τη μετάβαση.
//
//   flutter test test/core/widgets/local_database_banner_test.dart

import 'package:call_logger/core/database/database_path_resolution.dart';
import 'package:call_logger/core/init/network_database_return.dart';
import 'package:call_logger/core/widgets/local_database_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _network = r'\\popinio\CallLogger\Data Base\hospital.db';
const _interval = Duration(seconds: 30);

void main() {
  setUp(() {
    LocalDatabaseSessionFallback.accept(_network, r'C:\CallLogger\local.db');
  });

  tearDown(LocalDatabaseSessionFallback.forget);

  Future<({List<String> pressed})> pumpBanner(
    WidgetTester tester, {
    required bool networkAnswers,
  }) async {
    final pressed = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkDatabaseReturnIntervalProvider.overrideWithValue(_interval),
          networkDatabaseProbeProvider.overrideWithValue(
            (_) async => networkAnswers,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LocalDatabaseBanner(
              onOpenDatabaseSettings: () => pressed.add('settings'),
              onReturnToNetwork: () async => pressed.add('return'),
            ),
          ),
        ),
      ),
    );
    return (pressed: pressed);
  }

  testWidgets('όσο η δικτυακή δεν απαντά: σύνδεσμος στις Ρυθμίσεις βάσης', (
    tester,
  ) async {
    final banner = await pumpBanner(tester, networkAnswers: false);
    await tester.pump(_interval);
    await tester.pump();

    expect(find.text(kLocalDatabaseBannerText), findsOneWidget);
    expect(find.text(kReturnToNetworkDatabaseLink), findsNothing);

    await tester.tap(find.text(kLocalDatabaseSettingsLink));
    expect(banner.pressed, ['settings']);
  });

  testWidgets('το «Χ» μικραίνει τη λωρίδα σε σημάδι', (tester) async {
    await pumpBanner(tester, networkAnswers: false);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LocalDatabaseBanner)),
    );
    // Όπως το κέλυφος: κάποιος ρωτά «λωρίδα ή σημάδι;» όσο ζει η τοπική βάση.
    final indicator = container.listen(
      localDatabaseIndicatorProvider,
      (_, _) {},
    );
    addTearDown(indicator.close);
    expect(indicator.read(), LocalDatabaseIndicator.banner);

    await tester.tap(
      find.byKey(const ValueKey('local_database_banner_collapse')),
    );
    await tester.pump();

    expect(indicator.read(), LocalDatabaseIndicator.mark);
  });

  testWidgets('χωρίς ορατή μπάρα η λωρίδα δεν έχει «Χ»', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: LocalDatabaseBanner(
              onOpenDatabaseSettings: () {},
              onReturnToNetwork: () async {},
              canCollapse: false,
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('local_database_banner_collapse')),
      findsNothing,
      reason: 'Το σημάδι δεν θα το έβλεπε κανείς — η τοπική βάση χωρίς ένδειξη',
    );
  });

  group('λωρίδα ή σημάδι — μία απόφαση', () {
    ProviderContainer containerWith({required bool networkReturned}) {
      final container = ProviderContainer(
        overrides: [
          localDatabaseNetworkReturnedProvider.overrideWithValue(
            networkReturned,
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('μικρή λωρίδα ⇒ σημάδι, και το κλικ στο σημάδι την ξαναφέρνει', () {
      final container = containerWith(networkReturned: false);
      final indicator = container.listen(
        localDatabaseIndicatorProvider,
        (_, _) {},
      );
      final collapsed = container.read(
        localDatabaseBannerCollapsedProvider.notifier,
      );

      collapsed.collapse();
      expect(indicator.read(), LocalDatabaseIndicator.mark);

      collapsed.expand();
      expect(indicator.read(), LocalDatabaseIndicator.banner);
    });

    test('το «επανήλθε» ξαναφέρνει τη λωρίδα, ακόμη κι αν ήταν μικρή', () {
      final container = containerWith(networkReturned: true);
      final indicator = container.listen(
        localDatabaseIndicatorProvider,
        (_, _) {},
      );

      container.read(localDatabaseBannerCollapsedProvider.notifier).collapse();

      expect(indicator.read(), LocalDatabaseIndicator.banner);
    });
  });

  testWidgets('μόλις απαντήσει: «επανήλθε» και σύνδεσμος μετάβασης', (
    tester,
  ) async {
    final banner = await pumpBanner(tester, networkAnswers: true);
    expect(
      find.text(kLocalDatabaseBannerText),
      findsOneWidget,
      reason: 'Πριν από τον πρώτο έλεγχο τίποτα δεν έχει επιβεβαιωθεί',
    );

    await tester.pump(_interval);
    await tester.pump();

    expect(find.text(kNetworkDatabaseReturnedText), findsOneWidget);
    expect(find.text(kLocalDatabaseSettingsLink), findsNothing);
    expect(
      find.byKey(const ValueKey('local_database_banner_collapse')),
      findsNothing,
      reason: 'Η πράσινη είναι είδηση που ζητά απόφαση — δεν μικραίνει',
    );
    expect(banner.pressed, isEmpty, reason: 'Η ειδοποίηση δεν αλλάζει βάση');

    await tester.tap(find.text(kReturnToNetworkDatabaseLink));
    await tester.pump();
    expect(banner.pressed, ['return']);
  });
}
