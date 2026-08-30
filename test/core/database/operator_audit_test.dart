// Οι αλλαγές στα προφίλ χειριστών αφήνουν ίχνος — και το ίχνος διαβάζεται.
//
// Ως τη Φάση 4 τίποτα από αυτά δεν καταγραφόταν: ποιος έγινε διαχειριστής,
// ποιος πήρε ή έχασε δικαίωμα, ποιος απενεργοποιήθηκε. Εδώ φυλάγεται και ότι
// γράφεται, και ότι λέει ονομαστικά τι άλλαξε.
//
//   flutter test test/core/database/operator_audit_test.dart

import 'package:call_logger/core/database/audit_diff_helper.dart';
import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/database_table_labels.dart';
import 'package:call_logger/core/database/operator_audit.dart';
import 'package:call_logger/core/database/operator_repository.dart';
import 'package:call_logger/core/database/database_v1_schema.dart';
import 'package:call_logger/core/models/app_permission.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/features/operators/services/operator_management.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;
  late OperatorManagement management;

  setUpAll(() async {
    initSqfliteFfiForTests();
    db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    await db.execute(kCreateOperatorsTable);
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
    management = OperatorManagement(OperatorRepository(db));
  });

  setUp(() {
    CurrentOperator.reset();
  });

  tearDown(() async {
    await db.delete('audit_log');
    await db.delete('operators');
    CurrentOperator.reset();
  });

  tearDownAll(() async {
    await db.close();
  });

  Future<List<Map<String, Object?>>> auditRows() =>
      db.query('audit_log', orderBy: 'id');

  Future<Operator> createProfile({
    String name = 'Δοκιμαστικός',
    bool isAdmin = false,
    Map<String, bool> overrides = const <String, bool>{},
  }) async {
    final result = await management.create(
      displayName: name,
      isAdmin: isAdmin,
      permissionOverrides: overrides,
      now: DateTime(2026, 8, 22, 10),
    );
    expect(result.allowed, isTrue, reason: result.message);
    return result.operator!;
  }

  group('Δημιουργία προφίλ', () {
    test('αφήνει εγγραφή με τον δικό της τύπο, όχι με του υπαλλήλου', () async {
      final created = await createProfile(name: 'Ολγα');

      final rows = await auditRows();
      expect(rows, hasLength(1));
      expect(rows.single['action'], AuditActions.createOperator);
      expect(rows.single['entity_type'], AuditEntityTypes.operatorProfile);
      expect(rows.single['entity_id'], created.id);
      expect(rows.single['entity_name'], 'Ολγα');
      expect(
        rows.single['entity_type'],
        isNot(AuditEntityTypes.user),
        reason:
            'Ο χειριστής της εφαρμογής δεν είναι υπάλληλος του καταλόγου — '
            'δύο διαφορετικά πράγματα δεν μοιράζονται τύπο.',
      );
    });

    test('η οθόνη διαβάζει «Χρήστης», ξεχωριστά από τον «Υπάλληλο»', () {
      expect(
        databaseEntityTypeLabelEl(AuditEntityTypes.operatorProfile),
        'Χρήστης',
      );
      expect(databaseEntityTypeLabelEl(AuditEntityTypes.user), 'Υπάλληλος');
    });

    test('βρίσκεται με τη λέξη της οθόνης', () async {
      await createProfile(name: 'Ολγα');

      final page = await AuditService(
        db,
      ).queryPage(offset: 0, limit: 10, keywordNormalized: 'χρηστησ');
      expect(page.total, 1);
    });

    test('γράφει μόνο τα δικαιώματα που ορίστηκαν ρητά', () async {
      await createProfile(
        overrides: <String, bool>{AppPermission.fullBackup.key: true},
      );

      final json = '${(await auditRows()).single['new_values_json']}';
      expect(json, contains('permission_${AppPermission.fullBackup.key}'));
      expect(
        json,
        isNot(contains('permission_${AppPermission.browseDatabase.key}')),
        reason:
            'Τα δικαιώματα που δεν άγγιξε κανείς είναι προεπιλογές — μια λίστα '
            'από «Ναι» που δεν αποφάσισε άνθρωπος πνίγει όσα αποφασίστηκαν.',
      );
    });

    test('σφραγίζεται με το όνομα του χειριστή που την έκανε', () async {
      CurrentOperator.activate(
        Operator(id: 1, displayName: 'Βασίλης', createdAt: DateTime(2026)),
      );

      await createProfile(name: 'Νέος');

      expect((await auditRows()).single['user_performing'], 'Βασίλης');
    });
  });

  group('Αλλαγή προφίλ', () {
    test('η αλλαγή δικαιώματος καταγράφεται ονομαστικά, από τι σε τι', () async {
      final created = await createProfile();
      await db.delete('audit_log');

      await management.save(
        created,
        displayName: created.displayName,
        windowsAccount: null,
        isAdmin: created.isAdmin,
        isActive: true,
        permissionOverrides: <String, bool>{
          AppPermission.browseDatabase.key: false,
        },
      );

      final row = (await auditRows()).single;
      expect(row['action'], AuditActions.modifyOperator);
      final key = 'permission_${AppPermission.browseDatabase.key}';
      expect('${row['old_values_json']}', contains('"$key":true'));
      expect('${row['new_values_json']}', contains('"$key":false'));
      expect(
        '${row['search_text']}',
        contains('δικαιωμα'),
        reason:
            'Το ερώτημα «ποιος έδωσε σε ποιον ποιο δικαίωμα» πρέπει να '
            'απαντιέται από την αναζήτηση, όχι μόνο διαβάζοντας γραμμή-γραμμή.',
      );
    });

    test('η ετικέτα του δικαιώματος είναι αυτή που διάβασε ο διαχειριστής', () {
      expect(
        AuditDiffHelper.fieldTitleLabel(
          AuditEntityTypes.operatorProfile,
          'permission_${AppPermission.fullBackup.key}',
        ),
        'δικαίωμα «${AppPermission.fullBackup.label}»',
      );
    });

    test('η σήμανση διαχειριστή και η αρχειοθέτηση καταγράφονται', () async {
      final created = await createProfile(name: 'Πρώτος', isAdmin: true);
      await createProfile(name: 'Δεύτερος', isAdmin: true);
      await db.delete('audit_log');

      await management.save(
        created,
        displayName: 'Πρώτος',
        windowsAccount: null,
        isAdmin: false,
        isActive: false,
      );

      final row = (await auditRows()).single;
      expect('${row['old_values_json']}', contains('"is_admin":true'));
      expect('${row['new_values_json']}', contains('"is_admin":false'));
      expect('${row['new_values_json']}', contains('"is_active":false'));
    });

    test('αποθήκευση χωρίς καμία αλλαγή δεν γράφει εγγραφή', () async {
      final created = await createProfile();
      await db.delete('audit_log');

      await management.save(
        created,
        displayName: created.displayName,
        windowsAccount: created.windowsAccount,
        isAdmin: created.isAdmin,
        isActive: created.isActive,
      );

      expect(
        await auditRows(),
        isEmpty,
        reason:
            'Μια εγγραφή «άλλαξε ο Χ» που δεν λέει τι άλλαξε είναι θόρυβος — '
            'θάβει τις αληθινές.',
      );
    });

    test('παράκαμψη που συμφωνεί με την προεπιλογή δεν είναι αλλαγή', () async {
      final created = await createProfile();
      await db.delete('audit_log');

      await management.save(
        created,
        displayName: created.displayName,
        windowsAccount: null,
        isAdmin: created.isAdmin,
        isActive: created.isActive,
        permissionOverrides: <String, bool>{
          AppPermission.browseDatabase.key:
              AppPermission.browseDatabase.allowedByDefault,
        },
      );

      expect(await auditRows(), isEmpty);
    });
  });

  group('Η αναβάθμιση v51 δεν αγγίζει τα προφίλ', () {
    test('η «ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ» των προφίλ μένει ως έχει', () async {
      final created = await createProfile();
      await db.delete('audit_log');
      await management.save(
        created,
        displayName: 'Μετονομασμένος',
        windowsAccount: null,
        isAdmin: created.isAdmin,
        isActive: created.isActive,
      );

      await migrateDatabaseToV51(db);

      expect(
        (await auditRows()).single['action'],
        AuditActions.modifyOperator,
        reason:
            'Η v51 μετονομάζει «ΧΡΗΣΤΗ» σε «ΥΠΑΛΛΗΛΟΥ» για τον κατάλογο. Αν '
            'δεν κοίταζε τον τύπο, θα βάφτιζε και τα προφίλ — και θα έλεγαν '
            'για πάντα το λάθος πράγμα.',
      );
    });

    test(
      'η «ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ» των υπαλλήλων μετονομάζεται κανονικά',
      () async {
        await db.insert('audit_log', {
          'action': 'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ',
          'timestamp': '2026-08-20T10:00:00.000',
          'entity_type': AuditEntityTypes.user,
          'entity_id': 7,
          'entity_name': 'Δήμητρα Παπαδοπούλου',
        });

        await migrateDatabaseToV51(db);

        expect((await auditRows()).single['action'], AuditActions.modifyUser);
      },
    );
  });

  group('Οι ισχύουσες τιμές των δικαιωμάτων', () {
    test('χωρίς παράκαμψη ισχύει η προεπιλογή του καταλόγου', () {
      final plain = Operator(displayName: 'Απλός', createdAt: DateTime(2026));

      for (final permission in AppPermission.values) {
        expect(
          OperatorAudit.effectivePermission(plain, permission),
          permission.allowedByDefault,
          reason: 'Το «${permission.label}» δεν ακολουθεί την προεπιλογή του.',
        );
      }
    });

    test('η ρητή παράκαμψη υπερισχύει', () {
      final tweaked = Operator(
        displayName: 'Ρυθμισμένος',
        createdAt: DateTime(2026),
        permissionOverrides: <String, bool>{
          AppPermission.fullBackup.key:
              !AppPermission.fullBackup.allowedByDefault,
        },
      );

      expect(
        OperatorAudit.effectivePermission(tweaked, AppPermission.fullBackup),
        !AppPermission.fullBackup.allowedByDefault,
      );
    });
  });
}
