// Ό,τι διαβάζει ο χρήστης στο Ιστορικό Εφαρμογής πρέπει να το βρίσκει και η
// αναζήτηση. Η οθόνη λέει «Υπάλληλος», άρα το ευρετήριο δεν επιτρέπεται να
// κρατά τη λέξη «χρήστης» — που πλέον σημαίνει τον χειριστή της εφαρμογής.
//
//   flutter test test/core/database/audit_entity_label_alignment_test.dart

import 'dart:convert';

import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/database_table_labels.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Ιστορικό Εφαρμογής — η οθόνη και η αναζήτηση λένε το ίδιο', () {
    /// Κάθε τύπος που μπορεί να γραφτεί στο ιστορικό, με τη λέξη που ο χρήστης
    /// βλέπει στη γραμμή και στο φίλτρο.
    const entityTypes = <String>[
      AuditEntityTypes.user,
      AuditEntityTypes.operatorProfile,
      AuditEntityTypes.department,
      AuditEntityTypes.equipment,
      AuditEntityTypes.category,
      AuditEntityTypes.task,
      AuditEntityTypes.call,
      AuditEntityTypes.phone,
      AuditEntityTypes.knowledge,
      AuditEntityTypes.bulkUsers,
      AuditEntityTypes.bulkDepartments,
      AuditEntityTypes.bulkEquipment,
      AuditEntityTypes.importData,
      AuditEntityTypes.maintenance,
      AuditEntityTypes.backup,
    ];

    test('κάθε τύπος έχει ελληνικό όνομα — κανένας δεν μένει αγγλικός', () {
      for (final type in entityTypes) {
        expect(
          databaseEntityTypeLabelEl(type),
          isNot(type),
          reason:
              'Ο τύπος «$type» εμφανίζεται ωμός στην οθόνη — λείπει η '
              'ελληνική του απόδοση.',
        );
      }
    });

    test('το ευρετήριο αναζήτησης παράγεται από ό,τι βλέπει ο χρήστης', () {
      for (final type in entityTypes) {
        final onScreen = databaseEntityTypeLabelEl(type);
        expect(
          databaseEntityTypeSearchLabelEl(type),
          SearchTextNormalizer.normalizeForSearch(onScreen),
          reason:
              'Ο τύπος «$type» γράφεται στο ευρετήριο με άλλη λέξη από '
              'αυτήν που δείχνει η οθόνη.',
        );
      }
    });

    test('άγνωστος τύπος δεν μολύνει το ευρετήριο', () {
      expect(databaseEntityTypeSearchLabelEl('κατι_αγνωστο'), '');
      expect(databaseEntityTypeSearchLabelEl(''), '');
      expect(databaseEntityTypeSearchLabelEl(null), '');
    });

    test('ο υπάλληλος δεν λέγεται πουθενά «χρήστης»', () {
      expect(databaseEntityTypeLabelEl(AuditEntityTypes.user), 'Υπάλληλος');
      expect(
        databaseEntityTypeSearchLabelEl(AuditEntityTypes.user),
        'υπαλληλοσ',
      );
      expect(
        databaseEntityTypeSearchLabelEl(AuditEntityTypes.bulkUsers),
        contains('υπαλληλων'),
      );
      expect(
        AuditActions.modifyUser,
        'ΤΡΟΠΟΠΟΙΗΣΗ ΥΠΑΛΛΗΛΟΥ',
        reason:
            'Η ενέργεια εμφανίζεται αυτούσια στη γραμμή, δίπλα στη λέξη '
            '«Υπάλληλος» — δεν μπορεί να λέει «ΧΡΗΣΤΗ».',
      );
      expect(AuditActions.createUser, 'ΔΗΜΙΟΥΡΓΙΑ ΥΠΑΛΛΗΛΟΥ');
    });
  });

  group('Αναβάθμιση v51 — παλιές εγγραφές υπαλλήλων', () {
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

    /// Εγγραφή όπως γραφόταν πριν τη μετονομασία: ενέργεια και ευρετήριο
    /// κουβαλούν ακόμη τη λέξη «χρήστης».
    Future<int> insertLegacyUserRow() {
      return db.insert('audit_log', {
        'action': 'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ',
        'timestamp': '2026-08-20T10:00:00.000',
        'user_performing': 'Βασίλης',
        'entity_type': AuditEntityTypes.user,
        'entity_id': 7,
        'entity_name': 'Δήμητρα Παπαδοπούλου',
        'new_values_json': jsonEncode({'department_text': 'Ακτινολογικό'}),
        'search_text': SearchTextNormalizer.normalizeForSearch(
          'Δήμητρα Παπαδοπούλου χρηστης τμημα Ακτινολογικό',
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

    test('πριν την αναβάθμιση, το «υπάλληλος» δεν βρίσκει τίποτα', () async {
      await insertLegacyUserRow();

      expect(await matchesFor('χρήστης'), 1);
      expect(
        await matchesFor('υπάλληλος'),
        0,
        reason:
            'Η οθόνη λέει ήδη «Υπάλληλος», αλλά το αποθηκευμένο ευρετήριο '
            'κρατά την παλιά λέξη — αυτό διορθώνει η v51.',
      );
    });

    test('μετά την αναβάθμιση, βρίσκεται με τη λέξη της οθόνης', () async {
      await insertLegacyUserRow();

      await migrateDatabaseToV51(db);

      expect(await matchesFor('υπάλληλος'), 1);
      expect(
        await matchesFor('χρήστης'),
        0,
        reason:
            'Καθαρή αντικατάσταση: το «χρήστης» ανήκει πλέον στα προφίλ της '
            'εφαρμογής, όχι στους υπαλλήλους του καταλόγου.',
      );
    });

    test('μετά την αναβάθμιση, η ενέργεια λέει «ΥΠΑΛΛΗΛΟΥ»', () async {
      final id = await insertLegacyUserRow();
      final createdId = await db.insert('audit_log', {
        'action': 'ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ',
        'timestamp': '2026-08-20T09:00:00.000',
        'user_performing': 'Βασίλης',
        'entity_type': AuditEntityTypes.user,
        'entity_id': 8,
        'entity_name': 'Νέος Υπάλληλος',
      });

      await migrateDatabaseToV51(db);

      final rows = await db.query(
        'audit_log',
        columns: ['id', 'action'],
        where: 'id IN (?, ?)',
        whereArgs: [id, createdId],
        orderBy: 'id',
      );
      expect(rows.map((r) => r['action']), [
        'ΤΡΟΠΟΠΟΙΗΣΗ ΥΠΑΛΛΗΛΟΥ',
        'ΔΗΜΙΟΥΡΓΙΑ ΥΠΑΛΛΗΛΟΥ',
      ]);
    });

    test('η αναβάθμιση ξανατρέχει χωρίς παρενέργειες', () async {
      await insertLegacyUserRow();

      await migrateDatabaseToV51(db);
      final afterFirst = await db.query('audit_log');

      await migrateDatabaseToV51(db);
      final afterSecond = await db.query('audit_log');

      expect(
        afterSecond.single['search_text'],
        afterFirst.single['search_text'],
      );
      expect(afterSecond.single['action'], afterFirst.single['action']);
    });

    test('η αναβάθμιση δεν χάνει το περιεχόμενο της εγγραφής', () async {
      final id = await insertLegacyUserRow();

      await migrateDatabaseToV51(db);

      final row = (await db.query(
        'audit_log',
        where: 'id = ?',
        whereArgs: [id],
      )).single;
      expect(row['entity_name'], 'Δήμητρα Παπαδοπούλου');
      expect(row['user_performing'], 'Βασίλης');
      expect(row['new_values_json'], contains('Ακτινολογικό'));
      expect(await matchesFor('Ακτινολογικό'), 1);
    });
  });
}
