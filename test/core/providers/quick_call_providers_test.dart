// Έλεγχος διαθεσιμότητας γρήγορης κλήσης.
//
//   flutter test test/core/providers/quick_call_providers_test.dart

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

Future<ProviderContainer> _pumpProbe(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [showQuickCallFabProvider.overrideWith((ref) async => true)],
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
  });
}
