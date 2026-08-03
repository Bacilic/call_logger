// Η δέσμευση δοκιμαστικής βάσης (οθόνη «Σενάρια σφαλμάτων») πρέπει να λύνεται
// όταν ο χρήστης επιλέξει ρητά άλλη βάση — αλλιώς η αλλαγή μένει στα χαρτιά.
//
//   flutter test test/core/init/debug_database_binding_release_test.dart --timeout 30s

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/database/database_path_pick_flow.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String debugPath;
  late String chosenPath;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    initSqfliteFfiForTests();
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    forgetDatabaseInitResult();

    tempDir = await Directory.systemTemp.createTemp('debug_binding_release_');
    debugPath = '${tempDir.path}/debug_problematic.db';
    chosenPath = '${tempDir.path}/hospital.db';
    await DatabaseHelper.instance.createNewDatabaseFile(debugPath);
    await DatabaseHelper.instance.createNewDatabaseFile(chosenPath);
    await DatabaseHelper.instance.closeConnection();
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    forgetDatabaseInitResult();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Στήνει την κατάσταση «είμαι στη δοκιμαστική βάση» ακριβώς όπως ο seeder.
  Future<void> activateDebugDatabase() async {
    await DatabaseHelper.bindTestDatabaseFile(debugPath);
    await DatabaseHelper.instance.initializeDatabase();
    expect(
      DatabaseHelper.instance.isUsingLocalDb,
      isTrue,
      reason: greekExpectMsg(
        'Προϋπόθεση: η δοκιμαστική βάση σηματοδοτεί λειτουργία ανάπτυξης',
      ),
    );
  }

  test(
    'μετά την αποδέσμευση, οι έλεγχοι ανοίγουν τη ρυθμισμένη βάση χωρίς ένδειξη ανάπτυξης',
    () async {
      await activateDebugDatabase();
      await SettingsService().setDatabasePath(chosenPath);

      await DatabaseHelper.restoreConfiguredDatabasePath();

      // Ίδιες παράμετροι με τον AppInitializer μετά από εναλλαγή βάσης.
      final runnerResult = await runDatabaseInitChecks(
        closeConnectionFirst: false,
        reuseIfFresh: true,
      );

      expect(
        runnerResult.isLocalDevMode,
        isFalse,
        reason: greekExpectMsg(
          'Η ένδειξη «ΛΕΙΤΟΥΡΓΙΑ ΑΝΑΠΤΥΞΗΣ» πρέπει να σβήνει μόλις ο χρήστης '
          'επιλέξει κανονική βάση',
        ),
      );

      final db = await DatabaseHelper.instance.database;
      expect(
        p.equals(db.path, chosenPath),
        isTrue,
        reason: greekExpectMsg(
          'Η ενεργή σύνδεση πρέπει να είναι η βάση που επέλεξε ο χρήστης, '
          'όχι η δοκιμαστική που είχε δεσμευτεί',
        ),
      );
    },
  );

  test(
    'η επαλήθευση νέας διαδρομής αφορά την επιλεγμένη βάση, όχι τη δεσμευμένη',
    () async {
      await activateDebugDatabase();

      final outcome = await setAndVerifyDatabasePath(chosenPath);

      expect(
        outcome.ok,
        isTrue,
        reason: greekExpectMsg('Η επιλεγμένη βάση είναι έγκυρη'),
      );
      expect(
        outcome.runner.isLocalDevMode,
        isFalse,
        reason: greekExpectMsg(
          'Η επαλήθευση δεν πρέπει να αναφέρει λειτουργία ανάπτυξης για βάση '
          'που δεν είναι η δοκιμαστική',
        ),
      );

      final db = await DatabaseHelper.instance.database;
      expect(
        p.equals(db.path, chosenPath),
        isTrue,
        reason: greekExpectMsg(
          'Η επαλήθευση άνοιξε την επιλεγμένη βάση — αλλιώς θα ανακοίνωνε '
          'επιτυχία έχοντας ελέγξει τη δοκιμαστική',
        ),
      );
    },
  );

  test('χωρίς ενεργή δέσμευση η αποδέσμευση δεν κλείνει την ανοιχτή σύνδεση', () async {
    await SettingsService().setDatabasePath(chosenPath);
    await DatabaseHelper.instance.initializeDatabase();
    final generationBefore = DatabaseHelper.instance.connectionGeneration;

    await DatabaseHelper.restoreConfiguredDatabasePath();

    expect(
      DatabaseHelper.instance.connectionGeneration,
      generationBefore,
      reason: greekExpectMsg(
        'Στην κανονική αλλαγή βάσης δεν υπάρχει δέσμευση να λυθεί — η '
        'αποδέσμευση δεν πρέπει να κλείνει σύνδεση χωρίς λόγο',
      ),
    );
  });
}
