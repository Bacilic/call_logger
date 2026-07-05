// Έλεγχος: refreshAfterCallMutation ακυρώνει totalCallsCountProvider
// ώστε να μην εξαρτάται από ref.watch(historyCallsProvider) κατά το build.
//
//   flutter test test/features/calls/call_mutation_refresh_total_count_test.dart

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/calls/provider/call_mutation_refresh.dart';
import 'package:call_logger/features/history/providers/history_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

const _kTotalCountInvalidateMarker = 'TOTAL_COUNT_INVALIDATE_TEST';

Ref? _capturedRef;

final _refCaptureProvider = Provider<int>((ref) {
  _capturedRef = ref;
  return 0;
});

Future<int> _insertCall() async {
  final db = await DatabaseHelper.instance.database;
  return CallsRepository(db).insertCall(
    CallModel(
      phoneText: kTestPhoneDigits,
      issue: _kTotalCountInvalidateMarker,
      status: 'completed',
    ),
  );
}

Future<ProviderContainer> _totalCountRefreshTestContainer() async {
  final container = ProviderContainer(
    overrides: callLoggerTestProviderOverrides(),
  );
  container.read(_refCaptureProvider);
  return container;
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('refreshAfterCallMutation — totalCallsCountProvider', () {
    setUp(() async {
      await bindCallLoggerIsolatedTestDatabase();
    });

    test(
      'refreshAfterCallMutation ακυρώνει totalCallsCountProvider όταν invalidateHistory=true',
      () async {
        await _insertCall();
        final container = await _totalCountRefreshTestContainer();

        container.listen(historyCallsProvider, (_, _) {});
        container.listen(totalCallsCountProvider, (_, _) {});

        await container.read(totalCallsCountProvider.future);
        expect(
          container.read(totalCallsCountProvider).hasValue,
          isTrue,
          reason:
              'Προϋπόθεση: totalCallsCountProvider έχει φορτώσει πριν τη mutation',
        );

        refreshAfterCallMutation(_capturedRef!, invalidateHistory: true);

        expect(
          container.read(totalCallsCountProvider).isLoading,
          isTrue,
          reason:
              'totalCallsCountProvider πρέπει να ακυρωθεί ρητά μετά call mutation',
        );

        container.dispose();
      },
    );
  });
}
