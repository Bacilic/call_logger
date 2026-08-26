import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/department_repository.dart';
import 'package:call_logger/core/database/phone_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('DepartmentRepository department writes — executor awareness', () {
    late DepartmentRepository departments;
    late PhoneRepository phones;
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
      departments = DepartmentRepository(db);
      phones = PhoneRepository(db);
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
            await departments.insertDepartment(
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
            final id = await departments.insertDepartment(
              departmentRow(deptName),
              executor: txn,
            );
            await phones.addDepartmentDirectPhone(
              id,
              '2310999888',
              executor: txn,
            );
            throw StateError('προσομοίωση σφάλματος μετά το τηλέφωνο τμήματος');
          }),
          throwsA(isA<StateError>()),
        );

        expect(
          await db.query(
            'departments',
            where: 'name = ?',
            whereArgs: [deptName],
          ),
          isEmpty,
        );
        expect(
          await db.query(
            'phones',
            where: 'number = ?',
            whereArgs: ['2310999888'],
          ),
          isEmpty,
        );
        expect(await db.query('department_phones'), isEmpty);
      },
    );

    test(
      'ατομικότητα: αποτυχία του Ιστορικού δεν αφήνει εγγραφή χωρίς ίχνος '
      '(updateDepartment χωρίς executor)',
      () async {
        final id = await db.insert(
          'departments',
          departmentRow('Γραμματεία ΤΕΠ'),
        );
        // Σπάμε το Ιστορικό στη μέση της δουλειάς: κάθε νέο ίχνος αποτυγχάνει.
        await db.execute(
          "CREATE TRIGGER break_audit BEFORE INSERT ON audit_log "
          "BEGIN SELECT RAISE(ABORT, 'σπασμένο Ιστορικό'); END",
        );
        try {
          await expectLater(
            departments.updateDepartment(
              id,
              {'name': 'Γραμματεία ΧΕΙΛ'},
              expected: null,
            ),
            throwsA(anything),
          );
        } finally {
          await db.execute('DROP TRIGGER break_audit');
        }

        final rows = await db.query(
          'departments',
          where: 'id = ?',
          whereArgs: [id],
        );
        expect(
          rows.single['name'],
          'Γραμματεία ΤΕΠ',
          reason:
              'φρουρός, εγγραφή και Ιστορικό οφείλουν να γίνονται μονομιάς — '
              'διακοπή στη μέση δεν αφήνει αλλαγή χωρίς ίχνος',
        );
      },
    );

    test(
      'executor participation: συμμετοχή σε εξωτερική transaction χωρίς nested transaction',
      () async {
        const deptName = 'Τμήμα Εξωτερικής Συναλλαγής';

        await db.transaction((txn) async {
          final id = await departments.insertDepartment(
            departmentRow(deptName),
            executor: txn,
          );
          await phones.addDepartmentDirectPhone(
            id,
            '2310111222',
            executor: txn,
          );
          await departments.updateDepartment(id, {
            'notes': 'ενημέρωση εντός txn',
          }, executor: txn, expected: null);
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
        final id = await departments.insertDepartment(
          departmentRow('Τμήμα Regression'),
        );
        expect(id, greaterThan(0));

        final updated = await departments.updateDepartment(id, {
          'notes': 'σημείωση',
        }, expected: null);
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
        final first = await departments.getOrCreateDepartmentIdByName(
          'Τμήμα GetOrCreate',
          recordAudit: false,
        );
        final second = await departments.getOrCreateDepartmentIdByName(
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
        final id = await departments.insertDepartment(
          departmentRow('Τμήμα Τηλέφωνα'),
        );
        await phones.addDepartmentDirectPhone(id, '2310333444');
        expect(
          await phones.getDepartmentDirectPhonesMap(),
          containsPair(id, ['2310333444']),
        );

        await phones.removeDepartmentDirectPhone(id, '2310333444');
        expect(
          await phones.getDepartmentDirectPhonesMap(),
          isNot(contains(id)),
        );
      },
    );
  });
}
