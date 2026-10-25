// Ό,τι διαβάζει ο χρήστης στο Ιστορικό Εφαρμογής πρέπει να το βρίσκει και η
// αναζήτηση. Η οθόνη λέει «Υπάλληλος», άρα το ευρετήριο δεν επιτρέπεται να
// κρατά τη λέξη «χρήστης» — που πλέον σημαίνει τον χειριστή της εφαρμογής.
//
//   flutter test test/core/database/audit_entity_label_alignment_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/audit_action_labels.dart';
import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/database/calls_lansweeper_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_audit_helpers.dart';
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
        'υπαλληλοσ',
        reason:
            'Η μαζική ενημέρωση δεν είναι οντότητα: αφορά υπαλλήλους, και '
            'λέγεται «Υπάλληλος - Μαζική ενημέρωση».',
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

    test(
      'πριν την αναβάθμιση, το ευρετήριο κρατά ακόμη το «χρήστης»',
      () async {
        await insertLegacyUserRow();

        expect(
          await matchesFor('χρήστης'),
          1,
          reason:
              'Το αποθηκευμένο ευρετήριο κρατά την παλιά λέξη — αυτό '
              'διορθώνει η v51.',
        );
      },
    );

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

  group('Ενέργεια ως «Οντότητα - Ενέργεια»', () {
    test('καμία ενέργεια του κώδικα δεν φτάνει ωμή στην οθόνη', () {
      // Κάθε ενέργεια που γράφει η εφαρμογή στο ιστορικό, μαζεμένη από τον
      // κώδικα — ώστε μια νέα ενέργεια χωρίς ετικέτα να κοκκινίζει εδώ αντί
      // να εμφανιστεί ως «Υπάλληλος - ΚΑΤΙ ΝΕΟ».
      final written = <String>{
        AuditActions.modifyUser,
        AuditActions.createUser,
        AuditActions.modifyDepartment,
        AuditActions.modifyEquipment,
        AuditActions.modifyPhone,
        AuditActions.modifyCategory,
        AuditActions.modifyCall,
        AuditActions.modifyTask,
        AuditActions.modifyOperator,
        AuditActions.createOperator,
        ...AuditActions.genericModifyActions,
        DatabaseHelper.auditActionDelete,
        DatabaseHelper.auditActionRestore,
        DatabaseHelper.auditActionBulkDelete,
        DatabaseHelper.auditActionIntegrityFix,
        kAuditCallAssociationAction,
        for (final state in ['sent', 'unsent', 'excluded', 'failed', '?'])
          lansweeperAuditAction(state),
      };
      final literal = RegExp(r"action:\s*'([^']*[Α-Ωα-ω][^']*)'");
      final backup = RegExp(r"'(ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ [^']+)'");
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();
        for (final m in literal.allMatches(source)) {
          written.add(m.group(1)!);
        }
        for (final m in backup.allMatches(source)) {
          written.add(m.group(1)!);
        }
      }

      final unlabelled = written
          .where((a) => !knownAuditActions.contains(a))
          .toList();
      expect(
        unlabelled,
        isEmpty,
        reason:
            'Οι ενέργειες αυτές θα εμφανίζονταν ωμές — λείπουν από τον '
            'κατάλογο ετικετών.',
      );
    });

    test('η ίδια ενέργεια ξεχωρίζει από τον τύπο της οντότητας', () {
      expect(
        auditActionLabelEl(
          entityType: AuditEntityTypes.user,
          action: 'ΔΙΑΓΡΑΦΗ',
        ),
        'Υπάλληλος - Διαγραφή',
      );
      expect(
        auditActionLabelEl(
          entityType: AuditEntityTypes.call,
          action: 'ΔΙΑΓΡΑΦΗ',
        ),
        'Κλήση - Διαγραφή',
      );
    });

    test('η μαζική ενημέρωση ανήκει στην οντότητα που αφορά', () {
      expect(
        auditActionLabelEl(
          entityType: AuditEntityTypes.bulkUsers,
          action: 'ΜΑΖΙΚΗ ΕΝΗΜΕΡΩΣΗ',
        ),
        'Υπάλληλος - Μαζική ενημέρωση',
      );
    });

    test('άγνωστη ενέργεια φαίνεται όπως γράφτηκε, όχι κενή', () {
      expect(
        auditActionLabelEl(
          entityType: AuditEntityTypes.user,
          action: 'ΚΑΤΙ ΝΕΟ',
        ),
        'Υπάλληλος - ΚΑΤΙ ΝΕΟ',
      );
    });
  });

  group('Φίλτρα και αναζήτηση με την ετικέτα της οθόνης', () {
    late Database db;
    late AuditService service;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await db.execute(_auditLogTableSql);
      service = AuditService(db);

      Future<void> log(String type, String action, String name) =>
          AuditService.log(
            db,
            action: action,
            userPerforming: 'Βασίλης',
            entityType: type,
            entityId: 1,
            entityName: name,
          );
      await log(AuditEntityTypes.user, 'ΔΙΑΓΡΑΦΗ', 'Δήμητρα Παπαδοπούλου');
      await log(AuditEntityTypes.call, 'ΔΙΑΓΡΑΦΗ', 'Ακτινολογικό');
      await log(AuditEntityTypes.user, 'ΤΡΟΠΟΠΟΙΗΣΗ ΥΠΑΛΛΗΛΟΥ', 'Νίκος Ρήγας');
      // Παλιά εγγραφή με τη γενική λέξη: ίδια ετικέτα με την από πάνω.
      await log(AuditEntityTypes.user, 'ΤΡΟΠΟΠΟΙΗΣΗ', 'Ελένη Μάρκου');
      await AuditService.logBulk(
        db,
        action: 'ΜΑΖΙΚΗ ΕΝΗΜΕΡΩΣΗ',
        userPerforming: 'Βασίλης',
        entityType: AuditEntityTypes.bulkUsers,
        affectedIds: const [1, 2],
        appliedFields: const {'department_text': 'Φαρμακείο'},
      );
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> count({
      String? action,
      String? entityType,
      String? keyword,
    }) async {
      final page = await service.queryPage(
        offset: 0,
        limit: 50,
        action: action,
        entityType: entityType,
        keywordNormalized: keyword == null
            ? null
            : SearchTextNormalizer.normalizeForSearch(keyword),
      );
      return page.total;
    }

    test(
      'το φίλτρο «Ενέργεια» δείχνει ετικέτες, μία φορά την καθεμιά',
      () async {
        final options = await service.queryDistinctActions();

        expect(options, [
          'Κλήση - Διαγραφή',
          'Υπάλληλος - Διαγραφή',
          'Υπάλληλος - Μαζική ενημέρωση',
          'Υπάλληλος - Τροποποίηση',
        ]);
      },
    );

    test('η επιλογή ετικέτας φέρνει μόνο τη δική της οντότητα', () async {
      expect(await count(action: 'Υπάλληλος - Διαγραφή'), 1);
      expect(
        await count(action: 'Υπάλληλος - Τροποποίηση'),
        2,
        reason: 'Η παλιά και η νέα γραφή της ενέργειας λένε το ίδιο.',
      );
    });

    test('ο τύπος «Υπάλληλος» πιάνει και τις μαζικές ενημερώσεις', () async {
      expect(await count(entityType: AuditEntityTypes.user), 4);
    });

    test('η αναζήτηση βρίσκει την ενέργεια με τη λέξη της οθόνης', () async {
      expect(await count(keyword: 'διαγραφή'), 2);
      expect(await count(keyword: 'υπάλληλος διαγραφή'), 1);
      expect(await count(keyword: 'μαζική'), 1);
    });
  });
}

const String _auditLogTableSql = '''
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
''';
