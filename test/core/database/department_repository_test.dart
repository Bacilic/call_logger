import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:call_logger/core/errors/department_exists_exception.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Κλείδωμα συμπεριφοράς τμημάτων πριν από Φάση Γ.2α (DepartmentRepository).
void main() {
  group('DepartmentRepository behavior — lock πριν εξαγωγή', () {
    late DirectoryRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir =
          await Directory.systemTemp.createTemp('department_repository_test_');
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/department_repo.db',
      );
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
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

    test('getDepartments / getActiveDepartments / getDepartmentRowById / getDepartmentNameById',
        () async {
      final activeId = await db.insert('departments', {
        'name': 'Ενεργό Τμήμα',
        'name_key': SearchTextNormalizer.normalizeForSearch('Ενεργό Τμήμα'),
        'is_deleted': 0,
      });
      await db.insert('departments', {
        'name': 'Διαγραμμένο Τμήμα',
        'name_key':
            SearchTextNormalizer.normalizeForSearch('Διαγραμμένο Τμήμα'),
        'is_deleted': 1,
      });

      final all = await repo.getDepartments();
      expect(all, hasLength(2));

      final active = await repo.getActiveDepartments();
      expect(active, hasLength(1));
      expect(active.single['id'], activeId);

      final row = await repo.getDepartmentRowById(activeId);
      expect(row?['name'], 'Ενεργό Τμήμα');

      expect(await repo.getDepartmentNameById(activeId), 'Ενεργό Τμήμα');
      expect(await repo.getDepartmentNameById(99999), isNull);
    });

    test('departmentNameExists: κανονικοποίηση ονόματος', () async {
      await db.insert('departments', {
        'name': 'Τμήμα Πληροφορικής',
        'name_key':
            SearchTextNormalizer.normalizeForSearch('Τμήμα Πληροφορικής'),
        'is_deleted': 0,
      });

      expect(await repo.departmentNameExists('ΤΜΗΜΑ ΠΛΗΡΟΦΟΡΙΚΗΣ'), isTrue);
      expect(await repo.departmentNameExists('Άγνωστο'), isFalse);
    });

    test('getOrCreateDepartmentIdByName: δημιουργία μία φορά + επανάχρηση', () async {
      final first = await repo.getOrCreateDepartmentIdByName(
        'Τμήμα GetOrCreate Lock',
        recordAudit: false,
      );
      final second = await repo.getOrCreateDepartmentIdByName(
        'τμήμα getorcreate lock',
        recordAudit: false,
      );
      expect(first, isNotNull);
      expect(second, equals(first));
      expect(await db.query('departments'), hasLength(1));
    });

    test('getOrCreateDepartmentIdByName: executor awareness', () async {
      int? idInTxn;
      await db.transaction((txn) async {
        idInTxn = await repo.getOrCreateDepartmentIdByName(
          'Τμήμα Εξωτερικής Txn',
          recordAudit: false,
          executor: txn,
        );
      });
      expect(idInTxn, isNotNull);
      final rows = await db.query(
        'departments',
        where: 'name = ?',
        whereArgs: ['Τμήμα Εξωτερικής Txn'],
      );
      expect(rows, hasLength(1));
    });

    test('insertDepartment: DepartmentExistsException για διπλό όνομα', () async {
      const name = 'Διπλό Τμήμα';
      await repo.insertDepartment(departmentRow(name));

      await expectLater(
        repo.insertDepartment(departmentRow(name)),
        throwsA(
          isA<DepartmentExistsException>().having(
            (e) => e.isDeleted,
            'isDeleted',
            false,
          ),
        ),
      );
    });

    test('softDeleteDepartment / restoreDepartments: is_deleted και audit', () async {
      final id = await repo.insertDepartment(departmentRow('Τμήμα Audit'));
      await repo.setSetting(
        DatabaseHelper.auditUserPerformingSettingsKey,
        'Admin Τμημάτων',
      );

      await db.delete('audit_log');
      await repo.softDeleteDepartment(id);

      final deleted = await db.query('departments', where: 'id = ?', whereArgs: [id]);
      expect(deleted.single['is_deleted'], 1);

      final deleteAudit = await db.query(
        'audit_log',
        where: 'entity_id = ? AND action = ?',
        whereArgs: [id, DatabaseHelper.auditActionDelete],
      );
      expect(deleteAudit, hasLength(1));
      expect(deleteAudit.single['user_performing'], 'Admin Τμημάτων');

      await db.delete('audit_log');
      await repo.restoreDepartments([id]);

      final restored = await db.query('departments', where: 'id = ?', whereArgs: [id]);
      expect(restored.single['is_deleted'], 0);

      final restoreAudit = await db.query(
        'audit_log',
        where: 'entity_id = ? AND action = ?',
        whereArgs: [id, DatabaseHelper.auditActionRestore],
      );
      expect(restoreAudit, hasLength(1));
    });

    test('backfillDepartmentFloorIdsFromMapFloor', () async {
      final floorId = await db.insert('building_map_floors', {
        'sort_order': 0,
        'label': 'Όροφος Backfill',
        'image_path': 'f.png',
        'rotation_degrees': 0.0,
      });
      final deptId = await db.insert('departments', {
        'name': 'Τμήμα Map Floor',
        'name_key': SearchTextNormalizer.normalizeForSearch('Τμήμα Map Floor'),
        'is_deleted': 0,
        'map_floor': floorId.toString(),
        'floor_id': null,
      });

      final count = await repo.backfillDepartmentFloorIdsFromMapFloor();
      expect(count, 1);

      final row = await db.query('departments', where: 'id = ?', whereArgs: [deptId]);
      expect(row.single['floor_id'], floorId);
    });

    test('backfillAllDepartmentNameKeys: μετρητές και σύγκρουση', () async {
      final canonicalKey =
          SearchTextNormalizer.normalizeForSearch('ΤΜΗΜΑ ΠΛΗΡΟΦΟΡΙΚΗΣ');
      await db.insert('departments', {
        'name': 'ΤΜΗΜΑ ΠΛΗΡΟΦΟΡΙΚΗΣ',
        'name_key': canonicalKey,
        'is_deleted': 0,
      });
      await db.insert('departments', {
        'name': 'Τμήμα Πληροφορικής',
        'name_key': 'τμήμα πληροφορικής',
        'is_deleted': 0,
      });

      final result = await repo.backfillAllDepartmentNameKeys();
      expect(result.updated, 0);
      expect(result.skippedCollision, 1);
      expect(result.alreadyCorrect, greaterThanOrEqualTo(1));
    });

    test(
      'ατομικότητα: αποτυχία μέσα σε εξωτερική transaction κάνει rollback insertDepartment',
      () async {
        const deptName = 'Τμήμα Rollback Lock';

        await expectLater(
          db.transaction((txn) async {
            await repo.insertDepartment(
              departmentRow(deptName),
              executor: txn,
            );
            throw StateError('προσομοίωση σφάλματος');
          }),
          throwsA(isA<StateError>()),
        );

        expect(
          await db.query('departments', where: 'name = ?', whereArgs: [deptName]),
          isEmpty,
        );
      },
    );
  });
}
