import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/utils/phone_list_parser.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:call_logger/features/lamp/services/lamp_transfer_preview.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('LampMigrationService draft builders — merge existing with Lamp', () {
    late LampMigrationService service;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lamp_draft_merge_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/lamp_draft_merge.db');
      await DatabaseHelper.instance.database;
      service = LampMigrationService();
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('phones');
      await db.delete('equipment');
      await db.delete('users');
      await db.delete('departments');
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    group('owner', () {
      const firstName = 'Νίκος';
      const lastName = 'Αντωνίου';

      Future<int> seedExistingOwner({
        required String phone,
        String? departmentName,
      }) async {
        final db = await DatabaseHelper.instance.database;
        int? departmentId;
        if (departmentName != null && departmentName.isNotEmpty) {
          departmentId = await db.insert('departments', {
            'name': departmentName,
            'name_key': departmentName.toLowerCase(),
            'is_deleted': 0,
          });
        }
        final userId = await db.insert('users', {
          'first_name': firstName,
          'last_name': lastName,
          'department_id': departmentId,
          'is_deleted': 0,
        });
        final phoneId = await db.insert('phones', {'number': phone});
        await db.insert('user_phones', {
          'user_id': userId,
          'phone_id': phoneId,
        });
        return userId;
      }

      Map<String, Object?> ownerSourceRow({
        required String phones,
        required String department,
      }) {
        return {
          'first_name': firstName,
          'last_name': lastName,
          'owner_phones': phones,
          'office_name': department,
        };
      }

      test('merges destination and Lamp phones when updating existing owner', () async {
        await seedExistingOwner(phone: '2310501234');

        final draft = await service.buildDraft(
          target: LampTransferTarget.owner,
          sourceRow: ownerSourceRow(
            phones: '2310501234, 6971122334',
            department: '',
          ),
        );

        expect(draft.selectedCandidateId, isNotNull);
        final seededPhones = PhoneListParser.splitPhones(draft.formValues['phones']);
        expect(seededPhones, contains('2310501234'));
        expect(seededPhones, contains('6971122334'));
      });

      test('preview marks Lamp-only phones as created after merge', () async {
        await seedExistingOwner(phone: '2310501234');

        final draft = await service.buildDraft(
          target: LampTransferTarget.owner,
          sourceRow: ownerSourceRow(
            phones: '2310501234, 6971122334',
            department: '',
          ),
        );

        final preview = buildLampTransferPreview(
          draft: draft,
          currentFormValues: draft.formValues,
          selectedCandidateId: draft.selectedCandidateId,
        );
        final phonesField = preview.fields.firstWhere((f) => f.formKey == 'phones');
        final lampOnlyItem = phonesField.items.where(
          (item) => item.value == '6971122334',
        );
        expect(lampOnlyItem, hasLength(1));
        expect(lampOnlyItem.first.action, TransferFieldAction.created);
      });

      test('fills empty department from Lamp', () async {
        await seedExistingOwner(phone: '2100000001');

        final draft = await service.buildDraft(
          target: LampTransferTarget.owner,
          sourceRow: ownerSourceRow(
            phones: '2100000001',
            department: 'Τμήμα Μισθοδοσίας',
          ),
        );

        expect(draft.selectedCandidateId, isNotNull);
        expect(draft.formValues['department_name'], 'Τμήμα Μισθοδοσίας');
      });

      test('keeps non-empty destination department over Lamp', () async {
        await seedExistingOwner(
          phone: '2100000002',
          departmentName: 'Τμήμα Α',
        );

        final draft = await service.buildDraft(
          target: LampTransferTarget.owner,
          sourceRow: ownerSourceRow(
            phones: '2100000002',
            department: 'Τμήμα Β',
          ),
        );

        expect(draft.selectedCandidateId, isNotNull);
        expect(draft.formValues['department_name'], 'Τμήμα Α');
      });

      test('new owner draft uses pure Lamp data', () async {
        final draft = await service.buildDraft(
          target: LampTransferTarget.owner,
          sourceRow: {
            'first_name': 'Άγνωστος',
            'last_name': 'Χρήστης',
            'owner_phones': '6999999999',
            'office_name': 'Τμήμα Λάμπας',
            'code_equipment': 'PC-NEW',
          },
        );

        expect(draft.selectedCandidateId, isNull);
        expect(draft.formValues, draft.newRecordFormValues);
        expect(draft.formValues['phones'], '6999999999');
        expect(draft.formValues['department_name'], 'Τμήμα Λάμπας');
      });
    });

    group('equipment', () {
      const equipmentCode = 'PC-MERGE';

      Future<int> seedExistingEquipment({
        String? type,
        String? notes,
        String? location,
      }) async {
        final db = await DatabaseHelper.instance.database;
        return db.insert('equipment', {
          'code_equipment': equipmentCode,
          'type': type,
          'notes': notes,
          'location': location,
          'is_deleted': 0,
        });
      }

      test('fills empty type/notes/location from Lamp when updating', () async {
        await seedExistingEquipment();

        final draft = await service.buildDraft(
          target: LampTransferTarget.equipment,
          sourceRow: {
            'code': equipmentCode,
            'description': 'Laptop Dell',
            'equipment_comments': 'Σημείωση Λάμπας',
            'office_name': 'Τμήμα IT',
          },
        );

        expect(draft.selectedCandidateId, isNotNull);
        expect(draft.formValues['type'], 'Laptop Dell');
        expect(draft.formValues['notes'], 'Σημείωση Λάμπας');
        expect(draft.formValues['code_equipment'], equipmentCode);
      });

      test('keeps non-empty destination type over Lamp', () async {
        await seedExistingEquipment(type: 'Desktop HP');

        final draft = await service.buildDraft(
          target: LampTransferTarget.equipment,
          sourceRow: {
            'code': equipmentCode,
            'description': 'Laptop Dell',
          },
        );

        expect(draft.selectedCandidateId, isNotNull);
        expect(draft.formValues['type'], 'Desktop HP');
      });
    });

    group('department', () {
      const departmentName = 'Φαρμακείο';

      Future<int> seedExistingDepartment({
        String? building,
        String? notes,
      }) async {
        final db = await DatabaseHelper.instance.database;
        return db.insert('departments', {
          'name': departmentName,
          'name_key': departmentName.toLowerCase(),
          'building': building,
          'notes': notes,
          'is_deleted': 0,
        });
      }

      test('fills empty building/notes from Lamp when updating', () async {
        await seedExistingDepartment();

        final draft = await service.buildDraft(
          target: LampTransferTarget.department,
          sourceRow: {
            'office_name': departmentName,
            'building': 'Κτίριο Λάμπας',
            'level': '3',
          },
        );

        expect(draft.selectedCandidateId, isNotNull);
        expect(draft.formValues['building'], 'Κτίριο Λάμπας');
        expect(draft.formValues['level'], '3');
        expect(draft.formValues['name'], departmentName);
      });

      test('keeps non-empty destination building over Lamp', () async {
        await seedExistingDepartment(building: 'Κτίριο Α');

        final draft = await service.buildDraft(
          target: LampTransferTarget.department,
          sourceRow: {
            'office_name': departmentName,
            'building': 'Κτίριο Β',
          },
        );

        expect(draft.selectedCandidateId, isNotNull);
        expect(draft.formValues['building'], 'Κτίριο Α');
      });
    });
  });
}
