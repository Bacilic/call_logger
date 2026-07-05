// Έλεγχος: Lansweeper mutations ακυρώνουν historyCallsProvider, όχι μόνο dashboard providers.
//
//   flutter test test/features/history/lansweeper_sync_invalidates_history_test.dart

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/models/lansweeper_sync_state.dart';
import 'package:call_logger/features/history/providers/dashboard_provider.dart';
import 'package:call_logger/features/history/providers/history_provider.dart';
import 'package:call_logger/features/history/providers/lansweeper_sync_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;

import '../../test_setup.dart';
import 'lansweeper_report_test_doubles.dart';

const _kLansweeperSyncInvalidateMarker = 'LS_SYNC_INVALIDATE_TEST';

Future<int> _insertUnsentCall() async {
  final db = await DatabaseHelper.instance.database;
  return CallsRepository(db).insertCall(
    CallModel(
      phoneText: kTestPhoneDigits,
      issue: _kLansweeperSyncInvalidateMarker,
      status: 'completed',
      lansweeperState: LansweeperSyncState.unsent,
    ),
  );
}

Future<ProviderContainer> _testContainer() async {
  return ProviderContainer(
    overrides: <Override>[
      ...callLoggerTestProviderOverrides(),
      dashboardFilterProvider.overrideWith(AllDatesDashboardFilterNotifier.new),
    ],
  );
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Lansweeper sync — invalidates history', () {
    setUp(() async {
      await bindCallLoggerIsolatedTestDatabase();
    });

    test(
      'markRegistered ακυρώνει historyCallsProvider μετά Lansweeper mutation',
      () async {
        final callId = await _insertUnsentCall();
        final container = await _testContainer();

        // Κρατάμε ζωντανούς autoDispose providers (όπως ανοιχτές οθόνες Ιστορικού/Lansweeper).
        container.listen(historyCallsProvider, (_, _) {});
        container.listen(dashboardCallsForReportProvider, (_, _) {});
        container.listen(lansweeperSyncProvider, (_, _) {});

        await container.read(historyCallsProvider.future);
        await container.read(dashboardCallsForReportProvider.future);
        expect(
          container.read(historyCallsProvider).hasValue,
          isTrue,
          reason:
              'Προϋπόθεση: historyCallsProvider έχει φορτώσει πριν τη mutation',
        );

        await container.read(lansweeperSyncProvider.notifier).markRegistered(
              callId: callId,
              ticketId: '123',
            );

        expect(
          container.read(historyCallsProvider).isLoading,
          isTrue,
          reason:
              'historyCallsProvider πρέπει να ακυρωθεί μετά Lansweeper markRegistered',
        );

        container.dispose();
      },
    );
  });
}
