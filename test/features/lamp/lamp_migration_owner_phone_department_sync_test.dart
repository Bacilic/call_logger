import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('Lamp owner transfer — phone department sync', () {
    late LampMigrationService service;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lamp_owner_dept_sync_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/lamp_owner_dept_sync.db');
      await DatabaseHelper.instance.database;
      service = LampMigrationService();
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      await db.delete('user_equipment');
      await db.delete('department_phones');
      await db.delete('user_phones');
      await db.delete('phones');
      await db.delete('equipment');
      await db.delete('users');
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

    Future<int> insertDepartment(String name) async {
      final db = await DatabaseHelper.instance.database;
      final id = await db.insert('departments', {
        'name': name,
        'name_key': SearchTextNormalizer.normalizeForSearch(name),
        'is_deleted': 0,
      });
      await reloadLookup();
      return id;
    }

    Future<int> insertUserWithPhone({
      required String firstName,
      required String lastName,
      required int departmentId,
      required String phone,
    }) async {
      final db = await DatabaseHelper.instance.database;
      final dir = DirectoryRepository(db);
      final userId = await dir.insertUser(
        firstName: firstName,
        lastName: lastName,
        phones: [phone],
        departmentId: departmentId,
      );
      await reloadLookup();
      return userId;
    }

    Future<int?> phoneDepartmentId(String phone) async {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'phones',
        columns: ['department_id'],
        where: 'number = ?',
        whereArgs: [phone],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['department_id'] as int?;
    }

    Future<void> insertPhoneForDepartment({
      required int departmentId,
      required String phone,
    }) async {
      final db = await DatabaseHelper.instance.database;
      final dir = DirectoryRepository(db);
      await dir.addDepartmentDirectPhone(departmentId, phone);
      await reloadLookup();
    }

    Map<String, String> ownerForm({
      required String phones,
      required String departmentName,
      String firstName = 'Νέος',
      String lastName = 'Υπάλληλος',
    }) {
      return {
        'first_name': firstName,
        'last_name': lastName,
        'phones': phones,
        'equipment_codes': '',
        'department_name': departmentName,
        'location': '',
        'notes': '',
      };
    }

    test(
      'νέος χρήστης με τηλέφωνο σε τμήμα D → εμφανίζεται στο getDepartmentDirectPhonesMap',
      () async {
        const phone = '2370123456';
        const deptName = 'Τμήμα D';
        final deptId = await insertDepartment(deptName);

        final result = await service.save(
          target: LampTransferTarget.owner,
          formValues: ownerForm(phones: phone, departmentName: deptName),
          selectedCandidateId: null,
        );
        expect(result.id, isNotNull);

        final db = await DatabaseHelper.instance.database;
        final dir = DirectoryRepository(db);
        final phonesMap = await dir.getDepartmentDirectPhonesMap();
        expect(phonesMap[deptId], contains(phone));
        expect(await phoneDepartmentId(phone), deptId);
      },
    );

    test(
      'τηλέφωνο άλλου τμήματος → απαιτείται απόφαση, όχι σιωπηλή μετακίνηση',
      () async {
        const phone = '2370999888';
        final deptSource = await insertDepartment('Τμήμα Πηγής');
        final deptTarget = await insertDepartment('Τμήμα Προορισμού');
        await insertPhoneForDepartment(departmentId: deptSource, phone: phone);
        await reloadLookup();

        await expectLater(
          service.save(
            target: LampTransferTarget.owner,
            formValues: ownerForm(phones: phone, departmentName: 'Τμήμα Προορισμού'),
            selectedCandidateId: null,
          ),
          throwsA(isA<StateError>()),
        );

        final db = await DatabaseHelper.instance.database;
        final dir = DirectoryRepository(db);
        var phonesMap = await dir.getDepartmentDirectPhonesMap();
        expect(phonesMap[deptSource], contains(phone));
        expect(phonesMap[deptTarget], isNull);

        await service.save(
          target: LampTransferTarget.owner,
          formValues: ownerForm(phones: phone, departmentName: 'Τμήμα Προορισμού'),
          selectedCandidateId: null,
          ownerConflictDecisions: [
            LampOwnerConflictDecision(
              conflictId: 'phone:${SearchTextNormalizer.normalizeForSearch(phone)}',
              action: LampOwnerConflictAction.transferToSelectedOwner,
            ),
          ],
        );

        phonesMap = await dir.getDepartmentDirectPhonesMap();
        expect(phonesMap[deptTarget], contains(phone));
        expect(phonesMap[deptSource] ?? const <String>[], isNot(contains(phone)));
        expect(await phoneDepartmentId(phone), deptTarget);
      },
    );

    test(
      'ενημέρωση υπάρχοντος χρήστη → phones.department_id ακολουθεί το νέο τμήμα',
      () async {
        const phone = '2370555123';
        final deptA = await insertDepartment('Τμήμα Α');
        final deptB = await insertDepartment('Τμήμα Β');
        final userId = await insertUserWithPhone(
          firstName: 'Μαρία',
          lastName: 'Δοκιμή',
          departmentId: deptA,
          phone: phone,
        );
        await dirUpdatePhoneDepartment(deptA, phone);

        await service.save(
          target: LampTransferTarget.owner,
          formValues: ownerForm(
            phones: phone,
            departmentName: 'Τμήμα Β',
            firstName: 'Μαρία',
            lastName: 'Δοκιμή',
          ),
          selectedCandidateId: userId,
        );

        expect(await phoneDepartmentId(phone), deptB);

        final db = await DatabaseHelper.instance.database;
        final dir = DirectoryRepository(db);
        final phonesMap = await dir.getDepartmentDirectPhonesMap();
        expect(phonesMap[deptB], contains(phone));
        expect(phonesMap[deptA] ?? const <String>[], isNot(contains(phone)));
      },
    );
  });
}

Future<void> dirUpdatePhoneDepartment(int departmentId, String phone) async {
  final db = await DatabaseHelper.instance.database;
  final dir = DirectoryRepository(db);
  await dir.updatePhoneDepartment(phone, departmentId);
}
