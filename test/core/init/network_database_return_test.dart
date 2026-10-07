// Η τοπική βάση «γι' αυτή τη φορά»: ο φρουρός που λέει πότε επανήλθε η
// δικτυακή, και η μετάβαση που ανακοινώνει μόνο ό,τι όντως άνοιξε.
//
//   flutter test test/core/init/network_database_return_test.dart

import 'package:call_logger/core/database/database_init_progress_provider.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/database/database_path_resolution.dart';
import 'package:call_logger/core/database/database_switch_success_notice.dart';
import 'package:call_logger/core/init/network_database_return.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _network = r'\\popinio\CallLogger\Data Base\hospital.db';
const _local = r'C:\CallLogger\call_logger.db';

Future<WidgetRef> _pumpWidgetRef(
  WidgetTester tester,
  ProviderContainer container,
) async {
  late WidgetRef widgetRef;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            widgetRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return widgetRef;
}

ProviderContainer _container() => ProviderContainer(
  overrides: [
    lookupServiceProvider.overrideWith(
      (ref) async => LookupLoadResult(service: LookupService.instance),
    ),
  ],
);

/// Ψεύτικος εκτελεστής ελέγχων: απαντά με τη σειρά τα δοσμένα αποτελέσματα και
/// θυμάται ποια βάση θα άνοιγε κάθε φορά.
class _FakeRunner {
  _FakeRunner(this._results);

  final List<DatabaseInitResult> _results;
  final List<String?> openedFor = [];

  Future<DatabaseInitRunnerResult> call({
    bool closeConnectionFirst = false,
    DatabaseInitProgressNotifier? progressNotifier,
  }) async {
    final configured = LocalDatabaseSessionFallback.acceptedNetworkPath;
    openedFor.add(
      configured == null
          ? _network
          : LocalDatabaseSessionFallback.acceptedLocalPathFor(configured),
    );
    return DatabaseInitRunnerResult(
      result: _results.removeAt(0),
      isLocalDevMode: configured != null,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocalDatabaseSessionFallback.forget();
  });

  tearDown(LocalDatabaseSessionFallback.forget);

  group('ο φρουρός επανόδου', () {
    test('ειδοποιεί μόλις απαντήσει η δικτυακή, και μετά σιωπά', () async {
      final answers = [false, false, true];
      var asked = 0;
      final container = ProviderContainer(
        overrides: [
          networkDatabaseReturnIntervalProvider.overrideWithValue(
            const Duration(milliseconds: 5),
          ),
          networkDatabaseProbeProvider.overrideWithValue((path) async {
            expect(path, _network);
            asked++;
            return answers.isEmpty ? true : answers.removeAt(0);
          }),
        ],
      );
      addTearDown(container.dispose);

      final seen = <bool>[];
      container.listen(
        networkDatabaseReturnedProvider(_network),
        (_, next) => next.whenData(seen.add),
        fireImmediately: true,
      );
      expect(seen, isEmpty, reason: 'Πριν από την απάντηση: καμία ειδοποίηση');

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(seen, [true]);
      expect(
        asked,
        3,
        reason: 'Μετά το «επανήλθε» ο φρουρός σταματά να ρωτά το δίκτυο',
      );
    });
  });

  group('«Μετάβαση στη δικτυακή βάση»', () {
    testWidgets('ανοίγει τη δικτυακή και μόνο τότε την ανακοινώνει', (
      tester,
    ) async {
      LocalDatabaseSessionFallback.accept(_network, _local);
      final container = _container();
      addTearDown(container.dispose);
      final ref = await _pumpWidgetRef(tester, container);
      final runner = _FakeRunner([DatabaseInitResult.success(_network)]);
      var shellRechecked = 0;

      final outcome = await returnToNetworkDatabase(
        ref: ref,
        onDatabaseReopened: () async => shellRechecked++,
        runInitChecks: runner.call,
      );
      await tester.pump();

      expect(outcome.switched, isTrue);
      expect(runner.openedFor, [_network]);
      expect(LocalDatabaseSessionFallback.acceptedNetworkPath, isNull);
      expect(shellRechecked, 1, reason: 'Η λωρίδα συγχρονίζεται με τη βάση');
      expect(
        container.read(databaseSwitchSuccessNoticeProvider),
        databaseSwitchSuccessMessage(_network),
      );
    });

    testWidgets('αν η δικτυακή ξαναχαθεί, μένει στην τοπική χωρίς ανακοίνωση', (
      tester,
    ) async {
      LocalDatabaseSessionFallback.accept(_network, _local);
      final container = _container();
      addTearDown(container.dispose);
      final ref = await _pumpWidgetRef(tester, container);
      final runner = _FakeRunner([
        DatabaseInitResult.networkUnreachable(_network),
        DatabaseInitResult.success(_local),
      ]);
      var shellRechecked = 0;

      final outcome = await returnToNetworkDatabase(
        ref: ref,
        onDatabaseReopened: () async => shellRechecked++,
        runInitChecks: runner.call,
      );
      await tester.pump();

      expect(outcome.switched, isFalse);
      expect(outcome.errorMessage, isNotEmpty);
      expect(
        runner.openedFor,
        [_network, _local],
        reason:
            'Δοκιμάζει τη δικτυακή και, όταν αποτύχει, ξανανοίγει την τοπική',
      );
      expect(
        LocalDatabaseSessionFallback.acceptedLocalPathFor(_network),
        _local,
        reason: 'Η απόφαση «τοπική» αποκαθίσταται',
      );
      expect(shellRechecked, 1);
      expect(
        container.read(databaseSwitchSuccessNoticeProvider),
        isNull,
        reason: 'Καμία πράσινη λωρίδα για βάση που δεν άνοιξε',
      );
    });
  });
}
