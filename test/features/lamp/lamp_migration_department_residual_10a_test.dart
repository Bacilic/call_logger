import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('ΖΤ-18 residual 10Α — removePhoneFromAllUsers μέσα σε transaction', () {
    late LampMigrationService service;
    late DirectoryRepository repo;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lamp_dept_res_10a_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/lamp_dept_res_10a.db');
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
      await db.delete('users');
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
      repo = DirectoryRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test(
      'repository: removePhoneFromAllUsers σε αποτυχημένη transaction επαναφέρει user_phones',
      () async {
        const phone = '2310666000';
        final userId = await repo.insertUser(
          firstName: 'Κάτοχος',
          lastName: 'Τηλεφώνου',
          phones: [phone],
        );
        final db = await DatabaseHelper.instance.database;

        await expectLater(
          db.transaction((txn) async {
            await repo.removePhoneFromAllUsers(phone, executor: txn);
            throw StateError('προσομοίωση αποτυχίας αποθήκευσης τμήματος');
          }),
          throwsA(isA<StateError>()),
        );

        final links = await db.query(
          'user_phones',
          where: 'user_id = ?',
          whereArgs: [userId],
        );
        expect(links, hasLength(1));
      },
    );

    test(
      'service: επιτυχής μεταφορά κοινόχρηστου τηλεφώνου σε νέο τμήμα (smoke)',
      () async {
        const phone = '2310777000';
        const sourceDept = 'Πηγή Τμήμα';
        const newDept = 'Νέο Τμήμα Residual';

        final db = await DatabaseHelper.instance.database;
        final sourceDeptId = await db.insert('departments', {
          'name': sourceDept,
          'name_key': SearchTextNormalizer.normalizeForSearch(sourceDept),
          'is_deleted': 0,
        });
        await repo.addDepartmentDirectPhone(sourceDeptId, phone);
        await repo.insertUser(
          firstName: 'Χρήστης',
          lastName: 'Πηγής',
          phones: [phone],
        );
        LookupService.instance.resetForReload();
        await LookupService.instance.loadFromDatabase();

        final result = await service.save(
          target: LampTransferTarget.department,
          formValues: {
            'name': newDept,
            'building': '',
            'level': '',
            'notes': '',
            'phones': phone,
          },
          selectedCandidateId: null,
          ownerConflictDecisions: [
            LampOwnerConflictDecision(
              conflictId: 'phone:${SearchTextNormalizer.normalizeForSearch(phone)}',
              action: LampOwnerConflictAction.transferToSelectedOwner,
            ),
          ],
        );

        final phonesMap = await repo.getDepartmentDirectPhonesMap();
        expect(phonesMap[result.id], contains(phone));
      },
    );
  });
}
