import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:call_logger/core/services/audit_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Κλείδωμα συμπεριφοράς εξοπλισμού πριν από Φάση Γ.2β (EquipmentRepository).
void main() {
  group('EquipmentRepository behavior — lock πριν εξαγωγή', () {
    late DirectoryRepository repo;
    late Database db;
    late int userId;
    late int userId2;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir =
          await Directory.systemTemp.createTemp('equipment_repository_test_');
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/equipment_repo.db',
      );
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('user_equipment');
      await db.delete('calls');
      await db.delete('tasks');
      await db.delete('equipment');
      await db.delete('departments');
      await db.delete('users');
      userId = await db.insert('users', {
        'first_name': 'Κάτοχος',
        'last_name': 'Α',
        'is_deleted': 0,
      });
      userId2 = await db.insert('users', {
        'first_name': 'Κάτοχος',
        'last_name': 'Β',
        'is_deleted': 0,
      });
      repo = DirectoryRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Map<String, dynamic> equipmentRow(String code) => {
          'code_equipment': code,
          'is_deleted': 0,
        };

    Map<String, dynamic>? decodeJson(String? raw) {
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    }

    Future<int> insertDepartment(String name) async {
      return db.insert('departments', {
        'name': name,
        'name_key': SearchTextNormalizer.normalizeForSearch(name),
        'is_deleted': 0,
      });
    }

    test('getAllEquipment: μόνο ενεργά', () async {
      await db.insert('equipment', equipmentRow('PC-ACTIVE'));
      await db.insert('equipment', {
        'code_equipment': 'PC-DELETED',
        'is_deleted': 1,
      });

      final rows = await repo.getAllEquipment();
      expect(rows, hasLength(1));
      expect(rows.single['code_equipment'], 'PC-ACTIVE');
    });

    test('getEquipmentIdByCode / equipmentCodeExists', () async {
      final id = await db.insert('equipment', equipmentRow('PC-LOOKUP'));

      expect(await repo.getEquipmentIdByCode('PC-LOOKUP'), id);
      expect(await repo.getEquipmentIdByCode('  PC-LOOKUP  '), id);
      expect(await repo.equipmentCodeExists('PC-LOOKUP'), isTrue);
      expect(await repo.equipmentCodeExists('PC-MISSING'), isFalse);
    });

    test('insertEquipmentFromMap: νέος εξοπλισμός', () async {
      final id = await repo.insertEquipmentFromMap(equipmentRow('PC-NEW'));

      expect(id, greaterThan(0));
      final rows = await db.query('equipment', where: 'id = ?', whereArgs: [id]);
      expect(rows.single['code_equipment'], 'PC-NEW');
      expect(rows.single['is_deleted'], 0);
    });

    test(
      'updateEquipmentDepartment: δημιουργία αν λείπει + audit department',
      () async {
        final deptId = await insertDepartment('Τμήμα Εξοπλισμού');

        await repo.setSetting(
          DatabaseHelper.auditUserPerformingSettingsKey,
          'Editor Εξοπλισμού',
        );
        await db.delete('audit_log');

        await repo.updateEquipmentDepartment('PC-DEPT-CREATE', deptId);

        final rows = await db.query(
          'equipment',
          where: 'code_equipment = ?',
          whereArgs: ['PC-DEPT-CREATE'],
        );
        expect(rows, hasLength(1));
        expect(rows.single['department_id'], deptId);

        final auditRows = await db.query(
          'audit_log',
          where: 'entity_type = ? AND action = ?',
          whereArgs: [AuditEntityTypes.equipment, 'ΔΗΜΙΟΥΡΓΙΑ ΕΞΟΠΛΙΣΜΟΥ'],
        );
        expect(auditRows, hasLength(1));
        final newV = decodeJson(auditRows.single['new_values_json'] as String?);
        expect(newV?['department_id'], deptId);
        expect(newV?['department_text'], 'Τμήμα Εξοπλισμού');
      },
    );

    test(
      'updateEquipmentDepartment: υπάρχων — σωστό audit old/new department',
      () async {
        final oldDeptId = await insertDepartment('Παλιό Τμήμα');
        final newDeptId = await insertDepartment('Νέο Τμήμα');
        const code = 'PC-DEPT-UPDATE';

        final eqId = await db.insert('equipment', {
          'code_equipment': code,
          'department_id': oldDeptId,
          'is_deleted': 0,
        });

        await db.delete('audit_log');
        await repo.updateEquipmentDepartment(code, newDeptId);

        final row = await db.query('equipment', where: 'id = ?', whereArgs: [eqId]);
        expect(row.single['department_id'], newDeptId);

        final auditRows = await db.query(
          'audit_log',
          where: 'entity_id = ? AND action = ?',
          whereArgs: [eqId, 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΞΟΠΛΙΣΜΟΥ'],
        );
        expect(auditRows, hasLength(1));
        final oldV = decodeJson(auditRows.single['old_values_json'] as String?);
        final newV = decodeJson(auditRows.single['new_values_json'] as String?);
        expect(oldV?['department_id'], oldDeptId);
        expect(oldV?['department_text'], 'Παλιό Τμήμα');
        expect(newV?['department_id'], newDeptId);
        expect(newV?['department_text'], 'Νέο Τμήμα');
      },
    );

    test('clearEquipmentSharedDepartment', () async {
      final deptId = await insertDepartment('Κοινό Τμήμα');
      const code = 'PC-CLEAR-DEPT';
      final eqId = await db.insert('equipment', {
        'code_equipment': code,
        'department_id': deptId,
        'is_deleted': 0,
      });

      await db.delete('audit_log');
      await repo.clearEquipmentSharedDepartment(code, deptId);

      final row = await db.query('equipment', where: 'id = ?', whereArgs: [eqId]);
      expect(row.single['department_id'], isNull);

      final auditRows = await db.query(
        'audit_log',
        where: 'entity_id = ?',
        whereArgs: [eqId],
      );
      expect(auditRows, hasLength(1));
      expect(
        auditRows.single['details'],
        'equipment id=$eqId (αφαίρεση κοινόχρηστου τμήματος $deptId)',
      );
    });

    test('replaceEquipmentUsers: audit σύνδεσης/αποσύνδεσης χρηστών', () async {
      final eqId = await repo.insertEquipmentFromMap(equipmentRow('PC-REPLACE'));

      await db.delete('audit_log');
      await repo.replaceEquipmentUsers(eqId, [userId]);

      final linkAudit = await db.query(
        'audit_log',
        where: 'entity_id = ? AND details = ?',
        whereArgs: [
          eqId,
          'equipment id=$eqId (αντικατάσταση χρηστών)',
        ],
      );
      expect(linkAudit, hasLength(1));

      await db.delete('audit_log');
      await repo.replaceEquipmentUsers(eqId, []);

      final unlinkAudit = await db.query(
        'audit_log',
        where: 'entity_id = ? AND details = ?',
        whereArgs: [
          eqId,
          'equipment id=$eqId (αντικατάσταση χρηστών)',
        ],
      );
      expect(unlinkAudit, hasLength(1));

      expect(await db.query('user_equipment', where: 'equipment_id = ?', whereArgs: [eqId]),
          isEmpty);
    });

    test('copyUserEquipmentLinks', () async {
      final eqId = await repo.insertEquipmentFromMap(equipmentRow('PC-COPY'));
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': eqId,
      });

      await db.delete('audit_log');
      await repo.copyUserEquipmentLinks(userId, userId2);

      final links = await db.query(
        'user_equipment',
        where: 'user_id = ?',
        whereArgs: [userId2],
      );
      expect(links, hasLength(1));
      expect(links.single['equipment_id'], eqId);

      final userAudit = await db.query(
        'audit_log',
        where: 'entity_id = ? AND details = ?',
        whereArgs: [
          userId2,
          'users id=$userId2 (αντιγραφή συνδέσεων εξοπλισμού)',
        ],
      );
      expect(userAudit, hasLength(1));
    });

    test('countUsersLinkedToEquipment', () async {
      final eqId = await repo.insertEquipmentFromMap(equipmentRow('PC-COUNT'));
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': eqId,
      });
      await db.insert('user_equipment', {
        'user_id': userId2,
        'equipment_id': eqId,
      });

      expect(await repo.countUsersLinkedToEquipment(eqId), 2);
    });

    test('countEquipmentReferencesExcludingAudit', () async {
      const code = 'PC-REFS';
      final eqId = await db.insert('equipment', equipmentRow(code));
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': eqId,
      });
      await db.insert('calls', {
        'equipment_id': eqId,
        'is_deleted': 0,
      });

      expect(await repo.countEquipmentReferencesExcludingAudit(eqId), greaterThanOrEqualTo(2));
    });

    test('getEquipmentDefaultRemoteToolUsageCounts', () async {
      await db.insert('equipment', {
        'code_equipment': 'PC-TOOL-1',
        'default_remote_tool': '7',
        'is_deleted': 0,
      });
      await db.insert('equipment', {
        'code_equipment': 'PC-TOOL-2',
        'default_remote_tool': '7',
        'is_deleted': 0,
      });
      await db.insert('equipment', {
        'code_equipment': 'PC-TOOL-DELETED',
        'default_remote_tool': '7',
        'is_deleted': 1,
      });

      final counts = await repo.getEquipmentDefaultRemoteToolUsageCounts();
      expect(counts[7], 2);
    });

    test('deleteEquipments / restoreEquipment: is_deleted και audit', () async {
      final eqId = await repo.insertEquipmentFromMap(equipmentRow('PC-DELETE'));
      await repo.setSetting(
        DatabaseHelper.auditUserPerformingSettingsKey,
        'Admin Εξοπλισμού',
      );

      await db.delete('audit_log');
      await repo.deleteEquipments([eqId]);

      expect(
        (await db.query('equipment', where: 'id = ?', whereArgs: [eqId])).single['is_deleted'],
        1,
      );
      expect(
        await db.query(
          'audit_log',
          where: 'entity_id = ? AND action = ?',
          whereArgs: [eqId, DatabaseHelper.auditActionDelete],
        ),
        hasLength(1),
      );

      await db.delete('audit_log');
      await repo.restoreEquipment([eqId]);

      expect(
        (await db.query('equipment', where: 'id = ?', whereArgs: [eqId])).single['is_deleted'],
        0,
      );
      expect(
        await db.query(
          'audit_log',
          where: 'entity_id = ? AND action = ?',
          whereArgs: [eqId, DatabaseHelper.auditActionRestore],
        ),
        hasLength(1),
      );
    });

    test(
      'ατομικότητα: αποτυχία μέσα σε εξωτερική transaction κάνει rollback insertEquipmentFromMap',
      () async {
        const code = 'PC-ROLLBACK-LOCK';

        await expectLater(
          db.transaction((txn) async {
            await repo.insertEquipmentFromMap(
              equipmentRow(code),
              executor: txn,
            );
            throw StateError('προσομοίωση σφάλματος');
          }),
          throwsA(isA<StateError>()),
        );

        expect(
          await db.query('equipment', where: 'code_equipment = ?', whereArgs: [code]),
          isEmpty,
        );
      },
    );
  });
}
