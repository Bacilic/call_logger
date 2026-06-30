import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('Lamp owner transfer — atomicity (_saveOwner)', () {
    late LampMigrationService service;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lamp_owner_atomicity_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/lamp_owner_atomicity.db');
      await DatabaseHelper.instance.database;
      service = LampMigrationService();
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('phones');
      await db.delete('equipment');
      await db.delete('users');
      await db.delete('departments');
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Map<String, String> ownerForm({
      String firstName = 'Νέος',
      String lastName = 'Κάτοχος',
      String phones = '',
      String equipmentCodes = 'PC-ORPHAN-EQ',
      String departmentName = '',
    }) {
      return {
        'first_name': firstName,
        'last_name': lastName,
        'phones': phones,
        'equipment_codes': equipmentCodes,
        'department_name': departmentName,
        'location': '',
        'notes': '',
      };
    }

    test(
      'αποτυχία στη μέση (_syncOwnerEquipmentLinks) → καμία μερική εγγραφή χρήστη',
      () async {
        await expectLater(
          service.save(
            target: LampTransferTarget.owner,
            formValues: ownerForm(),
            selectedCandidateId: null,
            confirmEntityCreations: false,
          ),
          throwsA(isA<StateError>()),
        );

        final db = await DatabaseHelper.instance.database;
        expect(
          await db.query('users', where: 'first_name = ?', whereArgs: ['Νέος']),
          isEmpty,
        );
        expect(await db.query('user_phones'), isEmpty);
        expect(await db.query('user_equipment'), isEmpty);
      },
    );

    test(
      'επιτυχής αποθήκευση νέου κατόχου με εξοπλισμό παραμένει ατομική (smoke)',
      () async {
        final result = await service.save(
          target: LampTransferTarget.owner,
          formValues: ownerForm(equipmentCodes: 'PC-NEW-OWNER'),
          selectedCandidateId: null,
          confirmEntityCreations: true,
        );

        final db = await DatabaseHelper.instance.database;
        final equipment = await db.query(
          'equipment',
          where: 'code_equipment = ?',
          whereArgs: ['PC-NEW-OWNER'],
        );
        expect(equipment, hasLength(1));

        final links = await db.query(
          'user_equipment',
          where: 'user_id = ?',
          whereArgs: [result.id],
        );
        expect(links, hasLength(1));
        expect(links.single['equipment_id'], equipment.single['id']);
      },
    );
  });
}
