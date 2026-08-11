// Φρουρός έκδοσης για βάση ΝΕΟΤΕΡΗ από την εφαρμογή.
//
// Το σφάλμα της οθόνης: βάση σε έκδοση 42, εφαρμογή σε 40 → ο χρήστης έβλεπε
// «Προέκυψε σφάλμα (DatabaseInitException)» με άσχετα διαγνωστικά πρόσβασης,
// αντί για το σαφές μήνυμα που υπήρχε ήδη γραμμένο. Ο φρουρός πρέπει να
// σταματά ΠΡΙΝ το άνοιγμα, με το αρχείο ανέγγιχτο, με σαφές μήνυμα και με
// αξιολόγηση του αν προσφέρεται υποβάθμιση.
//
//   flutter test test/core/database/database_newer_schema_guard_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

Future<Uint8List> _bytes(String path) => File(path).readAsBytes();

/// Βάση με το τρέχον σχήμα και user_version «από το μέλλον».
Future<String> _createNewerSchemaDb(
  Directory dir,
  String name, {
  required int fileVersion,
  Future<void> Function(Database db)? mutate,
}) async {
  final dbPath = p.join(dir.path, name);
  await DatabaseHelper.instance.createNewDatabaseFile(dbPath);
  final db = await openDatabase(dbPath, singleInstance: false);
  if (mutate != null) {
    await mutate(db);
  }
  await db.rawQuery('PRAGMA user_version = $fileVersion');
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
    tempDir = await Directory.systemTemp.createTemp('newer_schema_');
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<DatabaseInitRunnerResult> runChecksFor(String dbPath) async {
    final settings = SettingsService();
    await settings.setDatabasePath(dbPath);
    await settings.catalogs.setDatabaseOpenTimeoutSeconds(2);
    await settings.catalogs.setDatabaseOpenMaxAttempts(1);
    return runDatabaseInitChecks(closeConnectionFirst: true);
  }

  test(
    'νεότερη βάση → σαφές μήνυμα με τις δύο εκδόσεις, όχι γενικό σφάλμα',
    () async {
      final fileVersion = kDatabaseSchemaVersion + 3;
      final dbPath = await _createNewerSchemaDb(
        tempDir,
        'newer.db',
        fileVersion: fileVersion,
      );
      // Ακόμη και η «καθημερινή» διαδρομή σταματά: η σιωπηλή παράκαμψη
      // ισχύει ΜΟΝΟ για αναβάθμιση, ποτέ για νεότερο αρχείο.
      await SettingsService().setLastOpenedDatabasePath(dbPath);

      final before = await _bytes(dbPath);
      final runner = await runChecksFor(dbPath);
      final after = await _bytes(dbPath);

      expect(runner.result.isSuccess, isFalse);
      expect(
        runner.result.recoveryKind,
        DatabaseInitRecoveryKind.databaseNewerThanApp,
      );
      final message = runner.result.message ?? '';
      expect(message, contains('$fileVersion'));
      expect(message, contains('$kDatabaseSchemaVersion'));
      expect(message, contains('νεότερης έκδοσης'));
      expect(message, contains('παλαιότερο αντίγραφο της εφαρμογής'));
      expect(message, contains('Αντίγραφα της εφαρμογής'));
      // Το ακατανόητο μήνυμα της οθόνης δεν πρέπει να ξαναϋπάρξει.
      expect(message, isNot(contains('Προέκυψε σφάλμα')));
      // Ούτε άσχετα διαγνωστικά κλειδώματος για πρόβλημα έκδοσης.
      expect(runner.result.details ?? '', isNot(contains('Lock diagnostics')));
      // Το αρχείο δεν αγγίχτηκε.
      expect(after, orderedEquals(before));
    },
  );

  test('ίδιο σχήμα με νεότερο αριθμό → η υποβάθμιση προσφέρεται', () async {
    final dbPath = await _createNewerSchemaDb(
      tempDir,
      'same_schema.db',
      fileVersion: kDatabaseSchemaVersion + 1,
    );

    final runner = await runChecksFor(dbPath);

    final assessment = runner.result.schemaDowngrade;
    expect(assessment, isNotNull);
    expect(assessment!.isBridgeable, isTrue);
    expect(assessment.fileVersion, kDatabaseSchemaVersion + 1);
    expect(assessment.appVersion, kDatabaseSchemaVersion);
  });

  test('νεότερη βάση με επιπλέον προαιρετική στήλη → γεφυρώσιμη', () async {
    // Το σενάριο 42→40: η «μελλοντική» μετάπτωση πρόσθεσε μόνο στήλη.
    final dbPath = await _createNewerSchemaDb(
      tempDir,
      'extra_column.db',
      fileVersion: kDatabaseSchemaVersion + 2,
      mutate: (db) => db.execute(
        'ALTER TABLE calls ADD COLUMN future_note TEXT',
      ),
    );

    final runner = await runChecksFor(dbPath);

    final assessment = runner.result.schemaDowngrade;
    expect(assessment, isNotNull);
    expect(
      assessment!.isBridgeable,
      isTrue,
      reason: 'Οι επιπλέον προαιρετικές στήλες αγνοούνται ακίνδυνα',
    );
  });

  test(
    'νεότερη βάση χωρίς στήλη που χρειάζεται η εφαρμογή → μη γεφυρώσιμη, '
    'με ονομαστικό λόγο',
    () async {
      // Το σενάριο 45→40 (η v43 κατάργησε στήλη): η «μελλοντική» μετάπτωση
      // μετονόμασε στήλη που αυτή η έκδοση χρησιμοποιεί.
      final dbPath = await _createNewerSchemaDb(
        tempDir,
        'renamed_column.db',
        fileVersion: kDatabaseSchemaVersion + 2,
        mutate: (db) => db.execute(
          'ALTER TABLE tasks RENAME COLUMN completed_at TO completed_at_v2',
        ),
      );

      final runner = await runChecksFor(dbPath);

      expect(
        runner.result.recoveryKind,
        DatabaseInitRecoveryKind.databaseNewerThanApp,
      );
      final assessment = runner.result.schemaDowngrade;
      expect(assessment, isNotNull);
      expect(assessment!.isBridgeable, isFalse);
      expect(assessment.blockersSummary, contains('completed_at'));
      expect(assessment.blockersSummary, contains('tasks'));
    },
  );

  group('DatabaseInitResult.fromException', () {
    test('έτοιμο DatabaseInitException περνά αυτούσιο, δεν ξαναμεταφράζεται',
        () {
      const ready = DatabaseInitResult(
        status: DatabaseStatus.applicationError,
        message: 'Σαφές μήνυμα προς τον χρήστη.',
        recoveryKind: DatabaseInitRecoveryKind.databaseNewerThanApp,
        technicalCode: '45→40',
      );

      final result = DatabaseInitResult.fromException(
        const DatabaseInitException(ready),
        r'C:\tmp\hosp.db',
      );

      expect(result.message, 'Σαφές μήνυμα προς τον χρήστη.');
      expect(
        result.recoveryKind,
        DatabaseInitRecoveryKind.databaseNewerThanApp,
      );
      expect(result.technicalCode, '45→40');
      // Η διαδρομή συμπληρώνεται από το hint όταν λείπει.
      expect(result.path, r'C:\tmp\hosp.db');
    });
  });
}
