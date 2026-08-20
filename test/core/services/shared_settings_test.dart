// Φάση 2 — Πακέτο Δ: τρεις ρυθμίσεις γίνονται ΚΟΙΝΕΣ, και τα νεκρά κλειδιά
// φεύγουν από τη βάση.
//
// Το ανέβασμα της τοπικής τιμής στα κοινά γίνεται ΜΙΑ φορά και μόνο από τον
// διαχειριστή (ή όταν δεν υπάρχει συνδεδεμένος χρήστης) — αλλιώς ένας απλός
// χρήστης θα άλλαζε σιωπηλά τη ρύθμιση όλων.
//
//   flutter test test/core/services/shared_settings_test.dart

import 'package:call_logger/core/config/audit_retention_config.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/core/services/shared_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../test_setup.dart';

Operator _operator(int id, {bool isAdmin = false}) => Operator(
  id: id,
  displayName: 'Χρήστης $id',
  isAdmin: isAdmin,
  createdAt: DateTime(2026, 8, 20),
);

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CurrentOperator.reset();
    db = await DatabaseHelper.instance.database;
    await db.delete('app_settings');
    SettingsService.registerAppSettingsProvider(
      (key) => SettingsRepository(db).getSetting(key),
      (key, value) => SettingsRepository(db).saveSetting(key, value),
    );
  });

  tearDown(CurrentOperator.reset);

  group('Ανέβασμα της τοπικής τιμής στα κοινά', () {
    test('ο διαχειριστής την ανεβάζει — μία φορά', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'update_folder_path': r'\\server\updates',
      });
      CurrentOperator.activate(_operator(1, isAdmin: true));

      expect(
        await SharedSettings.read(SharedSettingKeys.updateFolderPath),
        r'\\server\updates',
      );
      expect(
        await SettingsRepository(db).getSetting('update_folder_path'),
        r'\\server\updates',
        reason: 'Η τιμή ανέβηκε στα κοινά — από εκεί τη βλέπουν όλοι.',
      );
    });

    test('χωρίς συνδεδεμένο χρήστη ανεβαίνει επίσης', () async {
      // Μονοχρηστική εγκατάσταση: δεν επιτρέπεται να χάσει τη ρύθμισή της.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'update_folder_path': r'D:\updates',
      });
      CurrentOperator.reset();

      expect(
        await SharedSettings.read(SharedSettingKeys.updateFolderPath),
        r'D:\updates',
      );
    });

    test('ο απλός χρήστης ΔΕΝ ανεβάζει τη δική του', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'update_folder_path': r'C:\dikos_mou',
      });
      CurrentOperator.activate(_operator(2));

      expect(
        await SharedSettings.read(SharedSettingKeys.updateFolderPath),
        isNull,
        reason:
            'Θα άλλαζε σιωπηλά τη ρύθμιση όλων — τον φάκελο τον ορίζει ο '
            'διαχειριστής.',
      );
      expect(
        await SettingsRepository(db).getSetting('update_folder_path'),
        isNull,
      );
    });

    test('υπάρχουσα κοινή τιμή δεν αντικαθίσταται από τοπική', () async {
      await SettingsRepository(
        db,
      ).saveSetting('update_folder_path', r'\\koino\updates');
      SharedPreferences.setMockInitialValues(<String, Object>{
        'update_folder_path': r'C:\palio',
      });
      CurrentOperator.activate(_operator(1, isAdmin: true));

      expect(
        await SharedSettings.read(SharedSettingKeys.updateFolderPath),
        r'\\koino\updates',
      );
    });
  });

  group('Πολιτική εκκαθάρισης Ιστορικού — κοινή', () {
    test('η αποθήκευση γράφει στα κοινά και τη βλέπουν όλοι', () async {
      CurrentOperator.activate(_operator(1, isAdmin: true));
      await SettingsService().catalogs.setAuditRetentionConfig(
        const AuditRetentionConfig(enabled: true, maxAgeDays: 90),
      );

      // Άλλος χρήστης, ίδια βάση: βλέπει την ίδια πολιτική.
      CurrentOperator.activate(_operator(2));
      final loaded = await SettingsService().catalogs.getAuditRetentionConfig();

      expect(loaded.enabled, isTrue);
      expect(loaded.maxAgeDays, 90);
    });

    test('χωρίς ρύθμιση πουθενά, καμία εκκαθάριση', () async {
      final loaded = await SettingsService().catalogs.getAuditRetentionConfig();
      expect(
        loaded.enabled,
        isFalse,
        reason: 'Η ασφαλής προεπιλογή δεν σβήνει τίποτα.',
      );
    });
  });

  group('Παλέτα τμημάτων — κοινή', () {
    test('η λίστα κάνει σωστό γύρο μέσα από τα κοινά', () async {
      const slots = ['#FF0000', '', '#00FF00'];
      CurrentOperator.activate(_operator(1, isAdmin: true));
      await SharedSettings.write(
        SharedSettingKeys.departmentPaletteSlots,
        SharedSettings.encodeList(slots),
      );

      final raw = await SharedSettings.read(
        SharedSettingKeys.departmentPaletteSlots,
      );
      expect(SharedSettings.decodeList(raw), slots);
    });
  });

  group('Ο κατάλογος κοινών κλειδιών', () {
    test('δεν έχει διπλά κλειδιά', () {
      final keys = SharedSettingKeys.all.map((k) => k.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
    });
  });

  group('v49 — καθαρισμός νεκρών κλειδιών', () {
    test('σβήνει τα νεκρά, αφήνει τα ζωντανά', () async {
      final repo = SettingsRepository(db);
      for (final dead in kDeadAppSettingKeysV49) {
        await repo.saveSetting(dead, 'παλιά τιμή');
      }
      await repo.saveSetting('lansweeper_api_url', 'http://zwntano/api.aspx');

      await migrateDatabaseToV49(db);

      for (final dead in kDeadAppSettingKeysV49) {
        expect(await repo.getSetting(dead), isNull, reason: dead);
      }
      expect(
        await repo.getSetting('lansweeper_api_url'),
        'http://zwntano/api.aspx',
        reason: 'Τα ζωντανά κλειδιά δεν αγγίζονται.',
      );
    });

    test('είναι ακίνδυνη όταν τα κλειδιά δεν υπάρχουν (idempotent)', () async {
      await migrateDatabaseToV49(db);
      await migrateDatabaseToV49(db);
    });

    test('ο κωδικός σε απλό κείμενο είναι πρώτος στη λίστα', () {
      expect(kDeadAppSettingKeysV49.first, 'vnc_password');
    });

    test('η στήλη test_target_ip ΔΕΝ πειράζεται', () async {
      // Το κλειδί ρυθμίσεων είναι νεκρό· η ομώνυμη στήλη του `remote_tools`
      // είναι ζωντανή λειτουργία (πεδίο δοκιμής IP ανά εργαλείο).
      await migrateDatabaseToV49(db);
      final info = await db.rawQuery('PRAGMA table_info(remote_tools)');
      final columns = info.map((r) => r['name'] as String).toSet();
      expect(columns, contains('test_target_ip'));
    });
  });
}
