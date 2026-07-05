// Έλεγχος: refreshAfterCallMutation ακυρώνει dashboardCallsForReportProvider
// ώστε η λίστα του διαλόγου «Αναφορά Lansweeper» να ανανεώνεται αμέσως.
//
//   flutter test test/features/calls/call_mutation_refresh_report_provider_test.dart

import 'package:call_logger/features/calls/provider/call_mutation_refresh.dart';
import 'package:call_logger/features/history/providers/dashboard_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

Ref? _capturedRef;

final _refCaptureProvider = Provider<int>((ref) {
  _capturedRef = ref;
  return 0;
});

Future<ProviderContainer> _reportRefreshTestContainer() async {
  final container = ProviderContainer(
    overrides: callLoggerTestProviderOverrides(),
  );
  container.read(_refCaptureProvider);
  return container;
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('refreshAfterCallMutation — dashboardCallsForReportProvider', () {
    setUp(() async {
      await bindCallLoggerIsolatedTestDatabase();
    });

    test(
      'refreshAfterCallMutation ακυρώνει dashboardCallsForReportProvider όταν invalidateHistory=true',
      () async {
        final container = await _reportRefreshTestContainer();

        // Κρατάμε ζωντανό τον autoDispose provider με listener (όπως ο διάλογος Lansweeper).
        container.listen(dashboardCallsForReportProvider, (_, _) {});

        await container.read(dashboardCallsForReportProvider.future);
        expect(
          container.read(dashboardCallsForReportProvider).hasValue,
          isTrue,
          reason: 'Προϋπόθεση: ο provider έχει φορτώσει δεδομένα πριν τη mutation',
        );

        refreshAfterCallMutation(_capturedRef!, invalidateHistory: true);

        expect(
          container.read(dashboardCallsForReportProvider).isLoading,
          isTrue,
          reason:
              'dashboardCallsForReportProvider πρέπει να ακυρωθεί μαζί με historyCallsProvider/dashboardStatsProvider',
        );

        container.dispose();
      },
    );
  });
}
