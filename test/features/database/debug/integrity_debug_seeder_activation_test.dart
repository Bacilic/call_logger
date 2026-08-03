// Η ενεργοποίηση της δοκιμαστικής βάσης πρέπει να αλλάζει και τη ρυθμισμένη
// διαδρομή — αλλιώς οι Ρυθμίσεις δείχνουν άλλη βάση από αυτή που είναι ανοιχτή
// και η επανεπιλογή της «τρέχουσας» δεν κάνει τίποτα.
//
//   flutter test test/features/database/debug/integrity_debug_seeder_activation_test.dart --timeout 30s

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/database/database_path_pick_flow.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/features/database/debug/integrity_debug_seeder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../test_reporter.dart';
import '../../../test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String hospitalPath;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    initSqfliteFfiForTests();
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    forgetDatabaseInitResult();

    tempDir = await Directory.systemTemp.createTemp('seeder_activation_');
    hospitalPath = '${tempDir.path}/hospital.db';
    await DatabaseHelper.instance.createNewDatabaseFile(hospitalPath);
    await DatabaseHelper.instance.closeConnection();
    await SettingsService().setDatabasePath(hospitalPath);
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    forgetDatabaseInitResult();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'μετά την ενεργοποίηση, η ρυθμισμένη διαδρομή ΕΙΝΑΙ η δοκιμαστική βάση',
    () async {
      await DatabaseHelper.instance.initializeDatabase();
      final seeder = IntegrityDebugSeederService();
      final debugPath = await seeder.resolveDebugDatabasePath();

      final result = await seeder.seedAndActivate();
      expect(
        result.success,
        isTrue,
        reason: greekExpectMsg(
          'Προϋπόθεση: ο seeder ολοκληρώνεται (${result.errorMessage})',
        ),
      );

      expect(
        p.equals(await SettingsService().getDatabasePath(), debugPath),
        isTrue,
        reason: greekExpectMsg(
          'Η ρύθμιση διαδρομής πρέπει να δείχνει τη δοκιμαστική βάση, ώστε οι '
          'Ρυθμίσεις να μη μιλούν για άλλη βάση από αυτή που είναι ανοιχτή',
        ),
      );

      final db = await DatabaseHelper.instance.database;
      expect(
        p.equals(db.path, debugPath),
        isTrue,
        reason: greekExpectMsg('Η ανοιχτή σύνδεση είναι η δοκιμαστική βάση'),
      );
    },
  );

  test(
    'η ενεργοποίηση ΔΕΝ ανάβει την ένδειξη «τοπική βάση» — αυτή αφορά την πτώση από δικτυακή διαδρομή',
    () async {
      await DatabaseHelper.instance.initializeDatabase();
      await IntegrityDebugSeederService().seedAndActivate();

      expect(
        DatabaseHelper.instance.isUsingLocalDb,
        isFalse,
        reason: greekExpectMsg(
          'Η δοκιμαστική βάση δεν είναι «πτώση σε τοπική»: δύο διαφορετικές '
          'καταστάσεις δεν πρέπει να μοιράζονται το ίδιο σήμα',
        ),
      );
    },
  );

  test(
    'η δοκιμαστική βάση ΔΕΝ μπαίνει στις πρόσφατες — μόνο ο χρήστης γεμίζει τη λίστα',
    () async {
      await DatabaseHelper.instance.initializeDatabase();
      final seeder = IntegrityDebugSeederService();
      final debugPath = await seeder.resolveDebugDatabasePath();

      await seeder.seedAndActivate();

      final recents = await SettingsService().getRecentDatabasePaths();
      expect(
        recents.any((path) => p.equals(path, debugPath)),
        isFalse,
        reason: greekExpectMsg(
          'Η δοκιμαστική φτιάχνεται και σβήνεται προγραμματιστικά — στις '
          'γρήγορες επιλογές θα ήταν θόρυβος',
        ),
      );
      expect(
        p.equals(await SettingsService().getDatabasePath(), debugPath),
        isTrue,
        reason: greekExpectMsg(
          'Παρ όλα αυτά παραμένει η ΕΝΕΡΓΗ διαδρομή, οπότε το πεδίο τη δείχνει',
        ),
      );
    },
  );

  test(
    'επιλεγμένη από τον χρήστη, η ίδια βάση καταγράφεται κανονικά ως συνειδητή επιλογή',
    () async {
      await DatabaseHelper.instance.initializeDatabase();
      final seeder = IntegrityDebugSeederService();
      final debugPath = await seeder.resolveDebugDatabasePath();
      await seeder.seedAndActivate();

      // Ο χρήστης γυρίζει πίσω και μετά τη διαλέγει ο ίδιος από τον επιλογέα.
      await setAndVerifyDatabasePath(hospitalPath);
      final outcome = await setAndVerifyDatabasePath(debugPath);

      expect(outcome.ok, isTrue);
      final recents = await SettingsService().getRecentDatabasePaths();
      expect(
        recents.any((path) => p.equals(path, debugPath)),
        isTrue,
        reason: greekExpectMsg(
          'Η ρητή επιλογή του χρήστη είναι συνειδητή απόφαση και μένει στη λίστα',
        ),
      );
    },
  );

  test(
    'η προηγούμενη βάση παραμένει επιλέξιμη, ώστε να υπάρχει επιστροφή',
    () async {
      await DatabaseHelper.instance.initializeDatabase();
      await SettingsService().recordVerifiedDatabasePath(hospitalPath);

      await IntegrityDebugSeederService().seedAndActivate();

      final recents = await SettingsService().getRecentDatabasePaths();
      expect(
        recents.any((path) => p.equals(path, hospitalPath)),
        isTrue,
        reason: greekExpectMsg(
          'Χωρίς την προηγούμενη βάση στις πρόσφατες, ο χρήστης δεν έχει τρόπο '
          'να γυρίσει πίσω από τη δοκιμαστική',
        ),
      );
    },
  );
}
