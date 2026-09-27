// Απαγόρευση μόνιμης αναβάθμισης σχήματος όσο άλλος σταθμός κρατά τη βάση.
//
//   flutter test test/core/database/schema_upgrade_station_guard_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/database_state_notice.dart';
import 'package:call_logger/core/database/schema_upgrade_station_guard.dart';
import 'package:call_logger/core/models/operator_presence.dart';
import 'package:call_logger/core/services/session_liveness_mark.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

SessionLivenessMark _mark(String station, {required Duration ago}) {
  final now = DateTime(2026, 9, 25, 10, 0);
  return SessionLivenessMark(
    station: station,
    version: '4.1',
    startedAt: now.subtract(const Duration(hours: 1)),
    lastSeen: now.subtract(ago),
  );
}

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

  final now = DateTime(2026, 9, 25, 10, 0);

  group('ποιοι σταθμοί μετρούν', () {
    test('φρέσκο ίχνος άλλου σταθμού μπλοκάρει', () {
      final holders = freshMarksFromOtherStations(
        marks: [_mark('POPINIO', ago: const Duration(seconds: 30))],
        now: now,
        myStation: 'PICINIO',
      );
      expect(holders, hasLength(1));
      expect(holders.single.station, 'POPINIO');
    });

    test('ο δικός μου σταθμός δεν μπλοκάρει τον εαυτό του', () {
      // Δύο αντίγραφα στον ίδιο υπολογιστή μοιράζονται ένα ίχνος: η
      // δοκιμαστική έκδοση δεν κλειδώνει την κανονική.
      final holders = freshMarksFromOtherStations(
        marks: [_mark('picinio', ago: const Duration(seconds: 10))],
        now: now,
        myStation: 'PICINIO',
      );
      expect(holders, isEmpty);
    });

    test('ίχνος που έπαψε να ανανεώνεται δεν μπλοκάρει', () {
      // Απότομο κλείσιμο: το φάντασμα σβήνει μόνο του, η πόρτα ξεκλειδώνει.
      final holders = freshMarksFromOtherStations(
        marks: [
          _mark('POPINIO', ago: OperatorPresence.onlineWindow),
          _mark('TEP-02', ago: const Duration(minutes: 30)),
        ],
        now: now,
        myStation: 'PICINIO',
      );
      expect(holders, isEmpty);
    });

    test('το μήνυμα λέει ποιον σταθμό να κλείσει ο χρήστης', () {
      final text = describeStationsHoldingDatabase([
        _mark('POPINIO', ago: const Duration(minutes: 4)),
      ], now: now);
      expect(text, contains('POPINIO'));
      expect(text, contains('έκδοση 4.1'));
    });
  });

  group('η αναβάθμιση της καθημερινής βάσης', () {
    late Directory tempDir;

    setUpAll(() {
      initSqfliteFfiForTests();
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DatabaseHelper.instance.closeConnection();
      DatabaseHelper.releaseTestDatabaseBinding();
      tempDir = await Directory.systemTemp.createTemp('schema_station_guard_');
    });

    tearDown(() async {
      DatabaseHelper.instance.otherStationsProbeForTest = null;
      await DatabaseHelper.instance.closeConnection();
      DatabaseHelper.releaseTestDatabaseBinding();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> configure(String dbPath) async {
      final settings = SettingsService();
      await settings.setDatabasePath(dbPath);
      await settings.catalogs.setDatabaseOpenTimeoutSeconds(2);
      await settings.catalogs.setDatabaseOpenMaxAttempts(1);
    }

    test('άλλος σταθμός μέσα → η καθημερινή βάση ΔΕΝ αναβαθμίζεται', () async {
      final dbPath = await _createOldSchemaDb(tempDir, 'daily.db');
      // Η δικλείδα της καθημερινής βάσης: ίδια διαδρομή με την τελευταία που
      // άνοιξε ο σταθμός. Μέχρι τώρα περνούσε σιωπηλά.
      await SettingsService().setLastOpenedDatabasePath(dbPath);
      DatabaseHelper.instance.otherStationsProbeForTest = () async => [
        _mark('POPINIO', ago: const Duration(seconds: 20)),
      ];
      await configure(dbPath);

      final before = await _bytes(dbPath);
      final runner = await runDatabaseInitChecks(closeConnectionFirst: true);
      final after = await _bytes(dbPath);

      expect(runner.result.isSuccess, isFalse);
      expect(
        runner.result.recoveryKind,
        DatabaseInitRecoveryKind.schemaUpgradeBlockedByOtherStations,
      );
      expect(after, orderedEquals(before), reason: 'το αρχείο μένει άθικτο');
      expect(runner.result.details, contains('POPINIO'));
    });

    test('η αποθηκευμένη συγκατάθεση ΔΕΝ παρακάμπτει το μπλόκο', () async {
      final dbPath = await _createOldSchemaDb(tempDir, 'consented.db');
      await SettingsService().setLastOpenedDatabasePath(
        p.join(tempDir.path, 'other.db'),
      );
      final profile = await profileDatabaseFile(dbPath);
      await SettingsService().setSchemaUpgradeConsentIdentity(
        databaseContentIdentity(
          dbPath: dbPath,
          latestCallDate: profile.latestCallDate,
          callCount: profile.callCount,
          fileModifiedMs: File(
            dbPath,
          ).lastModifiedSync().millisecondsSinceEpoch,
        ),
      );
      DatabaseHelper.instance.otherStationsProbeForTest = () async => [
        _mark('POPINIO', ago: const Duration(seconds: 20)),
      ];
      await configure(dbPath);

      final runner = await runDatabaseInitChecks(closeConnectionFirst: true);

      expect(runner.result.isSuccess, isFalse);
      expect(
        runner.result.recoveryKind,
        DatabaseInitRecoveryKind.schemaUpgradeBlockedByOtherStations,
      );
    });

    test('κανείς άλλος μέσα → η αναβάθμιση προχωρά όπως πριν', () async {
      final dbPath = await _createOldSchemaDb(tempDir, 'alone.db');
      await SettingsService().setLastOpenedDatabasePath(dbPath);
      DatabaseHelper.instance.otherStationsProbeForTest = () async => const [];
      await configure(dbPath);

      final runner = await runDatabaseInitChecks(closeConnectionFirst: true);

      expect(runner.result.isSuccess, isTrue);
      final rows =
          await openDatabase(
            dbPath,
            readOnly: true,
            singleInstance: false,
          ).then((db) async {
            final r = await db.rawQuery('PRAGMA user_version');
            await db.close();
            return r;
          });
      expect(rows.first['user_version'], kDatabaseSchemaVersion);
    });
  });
}
