import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/directory_audit_helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('buildAuditCallAssociationEntry (Δ4)', () {
    test('ενέργεια σκέτη «συσχέτιση από κλήση», μέρη στις λεπτομέρειες', () {
      final entry = buildAuditCallAssociationEntry(
        userPart: 'Γιάννης Παπαδόπουλος',
        departmentPart: 'Ιατρική Υπηρεσία',
        phonePart: '2346111101',
        equipmentPart: 'PC-100',
      );

      expect(entry.action, kAuditCallAssociationAction);
      expect(entry.action, isNot(contains(':')));
      expect(
        entry.detailsLine,
        'Γιάννης Παπαδόπουλος - Ιατρική Υπηρεσία - 2346111101 - PC-100',
      );
    });

    test('χωρίς μέρη: μόνο σταθερή ενέργεια, κενές λεπτομέρειες', () {
      final entry = buildAuditCallAssociationEntry();
      expect(entry.action, kAuditCallAssociationAction);
      expect(entry.detailsLine, isNull);
    });

    test('mergeAuditCallAssociationDetails προτάσσει μέρη με διαχωριστικό', () {
      expect(
        mergeAuditCallAssociationDetails(
          associationDetails: 'Όνομα - Τμήμα',
          existingDetails: 'updateAssociationsIfNeeded userId=5',
        ),
        'Όνομα - Τμήμα · updateAssociationsIfNeeded userId=5',
      );
    });
  });

  group('normalizeLegacyCallAssociationAuditRow', () {
    test('μεταφέρει ουρά μετά την άνω-κάτω τελεία στις λεπτομέρειες', () {
      final normalized = normalizeLegacyCallAssociationAuditRow(
        action: 'συσχέτιση από κλήση: Όνομα - Τμήμα - 2345',
        details: 'updateAssociationsIfNeeded userId=1',
      );

      expect(normalized, isNotNull);
      expect(normalized!.action, kAuditCallAssociationAction);
      expect(
        normalized.details,
        'Όνομα - Τμήμα - 2345 · updateAssociationsIfNeeded userId=1',
      );
    });

    test('ήδη καθαρή γραμμή μένει ανέγγιχτη', () {
      final normalized = normalizeLegacyCallAssociationAuditRow(
        action: kAuditCallAssociationAction,
        details: 'Όνομα - Τμήμα',
      );
      expect(normalized, isNull);
    });
  });

  group('migrateDatabaseToV32', () {
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
          details TEXT
        )
      ''');
      return db;
    }

    test('κανονικοποιεί παλιά γραμμή με ουρά στην ενέργεια', () async {
      final db = await openAuditDb();
      try {
        await db.insert('audit_log', {
          'action': 'συσχέτιση από κλήση: Όνομα - Τμήμα - PC-1',
          'timestamp': '2026-07-11T10:00:00.000',
          'user_performing': 'tester',
          'details': 'updateAssociationsIfNeeded userId=3',
        });

        await migrateDatabaseToV32(db);

        final rows = await db.query('audit_log');
        expect(rows, hasLength(1));
        expect(rows.single['action'], kAuditCallAssociationAction);
        expect(
          rows.single['details'],
          'Όνομα - Τμήμα - PC-1 · updateAssociationsIfNeeded userId=3',
        );
      } finally {
        await db.close();
      }
    });

    test('ήδη καθαρή γραμμή μένει ανέγγιχτη', () async {
      final db = await openAuditDb();
      try {
        await db.insert('audit_log', {
          'action': kAuditCallAssociationAction,
          'timestamp': '2026-07-11T10:00:00.000',
          'user_performing': 'tester',
          'details': 'Όνομα - Τμήμα',
        });

        await migrateDatabaseToV32(db);

        final rows = await db.query('audit_log');
        expect(rows.single['action'], kAuditCallAssociationAction);
        expect(rows.single['details'], 'Όνομα - Τμήμα');
      } finally {
        await db.close();
      }
    });

    test('ξανατρέξιμο δεν διπλογράφει λεπτομέρειες', () async {
      final db = await openAuditDb();
      try {
        await db.insert('audit_log', {
          'action': 'συσχέτιση από κλήση: Μέρος1 - Μέρος2',
          'timestamp': '2026-07-11T10:00:00.000',
          'user_performing': 'tester',
          'details': null,
        });

        await migrateDatabaseToV32(db);
        await migrateDatabaseToV32(db);

        final rows = await db.query('audit_log');
        expect(rows.single['action'], kAuditCallAssociationAction);
        expect(rows.single['details'], 'Μέρος1 - Μέρος2');
      } finally {
        await db.close();
      }
    });
  });
}
