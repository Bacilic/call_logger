// Το αντίγραφο αναβάθμισης φορτώνεται αυτόματα — χωρίς δεύτερη ερώτηση.
//
//   flutter test test/features/database/upgrade_copy_autoload_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/features/database/services/database_upgrade_copy_service.dart';
import 'package:call_logger/features/database/widgets/schema_upgrade_consent_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    initSqfliteFfiForTests();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
  });

  test(
    'μετά τη δημιουργία αντιγράφου η βάση ανοίγει χωρίς νέα συγκατάθεση',
    () async {
      final dir = await Directory.systemTemp.createTemp('upgrade_autoload_');
      addTearDown(() async {
        // Πρώτα κλείνει η σύνδεση: το αρχείο του αντιγράφου μένει ανοιχτό.
        await DatabaseHelper.instance.closeConnection();
        DatabaseHelper.releaseTestDatabaseBinding();
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      // Πηγή με παλιότερο σχήμα — όπως η «παλιά_βάση_2023.db».
      final source = p.join(dir.path, 'παλιά_βάση_2023.db');
      await DatabaseHelper.instance.createNewDatabaseFile(source);
      final writer = await openDatabase(source, singleInstance: false);
      await writer.rawQuery('PRAGMA user_version = 30');
      await writer.close();

      final copy = await createUpgradeCopy(source);
      expect(copy.isSuccess, isTrue, reason: copy.errorMessage ?? '');
      final copyPath = copy.copyPath!;

      // Ό,τι κάνει η ροή του διαλόγου μετά την επιλογή «αντίγραφο».
      await SettingsService().setSchemaUpgradeConsentIdentity(
        await schemaUpgradeConsentIdentityForPath(copyPath),
      );
      await SettingsService().setDatabasePath(copyPath);
      final runner = await runDatabaseInitChecks(closeConnectionFirst: true);

      expect(
        runner.result.recoveryKind,
        isNot(DatabaseInitRecoveryKind.schemaUpgradeConsent),
        reason:
            'Η συγκατάθεση δόθηκε ήδη για αυτό το αντίγραφο — η δεύτερη '
            'ερώτηση εμφανιζόταν ως ψευδής «αποτυχία ανοίγματος αντιγράφου»',
      );
      expect(runner.result.isSuccess, isTrue);

      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('PRAGMA user_version');
      expect(rows.first['user_version'], kDatabaseSchemaVersion);
    },
  );
}
