// Διαθεσιμότητα της γρήγορης κλήσης και σε ποιες οθόνες φαίνεται το κουμπί.
//
//   flutter test test/core/providers/quick_call_providers_test.dart

import 'package:call_logger/core/models/quick_call_fab_places.dart';
import 'package:call_logger/core/providers/quick_call_providers.dart';
import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _AvailabilityProbe extends ConsumerWidget {
  const _AvailabilityProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = isQuickCallCaptureAvailable(ref);
    return Text(available ? 'available' : 'blocked');
  }
}

Future<ProviderContainer> _pumpProbe(
  WidgetTester tester, {
  QuickCallFabPlaces places = QuickCallFabPlaces.all,
}) async {
  final container = ProviderContainer(
    overrides: [quickCallFabPlacesProvider.overrideWith((ref) async => places)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: _AvailabilityProbe()),
    ),
  );
  await tester.pump();
  await tester.pump();
  return container;
}

void main() {
  group('isQuickCallCaptureAvailable', () {
    testWidgets('επιτρέπεται σε κάθε οθόνη, και στις Κλήσεις', (tester) async {
      await _pumpProbe(tester);
      expect(find.text('available'), findsOneWidget);
    });

    testWidgets('επιτρέπεται και με το κουμπί κρυμμένο παντού: η συντόμευση '
        'δουλεύει', (tester) async {
      await _pumpProbe(tester, places: QuickCallFabPlaces.none);
      expect(find.text('available'), findsOneWidget);
    });

    testWidgets('μπλοκάρεται όσο ο χάρτης είναι σε επεξεργασία', (
      tester,
    ) async {
      final container = await _pumpProbe(tester);
      container
          .read(buildingMapQuickCallBlockedProvider.notifier)
          .setBlocked(true);
      await tester.pump();
      expect(find.text('blocked'), findsOneWidget);
    });

    testWidgets('η Σχεδίαση χάρτη πάνω από την επεξεργασία την επιτρέπει', (
      tester,
    ) async {
      final container = await _pumpProbe(tester);
      container
          .read(buildingMapQuickCallBlockedProvider.notifier)
          .setBlocked(true);
      container.read(floorPlanDesignOpenProvider.notifier).setOpen(true);
      await tester.pump();
      expect(find.text('available'), findsOneWidget);

      container.read(floorPlanDesignOpenProvider.notifier).setOpen(false);
      await tester.pump();
      expect(find.text('blocked'), findsOneWidget);
    });
  });

  group('QuickCallFabPlaces', () {
    test('χωρίς δική του τιμή κληρονομεί τον παλιό διακόπτη', () {
      expect(QuickCallFabPlaces.fromStorage(null), QuickCallFabPlaces.all);
      expect(
        QuickCallFabPlaces.fromStorage(null, legacyShow: true),
        QuickCallFabPlaces.all,
      );
      expect(
        QuickCallFabPlaces.fromStorage(null, legacyShow: false),
        QuickCallFabPlaces.none,
      );
      expect(
        QuickCallFabPlaces.fromStorage('χαλασμένο', legacyShow: false),
        QuickCallFabPlaces.none,
      );
    });

    test('η αποθήκευση κρατά ακριβώς τα κρυμμένα σημεία', () {
      final places = QuickCallFabPlaces.all
          .withPlace(QuickCallFabPlace.settings, false)
          .withPlace(QuickCallFabPlace.mapView, false);
      final back = QuickCallFabPlaces.fromStorage(places.toJsonString());

      expect(back, places);
      expect(back.shows(QuickCallFabPlace.settings), isFalse);
      expect(back.shows(QuickCallFabPlace.floorPlanDesign), isTrue);
      expect(back.shownCount, QuickCallFabPlace.values.length - 2);
    });

    test('άγνωστο ή μελλοντικό όνομα σημείου αγνοείται', () {
      final back = QuickCallFabPlaces.fromStorage(
        '{"hidden":["settings","κάτι_άλλο"]}',
      );
      expect(back.shownCount, QuickCallFabPlace.values.length - 1);
    });
  });
}
