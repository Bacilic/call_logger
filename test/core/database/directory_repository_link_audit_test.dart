import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/core/database/audit_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Κλείδωμα συμπεριφοράς audit σύνδεσης/αποσύνδεσης τηλεφώνων και εξοπλισμού
/// (μέσω `auditPhoneUserLinkDeltaInTxn` / `auditEquipmentUserLinkDeltaInTxn`).
///
/// Από 13/07/2026 οι σύνδεσεις ενσωματώνονται ως ονομαστικές γραμμές στα
/// `details` της εγγραφής χρήστη — όχι ως ξεχωριστό audit στο entity phone/equipment.
void main() {
  group('DirectoryRepository user↔entity link audit — lock', () {
    late UserRepository repo;
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
      repo = UserRepository(db);
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

    /// Ονομαστική γραμμή delta όπως την παράγει `_userEntityLinkDetailLine`.
    String linkDetailLine({
      required String entityType,
      required String label,
      required bool isLink,
    }) {
      if (entityType == AuditEntityTypes.phone) {
        return isLink
            ? 'Προσθήκη τηλεφώνου $label'
            : 'Αποσύνδεση τηλεφώνου $label';
      }
      if (entityType == AuditEntityTypes.equipment) {
        return isLink
            ? 'Προσθήκη εξοπλισμού $label'
            : 'Αποσύνδεση εξοπλισμού $label';
      }
      throw ArgumentError('unsupported entityType: $entityType');
    }

    /// Βρίσκει την εγγραφή audit χρήστη που περιέχει τη γραμμή σύνδεσης/αποσύνδεσης.
    Future<Map<String, dynamic>> findLinkDeltaAudit({
      required int userId,
      required String entityType,
      required String label,
      required bool isLink,
    }) async {
      final line = linkDetailLine(
        entityType: entityType,
        label: label,
        isLink: isLink,
      );
      final rows = await db.query(
        'audit_log',
        where: 'entity_type = ? AND entity_id = ? AND details LIKE ?',
        whereArgs: [AuditEntityTypes.user, userId, '%$line%'],
      );
      expect(
        rows,
        hasLength(1),
        reason: 'αναμενόταν μία γραμμή χρήστη με: $line',
      );
      return rows.single;
    }

    test('phone σύνδεση: insertUser γράφει audit delta', () async {
      const phoneNumber = '2345888801';

      final userId = await repo.insertUser(
        firstName: 'Σύνδεση',
        lastName: 'Τηλεφώνου',
        phones: [phoneNumber],
        skipPhonePolicyValidation: true,
      );

      final row = await findLinkDeltaAudit(
        userId: userId,
        entityType: AuditEntityTypes.phone,
        label: phoneNumber,
        isLink: true,
      );
      expect(row['action'], 'ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ');
      expect(row['entity_name'], 'Σύνδεση Τηλεφώνου');
      final newV = decodeJson(row['new_values_json'] as String?);
      expect(newV?['linked_phone_numbers'], [phoneNumber]);
    });

    test(
      'phone αποσύνδεση: updateUser με κενά phones γράφει audit delta',
      () async {
        const phoneNumber = '2345888802';

        final userId = await repo.insertUser(
          firstName: 'Αποσύνδεση',
          lastName: 'Τηλεφώνου',
          phones: [phoneNumber],
          skipPhonePolicyValidation: true,
        );

        await db.delete('audit_log');

        await repo.updateUser(userId, {
          'phones': <String>[],
        }, skipPhonePolicyValidation: true);

        final row = await findLinkDeltaAudit(
          userId: userId,
          entityType: AuditEntityTypes.phone,
          label: phoneNumber,
          isLink: false,
        );
        expect(row['action'], AuditActions.modifyUser);
        final oldV = decodeJson(row['old_values_json'] as String?);
        final newV = decodeJson(row['new_values_json'] as String?);
        expect(oldV?['linked_phone_numbers'], [phoneNumber]);
        expect(newV?['linked_phone_numbers'], <String>[]);
      },
    );

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
        userId: userId,
        entityType: AuditEntityTypes.equipment,
        label: code,
        isLink: false,
      );
      expect(row['action'], DatabaseHelper.auditActionDelete);
      expect(row['entity_name'], 'Αποσύνδεση Εξοπλισμού');
    });

    test(
      'equipment σύνδεση: added-branch μέσω updateUser phones (ίδια λογική helper)',
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

        await repo.updateUser(userId, {
          'phones': [existingPhone, newPhone],
        }, skipPhonePolicyValidation: true);

        final row = await findLinkDeltaAudit(
          userId: userId,
          entityType: AuditEntityTypes.phone,
          label: newPhone,
          isLink: true,
        );
        expect(row['action'], AuditActions.modifyUser);
        final newV = decodeJson(row['new_values_json'] as String?);
        expect(newV?['linked_phone_numbers'], [existingPhone, newPhone]);
      },
    );

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
        userId: userId,
        entityType: AuditEntityTypes.equipment,
        label: '#$equipmentId',
        isLink: false,
      );
      expect(row['entity_name'], 'Fallback Ετικέτας');
      expect(row['details'], contains('Αποσύνδεση εξοπλισμού #$equipmentId'));
    });
  });
}
