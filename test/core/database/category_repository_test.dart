import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/category_repository.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/database/audit_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Κλείδωμα συμπεριφοράς κατηγοριών πριν από Φάση Γ.1α (CategoryRepository).
void main() {
  group('CategoryRepository behavior — lock πριν εξαγωγή', () {
    late CategoryRepository repo;
    late SettingsRepository settings;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir =
          await Directory.systemTemp.createTemp('category_repository_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/category_repo.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('calls');
      await db.delete('categories');
      repo = CategoryRepository(db);
      settings = SettingsRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<void> noopRebuild(Transaction txn, int categoryId) async {}

    test('getCategoryNames / getActiveCategoryRows: μόνο ενεργές, σωστή σειρά',
        () async {
      await db.insert('categories', {'name': 'Zebra', 'is_deleted': 0});
      await db.insert('categories', {'name': 'Alpha', 'is_deleted': 0});
      await db.insert('categories', {'name': 'Deleted', 'is_deleted': 1});

      final names = await repo.getCategoryNames();
      expect(names, ['Alpha', 'Zebra']);

      final rows = await repo.getActiveCategoryRows();
      expect(rows, hasLength(2));
      expect(rows.map((r) => r['name']), ['Alpha', 'Zebra']);
      expect(rows.every((r) => r['id'] != null), isTrue);
    });

    test('findActiveCategoryByNormalizedName: κανονικοποίηση ονόματος', () async {
      final id = await db.insert('categories', {
        'name': '  Δίκτυο  ',
        'is_deleted': 0,
      });

      final hit = await repo.findActiveCategoryByNormalizedName('δίκτυο');
      expect(hit, isNotNull);
      expect(hit!.id, id);
      expect(hit.name, 'Δίκτυο');

      expect(
        await repo.findActiveCategoryByNormalizedName('άγνωστη'),
        isNull,
      );
    });

    test('insertCategoryAndGetId: νέα κατηγορία', () async {
      final r = await repo.insertCategoryAndGetId(
        'Νέα Κατηγορία',
        rebuildSearchIndexInTxn: noopRebuild,
      );

      expect(r.restored, isFalse);
      expect(r.id, greaterThan(0));

      final rows = await db.query(
        'categories',
        where: 'id = ?',
        whereArgs: [r.id],
      );
      expect(rows.single['name'], 'Νέα Κατηγορία');
      expect(rows.single['is_deleted'], 0);
    });

    test('insertCategoryAndGetId: επαναφορά soft-deleted (restored:true)',
        () async {
      const originalName = 'Παλιά Κατηγορία';
      final softId = await db.insert('categories', {
        'name': originalName,
        'is_deleted': 1,
      });

      int? rebuildCategoryId;
      Object? rebuildTxn;

      final r = await repo.insertCategoryAndGetId(
        'παλιά κατηγορία',
        rebuildSearchIndexInTxn: (txn, categoryId) async {
          rebuildTxn = txn;
          rebuildCategoryId = categoryId;
        },
      );

      expect(r.restored, isTrue);
      expect(r.id, softId);

      final rows = await db.query(
        'categories',
        where: 'id = ?',
        whereArgs: [softId],
      );
      expect(rows.single['is_deleted'], 0);
      expect(rows.single['name'], 'παλιά κατηγορία');

      expect(rebuildCategoryId, softId);
      expect(rebuildTxn, isNotNull);

      final auditRows = await db.query(
        'audit_log',
        where: 'entity_type = ? AND entity_id = ? AND action = ?',
        whereArgs: [
          AuditEntityTypes.category,
          softId,
          DatabaseHelper.auditActionRestore,
        ],
      );
      expect(auditRows, hasLength(1));
      expect(
        auditRows.single['details'],
        'categories id=$softId (επαναφορά από διαγραμμένη)',
      );
    });

    test(
      'updateCategoryNameAndSyncCalls: όνομα, callback στην ίδια txn, audit',
      () async {
        const oldName = 'Παλιό Όνομα';
        const newName = 'Νέο Όνομα';
        final catId = await db.insert('categories', {
          'name': oldName,
          'is_deleted': 0,
        });
        await db.insert('calls', {
          'category_id': catId,
          'category_text': oldName,
          'is_deleted': 0,
        });

        await settings.saveSetting(
          DatabaseHelper.auditUserPerformingSettingsKey,
          'Editor Κατηγορίας',
        );

        int? rebuildCategoryId;
        Object? rebuildTxn;

        await repo.updateCategoryNameAndSyncCalls(
          id: catId,
          newCanonicalName: newName,
          rebuildSearchIndexInTxn: (txn, categoryId) async {
            rebuildTxn = txn;
            rebuildCategoryId = categoryId;
            final inTxn = await txn.query(
              'categories',
              columns: ['name'],
              where: 'id = ?',
              whereArgs: [categoryId],
            );
            expect(inTxn.single['name'], newName);
          },
        );

        expect(rebuildCategoryId, catId);
        expect(rebuildTxn, isNotNull);

        final catRows = await db.query(
          'categories',
          where: 'id = ?',
          whereArgs: [catId],
        );
        expect(catRows.single['name'], newName);

        final callRows = await db.query(
          'calls',
          where: 'category_id = ?',
          whereArgs: [catId],
        );
        expect(callRows.single['category_text'], newName);

        final auditRows = await db.query(
          'audit_log',
          where: 'entity_type = ? AND entity_id = ? AND action = ?',
          whereArgs: [AuditEntityTypes.category, catId, 'ΤΡΟΠΟΠΟΙΗΣΗ'],
        );
        expect(auditRows, hasLength(1));
        expect(auditRows.single['user_performing'], 'Editor Κατηγορίας');
        expect(auditRows.single['entity_name'], newName);
      },
    );

    test('softDeleteCategories / restoreCategories: ids και audit', () async {
      final id1 = await db.insert('categories', {
        'name': 'Διαγραφή 1',
        'is_deleted': 0,
      });
      final id2 = await db.insert('categories', {
        'name': 'Διαγραφή 2',
        'is_deleted': 0,
      });

      await settings.saveSetting(
        DatabaseHelper.auditUserPerformingSettingsKey,
        'Admin Κατηγοριών',
      );

      await repo.softDeleteCategories([id1, id2]);

      final deleted = await db.query(
        'categories',
        where: 'id IN (?, ?)',
        whereArgs: [id1, id2],
      );
      expect(deleted.every((r) => r['is_deleted'] == 1), isTrue);

      final deleteAudits = await db.query(
        'audit_log',
        where: 'action = ? AND entity_type = ?',
        whereArgs: [DatabaseHelper.auditActionDelete, AuditEntityTypes.category],
      );
      expect(deleteAudits, hasLength(2));

      await db.delete('audit_log');

      await repo.restoreCategories([id1]);

      final restored = await db.query(
        'categories',
        where: 'id = ?',
        whereArgs: [id1],
      );
      expect(restored.single['is_deleted'], 0);

      final stillDeleted = await db.query(
        'categories',
        where: 'id = ?',
        whereArgs: [id2],
      );
      expect(stillDeleted.single['is_deleted'], 1);

      final restoreAudits = await db.query(
        'audit_log',
        where: 'action = ? AND entity_id = ?',
        whereArgs: [DatabaseHelper.auditActionRestore, id1],
      );
      expect(restoreAudits, hasLength(1));
      expect(restoreAudits.single['user_performing'], 'Admin Κατηγοριών');
    });
  });
}
