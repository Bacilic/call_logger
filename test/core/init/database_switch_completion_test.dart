// Δεσμευτική σειρά ολοκλήρωσης εναλλαγής βάσης.
//
//   flutter test test/core/init/database_switch_completion_test.dart

import 'package:call_logger/core/database/database_switch_success_notice.dart';
import 'package:call_logger/core/init/database_switch_completion.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

ProviderContainer _containerWithFastLookup() {
  return ProviderContainer(
    overrides: [
      lookupServiceProvider.overrideWith(
        (ref) async => LookupLoadResult(service: LookupService.instance),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const path = r'C:\data\switched.db';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugDatabaseSwitchCompletionSteps = <String>[];
  });

  tearDown(() {
    debugDatabaseSwitchCompletionSteps = null;
  });

  testWidgets(
    'σειρά βημάτων: session → lifecycle → caches → appInit → ειδοποίηση',
    (tester) async {
      final container = _containerWithFastLookup();
      addTearDown(container.dispose);
      final ref = await _pumpWidgetRef(tester, container);

      await completeDatabaseSwitch(
        ref: ref,
        path: path,
        hooks: DatabaseSwitchCompletionHooks(
          onSessionStateUpdated: (_) async {},
          onLifecycleChanged: () async {},
        ),
      );
      await tester.pump();

      expect(
        debugDatabaseSwitchCompletionSteps,
        [
          'onSessionStateUpdated',
          'onLifecycleChanged',
          'invalidateCaches',
          'invalidateAppInit',
          'successNotice',
        ],
      );
      expect(
        container.read(databaseSwitchSuccessNoticeProvider),
        databaseSwitchSuccessMessage(path),
      );
    },
  );

  testWidgets(
    'η εκκαθάριση caches ΔΕΝ προηγείται του onLifecycleChanged',
    (tester) async {
      final container = _containerWithFastLookup();
      addTearDown(container.dispose);
      final ref = await _pumpWidgetRef(tester, container);

      await completeDatabaseSwitch(
        ref: ref,
        path: path,
        hooks: DatabaseSwitchCompletionHooks(
          onSessionStateUpdated: (_) async {},
          onLifecycleChanged: () async {},
        ),
      );
      await tester.pump();

      final steps = debugDatabaseSwitchCompletionSteps!;
      final lifecycleIndex = steps.indexOf('onLifecycleChanged');
      final cachesIndex = steps.indexOf('invalidateCaches');
      expect(lifecycleIndex, isNonNegative);
      expect(cachesIndex, isNonNegative);
      expect(
        cachesIndex,
        greaterThan(lifecycleIndex),
        reason:
            'Η αντιστροφή caches→lifecycle ήταν το σφάλμα της δημιουργίας νέας βάσης',
      );
    },
  );

  testWidgets(
    'showSuccessNotice: false — χωρίς ειδοποίηση, τα υπόλοιπα βήματα τρέχουν',
    (tester) async {
      final container = _containerWithFastLookup();
      addTearDown(container.dispose);
      final ref = await _pumpWidgetRef(tester, container);

      await completeDatabaseSwitch(
        ref: ref,
        path: path,
        showSuccessNotice: false,
        hooks: DatabaseSwitchCompletionHooks(
          onSessionStateUpdated: (_) async {},
          onLifecycleChanged: () async {},
        ),
      );
      await tester.pump();

      expect(
        debugDatabaseSwitchCompletionSteps,
        [
          'onSessionStateUpdated',
          'onLifecycleChanged',
          'invalidateCaches',
          'invalidateAppInit',
        ],
      );
      expect(container.read(databaseSwitchSuccessNoticeProvider), isNull);
    },
  );

  testWidgets(
    'hooks: null — το συμβόλαιο τηρείται χωρίς υποχρεωτική οθόνη',
    (tester) async {
      final container = _containerWithFastLookup();
      addTearDown(container.dispose);
      final ref = await _pumpWidgetRef(tester, container);

      await completeDatabaseSwitch(
        ref: ref,
        path: path,
        hooks: null,
      );
      await tester.pump();

      expect(
        debugDatabaseSwitchCompletionSteps,
        [
          'onSessionStateUpdated',
          'onLifecycleChanged',
          'invalidateCaches',
          'invalidateAppInit',
          'successNotice',
        ],
      );
      expect(
        container.read(databaseSwitchSuccessNoticeProvider),
        databaseSwitchSuccessMessage(path),
      );
    },
  );
}
