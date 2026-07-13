import 'dart:convert';

import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<Database> openAuditDb() async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      singleInstance: false,
    );
    await db.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT,
        timestamp TEXT,
        user_performing TEXT,
        details TEXT,
        entity_type TEXT,
        entity_id INTEGER,
        entity_name TEXT,
        search_text TEXT,
        old_values_json TEXT,
        new_values_json TEXT
      )
    ''');
    return db;
  }

  Future<int> insertAuditRow(
    Database db, {
    required String searchText,
    String action = 'ΤΡΟΠΟΠΟΙΗΣΗ',
  }) async {
    return db.insert('audit_log', {
      'action': action,
      'timestamp': '2026-07-11T12:00:00.000',
      'user_performing': 'tester',
      'search_text': searchText,
    });
  }

  group('AuditService keyword search', () {
    late Database db;
    late AuditService service;

    setUp(() async {
      db = await openAuditDb();
      service = AuditService(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('«θεσης» δεν επιστρέφει εγγραφή με μόνο «αλλαγη προθεσμιας»', () async {
      await insertAuditRow(
        db,
        searchText: SearchTextNormalizer.normalizeForSearch(
          'αλλαγη προθεσμιας απο 2026-01-01 σε 2026-02-01',
        ),
      );

      final keyword = SearchTextNormalizer.normalizeForSearch('θεσης');
      final page = await service.queryPage(
        offset: 0,
        limit: 10,
        keywordNormalized: keyword,
      );
      final ids = await service.queryMatchingIds(keywordNormalized: keyword);

      expect(page.total, 0);
      expect(ids, isEmpty);
    });

    test('«παραμε» δεν επιστρέφει «αντιγραφο ασφαλειας παραλειφθηκε»', () async {
      await insertAuditRow(
        db,
        searchText: SearchTextNormalizer.normalizeForSearch(
          'αντιγραφο ασφαλειας παραλειφθηκε',
        ),
        action: 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ',
      );

      final keyword = SearchTextNormalizer.normalizeForSearch('παραμε');
      final page = await service.queryPage(
        offset: 0,
        limit: 10,
        keywordNormalized: keyword,
      );
      final ids = await service.queryMatchingIds(keywordNormalized: keyword);

      expect(page.total, 0);
      expect(ids, isEmpty);
    });

    test('«θεση» βρίσκει «αλλαγη θεσης x» και «θεσης» βρίσκει «θεση»', () async {
      final positionRow = await insertAuditRow(
        db,
        searchText: SearchTextNormalizer.normalizeForSearch('αλλαγη θεσης x'),
      );
      final plainRow = await insertAuditRow(
        db,
        searchText: SearchTextNormalizer.normalizeForSearch('αλλαγη θεση y'),
      );

      final positionKeyword = SearchTextNormalizer.normalizeForSearch('θεση');
      final positionPage = await service.queryPage(
        offset: 0,
        limit: 10,
        keywordNormalized: positionKeyword,
      );
      expect(positionPage.total, 2);
      expect(
        positionPage.rows.map((r) => r['id']).toSet(),
        {positionRow, plainRow},
      );

      // Το «θεσης» πρέπει να βρίσκει ΚΑΙ την ίδια τη λέξη «θεσης x»
      // (πλήρες token) ΚΑΙ το «θεση y» (ανοχή πτώσης μέσω ρίζας).
      final caseKeyword = SearchTextNormalizer.normalizeForSearch('θεσης');
      final casePage = await service.queryPage(
        offset: 0,
        limit: 10,
        keywordNormalized: caseKeyword,
      );
      expect(casePage.total, 2);
      expect(
        casePage.rows.map((r) => r['id']).toSet(),
        {positionRow, plainRow},
      );
    });
  });

  group('AuditService search_text index', () {
    test('αλλαγή μόνο χρώματος δεν διαρρέει «θεση» από ίδια map_x/map_y', () {
      final searchText = AuditService.rebuildSearchTextForRow({
        'details': 'departments id=1',
        'entity_type': AuditEntityTypes.department,
        'entity_name': 'Τμήμα Δοκιμής',
        'old_values_json': jsonEncode({
          'color': '#1976D2',
          'map_x': 0.5,
          'map_y': 0.5,
          'map_width': 150.0,
          'map_height': 50.0,
        }),
        'new_values_json': jsonEncode({
          'color': '#EF5350',
          'map_x': '0.5',
          'map_y': '0.5000001',
          'map_width': '150',
          'map_height': '50.0',
        }),
      });

      expect(searchText, isNot(contains('θεση')));
      expect(searchText, contains('χρωμα'));
      expect(searchText, isNot(contains('θεσης')));
    });

    test('rebuildAllSearchTexts ανακατασκευά idempotent το search_text', () async {
      final db = await openAuditDb();
      try {
        final staleSearchText = SearchTextNormalizer.normalizeForSearch(
          'αλλαγη θεσης χ απο 0.5 σε 0.5 χρωμα',
        );
        final id = await db.insert('audit_log', {
          'action': 'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ',
          'timestamp': '2026-07-11T12:00:00.000',
          'user_performing': 'tester',
          'entity_type': AuditEntityTypes.department,
          'entity_name': 'Τμήμα',
          'search_text': staleSearchText,
          'old_values_json': jsonEncode({
            'color': '#1976D2',
            'map_x': 0.5,
          }),
          'new_values_json': jsonEncode({
            'color': '#EF5350',
            'map_x': '0.5',
          }),
        });

        await AuditService.rebuildAllSearchTexts(db);
        final afterFirst = await db.query(
          'audit_log',
          columns: ['search_text'],
          where: 'id = ?',
          whereArgs: [id],
        );
        final firstText = afterFirst.single['search_text'] as String;
        expect(firstText, isNot(contains('θεση')));
        expect(firstText, contains('χρωμα'));

        await AuditService.rebuildAllSearchTexts(db);
        final afterSecond = await db.query(
          'audit_log',
          columns: ['search_text'],
          where: 'id = ?',
          whereArgs: [id],
        );
        expect(afterSecond.single['search_text'], firstText);
      } finally {
        await db.close();
      }
    });
  });
}
