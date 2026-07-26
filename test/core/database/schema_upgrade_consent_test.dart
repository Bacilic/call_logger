// Συγκατάθεση πριν από μόνιμη αναβάθμιση σχήματος.
//
//   flutter test test/core/database/schema_upgrade_consent_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/database_state_notice.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

Future<Uint8List> _bytes(String path) => File(path).readAsBytes();

Future<String> _createOldSchemaDb(Directory dir, String name) async {
  final dbPath = p.join(dir.path, name);
  await DatabaseHelper.instance.createNewDatabaseFile(dbPath);
  final db = await openDatabase(dbPath, singleInstance: false);
  await db.rawQuery('PRAGMA user_version = 30');
  await db.close();
  return dbPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    initSqfliteFfiForTests();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    tempDir = await Directory.systemTemp.createTemp('schema_consent_');
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'νέα διαδρομή με παλιότερο user_version → schemaUpgradeConsent χωρίς εγγραφή',
    () async {
      final dbPath = await _createOldSchemaDb(tempDir, 'old_new_path.db');
      // Διαφορετική τελευταία διαδρομή → απαιτείται συγκατάθεση.
      await SettingsService().setLastOpenedDatabasePath(
        p.join(tempDir.path, 'other.db'),
      );

      final before = await _bytes(dbPath);
      final settings = SettingsService();
      await settings.setDatabasePath(dbPath);
      await settings.setDatabaseOpenTimeoutSeconds(2);
      await settings.setDatabaseOpenMaxAttempts(1);

      final runner = await runDatabaseInitChecks(closeConnectionFirst: true);
      final after = await _bytes(dbPath);

      expect(runner.result.isSuccess, isFalse);
      expect(
        runner.result.recoveryKind,
        DatabaseInitRecoveryKind.schemaUpgradeConsent,
      );
      expect(after, orderedEquals(before));
      expect(runner.result.message, contains('ΜΟΝΙΜΑ'));
      expect(runner.result.message, contains('30'));
      expect(runner.result.message, contains('$kDatabaseSchemaVersion'));
    },
  );

  test(
    'μετά την καταγραφή συγκατάθεσης το άνοιγμα προχωρά και αναβαθμίζει',
    () async {
      final dbPath = await _createOldSchemaDb(tempDir, 'old_consent.db');
      await SettingsService().setLastOpenedDatabasePath(
        p.join(tempDir.path, 'other.db'),
      );

      final profile = await profileDatabaseFile(dbPath);
      final identity = databaseContentIdentity(
        dbPath: dbPath,
        latestCallDate: profile.latestCallDate,
        callCount: profile.callCount,
        fileModifiedMs: File(dbPath).lastModifiedSync().millisecondsSinceEpoch,
      );
      await SettingsService().setSchemaUpgradeConsentIdentity(identity);

      final settings = SettingsService();
      await settings.setDatabasePath(dbPath);
      await settings.setDatabaseOpenTimeoutSeconds(2);
      await settings.setDatabaseOpenMaxAttempts(1);

      final runner = await runDatabaseInitChecks(closeConnectionFirst: true);
      expect(runner.result.isSuccess, isTrue);

      final versionRows =
          await openDatabase(
            dbPath,
            readOnly: true,
            singleInstance: false,
          ).then((db) async {
            final rows = await db.rawQuery('PRAGMA user_version');
            await db.close();
            return rows;
          });
      expect(versionRows.first['user_version'], kDatabaseSchemaVersion);
    },
  );

  test(
    'ίδια διαδρομή με lastOpened → σιωπηλή αναβάθμιση χωρίς ερώτηση',
    () async {
      final dbPath = await _createOldSchemaDb(tempDir, 'daily.db');
      await SettingsService().setLastOpenedDatabasePath(dbPath);

      final settings = SettingsService();
      await settings.setDatabasePath(dbPath);
      await settings.setDatabaseOpenTimeoutSeconds(2);
      await settings.setDatabaseOpenMaxAttempts(1);

      final runner = await runDatabaseInitChecks(closeConnectionFirst: true);
      expect(runner.result.isSuccess, isTrue);
      expect(runner.result.recoveryKind, isNull);

      final versionRows =
          await openDatabase(
            dbPath,
            readOnly: true,
            singleInstance: false,
          ).then((db) async {
            final rows = await db.rawQuery('PRAGMA user_version');
            await db.close();
            return rows;
          });
      expect(versionRows.first['user_version'], kDatabaseSchemaVersion);
    },
  );
}
