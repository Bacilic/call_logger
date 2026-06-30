import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Κλείδωμα αμφίδρομης συμβατότητας app_settings (Φάση Γ.4 / Tier 2).
void main() {
  group('SettingsRepository ↔ DirectoryRepository app_settings compat', () {
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'settings_repository_compat_test_',
      );
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/settings_compat.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('app_settings');
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test('DirectoryRepository.setSetting → SettingsRepository.getSetting', () async {
      await DirectoryRepository(db).setSetting('k', 'v');
      expect(await SettingsRepository(db).getSetting('k'), 'v');
    });

    test('SettingsRepository.saveSetting → DirectoryRepository.getSetting', () async {
      await SettingsRepository(db).saveSetting('k2', 'v2');
      expect(await DirectoryRepository(db).getSetting('k2'), 'v2');
    });

    test('getSetting ανύπαρκτου κλειδιού → null', () async {
      expect(await SettingsRepository(db).getSetting('missing_key'), isNull);
      expect(await DirectoryRepository(db).getSetting('missing_key'), isNull);
    });
  });
}
