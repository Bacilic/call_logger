// Οι ομάδες τμημάτων: κλειστός κατάλογος που τα τμήματα ακολουθούν.
//
// Η ομάδα οργανώνει τον επιλογέα του χάρτη, οπότε αφορά ΜΟΝΟ όσες καρτέλες
// ζουν πάνω του — εταιρείες και εξωτερικές μονάδες δεν έχουν καν το πεδίο.
//
//   flutter test test/features/directory/department_groups_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/department_repository.dart';
import 'package:call_logger/core/services/settings_service_catalogs.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/directory/models/catalog_validation_finding.dart';
import 'package:call_logger/features/directory/models/catalog_validation_rules.dart';
import 'package:call_logger/features/directory/models/department_kind.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/services/catalog_validation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Ο κατάλογος δέχεται μία φορά το ίδιο', () {
    test('κενά και διπλότυπα φεύγουν', () {
      expect(
        SettingsServiceCatalogs.splitDepartmentGroupCatalog(
          'Εργαστήρια, , Κλινικές, Εργαστήρια',
        ),
        ['Εργαστήρια', 'Κλινικές'],
      );
    });

    test('τόνοι και πεζά δεν γεννούν δεύτερη ομάδα', () {
      expect(
        SettingsServiceCatalogs.splitDepartmentGroupCatalog(
          'Εργαστήρια, εργαστηρια',
        ),
        hasLength(1),
        reason: 'ακριβώς το πρόβλημα που γεννήθηκε ο κατάλογος για να λύσει',
      );
    });

    test('κενός κατάλογος = δεν έχει οριστεί', () {
      expect(
        SettingsServiceCatalogs.splitDepartmentGroupCatalog(null),
        isEmpty,
      );
    });
  });

  group('Ο έλεγχος δεδομένων βλέπει μόνο τα τμήματα του χάρτη', () {
    const service = CatalogValidationService(
      CatalogValidationRules(
        departmentBuildingEnabled: false,
        emptyDepartmentEnabled: false,
        equipmentWithoutDepartmentEnabled: false,
        userWithoutDepartmentEnabled: false,
      ),
    );

    List<CatalogValidationFinding> scan(List<DepartmentModel> departments) {
      return service
          .scan(users: const [], departments: departments, equipment: const [])
          .where((f) => f.message == 'Δεν ανήκει σε καμία ομάδα')
          .toList();
    }

    test('τμήμα νοσοκομείου χωρίς ομάδα: εύρημα', () {
      final findings = scan([DepartmentModel(id: 49, name: 'Αιμοδοσία')]);

      expect(findings, hasLength(1));
      expect(findings.single.fieldLabel, 'Ομάδα');
      expect(findings.single.records.single.focusedField, 'group');
    });

    test('με ομάδα: κανένα εύρημα', () {
      final findings = scan([
        DepartmentModel(id: 49, name: 'Αιμοδοσία', groupName: 'Εργαστήρια'),
      ]);

      expect(findings, isEmpty);
    });

    test('εταιρεία χωρίς ομάδα: ΠΟΤΕ εύρημα', () {
      final findings = scan([
        DepartmentModel(id: 70, name: 'DataMed', kind: DepartmentKind.company),
      ]);

      expect(
        findings,
        isEmpty,
        reason: 'η εταιρεία δεν μπαίνει στον χάρτη — δεν έχει καν το πεδίο',
      );
    });

    test('εξωτερική μονάδα χωρίς ομάδα: ΠΟΤΕ εύρημα', () {
      final findings = scan([
        DepartmentModel(
          id: 71,
          name: 'Κέντρο Υγείας',
          kind: DepartmentKind.externalUnit,
        ),
      ]);

      expect(findings, isEmpty);
    });

    test('σβηστός διακόπτης: κανένα εύρημα', () {
      const s = CatalogValidationService(
        CatalogValidationRules(
          departmentBuildingEnabled: false,
          emptyDepartmentEnabled: false,
          equipmentWithoutDepartmentEnabled: false,
          userWithoutDepartmentEnabled: false,
          departmentGroupEnabled: false,
        ),
      );
      final findings = s
          .scan(
            users: const [],
            departments: [DepartmentModel(id: 49, name: 'Αιμοδοσία')],
            equipment: const [],
          )
          .where((f) => f.message == 'Δεν ανήκει σε καμία ομάδα')
          .toList();

      expect(findings, isEmpty);
    });
  });

  group('Ο κατάλογος είναι ο κύριος, τα τμήματα ακολουθούν', () {
    late Database db;
    late DepartmentRepository repo;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('dept_groups_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/groups.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      repo = DepartmentRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<int> insert(String name, {String? group, DepartmentKind? kind}) {
      return db.insert('departments', {
        'name': name,
        'name_key': SearchTextNormalizer.normalizeForSearch(name),
        'group_name': group,
        'kind': (kind ?? DepartmentKind.hospital).dbValue,
        'is_deleted': 0,
      });
    }

    Future<String?> groupOf(String name) async {
      final rows = await db.query(
        'departments',
        columns: ['group_name'],
        where: 'name = ?',
        whereArgs: [name],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first['group_name'] as String?;
    }

    test('η μετονομασία ακολουθεί όλα τα τμήματα', () async {
      await insert('Αιμοδοσία', group: 'Εργαστήρια');
      await insert('Βιοχημικό', group: 'Εργαστήρια');
      await insert('Αξονικός', group: 'Απεικονιστικά');

      final touched = await repo.renameGroupInDepartments(
        from: 'Εργαστήρια',
        to: 'Εργαστήρια Αίματος',
      );

      expect(touched, 2);
      expect(await groupOf('Αιμοδοσία'), 'Εργαστήρια Αίματος');
      expect(await groupOf('Βιοχημικό'), 'Εργαστήρια Αίματος');
      expect(
        await groupOf('Αξονικός'),
        'Απεικονιστικά',
        reason: 'άλλη ομάδα δεν αγγίζεται',
      );
    });

    test('η διαγραφή ΑΔΕΙΑΖΕΙ τα τμήματα, δεν τα σβήνει', () async {
      await insert('Αιμοδοσία', group: 'Εργαστήρια');

      final cleared = await repo.clearGroupFromDepartments('Εργαστήρια');

      expect(cleared, 1);
      expect(await groupOf('Αιμοδοσία'), isNull);
      final rows = await db.query(
        'departments',
        where: 'name = ? AND is_deleted = 0',
        whereArgs: ['Αιμοδοσία'],
      );
      expect(rows, hasLength(1), reason: 'το τμήμα ζει, μόνο η ομάδα έφυγε');
    });

    test('ο μετρητής αγνοεί εταιρείες και εξωτερικές μονάδες', () async {
      // Η αφετηρία μετριέται πρώτη: το στήσιμο αφήνει δικό του τμήμα, και το
      // ζητούμενο είναι η ΔΙΑΦΟΡΑ που φέρνουν οι τέσσερις καρτέλες.
      final before = (await repo.countDepartmentsPerGroup()).withoutGroup;

      await insert('Αιμοδοσία', group: 'Εργαστήρια');
      await insert('Βιοχημικό');
      await insert('DataMed', kind: DepartmentKind.company);
      await insert('Κέντρο Υγείας', kind: DepartmentKind.externalUnit);

      final usage = await repo.countDepartmentsPerGroup();

      expect(usage.countFor('Εργαστήρια'), 1);
      expect(
        usage.withoutGroup - before,
        1,
        reason: 'μόνο το Βιοχημικό — οι άλλες δύο δεν μπαίνουν στον χάρτη',
      );
    });
  });
}
