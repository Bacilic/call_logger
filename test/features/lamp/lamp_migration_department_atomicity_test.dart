import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('Lamp department transfer — atomicity (_saveDepartment)', () {
    late LampMigrationService service;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lamp_dept_atomicity_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/lamp_dept_atomicity.db');
      await DatabaseHelper.instance.database;
      service = LampMigrationService();
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      await db.delete('department_phones');
      await db.delete('user_phones');
      await db.delete('phones');
      await db.delete('departments');
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<void> reloadLookup() async {
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    }

    Future<int> insertDepartmentWithPhone({
      required String name,
      required String phone,
    }) async {
      final db = await DatabaseHelper.instance.database;
      final dir = DirectoryRepository(db);
      final id = await db.insert('departments', {
        'name': name,
        'name_key': SearchTextNormalizer.normalizeForSearch(name),
        'is_deleted': 0,
      });
      await dir.addDepartmentDirectPhone(id, phone);
      await reloadLookup();
      return id;
    }

    test(
      'αποτυχία στη μέση (_applyDepartmentDirectPhones) → καμία μερική εγγραφή τμήματος',
      () async {
        const existingDept = 'Υπάρχον Τμήμα';
        const newDept = 'Νέο Τμήμα Μεταφοράς';
        const sharedPhone = '2310501000';

        await insertDepartmentWithPhone(
          name: existingDept,
          phone: sharedPhone,
        );

        await expectLater(
          service.save(
            target: LampTransferTarget.department,
            formValues: {
              'name': newDept,
              'building': '',
              'level': '',
              'notes': '',
              'phones': sharedPhone,
            },
            selectedCandidateId: null,
          ),
          throwsA(isA<StateError>()),
        );

        final db = await DatabaseHelper.instance.database;
        final newDeptRows = await db.query(
          'departments',
          where: 'name = ?',
          whereArgs: [newDept],
        );
        expect(newDeptRows, isEmpty);

        final phoneRows = await db.query(
          'phones',
          where: 'number = ?',
          whereArgs: [sharedPhone],
        );
        expect(phoneRows, hasLength(1));
        expect(phoneRows.single['department_id'], isNotNull);
      },
    );

    test(
      'επιτυχής αποθήκευση νέου τμήματος με τηλέφωνα παραμένει ατομική (smoke)',
      () async {
        final result = await service.save(
          target: LampTransferTarget.department,
          formValues: {
            'name': 'Φαρμακείο Ατομικό',
            'building': '',
            'level': '',
            'notes': '',
            'phones': '2310502000, 2310502001',
          },
          selectedCandidateId: null,
        );

        final db = await DatabaseHelper.instance.database;
        final dir = DirectoryRepository(db);
        final phonesMap = await dir.getDepartmentDirectPhonesMap();
        final saved = phonesMap[result.id] ?? const <String>[];
        expect(saved, containsAll(['2310502000', '2310502001']));
        expect(saved.length, 2);
      },
    );
  });
}
