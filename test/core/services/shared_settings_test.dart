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
import 'package:call_logger/features/directory/screens/widgets/department_color_palette.dart';
import 'package:call_logger/features/directory/screens/widgets/department_palette_store.dart';
import 'package:flutter/painting.dart';
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
      (key, change) => SettingsRepository(db).updateSetting(key, change),
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
      await SettingsRepository(db)
          .saveSetting('update_folder_path', r'\\koino\updates');
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
        const AuditRetentionConfig(
          purgeOnAppStart: true,
          volatileMaxAgeDays: 90,
        ),
      );

      // Άλλος χρήστης, ίδια βάση: βλέπει την ίδια πολιτική.
      CurrentOperator.activate(_operator(2));
      final loaded = await SettingsService().catalogs.getAuditRetentionConfig();

      expect(loaded.purgeOnAppStart, isTrue);
      expect(loaded.volatileMaxAgeDays, 90);
    });

    test('χωρίς ρύθμιση πουθενά, καμία εκκαθάριση', () async {
      final loaded = await SettingsService().catalogs.getAuditRetentionConfig();
      expect(
        loaded.purgeOnAppStart,
        isFalse,
        reason: 'Η ασφαλής προεπιλογή δεν σβήνει τίποτα.',
      );
    });

    // Η παλιά μορφή είχε δύο διακόπτες και απαιτούσε ΚΑΙ ΤΟΥΣ ΔΥΟ. Ο πρώτος
    // αφαιρέθηκε· ένα αποθηκευμένο «σβηστό» δεν επιτρέπεται να γίνει ξαφνικά
    // «αναμμένο» επειδή αναβαθμίστηκε η εφαρμογή.
    test('παλιά ρύθμιση με σβηστή «ενεργή πολιτική» δεν καθαρίζει μετά την αναβάθμιση', () {
      final stored = AuditRetentionConfig.fromJsonString(
        '{"enabled": false, "max_age_days": 90, "purge_on_app_start": true}',
      );

      expect(
        stored.purgeOnAppStart,
        isFalse,
        reason:
            'Ο χειριστής είχε αφήσει την πολιτική σβηστή — η αναβάθμιση δεν '
            'ενεργοποιεί διαγραφές που δεν ζήτησε κανείς.',
      );
      // Το παλιό ενιαίο όριο μεταφέρεται και στις δύο αναλώσιμες
      // κλάσεις: μια πολιτική που είχε οριστεί δεν χαλαρώνει σιωπηλά.
      expect(stored.volatileMaxAgeDays, 90, reason: 'Τα όρια δεν χάνονται.');
      expect(stored.operationalMaxAgeDays, 90);
    });

    // Ο Α έχει ανοιχτή τη Συντήρηση από το πρωί. Στο μεταξύ ο Β αλλάζει από
    // άλλον σταθμό ένα όριο. Ο Α αλλάζει κάτι άλλο και πατά «Αποθήκευση».
    test('η αποθήκευση γράφει μόνο ό,τι άλλαξε η οθόνη — η αλλαγή του '
        'συναδέλφου μένει', () async {
      CurrentOperator.activate(_operator(1, isAdmin: true));
      final catalogs = SettingsService().catalogs;
      await catalogs.setAuditRetentionConfig(
        const AuditRetentionConfig(volatileMaxAgeDays: 90),
      );
      final screenOfA = await catalogs.getAuditRetentionConfig();

      await catalogs.setAuditRetentionConfig(
        screenOfA.copyWith(volatileMaxAgeDays: 30),
      );

      final saved = await catalogs.saveAuditRetentionChanges(
        edited: screenOfA.copyWith(maxRows: 5000, exportBeforePurge: false),
        baseline: screenOfA,
      );

      final stored = await catalogs.getAuditRetentionConfig();
      expect(
        stored.volatileMaxAgeDays,
        30,
        reason: 'Ο Α δεν άγγιξε το όριο· το 30 του Β δεν γίνεται ξανά 90.',
      );
      expect(stored.maxRows, 5000);
      expect(stored.exportBeforePurge, isFalse);
      expect(
        saved.volatileMaxAgeDays,
        30,
        reason: 'Η οθόνη του Α δείχνει πια ό,τι ισχύει, μαζί με τον Β.',
      );
    });

    test('όριο που σβήνει ο χρήστης σβήνεται, ακόμη κι αν άλλαξε κάτι άλλο ο '
        'συνάδελφος', () async {
      CurrentOperator.activate(_operator(1, isAdmin: true));
      final catalogs = SettingsService().catalogs;
      await catalogs.setAuditRetentionConfig(
        const AuditRetentionConfig(volatileMaxAgeDays: 90, maxRows: 9000),
      );
      final screenOfA = await catalogs.getAuditRetentionConfig();
      await catalogs.setAuditRetentionConfig(
        screenOfA.copyWith(purgeOnAppStart: true),
      );

      await catalogs.saveAuditRetentionChanges(
        edited: screenOfA.copyWith(clearMaxRows: true),
        baseline: screenOfA,
      );

      final stored = await catalogs.getAuditRetentionConfig();
      expect(stored.maxRows, isNull);
      expect(stored.purgeOnAppStart, isTrue);
      expect(stored.volatileMaxAgeDays, 90);
    });

    test('παλιά ρύθμιση με αναμμένους και τους δύο διακόπτες καθαρίζει', () {
      final stored = AuditRetentionConfig.fromJsonString(
        '{"enabled": true, "max_age_days": 30, "purge_on_app_start": true}',
      );

      expect(stored.purgeOnAppStart, isTrue);
      expect(stored.volatileMaxAgeDays, 30);
      expect(stored.operationalMaxAgeDays, 30);
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

  group('Παλέτα τμημάτων — η αλλαγή του συναδέλφου δεν σβήνεται', () {
    const red = Color(0xFFFF0000);
    const green = Color(0xFF00AA00);
    final store = DepartmentPaletteStore.instance;

    Future<List<String>> storedSlots() async => SharedSettings.decodeList(
      await SharedSettings.read(SharedSettingKeys.departmentPaletteSlots),
    );

    setUp(() async {
      CurrentOperator.activate(_operator(1, isAdmin: true));
      await SharedSettings.write(
        SharedSettingKeys.departmentPaletteSlots,
        SharedSettings.encodeList(List.filled(8, '')),
      );
      // Η εφαρμογή του Α διάβασε την παλέτα το πρωί — άδεια.
      await store.reloadFromPreferences();
    });

    Future<void> colleagueFillsFirstSlot() => SharedSettings.write(
      SharedSettingKeys.departmentPaletteSlots,
      SharedSettings.encodeList([
        colorToDepartmentHex(red),
        ...List.filled(7, ''),
      ]),
    );

    test('αλλαγή σε άλλη θέση δεν ξαναγράφει άδεια τη θέση του Β', () async {
      await colleagueFillsFirstSlot();

      await store.setCustomSlot(2, green);

      final slots = await storedSlots();
      expect(
        slots[0],
        colorToDepartmentHex(red),
        reason:
            'Πριν από τη διόρθωση γράφονταν και οι οκτώ θέσεις από την '
            'εικόνα του πρωινού, και η 1η ξαναγινόταν άδεια.',
      );
      expect(slots[2], colorToDepartmentHex(green));
    });

    test('η «πρώτη κενή θέση» κρίνεται από τη φρέσκια παλέτα', () async {
      await colleagueFillsFirstSlot();

      await store.refresh();

      expect(store.firstEmptySlotIndex, 1);
      expect(store.customSlots[0], isNotNull);
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
