// Έλεγχος διαθεσιμότητας γρήγορης κλήσης ανά προορισμό κελύφους.
//
//   flutter test test/core/providers/quick_call_providers_test.dart

import 'package:call_logger/core/providers/quick_call_providers.dart';
import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/widgets/main_nav_destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _AvailabilityProbe extends ConsumerStatefulWidget {
  const _AvailabilityProbe({required this.destination});

  final MainNavDestination destination;

  @override
  ConsumerState<_AvailabilityProbe> createState() => _AvailabilityProbeState();
}

class _AvailabilityProbeState extends ConsumerState<_AvailabilityProbe> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(mainShellEffectiveDestinationProvider.notifier)
          .setDestination(widget.destination);
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final available = isQuickCallCaptureAvailable(ref);
    return Text(available ? 'available' : 'blocked');
  }
}

void main() {
  group('isQuickCallCaptureAvailable', () {
    testWidgets('επιτρέπεται σε Βάση Δεδομένων', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            overrides: [
              showQuickCallFabProvider.overrideWith((ref) async => true),
            ],
            child: const _AvailabilityProbe(
              destination: MainNavDestination.database,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('available'), findsOneWidget);
    });

    testWidgets('απενεργοποιείται μόνο στην οθόνη Κλήσεων', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            overrides: [
              showQuickCallFabProvider.overrideWith((ref) async => true),
            ],
            child: const _AvailabilityProbe(
              destination: MainNavDestination.calls,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('blocked'), findsOneWidget);
    });
  });
}
