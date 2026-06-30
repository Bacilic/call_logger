import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_repository.dart';
import 'package:call_logger/core/services/audit_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Κλείδωμα συμπεριφοράς audit σύνδεσης/αποσύνδεσης τηλεφώνων και εξοπλισμού
/// (μέσω `_auditPhoneUserLinkDeltaInTxn` / `_auditEquipmentUserLinkDeltaInTxn`).
void main() {
  group('DirectoryRepository user↔entity link audit — lock', () {
    late DirectoryRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('link_audit_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/link_audit.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('phones');
      await db.delete('equipment');
      await db.delete('users');
      repo = DirectoryRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Map<String, dynamic>? decodeJson(String? raw) {
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    }

    Future<Map<String, dynamic>?> findLinkDeltaAudit({
      required String entityWord,
      required String entityType,
      required int entityId,
      required bool isLink,
    }) async {
      final op = isLink ? 'σύνδεση' : 'αποσύνδεση';
      final expectedDetails = '$entityWord id=$entityId ($op χρήστη)';
      final rows = await db.query(
        'audit_log',
        where:
            'action = ? AND entity_type = ? AND entity_id = ? AND details = ?',
        whereArgs: ['ΤΡΟΠΟΠΟΙΗΣΗ', entityType, entityId, expectedDetails],
      );
      expect(rows, hasLength(1), reason: 'αναμενόταν μία γραμμή: $expectedDetails');
      return rows.single;
    }

    void expectLinkDeltaValues({
      required Map<String, dynamic> row,
      required int userId,
      required bool isLink,
      required String entityName,
    }) {
      expect(row['entity_name'], entityName);
      final oldV = decodeJson(row['old_values_json'] as String?);
      final newV = decodeJson(row['new_values_json'] as String?);
      if (isLink) {
        expect(oldV, {'linked_user_id': null});
        expect(newV, {'linked_user_id': userId});
      } else {
        expect(oldV, {'linked_user_id': userId});
        expect(newV, {'linked_user_id': null});
      }
    }

    test('phone σύνδεση: insertUser γράφει audit delta', () async {
      const phoneNumber = '2345888801';

      final userId = await repo.insertUser(
        firstName: 'Σύνδεση',
        lastName: 'Τηλεφώνου',
        phones: [phoneNumber],
        skipPhonePolicyValidation: true,
      );

      final phoneId = (await db.query(
        'phones',
        columns: ['id'],
        where: 'number = ?',
        whereArgs: [phoneNumber],
      ))
          .single['id'] as int;

      final row = await findLinkDeltaAudit(
        entityWord: 'phones',
        entityType: AuditEntityTypes.phone,
        entityId: phoneId,
        isLink: true,
      );
      expectLinkDeltaValues(
        row: row!,
        userId: userId,
        isLink: true,
        entityName: phoneNumber,
      );
    });

    test('phone αποσύνδεση: updateUser με κενά phones γράφει audit delta', () async {
      const phoneNumber = '2345888802';

      final userId = await repo.insertUser(
        firstName: 'Αποσύνδεση',
        lastName: 'Τηλεφώνου',
        phones: [phoneNumber],
        skipPhonePolicyValidation: true,
      );

      final phoneId = (await db.query(
        'phones',
        columns: ['id'],
        where: 'number = ?',
        whereArgs: [phoneNumber],
      ))
          .single['id'] as int;

      await db.delete('audit_log');

      await repo.updateUser(
        userId,
        {'phones': <String>[]},
        skipPhonePolicyValidation: true,
      );

      final row = await findLinkDeltaAudit(
        entityWord: 'phones',
        entityType: AuditEntityTypes.phone,
        entityId: phoneId,
        isLink: false,
      );
      expectLinkDeltaValues(
        row: row!,
        userId: userId,
        isLink: false,
        entityName: phoneNumber,
      );
    });

    test('equipment αποσύνδεση: deleteUsers γράφει audit delta', () async {
      const code = 'PC-UNLINK-AUDIT';

      final equipmentId = await db.insert('equipment', {
        'code_equipment': code,
        'is_deleted': 0,
      });
      final userId = await db.insert('users', {
        'first_name': 'Αποσύνδεση',
        'last_name': 'Εξοπλισμού',
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': equipmentId,
      });

      await db.delete('audit_log');

      await repo.deleteUsers([userId]);

      final row = await findLinkDeltaAudit(
        entityWord: 'equipment',
        entityType: AuditEntityTypes.equipment,
        entityId: equipmentId,
        isLink: false,
      );
      expectLinkDeltaValues(
        row: row!,
        userId: userId,
        isLink: false,
        entityName: code,
      );
    });

    test('equipment σύνδεση: added-branch μέσω updateUser phones (ίδια λογική helper)',
        () async {
      // `_auditEquipmentUserLinkDeltaInTxn` δεν καλείται από δημόσιο API για σύνδεση·
      // το added-branch κλειδώνεται μέσω phone updateUser (κοινός κώδικας helper).
      const existingPhone = '2345888804';
      const newPhone = '2345888805';

      final userId = await repo.insertUser(
        firstName: 'Δεύτερο',
        lastName: 'Τηλέφωνο',
        phones: [existingPhone],
        skipPhonePolicyValidation: true,
      );

      await db.delete('audit_log');

      await repo.updateUser(
        userId,
        {'phones': [existingPhone, newPhone]},
        skipPhonePolicyValidation: true,
      );

      final newPhoneId = (await db.query(
        'phones',
        columns: ['id'],
        where: 'number = ?',
        whereArgs: [newPhone],
      ))
          .single['id'] as int;

      final row = await findLinkDeltaAudit(
        entityWord: 'phones',
        entityType: AuditEntityTypes.phone,
        entityId: newPhoneId,
        isLink: true,
      );
      expectLinkDeltaValues(
        row: row!,
        userId: userId,
        isLink: true,
        entityName: newPhone,
      );
    });

    test('entityName fallback #id όταν λείπει ετικέτα στη βάση', () async {
      final equipmentId = await db.insert('equipment', {
        'code_equipment': null,
        'is_deleted': 0,
      });
      final userId = await db.insert('users', {
        'first_name': 'Fallback',
        'last_name': 'Ετικέτας',
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': equipmentId,
      });

      await db.delete('audit_log');
      await repo.deleteUsers([userId]);

      final row = await findLinkDeltaAudit(
        entityWord: 'equipment',
        entityType: AuditEntityTypes.equipment,
        entityId: equipmentId,
        isLink: false,
      );
      expect(row!['entity_name'], '#$equipmentId');
    });
  });
}
