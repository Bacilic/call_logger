// Ο «Έλεγχος σύνδεσης» είναι read-only probe: δεν επιτρέπεται να αποτυγχάνει
// (ούτε να επιχειρεί μετανάστευση σχήματος) σε βάση με διαφορετικό
// user_version — μια απολύτως προσβάσιμη βάση παλιότερης έκδοσης πρέπει να
// αναφέρεται ως επιτυχής σύνδεση.
//
//   flutter test test/core/database/database_helper_check_connection_readonly_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    initSqfliteFfiForTests();
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();

    tempDir = await Directory.systemTemp.createTemp('check_conn_ro_test_');
    dbPath = '${tempDir.path}/older_version.db';

    // Έγκυρη βάση SQLite με ΠΑΛΑΙΟΤΕΡΟ user_version από το τρέχον σχήμα.
    final db = await databaseFactory.openDatabase(dbPath);
    await db.execute('CREATE TABLE probe_marker (i INTEGER)');
    await db.execute('PRAGMA user_version = ${kDatabaseSchemaVersion - 1}');
    await db.close();

    await SettingsService().setDatabasePath(dbPath);
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'checkConnection πετυχαίνει σε βάση παλαιότερης έκδοσης σχήματος',
    () async {
      final result = await DatabaseHelper.instance.checkConnection();

      expect(
        result.success,
        isTrue,
        reason:
            'Το read-only probe απέτυχε σε προσβάσιμη βάση με παλαιότερο '
            'user_version — ψευδές «αποτυχία σύνδεσης» (το probe δεν έχει '
            'δουλειά να μεταναστεύει σχήμα).',
      );
    },
  );

  test('checkConnection δεν πειράζει το user_version του αρχείου', () async {
    await DatabaseHelper.instance.checkConnection();

    final db = await databaseFactory.openDatabase(dbPath);
    final rows = await db.rawQuery('PRAGMA user_version');
    await db.close();
    expect(rows.first.values.first, kDatabaseSchemaVersion - 1);
  });
}
