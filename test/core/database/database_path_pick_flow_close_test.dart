// Κλείσιμο της προηγούμενης σύνδεσης πριν από επαλήθευση νέας διαδρομής.
//
// Η ροή έκλεινε δύο φορές: μία χειροκίνητα και μία μέσω `closeConnectionFirst`.
// Και, κρίσιμα, η αποτυχία του χειροκίνητου κλεισίματος καταπινόταν σιωπηλά —
// αν έμενε ανοιχτή η παλιά σύνδεση, το `initializeDatabase()` θα την επέστρεφε
// και η ροή θα επαλήθευε την ΠΑΛΙΑ βάση αναφέροντας επιτυχία για τη νέα.
//
//   flutter test test/core/database/database_path_pick_flow_close_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_init_progress_provider.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/database/database_path_pick_flow.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;
  late String newPath;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('pick_flow_close_test_');
    newPath = '${tempDir.path}/new.db';
    await File(newPath).writeAsBytes(const <int>[]);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SettingsService().setDatabasePath('${tempDir.path}/old.db');
  });

  tearDownAll(() async {
    try {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  DatabaseInitChecksRunner successRunner(List<bool> capturedCloseFlags) {
    return ({
      bool closeConnectionFirst = false,
      bool reuseIfFresh = false,
      DatabaseInitProgressNotifier? progressNotifier,
    }) async {
      capturedCloseFlags.add(closeConnectionFirst);
      return DatabaseInitRunnerResult(
        result: DatabaseInitResult.success(newPath),
        isLocalDevMode: false,
      );
    };
  }

  test('η σύνδεση κλείνει ΜΙΑ φορά, όχι δύο', () async {
    var closeCalls = 0;
    final flags = <bool>[];

    final outcome = await setAndVerifyDatabasePath(
      newPath,
      runInitChecks: successRunner(flags),
      closeConnection: () async {
        closeCalls++;
      },
    );

    expect(outcome.ok, isTrue);
    expect(closeCalls, 1, reason: 'ένα κλείσιμο ανά επαλήθευση');
    expect(flags, [
      false,
    ], reason: 'ο runner δεν ξανακλείνει — η ροή το έχει ήδη κάνει');
  });

  test('αποτυχία κλεισίματος σταματά την επαλήθευση', () async {
    final flags = <bool>[];

    final outcome = await setAndVerifyDatabasePath(
      newPath,
      runInitChecks: successRunner(flags),
      closeConnection: () async {
        throw StateError('το αρχείο είναι κλειδωμένο');
      },
    );

    expect(outcome.ok, isFalse);
    expect(
      flags,
      isEmpty,
      reason: 'δεν επαληθεύουμε ποτέ με ανοιχτή την προηγούμενη σύνδεση',
    );
    expect(outcome.runner.result.isSuccess, isFalse);
  });

  test('αποτυχία κλεισίματος αφήνει τη ρύθμιση διαδρομής άθικτη', () async {
    final settings = SettingsService();
    final before = await settings.getDatabasePath();

    await setAndVerifyDatabasePath(
      newPath,
      runInitChecks: successRunner(<bool>[]),
      closeConnection: () async {
        throw StateError('κλειδωμένο');
      },
    );

    expect(
      await settings.getDatabasePath(),
      before,
      reason: 'η έξοδος γίνεται πριν γραφτεί η νέα διαδρομή',
    );
  });
}
