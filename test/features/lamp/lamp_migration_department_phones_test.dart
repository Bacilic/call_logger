import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('Lamp department transfer — office_phones', () {
    late LampMigrationService service;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lamp_dept_phones_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/lamp_dept_phones.db');
      await DatabaseHelper.instance.database;
      service = LampMigrationService();
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      await db.delete('department_phones');
      await db.delete('user_phones');
      await db.delete('phones');
      await db.delete('departments');
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<void> reloadLookup() async {
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    }

    Future<int> insertDepartment({
      required String name,
      List<String> phones = const [],
    }) async {
      final db = await DatabaseHelper.instance.database;
      final dir = DirectoryRepository(db);
      final id = await db.insert('departments', {
        'name': name,
        'name_key': SearchTextNormalizer.normalizeForSearch(name),
        'is_deleted': 0,
      });
      for (final phone in phones) {
        await dir.addDepartmentDirectPhone(id, phone);
      }
      await reloadLookup();
      return id;
    }

    Map<String, String> departmentForm({
      String name = 'Φαρμακείο',
      String building = '',
      String level = '',
      String notes = '',
      String phones = '',
    }) {
      return {
        'name': name,
        'building': building,
        'level': level,
        'notes': notes,
        'phones': phones,
      };
    }

    test(
      'νέο τμήμα με office_phones → αποθηκεύονται και τα δύο στο department_phones',
      () async {
        final result = await service.save(
          target: LampTransferTarget.department,
          formValues: departmentForm(
            phones: '2310501000, 2310501001',
          ),
          selectedCandidateId: null,
        );

        final db = await DatabaseHelper.instance.database;
        final dir = DirectoryRepository(db);
        final phonesMap = await dir.getDepartmentDirectPhonesMap();
        final saved = phonesMap[result.id] ?? const <String>[];
        expect(saved, containsAll(['2310501000', '2310501001']));
        expect(saved.length, 2);
      },
    );

    test(
      'ενημέρωση υπάρχοντος → προ-γέμισμα με ένωση υπαρχόντων ∪ office_phones',
      () async {
        const departmentName = 'Φαρμακείο';
        await insertDepartment(
          name: departmentName,
          phones: ['2310501000'],
        );

        final draft = await service.buildDraft(
          target: LampTransferTarget.department,
          sourceRow: {
            'office_name': departmentName,
            'office_phones': '2310501001',
          },
        );

        expect(draft.selectedCandidateId, isNotNull);
        expect(
          draft.formValues['phones'],
          '2310501000, 2310501001',
        );
      },
    );

    test('κενό office_phones → καμία αλλαγή στο department_phones', () async {
      const departmentName = 'Φαρμακείο';
      final deptId = await insertDepartment(
        name: departmentName,
        phones: ['2310501000'],
      );

      final db = await DatabaseHelper.instance.database;
      final dir = DirectoryRepository(db);
      final before = await dir.getDepartmentDirectPhonesMap();

      await service.save(
        target: LampTransferTarget.department,
        formValues: departmentForm(
          name: departmentName,
          phones: '',
        ),
        selectedCandidateId: deptId,
      );

      final after = await dir.getDepartmentDirectPhonesMap();
      expect(after[deptId], before[deptId]);
    });

    test(
      'buildDraft νέου τμήματος → phones seed από office_phones',
      () async {
        final draft = await service.buildDraft(
          target: LampTransferTarget.department,
          sourceRow: {
            'office_name': 'Φαρμακείο',
            'office_phones': '2310501000, 2310501001',
          },
        );

        expect(draft.selectedCandidateId, isNull);
        expect(draft.formValues['phones'], '2310501000, 2310501001');
      },
    );
  });
}
