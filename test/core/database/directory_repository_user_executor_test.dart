import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('DirectoryRepository user writes — executor awareness', () {
    late DirectoryRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('user_executor_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/user_executor.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('user_phones');
      await db.delete('phones');
      await db.delete('users');
      repo = DirectoryRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test(
      'atomicity: failure μέσα σε εξωτερική transaction κάνει rollback insertUser',
      () async {
        await expectLater(
          db.transaction((txn) async {
            await repo.insertUser(
              firstName: 'Ρollback',
              lastName: 'Χρήστης',
              phones: ['23451111'],
              executor: txn,
            );
            throw StateError('προσομοίωση σφάλματος μετά την εγγραφή χρήστη');
          }),
          throwsA(isA<StateError>()),
        );

        expect(await db.query('users'), isEmpty);
        expect(await db.query('user_phones'), isEmpty);
        expect(await db.query('phones'), isEmpty);
      },
    );

    test(
      'atomicity: failure μετά removePhoneFromAllUsers κάνει rollback user_phones',
      () async {
        const phone = '23452222';
        final userId = await repo.insertUser(
          firstName: 'Κάτοχος',
          lastName: 'Τηλεφώνου',
          phones: [phone],
        );

        await expectLater(
          db.transaction((txn) async {
            await repo.removePhoneFromAllUsers(phone, executor: txn);
            throw StateError('προσομοίωση σφάλματος μετά την αποσύνδεση');
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
      'executor participation: συμμετοχή σε εξωτερική transaction χωρίς nested transaction',
      () async {
        await db.transaction((txn) async {
          final id = await repo.insertUser(
            firstName: 'Εξωτερικό',
            lastName: 'Txn',
            phones: ['23453333'],
            executor: txn,
          );
          await repo.updateUser(
            id,
            {'notes': 'ενημέρωση εντός txn'},
            executor: txn,
          );
        });

        final rows = await db.query('users', where: 'last_name = ?', whereArgs: ['Txn']);
        expect(rows, hasLength(1));
        expect(rows.single['notes'], 'ενημέρωση εντός txn');
        expect(await db.query('user_phones'), hasLength(1));
      },
    );

    test(
      'regression: insertUser / updateUser / removePhoneFromAllUsers χωρίς executor',
      () async {
        const phone = '23454444';
        final id = await repo.insertUser(
          firstName: 'Regression',
          lastName: 'Χρήστης',
          phones: [phone],
        );
        expect(id, greaterThan(0));

        await repo.updateUser(id, {'location': 'Αίθουσα'});
        final row = await db.query('users', where: 'id = ?', whereArgs: [id]);
        expect(row.single['location'], 'Αίθουσα');

        await repo.removePhoneFromAllUsers(phone);
        expect(await db.query('user_phones', where: 'user_id = ?', whereArgs: [id]), isEmpty);
      },
    );
  });
}
