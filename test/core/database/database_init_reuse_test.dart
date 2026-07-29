// Μία αλλαγή διαδρομής = ΜΙΑ επαληθευμένη αρχικοποίηση.
//
// Η αλυσίδα εναλλαγής βάσης έτρεχε τους ελέγχους τρεις φορές στη σειρά:
// επαλήθευση διαδρομής → onLifecycleChanged (κλείσιμο + άνοιγμα ξανά) →
// invalidate(appInitProvider) → τρίτο πέρασμα.
//
//   flutter test test/core/database/database_init_reuse_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_setup.dart';

void main() {
  late Directory tempDir;
  late String dbPath;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    initSqfliteFfiForTests();
    tempDir = await Directory.systemTemp.createTemp('init_reuse_test_');
    dbPath = '${tempDir.path}/init_reuse.db';
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await DatabaseHelper.bindTestDatabaseFile(dbPath);
    await DatabaseHelper.instance.database;
    await SettingsService().setDatabasePath(dbPath);
    forgetDatabaseInitResult();
    debugDatabaseInitChecksRunCount = 0;
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    try {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('η αλυσίδα εναλλαγής ανοίγει τη βάση ΜΙΑ φορά, όχι τρεις', () async {
    // Κρίκος 1 — επαλήθευση της νέας διαδρομής: τρέχει κανονικά.
    final first = await runDatabaseInitChecks(closeConnectionFirst: true);
    expect(first.result.isSuccess, isTrue);
    expect(debugDatabaseInitChecksRunCount, 1);

    // Κρίκος 2 — onLifecycleChanged (AppShortcuts._recheckDatabase).
    final second = await runDatabaseInitChecks(
      closeConnectionFirst: true,
      reuseIfFresh: true,
    );

    // Κρίκος 3 — invalidate(appInitProvider) → AppInitializer.
    final third = await runDatabaseInitChecks(reuseIfFresh: true);

    expect(
      debugDatabaseInitChecksRunCount,
      1,
      reason: 'οι κρίκοι 2 και 3 επαναχρησιμοποιούν το ήδη επαληθευμένο',
    );
    expect(second.result.isSuccess, isTrue);
    expect(third.result.isSuccess, isTrue);
    expect(second.databaseProfile, first.databaseProfile);
    expect(third.isLocalDevMode, first.isLocalDevMode);
  });

  test('η επαναχρήση δεν κλείνει τη σύνδεση που μόλις άνοιξε', () async {
    await runDatabaseInitChecks(closeConnectionFirst: true);
    final generationAfterFirst = DatabaseHelper.instance.connectionGeneration;

    await runDatabaseInitChecks(closeConnectionFirst: true, reuseIfFresh: true);

    expect(
      DatabaseHelper.instance.connectionGeneration,
      generationAfterFirst,
      reason: 'κανένα δεύτερο κλείσιμο με WAL checkpoint',
    );
  });

  test(
    'χωρίς reuseIfFresh τρέχει πάντα — καμία αλλαγή για τους παλιούς',
    () async {
      await runDatabaseInitChecks();
      await runDatabaseInitChecks();
      await runDatabaseInitChecks();

      expect(debugDatabaseInitChecksRunCount, 3);
    },
  );

  test(
    'κλείσιμο σύνδεσης ακυρώνει τη μνήμη χωρίς να το ζητήσει κανείς',
    () async {
      await runDatabaseInitChecks();
      expect(debugDatabaseInitChecksRunCount, 1);

      // Η ρητή «Επαναδοκιμή» περνά πάντα από εδώ.
      await DatabaseHelper.instance.closeConnection();

      await runDatabaseInitChecks(reuseIfFresh: true);
      expect(
        debugDatabaseInitChecksRunCount,
        2,
        reason: 'μετά από κλείσιμο δεν επιτρέπεται «όλα καλά» από μνήμη',
      );
    },
  );

  test('αλλαγή διαδρομής ακυρώνει τη μνήμη', () async {
    await runDatabaseInitChecks();
    expect(debugDatabaseInitChecksRunCount, 1);

    final otherPath = '${tempDir.path}/other.db';
    await File(otherPath).writeAsBytes(const <int>[]);
    await SettingsService().setDatabasePath(otherPath);

    await runDatabaseInitChecks(reuseIfFresh: true);
    expect(
      debugDatabaseInitChecksRunCount,
      2,
      reason: 'άλλη διαδρομή σημαίνει άλλο αποτέλεσμα',
    );

    await SettingsService().setDatabasePath(dbPath);
  });

  test('αποτυχία δεν αποθηκεύεται ποτέ', () async {
    final missing = '${tempDir.path}/missing.db';
    await SettingsService().setDatabasePath(missing);

    final failed = await runDatabaseInitChecks();
    expect(failed.result.isSuccess, isFalse);
    final afterFailure = debugDatabaseInitChecksRunCount;

    await runDatabaseInitChecks(reuseIfFresh: true);
    expect(
      debugDatabaseInitChecksRunCount,
      afterFailure + 1,
      reason: 'μια αποτυχία πρέπει να ξαναδοκιμάζεται πάντα',
    );

    await SettingsService().setDatabasePath(dbPath);
  });
}
