// Μετάπτωση v46: οι ρυθμίσεις της καταργημένης «Αυτόματης σύνδεσης Help Desk»
// σβήνονται από το app_settings — μαζί και ο κωδικός web console που έμενε
// εκεί σε απλό κείμενο. Οι υπόλοιπες ρυθμίσεις δεν αγγίζονται.
//
//   flutter test test/core/database/helpdesk_credentials_cleanup_migration_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('helpdesk_cleanup_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/cleanup.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await db.delete('app_settings');
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  test('η v46 σβήνει και τις 4 ρυθμίσεις της αυτόματης σύνδεσης', () async {
    final repo = SettingsRepository(db);
    await repo.saveSetting('lansweeper_helpdesk_auto_login', '1');
    await repo.saveSetting(
      'lansweeper_helpdesk_login_url',
      'http://test.example/login.aspx',
    );
    await repo.saveSetting('lansweeper_helpdesk_web_username', 'VAL_USER');
    await repo.saveSetting('lansweeper_helpdesk_web_password', 'VAL_SECRET');

    await migrateDatabaseToV46(db);

    expect(await repo.getSetting('lansweeper_helpdesk_auto_login'), isNull);
    expect(await repo.getSetting('lansweeper_helpdesk_login_url'), isNull);
    expect(await repo.getSetting('lansweeper_helpdesk_web_username'), isNull);
    expect(await repo.getSetting('lansweeper_helpdesk_web_password'), isNull);
  });

  test('η v46 ΔΕΝ αγγίζει τις υπόλοιπες ρυθμίσεις Lansweeper', () async {
    final repo = SettingsRepository(db);
    await repo.saveSetting(kLansweeperApiKeySettingKey, 'VAL_API_KEY');
    await repo.saveSetting(kLansweeperUrlSettingKey, 'http://test/NewTicket');
    await repo.saveSetting('lansweeper_helpdesk_web_password', 'VAL_SECRET');

    await migrateDatabaseToV46(db);

    expect(
      await repo.getSetting(kLansweeperApiKeySettingKey),
      'VAL_API_KEY',
    );
    expect(
      await repo.getSetting(kLansweeperUrlSettingKey),
      'http://test/NewTicket',
    );
    expect(await repo.getSetting('lansweeper_helpdesk_web_password'), isNull);
  });

  test('η v46 είναι αβλαβής όταν δεν υπάρχει τίποτα να σβήσει', () async {
    await migrateDatabaseToV46(db);
    await migrateDatabaseToV46(db);

    final rows = await db.query('app_settings');
    expect(rows, isEmpty);
  });
}
