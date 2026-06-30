import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('DirectoryRepository equipment writes — executor awareness', () {
    late DirectoryRepository repo;
    late Database db;
    late int userId;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('equip_executor_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/equip_executor.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('user_equipment');
      await db.delete('equipment');
      await db.delete('users');
      userId = await db.insert('users', {
        'first_name': 'Δοκιμή',
        'last_name': 'Χρήστης',
        'is_deleted': 0,
      });
      repo = DirectoryRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Map<String, dynamic> equipmentRow(String code) => {
          'code_equipment': code,
          'is_deleted': 0,
        };

    test(
      'atomicity: failure μέσα σε εξωτερική transaction κάνει rollback insertEquipmentFromMap',
      () async {
        const code = 'PC-ROLLBACK-INSERT';

        await expectLater(
          db.transaction((txn) async {
            await repo.insertEquipmentFromMap(
              equipmentRow(code),
              executor: txn,
            );
            throw StateError(
              'προσομοίωση σφάλματος μετά την εγγραφή εξοπλισμού',
            );
          }),
          throwsA(isA<StateError>()),
        );

        final rows = await db.query(
          'equipment',
          where: 'code_equipment = ?',
          whereArgs: [code],
        );
        expect(rows, isEmpty);
      },
    );

    test(
      'atomicity: failure μετά από replaceEquipmentUsers κάνει rollback εξοπλισμού',
      () async {
        const code = 'PC-ROLLBACK-REPLACE';

        await expectLater(
          db.transaction((txn) async {
            final id = await repo.insertEquipmentFromMap(
              equipmentRow(code),
              executor: txn,
            );
            await repo.replaceEquipmentUsers(
              id,
              [userId],
              executor: txn,
            );
            throw StateError(
              'προσομοίωση σφάλματος μετά το replaceEquipmentUsers',
            );
          }),
          throwsA(isA<StateError>()),
        );

        expect(
          await db.query(
            'equipment',
            where: 'code_equipment = ?',
            whereArgs: [code],
          ),
          isEmpty,
        );
        expect(await db.query('user_equipment'), isEmpty);
      },
    );

    test(
      'executor participation: συμμετοχή σε εξωτερική transaction χωρίς nested transaction',
      () async {
        const code = 'PC-EXT-TXN';

        await db.transaction((txn) async {
          final id = await repo.insertEquipmentFromMap(
            equipmentRow(code),
            executor: txn,
          );
          await repo.replaceEquipmentUsers(
            id,
            [userId],
            executor: txn,
          );
          await repo.updateEquipment(
            id,
            {'notes': 'ενημέρωση εντός txn'},
            executor: txn,
          );
        });

        final equipRows = await db.query(
          'equipment',
          where: 'code_equipment = ?',
          whereArgs: [code],
        );
        expect(equipRows, hasLength(1));
        expect(equipRows.single['notes'], 'ενημέρωση εντός txn');

        final linkRows = await db.query(
          'user_equipment',
          where: 'equipment_id = ?',
          whereArgs: [equipRows.single['id']],
        );
        expect(linkRows, hasLength(1));
        expect(linkRows.single['user_id'], userId);
      },
    );

    test(
      'regression: χωρίς executor insertEquipmentFromMap / updateEquipment ίδια συμπεριφορά',
      () async {
        final id = await repo.insertEquipmentFromMap(
          equipmentRow('PC-REGRESSION'),
        );
        expect(id, greaterThan(0));

        final updated = await repo.updateEquipment(
          id,
          {'notes': 'σημείωση'},
        );
        expect(updated, 1);

        final row = await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [id],
        );
        expect(row.single['notes'], 'σημείωση');
      },
    );

    test(
      'regression: replace/link/unlink χωρίς executor',
      () async {
        final id = await repo.insertEquipmentFromMap(equipmentRow('PC-LINKS'));
        await repo.replaceEquipmentUsers(id, [userId]);
        expect(
          await db.query(
            'user_equipment',
            where: 'equipment_id = ?',
            whereArgs: [id],
          ),
          hasLength(1),
        );

        await repo.unlinkUserFromEquipment(userId, id);
        expect(
          await db.query(
            'user_equipment',
            where: 'equipment_id = ?',
            whereArgs: [id],
          ),
          isEmpty,
        );

        await repo.linkUserToEquipment(userId, id);
        expect(
          await db.query(
            'user_equipment',
            where: 'equipment_id = ?',
            whereArgs: [id],
          ),
          hasLength(1),
        );
      },
    );
  });
}
