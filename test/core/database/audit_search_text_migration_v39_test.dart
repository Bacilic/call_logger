// Το ευρετήριο αναζήτησης του Ιστορικού Εφαρμογής γράφεται τη στιγμή της
// καταγραφής. Όταν συμπληρώνονται ελληνικές ετικέτες πεδίων, οι ήδη γραμμένες
// εγγραφές κουβαλούν ακόμη τα αγγλικά κλειδιά — η αναβάθμιση v39 τις ξαναχτίζει.
//
//   flutter test test/core/database/audit_search_text_migration_v39_test.dart

import 'dart:convert';

import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Αναβάθμιση v39 — ευρετήριο αναζήτησης ιστορικού', () {
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
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
    });

    tearDown(() async {
      await db.delete('audit_log');
    });

    tearDownAll(() async {
      await db.close();
    });

    /// Εγγραφή όπως γραφόταν πριν τις ελληνικές ετικέτες: το `search_text`
    /// κουβαλά το αγγλικό κλειδί του πεδίου.
    Future<int> insertLegacyRow({
      required String action,
      required Map<String, dynamic> newValues,
      required String legacySearchText,
    }) {
      return db.insert('audit_log', {
        'action': action,
        'timestamp': '2026-08-06T10:00:00.000',
        'user_performing': 'tester',
        'entity_type': 'user',
        'entity_id': 7,
        'entity_name': 'Δήμητρα',
        'new_values_json': jsonEncode(newValues),
        'search_text': SearchTextNormalizer.normalizeForSearch(
          legacySearchText,
        ),
      });
    }

    Future<int> matchesFor(String term) async {
      final page = await AuditService(db).queryPage(
        offset: 0,
        limit: 50,
        keywordNormalized: SearchTextNormalizer.normalizeForSearch(term),
      );
      return page.total;
    }

    test('πριν την αναβάθμιση, ο ελληνικός όρος δεν βρίσκει τίποτα', () async {
      await insertLegacyRow(
        action: 'συσχέτιση από κλήση',
        newValues: {'equipment_code': '3180'},
        legacySearchText: 'συσχετιση απο κληση equipment code',
      );

      expect(await matchesFor('equipment code'), 1);
      expect(
        await matchesFor('κωδικος εξοπλισμου'),
        0,
        reason: 'Χωρίς την αναβάθμιση, ο ελληνικός όρος δεν υπάρχει στο '
            'αποθηκευμένο ευρετήριο — αυτό ακριβώς διορθώνει η v39.',
      );
    });

    test('μετά την αναβάθμιση, ο ελληνικός όρος βρίσκει την παλιά εγγραφή',
        () async {
      await insertLegacyRow(
        action: 'συσχέτιση από κλήση',
        newValues: {'equipment_code': '3180'},
        legacySearchText: 'συσχετιση απο κληση equipment code',
      );

      await migrateDatabaseToV39(db);

      expect(await matchesFor('κωδικος εξοπλισμου'), 1);
    });

    test('η αναβάθμιση ξανατρέχει χωρίς παρενέργειες', () async {
      await insertLegacyRow(
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΚΛΗΣΗΣ',
        newValues: {'lansweeper_main_ticket_id': 17444},
        legacySearchText: 'τροποποιηση κλησης lansweeper main ticket id',
      );

      await migrateDatabaseToV39(db);
      final afterFirst = await db.query('audit_log', columns: ['search_text']);

      await migrateDatabaseToV39(db);
      final afterSecond = await db.query('audit_log', columns: ['search_text']);

      expect(afterSecond.single['search_text'], afterFirst.single['search_text']);
      expect(await matchesFor('εισιτηριο lansweeper'), 1);
    });

    test('η αναβάθμιση δεν χάνει το περιεχόμενο της εγγραφής', () async {
      final id = await insertLegacyRow(
        action: 'συσχέτιση από κλήση',
        newValues: {'equipment_code': '3180'},
        legacySearchText: 'συσχετιση απο κληση equipment code',
      );

      await migrateDatabaseToV39(db);

      final row = (await db.query(
        'audit_log',
        where: 'id = ?',
        whereArgs: [id],
      )).single;
      expect(row['entity_name'], 'Δήμητρα');
      expect(row['new_values_json'], contains('3180'));
      // Ο κωδικός παραμένει αναζητήσιμος — το ευρετήριο κρατά και τις τιμές.
      expect(await matchesFor('3180'), 1);
    });
  });
}
