// Η ενεργοποίηση της δοκιμαστικής βάσης οφείλει να περνά ΟΛΟΚΛΗΡΗ από την
// completeDatabaseSwitch — όχι μόνο από την εκκαθάριση caches.
//
// Το `invalidate(appInitProvider)` είναι το μόνο σημείο απ' όπου ανανεώνονται
// το DatabaseInitResult και το προφίλ αρχείου· χωρίς αυτό η λωρίδα κατάστασης
// και το μήνυμα σύνδεσης μένουν παγωμένα στην προηγούμενη βάση, ενώ διαδρομή
// και στατιστικά δείχνουν τη νέα.
//
//   flutter test test/features/database/debug/integrity_debug_switch_completion_test.dart --timeout 30s

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/database/database_switch_success_notice.dart';
import 'package:call_logger/core/init/database_switch_completion.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/features/database/debug/integrity_debug_provider_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../test_reporter.dart';
import '../../../test_setup.dart';

Future<WidgetRef> _pumpWidgetRef(
  WidgetTester tester,
  ProviderContainer container,
) async {
  late WidgetRef captured;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return captured;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    initSqfliteFfiForTests();
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    forgetDatabaseInitResult();
    debugDatabaseSwitchCompletionSteps = <String>[];

    tempDir = await Directory.systemTemp.createTemp('debug_switch_completion_');
    dbPath = '${tempDir.path}/integrity_debug.db';
    await DatabaseHelper.instance.createNewDatabaseFile(dbPath);
    await DatabaseHelper.instance.closeConnection();
    await SettingsService().setDatabasePath(dbPath);
  });

  tearDown(() async {
    debugDatabaseSwitchCompletionSteps = null;
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    forgetDatabaseInitResult();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets(
    'η ανανέωση μετά τον seeder ακυρώνει το appInit — αλλιώς η λωρίδα μιλά για την παλιά βάση',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = await _pumpWidgetRef(tester, container);

      await tester.runAsync(
        () => refreshProvidersAfterIntegrityDebugSwitch(
          ref,
          activatedPath: dbPath,
        ),
      );
      await tester.pump();

      final steps = debugDatabaseSwitchCompletionSteps!;
      expect(
        steps,
        contains('invalidateAppInit'),
        reason: greekExpectMsg(
          'Χωρίς ακύρωση του appInit, το DatabaseInitResult και το προφίλ '
          'αρχείου μένουν της προηγούμενης βάσης: η λωρίδα κατάστασης και το '
          'μήνυμα σύνδεσης δείχνουν άλλη βάση από τη διαδρομή',
        ),
      );
      expect(
        steps,
        contains('invalidateCaches'),
        reason: greekExpectMsg(
          'Η εκκαθάριση caches παραμένει μέρος της ίδιας ροής',
        ),
      );
      expect(
        container.read(databaseSwitchSuccessNoticeProvider),
        databaseSwitchSuccessMessage(dbPath),
        reason: greekExpectMsg(
          'Ο χρήστης βλέπει σε ποια βάση βρέθηκε, όπως σε κάθε άλλη αλλαγή βάσης',
        ),
      );
    },
  );
}
