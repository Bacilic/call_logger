import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('DirectoryRepository.getOrCreateDepartmentIdByName', () {
    late DirectoryRepository repo;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('dept_name_key_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/dept_name_key.db');
      await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      await db.delete('departments');
      repo = DirectoryRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test(
      'reuses existing department when only final sigma differs (ς vs σ)',
      () async {
        const typedName = 'Τμήμα Πληροφορικής';
        const uppercaseName = 'ΤΜΗΜΑ ΠΛΗΡΟΦΟΡΙΚΗΣ';

        final firstId =
            await repo.getOrCreateDepartmentIdByName(typedName, recordAudit: false);
        final secondId = await repo.getOrCreateDepartmentIdByName(
          uppercaseName,
          recordAudit: false,
        );

        expect(firstId, isNotNull);
        expect(secondId, equals(firstId));

        final db = await DatabaseHelper.instance.database;
        final rows = await db.query('departments');
        expect(rows, hasLength(1));
        expect(
          rows.single['name_key'],
          SearchTextNormalizer.normalizeForSearch(typedName),
        );
      },
    );

    test('backfillAllDepartmentNameKeys updates stale keys without merging duplicates', () async {
      final db = await DatabaseHelper.instance.database;
      final canonicalKey =
          SearchTextNormalizer.normalizeForSearch('ΤΜΗΜΑ ΠΛΗΡΟΦΟΡΙΚΗΣ');
      final staleKey = 'τμήμα πληροφορικής';

      final winnerId = await db.insert('departments', {
        'name': 'ΤΜΗΜΑ ΠΛΗΡΟΦΟΡΙΚΗΣ',
        'name_key': canonicalKey,
        'is_deleted': 0,
      });
      final loserId = await db.insert('departments', {
        'name': 'Τμήμα Πληροφορικής',
        'name_key': staleKey,
        'is_deleted': 0,
      });

      final result = await repo.backfillAllDepartmentNameKeys();

      expect(result.updated, 0);
      expect(result.skippedCollision, 1);

      final winner = await db.query(
        'departments',
        where: 'id = ?',
        whereArgs: [winnerId],
      );
      final loser = await db.query(
        'departments',
        where: 'id = ?',
        whereArgs: [loserId],
      );
      expect(winner.single['name_key'], canonicalKey);
      expect(loser.single['name_key'], staleKey);
    });

    test('backfillAllDepartmentNameKeys fixes legacy sigma key when no collision', () async {
      final db = await DatabaseHelper.instance.database;
      const name = 'Τμήμα Πληροφορικής';
      final expected = SearchTextNormalizer.normalizeForSearch(name);
      final legacyKey = 'τμήμα πληροφορικής';

      final id = await db.insert('departments', {
        'name': name,
        'name_key': legacyKey,
        'is_deleted': 0,
      });

      final result = await repo.backfillAllDepartmentNameKeys();

      expect(result.updated, 1);
      final row = await db.query('departments', where: 'id = ?', whereArgs: [id]);
      expect(row.single['name_key'], expected);
      expect(row.single['name_key'], isNot(legacyKey));
    });
  });
}
