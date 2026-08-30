// Οι είκοσι δύο κανόνες επικύρωσης ζουν σε ΕΝΑ κλειδί. Δύο διαχειριστές με την
// οθόνη ανοιχτή αλλάζουν διαφορετικούς διακόπτες — και ο δεύτερος έγραφε
// ολόκληρο το JSON από την εικόνα που είχε φορτώσει, επαναφέροντας τον διακόπτη
// του πρώτου χωρίς να το μάθει κανείς.
//
//   flutter test test/features/directory/catalog_validation_rules_concurrent_write_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/features/directory/models/catalog_validation_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Κανόνες επικύρωσης — δύο διαχειριστές στο ίδιο κλειδί', () {
    late Database db;
    late SettingsService settings;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('catalog_rules_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/rules.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('app_settings');
      // Ο πάροχος όπως τον στήνει η εφαρμογή μετά το άνοιγμα της βάσης.
      SettingsService.registerAppSettingsProvider(
        (key) => SettingsRepository(db).getSetting(key),
        (key, value) => SettingsRepository(db).saveSetting(key, value),
        (key, change) => SettingsRepository(db).updateSetting(key, change),
      );
      settings = SettingsService();
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<CatalogValidationRules> stored() async =>
        CatalogValidationRules.fromRawJson(
          await settings.catalogs.getCatalogValidationRulesRaw(),
        );

    /// Μία αλλαγή διακόπτη, όπως τη στέλνει η οθόνη.
    Future<void> toggle(
      CatalogValidationRules Function(CatalogValidationRules current) change,
    ) async {
      await settings.catalogs.updateCatalogValidationRulesRaw(
        (raw) => change(CatalogValidationRules.fromRawJson(raw)).toRawJson(),
      );
    }

    test('οι αλλαγές δύο διαχειριστών επιβιώνουν και οι δύο', () async {
      // Ο πρώτος σβήνει τον έλεγχο διπλότυπων ονομάτων.
      await toggle((r) => r.copyWith(duplicateNamesEnabled: false));

      // Ο δεύτερος, με την οθόνη ανοιχτή από πριν, αλλάζει τα ψηφία των
      // εσωτερικών τηλεφώνων. Η εικόνα του ΔΕΝ έχει την αλλαγή του πρώτου.
      await toggle((r) => r.copyWith(internalPhoneDigits: 5));

      final result = await stored();
      expect(result.internalPhoneDigits, 5, reason: 'η δική μου αλλαγή');
      expect(
        result.duplicateNamesEnabled,
        isFalse,
        reason: 'ο διακόπτης του συναδέλφου δεν επιτρέπεται να επανέλθει',
      );
    });

    test('η ρητή αλλαγή στο ΙΔΙΟ πεδίο κερδίζει', () async {
      await toggle((r) => r.copyWith(equipmentLatinCodeEnabled: false));
      await toggle((r) => r.copyWith(equipmentLatinCodeEnabled: true));

      expect((await stored()).equipmentLatinCodeEnabled, isTrue);
    });

    test(
      'χωρίς αποθηκευμένη τιμή γράφονται οι προεπιλογές με την αλλαγή',
      () async {
        await toggle((r) => r.copyWith(emptyDepartmentEnabled: false));

        final result = await stored();
        expect(result.emptyDepartmentEnabled, isFalse);
        expect(
          result.internalPhoneDigits,
          const CatalogValidationRules().internalPhoneDigits,
          reason: 'ό,τι δεν άγγιξα μένει στην προεπιλογή του',
        );
      },
    );

    test(
      'πέντε διαδοχικές αλλαγές συσσωρεύονται, δεν αλληλοσβήνονται',
      () async {
        await toggle((r) => r.copyWith(swappedNamesEnabled: false));
        await toggle((r) => r.copyWith(crossDepartmentPhoneEnabled: false));
        await toggle((r) => r.copyWith(phoneEquipmentCodeEnabled: false));
        await toggle((r) => r.copyWith(equipmentMinDigits: 2));
        await toggle((r) => r.copyWith(personNameAllowedSymbols: '(, -'));

        final result = await stored();
        expect(result.swappedNamesEnabled, isFalse);
        expect(result.crossDepartmentPhoneEnabled, isFalse);
        expect(result.phoneEquipmentCodeEnabled, isFalse);
        expect(result.equipmentMinDigits, 2);
        expect(result.personNameAllowedSymbols, '(, -');
      },
    );
  });
}
