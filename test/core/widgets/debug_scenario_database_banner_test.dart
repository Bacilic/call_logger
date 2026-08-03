// Λωρίδα «ΔΟΚΙΜΑΣΤΙΚΗ ΒΑΣΗ ΣΕΝΑΡΙΩΝ» στο MainShell.
//
// Η προειδοποίηση πρέπει να συνοδεύει τον χρήστη σε ΚΑΘΕ οθόνη όσο τρέχει πάνω
// σε κατασκευασμένα δεδομένα — και ανάβει από την υπογραφή του σπορέα ΜΕΣΑ στη
// βάση, όχι από το όνομα του αρχείου: η μετονομασία δεν την κρύβει και η
// επαναφορά αληθινών δεδομένων πάνω στο ίδιο όνομα δεν την ανάβει ψευδώς.
//
//   flutter test test/core/widgets/debug_scenario_database_banner_test.dart --timeout 30s

import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/widgets/main_shell.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/calls/provider/calls_dashboard_providers.dart';
import 'package:call_logger/features/database/debug/integrity_debug_seeder_service.dart';
import 'package:call_logger/features/tasks/providers/tasks_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

const _bannerKey = ValueKey('debug_scenario_database_banner');

/// Πλήρες προφίλ, ώστε να μην ανάβει η άσχετη λωρίδα «ημιτελής βάση».
DatabaseFileProfile _healthyProfile({bool debugSignature = false}) {
  final today = DateTime.now();
  return DatabaseFileProfile(
    kind: DatabaseFileKind.callLogger,
    callCount: 17,
    userCount: 12,
    phoneCount: 15,
    equipmentCount: 13,
    departmentCount: 12,
    latestCallDate:
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}',
    hasDebugScenarioSignature: debugSignature,
  );
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required String path,
  required DatabaseFileProfile profile,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...callLoggerTestProviderOverrides(),
        globalRecentCallsProvider.overrideWith(
          (ref) async => const <CallModel>[],
        ),
        globalPendingTasksCountProvider.overrideWith((ref) async => 0),
      ],
      child: MaterialApp(
        home: MainShell(
          databaseResult: DatabaseInitResult.success(path),
          isLocalDevMode: false,
          databaseProfile: profile,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _flushPendingTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 11));
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  setUpAll(() async {
    LookupService.instance.resetForReload();
    await LookupService.instance.loadFromDatabase();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('βάση με υπογραφή σπορέα προειδοποιεί — όποιο όνομα κι αν έχει', (
    tester,
  ) async {
    final realPath = (await DatabaseHelper.instance.database).path;
    // Επίτηδες κανονικό όνομα αρχείου: η μετονομασία δεν κρύβει τη δοκιμαστική.
    final renamedPath = p.join(p.dirname(realPath), 'patates.db');

    await _pumpShell(
      tester,
      path: renamedPath,
      profile: _healthyProfile(debugSignature: true),
    );

    expect(
      find.byKey(_bannerKey),
      findsOneWidget,
      reason: greekExpectMsg(
        'Χωρίς λωρίδα, ο χρήστης δουλεύει πάνω σε κατασκευασμένα δεδομένα '
        'χωρίς να το ξέρει — και το όνομα του αρχείου δεν αποδεικνύει τίποτα',
      ),
    );
    expect(find.textContaining('ΔΟΚΙΜΑΣΤΙΚΗ ΒΑΣΗ'), findsOneWidget);
    await _flushPendingTimers(tester);
  });

  testWidgets('βάση χωρίς υπογραφή δεν δείχνει τη λωρίδα — ακόμη κι αν λέγεται integrity_debug.db', (
    tester,
  ) async {
    final realPath = (await DatabaseHelper.instance.database).path;
    // Επίτηδες το όνομα της δοκιμαστικής: μετά από επαναφορά αληθινών
    // δεδομένων πάνω στο ίδιο αρχείο, η προειδοποίηση θα έλεγε ψέματα.
    final debugNamedPath = p.join(
      p.dirname(realPath),
      IntegrityDebugSeederService.databaseFileName,
    );

    await _pumpShell(
      tester,
      path: debugNamedPath,
      profile: _healthyProfile(),
    );

    expect(
      find.byKey(_bannerKey),
      findsNothing,
      reason: greekExpectMsg(
        'Μια προειδοποίηση που εμφανίζεται πάντα δεν προειδοποιεί για τίποτα',
      ),
    );
    await _flushPendingTimers(tester);
  });
}
