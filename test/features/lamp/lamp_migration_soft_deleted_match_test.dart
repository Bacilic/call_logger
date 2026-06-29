import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('LampMigrationService soft-deleted match', () {
    late LampMigrationService service;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lamp_soft_del_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/lamp_soft_del.db');
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

    Future<int> activeUserCount() async {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM users WHERE COALESCE(is_deleted, 0) = 0',
      );
      return rows.first['c'] as int;
    }

    Future<int> totalUserCount() async {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM users');
      return rows.first['c'] as int;
    }

    Future<int> activeEquipmentCount() async {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM equipment WHERE COALESCE(is_deleted, 0) = 0',
      );
      return rows.first['c'] as int;
    }

    Future<int> totalEquipmentCount() async {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM equipment');
      return rows.first['c'] as int;
    }

    Future<int> activeDepartmentCount() async {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM departments WHERE COALESCE(is_deleted, 0) = 0',
      );
      return rows.first['c'] as int;
    }

    Future<int> totalDepartmentCount() async {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM departments');
      return rows.first['c'] as int;
    }

    Map<String, String> ownerForm({
      String firstName = 'Γιώργος',
      String lastName = 'Παπαδόπουλος',
    }) {
      return {
        'first_name': firstName,
        'last_name': lastName,
        'phones': '',
        'equipment_codes': '',
        'department_name': '',
        'location': '',
        'notes': 'από Λάμπα',
      };
    }

    group('κάτοχος', () {
      test('χωρίς απόφαση → StateError, κανένας νέος χρήστης', () async {
        final db = await DatabaseHelper.instance.database;
        await db.insert('users', {
          'first_name': 'Γιώργος',
          'last_name': 'Παπαδόπουλος',
          'is_deleted': 1,
        });

        await expectLater(
          service.save(
            target: LampTransferTarget.owner,
            formValues: ownerForm(),
            selectedCandidateId: null,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message.toLowerCase(),
              'message',
              contains('διαγραμμένη όμοια'),
            ),
          ),
        );

        expect(await activeUserCount(), 0);
        expect(await totalUserCount(), 1);
      });

      test('απόφαση επαναφορά → ενεργοποίηση soft-deleted, χωρίς νέα γραμμή', () async {
        final db = await DatabaseHelper.instance.database;
        final deletedId = await db.insert('users', {
          'first_name': 'Γιώργος',
          'last_name': 'Παπαδόπουλος',
          'notes': 'παλιό',
          'is_deleted': 1,
        });

        final result = await service.save(
          target: LampTransferTarget.owner,
          formValues: ownerForm(),
          selectedCandidateId: null,
          softDeletedDecision: LampSoftDeletedDecision(
            action: LampSoftDeletedDecisionAction.reactivate,
            recordId: deletedId,
          ),
        );

        expect(result.id, deletedId);
        expect(result.updated, isTrue);
        expect(await totalUserCount(), 1);
        expect(await activeUserCount(), 1);

        final row = await db.query('users', where: 'id = ?', whereArgs: [deletedId]);
        expect(row.first['is_deleted'], 0);
        expect(row.first['notes'], 'από Λάμπα');
      });

      test('απόφαση δημιουργία νέας → νέος χρήστης, soft-deleted μένει διαγραμμένος', () async {
        final db = await DatabaseHelper.instance.database;
        final deletedId = await db.insert('users', {
          'first_name': 'Γιώργος',
          'last_name': 'Παπαδόπουλος',
          'is_deleted': 1,
        });

        final result = await service.save(
          target: LampTransferTarget.owner,
          formValues: ownerForm(),
          selectedCandidateId: null,
          softDeletedDecision: LampSoftDeletedDecision(
            action: LampSoftDeletedDecisionAction.createNew,
            recordId: deletedId,
          ),
        );

        expect(result.id, isNot(deletedId));
        expect(result.updated, isFalse);
        expect(await totalUserCount(), 2);
        expect(await activeUserCount(), 1);

        final deletedRow = await db.query(
          'users',
          where: 'id = ?',
          whereArgs: [deletedId],
        );
        expect(deletedRow.first['is_deleted'], 1);
      });

      test('ενεργός όμοιος → καμία προειδοποίηση soft-deleted', () async {
        final db = await DatabaseHelper.instance.database;
        await db.insert('users', {
          'first_name': 'Γιώργος',
          'last_name': 'Παπαδόπουλος',
          'is_deleted': 1,
        });
        await db.insert('users', {
          'first_name': 'Γιώργος',
          'last_name': 'Παπαδόπουλος',
          'is_deleted': 0,
        });

        final match = await service.detectSoftDeletedMatch(
          target: LampTransferTarget.owner,
          formValues: ownerForm(),
          selectedCandidateId: null,
        );

        expect(match, isNull);
      });

      test('detectSoftDeletedMatch δεν μεταλλάσσει τη βάση', () async {
        final db = await DatabaseHelper.instance.database;
        await db.insert('users', {
          'first_name': 'Γιώργος',
          'last_name': 'Παπαδόπουλος',
          'is_deleted': 1,
        });

        final beforeUsers = await totalUserCount();
        final beforeActive = await activeUserCount();

        final match = await service.detectSoftDeletedMatch(
          target: LampTransferTarget.owner,
          formValues: ownerForm(),
          selectedCandidateId: null,
        );

        expect(match, isNotNull);
        expect(await totalUserCount(), beforeUsers);
        expect(await activeUserCount(), beforeActive);
      });
    });

    group('εξοπλισμός', () {
      Map<String, String> equipmentForm() => const {
        'code_equipment': 'PC-SOFT-DEL',
        'owner_name': '',
        'type': 'Desktop',
        'department_name': '',
        'location': '',
        'notes': 'από Λάμπα',
      };

      test('χωρίς απόφαση → StateError, κανένας νέος εξοπλισμός', () async {
        final db = await DatabaseHelper.instance.database;
        await db.insert('equipment', {
          'code_equipment': 'PC-SOFT-DEL',
          'is_deleted': 1,
        });

        await expectLater(
          service.save(
            target: LampTransferTarget.equipment,
            formValues: equipmentForm(),
            selectedCandidateId: null,
          ),
          throwsA(isA<StateError>()),
        );

        expect(await activeEquipmentCount(), 0);
        expect(await totalEquipmentCount(), 1);
      });

      test('απόφαση επαναφορά → ενεργοποίηση soft-deleted', () async {
        final db = await DatabaseHelper.instance.database;
        final deletedId = await db.insert('equipment', {
          'code_equipment': 'PC-SOFT-DEL',
          'notes': 'παλιό',
          'is_deleted': 1,
        });

        final result = await service.save(
          target: LampTransferTarget.equipment,
          formValues: equipmentForm(),
          selectedCandidateId: null,
          softDeletedDecision: LampSoftDeletedDecision(
            action: LampSoftDeletedDecisionAction.reactivate,
            recordId: deletedId,
          ),
        );

        expect(result.id, deletedId);
        expect(await activeEquipmentCount(), 1);
        expect(await totalEquipmentCount(), 1);

        final row = await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [deletedId],
        );
        expect(row.first['is_deleted'], 0);
        expect(row.first['notes'], 'από Λάμπα');
      });

      test('απόφαση δημιουργία νέας → νέος κωδικός, soft-deleted μένει διαγραμμένος', () async {
        final db = await DatabaseHelper.instance.database;
        final deletedId = await db.insert('equipment', {
          'code_equipment': 'PC-SOFT-DEL',
          'is_deleted': 1,
        });

        final result = await service.save(
          target: LampTransferTarget.equipment,
          formValues: equipmentForm(),
          selectedCandidateId: null,
          softDeletedDecision: LampSoftDeletedDecision(
            action: LampSoftDeletedDecisionAction.createNew,
            recordId: deletedId,
          ),
        );

        expect(result.id, isNot(deletedId));
        expect(await totalEquipmentCount(), 2);
        expect(await activeEquipmentCount(), 1);
      });

      test('ενεργός όμοιος κωδικός → καμία προειδοποίηση soft-deleted', () async {
        final db = await DatabaseHelper.instance.database;
        await db.insert('equipment', {
          'code_equipment': 'PC-SOFT-DEL',
          'is_deleted': 1,
        });
        await db.insert('equipment', {
          'code_equipment': 'PC-SOFT-DEL',
          'is_deleted': 0,
        });

        final match = await service.detectSoftDeletedMatch(
          target: LampTransferTarget.equipment,
          formValues: equipmentForm(),
          selectedCandidateId: null,
        );

        expect(match, isNull);
      });
    });

    group('τμήμα', () {
      Map<String, String> departmentForm() => const {
        'name': 'Φαρμακείο',
        'building': 'Κτίριο Α',
        'level': '2',
        'notes': 'από Λάμπα',
      };

      test('χωρίς απόφαση → StateError, κανένα νέο τμήμα', () async {
        final db = await DatabaseHelper.instance.database;
        await db.insert('departments', {
          'name': 'Φαρμακείο',
          'name_key': 'φαρμακειο',
          'is_deleted': 1,
        });

        await expectLater(
          service.save(
            target: LampTransferTarget.department,
            formValues: departmentForm(),
            selectedCandidateId: null,
          ),
          throwsA(isA<StateError>()),
        );

        expect(await activeDepartmentCount(), 0);
        expect(await totalDepartmentCount(), 1);
      });

      test('απόφαση επαναφορά → ενεργοποίηση soft-deleted', () async {
        final db = await DatabaseHelper.instance.database;
        final deletedId = await db.insert('departments', {
          'name': 'Φαρμακείο',
          'name_key': 'φαρμακειο',
          'notes': 'παλιό',
          'is_deleted': 1,
        });

        final result = await service.save(
          target: LampTransferTarget.department,
          formValues: departmentForm(),
          selectedCandidateId: null,
          softDeletedDecision: LampSoftDeletedDecision(
            action: LampSoftDeletedDecisionAction.reactivate,
            recordId: deletedId,
          ),
        );

        expect(result.id, deletedId);
        expect(await activeDepartmentCount(), 1);
        expect(await totalDepartmentCount(), 1);

        final row = await db.query(
          'departments',
          where: 'id = ?',
          whereArgs: [deletedId],
        );
        expect(row.first['is_deleted'], 0);
        expect(row.first['notes'], 'από Λάμπα');
      });

      test('απόφαση δημιουργία νέας → νέο τμήμα, soft-deleted μένει διαγραμμένο', () async {
        final db = await DatabaseHelper.instance.database;
        final deletedId = await db.insert('departments', {
          'name': 'Φαρμακείο',
          'name_key': 'φαρμακειο',
          'is_deleted': 1,
        });

        final result = await service.save(
          target: LampTransferTarget.department,
          formValues: departmentForm(),
          selectedCandidateId: null,
          softDeletedDecision: LampSoftDeletedDecision(
            action: LampSoftDeletedDecisionAction.createNew,
            recordId: deletedId,
          ),
        );

        expect(result.id, isNot(deletedId));
        expect(await totalDepartmentCount(), 2);
        expect(await activeDepartmentCount(), 1);
      });

      test('ενεργό όμοιο τμήμα → καμία προειδοποίηση soft-deleted', () async {
        final db = await DatabaseHelper.instance.database;
        await db.insert('departments', {
          'name': 'Φαρμακείο',
          'name_key': 'φαρμακειο',
          'is_deleted': 0,
        });

        final match = await service.detectSoftDeletedMatch(
          target: LampTransferTarget.department,
          formValues: departmentForm(),
          selectedCandidateId: null,
        );

        expect(match, isNull);
      });
    });
  });
}
