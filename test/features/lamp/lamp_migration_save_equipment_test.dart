import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('LampMigrationService equipment save — owner conflict', () {
    late LampMigrationService service;
    late int userXId;
    late int userYId;
    late int equipmentId;
    const equipmentCode = 'PC-K';

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lamp_equip_save_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/lamp_equip_save.db');
      await DatabaseHelper.instance.database;
      service = LampMigrationService();
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      await db.delete('user_equipment');
      await db.delete('equipment');
      await db.delete('users');

      userXId = await db.insert('users', {
        'first_name': 'Γιάννης',
        'last_name': 'Χριστού',
        'is_deleted': 0,
      });
      userYId = await db.insert('users', {
        'first_name': 'Μαρία',
        'last_name': 'Γεωργίου',
        'is_deleted': 0,
      });
      equipmentId = await db.insert('equipment', {
        'code_equipment': equipmentCode,
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': userXId,
        'equipment_id': equipmentId,
      });
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Map<String, String> equipmentForm({required String ownerName}) {
      return {
        'code_equipment': equipmentCode,
        'owner_name': ownerName,
        'type': 'Desktop',
        'department_name': '',
        'location': '',
        'notes': '',
      };
    }

    String conflictIdForCode(String code) =>
        'equipment:${SearchTextNormalizer.normalizeForSearch(code)}';

    Future<Set<int>> ownerIdsForEquipment(int id) async {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'user_equipment',
        columns: ['user_id'],
        where: 'equipment_id = ?',
        whereArgs: [id],
      );
      return rows.map((r) => r['user_id'] as int).toSet();
    }

    test(
      'blocks save when owner changes without conflict decision',
      () async {
        await expectLater(
          service.save(
            target: LampTransferTarget.equipment,
            formValues: equipmentForm(ownerName: 'Μαρία Γεωργίου'),
            selectedCandidateId: equipmentId,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message.toLowerCase(),
              'message',
              contains('απαιτείται επίλυση'),
            ),
          ),
        );

        expect(await ownerIdsForEquipment(equipmentId), {userXId});
      },
    );

    test('keepWithoutAssignment preserves current owner', () async {
      await service.save(
        target: LampTransferTarget.equipment,
        formValues: equipmentForm(ownerName: 'Μαρία Γεωργίου'),
        selectedCandidateId: equipmentId,
        ownerConflictDecisions: [
          LampOwnerConflictDecision(
            conflictId: conflictIdForCode(equipmentCode),
            action: LampOwnerConflictAction.keepWithoutAssignment,
          ),
        ],
      );

      expect(await ownerIdsForEquipment(equipmentId), {userXId});
    });

    test('transferToSelectedOwner assigns new owner', () async {
      await service.save(
        target: LampTransferTarget.equipment,
        formValues: equipmentForm(ownerName: 'Μαρία Γεωργίου'),
        selectedCandidateId: equipmentId,
        ownerConflictDecisions: [
          LampOwnerConflictDecision(
            conflictId: conflictIdForCode(equipmentCode),
            action: LampOwnerConflictAction.transferToSelectedOwner,
          ),
        ],
      );

      expect(await ownerIdsForEquipment(equipmentId), {userYId});
    });

    test('new equipment saves without owner conflict', () async {
      final result = await service.save(
        target: LampTransferTarget.equipment,
        formValues: equipmentForm(ownerName: 'Γιάννης Χριστού'),
        selectedCandidateId: null,
      );

      expect(result.updated, isFalse);
      expect(result.id, isNotNull);
      expect(await ownerIdsForEquipment(result.id), {userXId});
    });
  });
}
