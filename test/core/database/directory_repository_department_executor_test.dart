import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('DirectoryRepository department writes — executor awareness', () {
    late DirectoryRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('dept_executor_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/dept_executor.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('department_phones');
      await db.delete('phones');
      await db.delete('departments');
      repo = DirectoryRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Map<String, dynamic> departmentRow(String name) => {
          'name': name,
          'name_key': SearchTextNormalizer.normalizeForSearch(name),
          'is_deleted': 0,
        };

    test(
      'atomicity: failure μέσα σε εξωτερική transaction κάνει rollback insertDepartment',
      () async {
        const deptName = 'Τμήμα Rollback Δοκιμής';

        await expectLater(
          db.transaction((txn) async {
            await repo.insertDepartment(
              departmentRow(deptName),
              executor: txn,
            );
            throw StateError('προσομοίωση σφάλματος μετά την εγγραφή τμήματος');
          }),
          throwsA(isA<StateError>()),
        );

        final rows = await db.query(
          'departments',
          where: 'name = ?',
          whereArgs: [deptName],
        );
        expect(rows, isEmpty);
      },
    );

    test(
      'atomicity: failure μετά από addDepartmentDirectPhone κάνει rollback τμήματος',
      () async {
        const deptName = 'Τμήμα Τηλεφώνου Rollback';

        await expectLater(
          db.transaction((txn) async {
            final id = await repo.insertDepartment(
              departmentRow(deptName),
              executor: txn,
            );
            await repo.addDepartmentDirectPhone(
              id,
              '2310999888',
              executor: txn,
            );
            throw StateError('προσομοίωση σφάλματος μετά το τηλέφωνο τμήματος');
          }),
          throwsA(isA<StateError>()),
        );

        expect(
          await db.query('departments', where: 'name = ?', whereArgs: [deptName]),
          isEmpty,
        );
        expect(
          await db.query('phones', where: 'number = ?', whereArgs: ['2310999888']),
          isEmpty,
        );
        expect(await db.query('department_phones'), isEmpty);
      },
    );

    test(
      'executor participation: συμμετοχή σε εξωτερική transaction χωρίς nested transaction',
      () async {
        const deptName = 'Τμήμα Εξωτερικής Συναλλαγής';

        await db.transaction((txn) async {
          final id = await repo.insertDepartment(
            departmentRow(deptName),
            executor: txn,
          );
          await repo.addDepartmentDirectPhone(
            id,
            '2310111222',
            executor: txn,
          );
          await repo.updateDepartment(
            id,
            {'notes': 'ενημέρωση εντός txn'},
            executor: txn,
          );
        });

        final deptRows = await db.query(
          'departments',
          where: 'name = ?',
          whereArgs: [deptName],
        );
        expect(deptRows, hasLength(1));
        expect(deptRows.single['notes'], 'ενημέρωση εντός txn');

        final phoneRows = await db.query(
          'department_phones',
          where: 'department_id = ?',
          whereArgs: [deptRows.single['id']],
        );
        expect(phoneRows, hasLength(1));
      },
    );

    test(
      'regression: χωρίς executor insertDepartment / updateDepartment ίδια συμπεριφορά',
      () async {
        final id = await repo.insertDepartment(departmentRow('Τμήμα Regression'));
        expect(id, greaterThan(0));

        final updated = await repo.updateDepartment(
          id,
          {'notes': 'σημείωση'},
        );
        expect(updated, 1);

        final row = await db.query(
          'departments',
          where: 'id = ?',
          whereArgs: [id],
        );
        expect(row.single['notes'], 'σημείωση');
      },
    );

    test(
      'regression: getOrCreateDepartmentIdByName χωρίς executor δημιουργεί μία φορά',
      () async {
        final first = await repo.getOrCreateDepartmentIdByName(
          'Τμήμα GetOrCreate',
          recordAudit: false,
        );
        final second = await repo.getOrCreateDepartmentIdByName(
          'Τμήμα GetOrCreate',
          recordAudit: false,
        );
        expect(first, isNotNull);
        expect(second, equals(first));
        expect(await db.query('departments'), hasLength(1));
      },
    );

    test(
      'regression: add/removeDepartmentDirectPhone χωρίς executor',
      () async {
        final id = await repo.insertDepartment(departmentRow('Τμήμα Τηλέφωνα'));
        await repo.addDepartmentDirectPhone(id, '2310333444');
        expect(
          await repo.getDepartmentDirectPhonesMap(),
          containsPair(id, ['2310333444']),
        );

        await repo.removeDepartmentDirectPhone(id, '2310333444');
        expect(await repo.getDepartmentDirectPhonesMap(), isNot(contains(id)));
      },
    );
  });
}
