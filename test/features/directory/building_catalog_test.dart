// Ο κατάλογος κτιρίων: μία κοινή λίστα ανά βάση, από την οποία διαλέγει το
// «Κτίριο» της φόρμας τμήματος και της μεταφοράς από τη Λάμπα. Η διαγραφή ενός
// κτιρίου αφήνει χωρίς κτίριο τα τμήματά του· η μετονομασία τα ενημερώνει.
//
//   flutter test test/features/directory/building_catalog_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/department_repository.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/services/catalog_list_change.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/features/directory/providers/building_catalog_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;
  late SettingsService settings;
  late DepartmentRepository departments;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('building_catalog_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/buildings.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    await db.delete('app_settings');
    await db.delete('departments');
    SettingsService.registerAppSettingsProvider(
      (key) => SettingsRepository(db).getSetting(key),
      (key, value) => SettingsRepository(db).saveSetting(key, value),
      (key, change) => SettingsRepository(db).updateSetting(key, change),
    );
    settings = SettingsService();
    departments = DepartmentRepository(db);
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  Future<int> addDepartment(String name, {String? building}) async {
    return db.insert('departments', {
      'name': name,
      'name_key': name.toLowerCase(),
      'building': building,
      'is_deleted': 0,
    });
  }

  group('Αποθήκευση του καταλόγου', () {
    test('χωρίς αποθηκευμένη λίστα, ο κατάλογος είναι κενός', () async {
      expect(await settings.catalogs.getBuildingCatalogRaw(), '');
      expect(await settings.catalogs.getBuildingCatalogList(), isEmpty);
    });

    test('διαβάζεται χωρίς κενά και διπλότυπα', () async {
      await SettingsRepository(db)
          .saveSetting('building_catalog', ' Καινούριο ,, Παλιό , καινουριο ');

      expect(
        await settings.catalogs.getBuildingCatalogList(),
        ['Καινούριο', 'Παλιό'],
        reason:
            'το «καινουριο» είναι το ίδιο στοιχείο, δεν μπαίνει δεύτερη φορά',
      );
    });

    test('η αλλαγή εφαρμόζεται πάνω σε ό,τι έγραψε στο μεταξύ άλλος', () async {
      await SettingsRepository(db)
          .saveSetting('building_catalog', 'Καινούριο, Παλιό, Πτέρυγα Γ');

      await settings.catalogs.changeBuildingCatalog(
        const CatalogListChange.add('Κτίριο Β'),
        whenUnset: const [],
      );

      expect(await settings.catalogs.getBuildingCatalogList(), [
        'Καινούριο',
        'Παλιό',
        'Πτέρυγα Γ',
        'Κτίριο Β',
      ]);
    });

    test('αλλαγή που δεν στέκει πια δεν γράφει τίποτα', () async {
      await SettingsRepository(db)
          .saveSetting('building_catalog', 'Καινούριο, Πτέρυγα Γ');

      await expectLater(
        () => settings.catalogs.changeBuildingCatalog(
          const CatalogListChange.remove('Παλιό'),
          whenUnset: const [],
        ),
        throwsA(isA<CatalogListChangedException>()),
      );

      expect(
        await settings.catalogs.getBuildingCatalogRaw(),
        'Καινούριο, Πτέρυγα Γ',
      );
    });

    test('χωρίς ορισμένο κατάλογο, η πρώτη αλλαγή κρατά τα κτίρια των '
        'τμημάτων', () async {
      await settings.catalogs.changeBuildingCatalog(
        const CatalogListChange.add('Κτίριο Β'),
        whenUnset: const ['Καινούριο', 'Παλιό'],
      );

      expect(await settings.catalogs.getBuildingCatalogList(), [
        'Καινούριο',
        'Παλιό',
        'Κτίριο Β',
      ]);
    });
  });

  group('Αλλαγή ενός στοιχείου πάνω στη φρέσκια λίστα', () {
    const fresh = ['Καινούριο', 'Β', 'Πτέρυγα Γ'];

    Matcher blockedBy(CatalogListChangeBlock block) => throwsA(
      isA<CatalogListChangedException>().having((e) => e.block, 'block', block),
    );

    test('μετονομασία αλλάζει μόνο το δικό της στοιχείο', () {
      expect(
        const CatalogListChange.rename(
          from: 'Β',
          to: 'Κτίριο Β',
        ).applyTo(fresh),
        ['Καινούριο', 'Κτίριο Β', 'Πτέρυγα Γ'],
      );
    });

    test('μετονομασία που διορθώνει μόνο τον τόνο του ίδιου περνά', () {
      expect(
        const CatalogListChange.rename(
          from: 'Καινούριο',
          to: 'Καινουριο',
        ).applyTo(fresh),
        ['Καινουριο', 'Β', 'Πτέρυγα Γ'],
      );
    });

    test('προσθήκη ονόματος που μπήκε στο μεταξύ σταματά', () {
      expect(
        () => const CatalogListChange.add('B').applyTo(fresh),
        blockedBy(CatalogListChangeBlock.nameTaken),
        reason: 'το λατινικό «B» είναι το ίδιο κτίριο με το ελληνικό «Β»',
      );
    });

    test('μετονομασία σε όνομα που μπήκε στο μεταξύ σταματά', () {
      expect(
        () => const CatalogListChange.rename(
          from: 'Β',
          to: 'πτερυγα γ',
        ).applyTo(fresh),
        blockedBy(CatalogListChangeBlock.nameTaken),
      );
    });

    test('μετονομασία ή διαγραφή στοιχείου που δεν υπάρχει πια σταματά', () {
      expect(
        () => const CatalogListChange.rename(
          from: 'Παλιό',
          to: 'Νέο',
        ).applyTo(fresh),
        blockedBy(CatalogListChangeBlock.targetGone),
      );
      expect(
        () => const CatalogListChange.remove('Παλιό').applyTo(fresh),
        blockedBy(CatalogListChangeBlock.targetGone),
      );
    });
  });

  group('Ταύτιση κτιρίου με τον κατάλογο', () {
    const catalog = ['Καινούριο', 'Β', 'Πτέρυγα Γ'];

    test('βρίσκει την ίδια τιμή ανεξάρτητα από πεζά και τόνους', () {
      expect(matchBuildingInCatalog('καινουριο', catalog), 'Καινούριο');
    });

    test('το λατινικό «B» είναι το ελληνικό «Β»', () {
      expect(
        matchBuildingInCatalog('B', catalog),
        'Β',
        reason: 'στη Λάμπα το ίδιο κτίριο γράφεται και στα δύο αλφάβητα',
      );
    });

    test('άγνωστο κτίριο δεν ταιριάζει με τίποτα', () {
      expect(matchBuildingInCatalog('ΚΕΦΙΑΠ', catalog), isNull);
      expect(matchBuildingInCatalog('  ', catalog), isNull);
    });
  });

  group('Χρήση των κτιρίων από τα τμήματα', () {
    test('μετρά ανά κτίριο και ξεχωριστά όσα δεν έχουν', () async {
      await addDepartment('Αιματολογικό', building: 'Καινούριο');
      await addDepartment('Αιμοδοσία', building: 'Καινούριο');
      await addDepartment('Βιοχημικό', building: 'Παλιό');
      await addDepartment('Ακτινολογικό');
      await addDepartment('Αξονικός', building: '   ');

      final usage = await departments.countDepartmentsPerBuilding();

      expect(usage.countFor('Καινούριο'), 2);
      expect(usage.countFor('Παλιό'), 1);
      expect(
        usage.withoutBuilding,
        2,
        reason: 'το κενό και το «μόνο κενά» μετράνε και τα δύο ως χωρίς κτίριο',
      );
    });

    test('τα διαγραμμένα τμήματα δεν μετράνε', () async {
      await addDepartment('Αιματολογικό', building: 'Καινούριο');
      final id = await addDepartment('Παλιό Τμήμα', building: 'Καινούριο');
      await db.update(
        'departments',
        {'is_deleted': 1},
        where: 'id = ?',
        whereArgs: [id],
      );

      final usage = await departments.countDepartmentsPerBuilding();
      expect(usage.countFor('Καινούριο'), 1);
    });
  });

  group('Διαγραφή κτιρίου', () {
    test('αφήνει χωρίς κτίριο τα τμήματά του και μόνο αυτά', () async {
      final a = await addDepartment('Αιματολογικό', building: 'Καινούριο');
      final b = await addDepartment('Βιοχημικό', building: 'Παλιό');

      final cleared = await departments.clearBuildingFromDepartments(
        'Καινούριο',
      );

      expect(cleared, 1);
      expect(await _buildingOf(db, a), isNull);
      expect(
        await _buildingOf(db, b),
        'Παλιό',
        reason: 'τα τμήματα άλλου κτιρίου δεν αγγίζονται',
      );
    });

    test(
      'κτίριο που δεν χρησιμοποιεί κανένα τμήμα δεν αλλάζει τίποτα',
      () async {
        await addDepartment('Αιματολογικό', building: 'Καινούριο');
        expect(await departments.clearBuildingFromDepartments('Πτέρυγα Γ'), 0);
      },
    );
  });

  group('Μετονομασία κτιρίου', () {
    test('ακολουθούν όλα τα τμήματα του κτιρίου', () async {
      final a = await addDepartment('Αιματολογικό', building: 'Καινουριο');
      final b = await addDepartment('Αιμοδοσία', building: 'Καινουριο');
      final c = await addDepartment('Βιοχημικό', building: 'Παλιό');

      final touched = await departments.renameBuildingInDepartments(
        from: 'Καινουριο',
        to: 'Καινούριο',
      );

      expect(touched, 2);
      expect(await _buildingOf(db, a), 'Καινούριο');
      expect(await _buildingOf(db, b), 'Καινούριο');
      expect(await _buildingOf(db, c), 'Παλιό');
    });

    test('ίδιο όνομα ή κενό δεν γράφει τίποτα', () async {
      final a = await addDepartment('Αιματολογικό', building: 'Καινούριο');

      expect(
        await departments.renameBuildingInDepartments(
          from: 'Καινούριο',
          to: 'Καινούριο',
        ),
        0,
      );
      expect(
        await departments.renameBuildingInDepartments(
          from: 'Καινούριο',
          to: '   ',
        ),
        0,
        reason: 'το άδειασμα γίνεται μόνο από τη διαγραφή, ρητά',
      );
      expect(await _buildingOf(db, a), 'Καινούριο');
    });
  });
}

Future<String?> _buildingOf(Database db, int id) async {
  final rows = await db.query(
    'departments',
    columns: ['building'],
    where: 'id = ?',
    whereArgs: [id],
  );
  return rows.single['building'] as String?;
}
