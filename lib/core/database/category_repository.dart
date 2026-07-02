import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'audit_service.dart';
import 'database_helper.dart';
import 'directory_support.dart';

/// Callback από orchestrator: επαναδόμηση `search_index` στο ίδιο transaction.
typedef RebuildCallSearchIndexForCategoryInTxn =
    Future<void> Function(Transaction txn, int categoryId);

/// Persistence κατηγοριών προβλημάτων κλήσεων.
class CategoryRepository {
  CategoryRepository(this.db, {DirectorySupport? support})
      : _support = support ?? DirectorySupport(db);

  final Database db;
  final DirectorySupport _support;

  Future<List<String>> getCategoryNames() async {
    final rows = await db.query(
      'categories',
      columns: ['name'],
      where: 'COALESCE(is_deleted, 0) = ?',
      whereArgs: [0],
      orderBy: 'name',
    );
    return rows
        .map((r) => r['name'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<List<Map<String, dynamic>>> getActiveCategoryRows() async {
    return db.query(
      'categories',
      columns: ['id', 'name'],
      where: DirectorySupport.notDeletedClause,
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  Future<({int id, String name})?> findActiveCategoryByNormalizedName(
    String input,
  ) async {
    final key = DatabaseHelper.normalizeCategoryNameForLookup(input);
    if (key.isEmpty) return null;
    final rows = await getActiveCategoryRows();
    for (final r in rows) {
      final n = (r['name'] as String?)?.trim() ?? '';
      if (DatabaseHelper.normalizeCategoryNameForLookup(n) == key) {
        return (id: r['id'] as int, name: n);
      }
    }
    return null;
  }

  Future<bool> categoryNormalizedNameTaken(
    String name, {
    int? excludeId,
  }) async {
    final key = DatabaseHelper.normalizeCategoryNameForLookup(name);
    if (key.isEmpty) return false;
    final rows = await getActiveCategoryRows();
    for (final r in rows) {
      if (excludeId != null && r['id'] == excludeId) continue;
      final n = (r['name'] as String?)?.trim() ?? '';
      if (DatabaseHelper.normalizeCategoryNameForLookup(n) == key) return true;
    }
    return false;
  }

  Future<({int id, String name})?> _findSoftDeletedCategoryRowByNormalizedName(
    String input,
  ) async {
    final key = DatabaseHelper.normalizeCategoryNameForLookup(input);
    if (key.isEmpty) return null;
    final rows = await db.query(
      'categories',
      columns: ['id', 'name'],
      where: 'COALESCE(is_deleted, 0) = ?',
      whereArgs: [1],
      orderBy: 'id DESC',
    );
    for (final r in rows) {
      final n = (r['name'] as String?)?.trim() ?? '';
      if (DatabaseHelper.normalizeCategoryNameForLookup(n) == key) {
        return (id: r['id'] as int, name: n);
      }
    }
    return null;
  }

  /// [rebuildSearchIndexInTxn]: από orchestrator — π.χ. [CallsRepository.rebuildSearchIndexForCallsByCategoryId].
  Future<({int id, bool restored})> insertCategoryAndGetId(
    String name, {
    required RebuildCallSearchIndexForCategoryInTxn rebuildSearchIndexInTxn,
  }) async {
    final t = name.trim();
    if (t.isEmpty) {
      throw StateError('Κενό όνομα κατηγορίας.');
    }
    if (await categoryNormalizedNameTaken(t)) {
      throw StateError('Υπάρχει ήδη κατηγορία με ισοδύναμο όνομα.');
    }
    final soft = await _findSoftDeletedCategoryRowByNormalizedName(t);
    if (soft != null) {
      final id = soft.id;
      final user = await _support.auditPerformingUser();
      await db.transaction((txn) async {
        await txn.update(
          'categories',
          {'is_deleted': 0, 'name': t},
          where: 'id = ?',
          whereArgs: [id],
        );
        await txn.rawUpdate(
          'UPDATE calls SET category_text = ? WHERE category_id = ?',
          [t, id],
        );
        await AuditService.log(
          txn,
          action: DatabaseHelper.auditActionRestore,
          userPerforming: user,
          details: 'categories id=$id (επαναφορά από διαγραμμένη)',
          entityType: AuditEntityTypes.category,
          entityId: id,
          entityName: t,
        );
        await rebuildSearchIndexInTxn(txn, id);
      });
      return (id: id, restored: true);
    }
    final newId = await db.insert('categories', {'name': t, 'is_deleted': 0});
    return (id: newId, restored: false);
  }

  Future<void> updateCategoryNameAndSyncCalls({
    required int id,
    required String newCanonicalName,
    required RebuildCallSearchIndexForCategoryInTxn rebuildSearchIndexInTxn,
  }) async {
    final t = newCanonicalName.trim();
    if (t.isEmpty) throw ArgumentError('empty name');
    if (await categoryNormalizedNameTaken(t, excludeId: id)) {
      throw StateError('Υπάρχει ήδη κατηγορία με ισοδύναμο όνομα.');
    }
    final user = await _support.auditPerformingUser();
    await db.transaction((txn) async {
      await txn.update(
        'categories',
        {'name': t},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.rawUpdate(
        'UPDATE calls SET category_text = ? WHERE category_id = ?',
        [t, id],
      );
      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ',
        userPerforming: user,
        details: 'categories id=$id',
        entityType: AuditEntityTypes.category,
        entityId: id,
        entityName: t,
        newValues: {'name': t},
      );
      await rebuildSearchIndexInTxn(txn, id);
    });
  }

  Future<void> softDeleteCategories(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _support.auditPerformingUser();
    await db.transaction((txn) async {
      for (final id in ids) {
        final catRows = await txn.query(
          'categories',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        final catName = catRows.isEmpty
            ? null
            : (catRows.first['name'] as String?)?.trim();
        await txn.update(
          'categories',
          {'is_deleted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await AuditService.log(
          txn,
          action: DatabaseHelper.auditActionDelete,
          userPerforming: user,
          details: 'categories id=$id',
          entityType: AuditEntityTypes.category,
          entityId: id,
          entityName: catName != null && catName.isNotEmpty ? catName : null,
        );
      }
    });
  }

  Future<void> restoreCategories(List<int> ids) async {
    if (ids.isEmpty) return;
    final user = await _support.auditPerformingUser();
    await db.transaction((txn) async {
      for (final id in ids) {
        final catRows = await txn.query(
          'categories',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        final catName = catRows.isEmpty
            ? null
            : (catRows.first['name'] as String?)?.trim();
        await txn.update(
          'categories',
          {'is_deleted': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
        await AuditService.log(
          txn,
          action: DatabaseHelper.auditActionRestore,
          userPerforming: user,
          details: 'categories id=$id',
          entityType: AuditEntityTypes.category,
          entityId: id,
          entityName: catName != null && catName.isNotEmpty ? catName : null,
        );
      }
    });
  }
}
