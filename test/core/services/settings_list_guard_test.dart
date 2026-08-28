// Ρυθμιζόμενες λίστες με κόμματα (τύποι εξοπλισμού, κατηγορίες λεξικού) ζουν σε
// ΕΝΑ κλειδί και γράφονται ολόκληρες. Ο χρήστης επεξεργάζεται ελεύθερο κείμενο,
// οπότε δεν υπάρχει σιωπηλή συγχώνευση που να ξέρει αν ένα στοιχείο που λείπει
// σβήστηκε επίτηδες — ο φρουρός σταματά και ρωτά (απόφαση Διευθυντή 25/08/2026).
//
//   flutter test test/core/services/settings_list_guard_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/services/settings_list_conflict.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Φρουρός ρυθμιζόμενης λίστας', () {
    late Database db;
    late SettingsService settings;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('settings_lists_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/lists.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('app_settings');
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

    test('το σβήσιμο δεν περνά πάνω από την προσθήκη του άλλου', () async {
      // Η οθόνη μου φόρτωσε αυτή τη λίστα.
      const asScreenSawIt = 'Υπολογιστής, Εκτυπωτής, Φαξ';
      await settings.catalogs.setEquipmentTypes(asScreenSawIt, expected: null);

      // Ο συνάδελφος προσθέτει «Σαρωτής» από το άλλο μηχάνημα.
      await settings.catalogs.setEquipmentTypes(
        'Υπολογιστής, Εκτυπωτής, Φαξ, Σαρωτής',
        expected: asScreenSawIt,
      );

      // Εγώ σβήνω το «Φαξ» πάνω στην παλιά μου εικόνα.
      await expectLater(
        () => settings.catalogs.setEquipmentTypes(
          'Υπολογιστής, Εκτυπωτής',
          expected: asScreenSawIt,
        ),
        throwsA(isA<SettingsListStaleException>()),
      );

      expect(
        await settings.catalogs.getEquipmentTypesRaw(),
        'Υπολογιστής, Εκτυπωτής, Φαξ, Σαρωτής',
        reason: 'η λίστα του συναδέλφου μένει άθικτη',
      );
    });

    test('η διένεξη λέει τι προστέθηκε και τι θα χαθεί', () async {
      const asScreenSawIt = 'Υπολογιστής, Εκτυπωτής, Φαξ';
      await settings.catalogs.setEquipmentTypes(asScreenSawIt, expected: null);
      await settings.catalogs.setEquipmentTypes(
        'Υπολογιστής, Εκτυπωτής, Φαξ, Σαρωτής',
        expected: asScreenSawIt,
      );

      try {
        await settings.catalogs.setEquipmentTypes(
          'Υπολογιστής, Εκτυπωτής',
          expected: asScreenSawIt,
        );
        fail('Έπρεπε να απορριφθεί η μπαγιάτικη εγγραφή');
      } on SettingsListStaleException catch (e) {
        expect(e.conflict.addedByOther, ['Σαρωτής']);
        expect(e.conflict.removedByOther, isEmpty);
        expect(e.conflict.changeLines, ['Προστέθηκε: Σαρωτής']);
        expect(e.conflict.lostIfIOverwrite, ['Σαρωτής']);
        expect(e.conflict.overwriteWarning, contains('Σαρωτής'));
      }
    });

    test('«κράτα τη δική μου» γράφει χωρίς αφετηρία', () async {
      const asScreenSawIt = 'Υπολογιστής, Εκτυπωτής, Φαξ';
      await settings.catalogs.setEquipmentTypes(asScreenSawIt, expected: null);
      await settings.catalogs.setEquipmentTypes(
        'Υπολογιστής, Εκτυπωτής, Φαξ, Σαρωτής',
        expected: asScreenSawIt,
      );

      await settings.catalogs.setEquipmentTypes(
        'Υπολογιστής, Εκτυπωτής',
        expected: null,
      );

      expect(
        await settings.catalogs.getEquipmentTypesRaw(),
        'Υπολογιστής, Εκτυπωτής',
      );
    });

    test('σε νέα βάση η πρώτη αποθήκευση δεν φαίνεται ξένη αλλαγή', () async {
      // Καμία αποθηκευμένη τιμή: η οθόνη δείχνει τις προεπιλογές, και αυτές
      // είναι η αφετηρία της. Χωρίς την κανονικοποίηση, η σύγκριση με το κενό
      // θα έβγαζε διένεξη σε κάθε νέα βάση.
      final shown = await settings.catalogs.getEquipmentTypesRaw();
      await settings.catalogs.setEquipmentTypes(
        '$shown, Σαρωτής',
        expected: shown,
      );

      expect(
        await settings.catalogs.getEquipmentTypesRaw(),
        'Υπολογιστής, Εκτυπωτής, Σαρωτής',
      );
    });

    test('οι κατηγορίες λεξικού φυλάγονται με τον ίδιο φρουρό', () async {
      final shown = await settings.catalogs.getLexiconCategoriesRaw();
      await settings.catalogs.setLexiconCategories(
        '$shown, Συντομογραφία',
        expected: shown,
      );

      await expectLater(
        () => settings.catalogs.setLexiconCategories('Γενική', expected: shown),
        throwsA(isA<SettingsListStaleException>()),
      );

      expect(
        await settings.catalogs.getLexiconCategoriesRaw(),
        contains('Συντομογραφία'),
      );
    });
  });

  group('SettingsListConflict — τι λέει στον άνθρωπο', () {
    test('προσθήκη και αφαίρεση μαζί', () {
      const conflict = SettingsListConflict(
        expected: 'Α, Β, Γ',
        fresh: 'Α, Γ, Δ',
        attempted: 'Α, Β, Γ, Ε',
      );

      expect(conflict.addedByOther, ['Δ']);
      expect(conflict.removedByOther, ['Β']);
      expect(conflict.lostIfIOverwrite, ['Δ']);
      expect(conflict.revivedIfIOverwrite, ['Β']);
      expect(
        conflict.overwriteWarning,
        'Αν κρατήσετε τη δική σας λίστα, θα χαθεί «Δ» και θα επανέλθει «Β».',
      );
    });

    test('ίδια στοιχεία με άλλη σειρά μετρούν ως αλλαγή', () {
      const conflict = SettingsListConflict(
        expected: 'Α, Β, Γ',
        fresh: 'Γ, Β, Α',
        attempted: 'Α, Β',
      );

      expect(conflict.hasChanges, isTrue);
      expect(conflict.changeLines, ['Άλλαξε η σειρά της λίστας']);
    });

    test('χωρίς όνομα δράστη η πρόταση στέκει', () {
      const conflict = SettingsListConflict(
        expected: 'Α',
        fresh: 'Α, Β',
        attempted: 'Α',
      );

      expect(
        conflict.headline(now: DateTime(2026, 8, 25, 13, 10)),
        'Κάποιος άλλος άλλαξε αυτή τη λίστα.',
      );
      expect(
        conflict.headline(
          changedBy: 'Βασίλης',
          changedAt: DateTime(2026, 8, 25, 13, 10),
          now: DateTime(2026, 8, 25, 14, 0),
        ),
        'Ο χρήστης «Βασίλης» άλλαξε αυτή τη λίστα στις 13:10.',
      );
    });
  });
}
