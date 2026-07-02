import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/phone_repository.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Κλείδωμα συμπεριφοράς κοινών βοηθών DirectorySupport πριν από Φάση Γ.0.
void main() {
  group('DirectorySupport helpers — lock πριν εξαγωγή', () {
    late UserRepository users;
    late PhoneRepository phones;
    late SettingsRepository settings;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir =
          await Directory.systemTemp.createTemp('support_extraction_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/support_extract.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('department_phones');
      await db.delete('phones');
      await db.delete('equipment');
      await db.delete('users');
      await db.delete('departments');
      users = UserRepository(db);
      phones = PhoneRepository(db);
      settings = SettingsRepository(db);
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

    Future<int> insertDepartment(String name) async {
      return db.insert('departments', {
        'name': name,
        'name_key': SearchTextNormalizer.normalizeForSearch(name),
        'is_deleted': 0,
      });
    }

    test('audit performing user: setSetting + ενέργεια audit → σωστό user_performing',
        () async {
      const performer = 'Χρήστης Δοκιμής Audit';
      await settings.saveSetting(
        DatabaseHelper.auditUserPerformingSettingsKey,
        performer,
      );

      const phoneNumber = '2345999901';
      final userId = await users.insertUser(
        firstName: 'Audit',
        lastName: 'Performer',
        phones: [phoneNumber],
        skipPhonePolicyValidation: true,
      );

      final rows = await db.query(
        'audit_log',
        where: 'user_performing = ?',
        whereArgs: [performer],
      );
      expect(rows, isNotEmpty);
      expect(
        rows.any((r) => r['entity_type'] == AuditEntityTypes.user),
        isTrue,
        reason: 'αναμενόταν audit εγγραφής χρήστη με σωστό user_performing',
      );

      await db.delete('audit_log');
      await users.updateUser(
        userId,
        {'notes': 'δοκιμή'},
        skipPhonePolicyValidation: true,
      );

      final updateRows = await db.query(
        'audit_log',
        where: 'user_performing = ? AND action = ?',
        whereArgs: [performer, 'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ'],
      );
      expect(updateRows, hasLength(1));
      expect(updateRows.single['entity_id'], userId);
    });

    test(
      'replaceUserPhones: υπάρχων + νέος αριθμός → χωρίς διπλότυπο phones',
      () async {
        const existingNumber = '2345999902';
        const newNumber = '2345999903';

        final existingPhoneId = await db.insert('phones', {
          'number': existingNumber,
          'is_deleted': 0,
        });
        final userId = await db.insert('users', {
          'first_name': 'Replace',
          'last_name': 'Phones',
          'is_deleted': 0,
        });

        await users.replaceUserPhones(userId, [existingNumber, newNumber]);

        final phonesForExisting = await db.query(
          'phones',
          where: 'number = ?',
          whereArgs: [existingNumber],
        );
        expect(phonesForExisting, hasLength(1));
        expect(phonesForExisting.single['id'], existingPhoneId);

        final phonesForNew = await db.query(
          'phones',
          where: 'number = ?',
          whereArgs: [newNumber],
        );
        expect(phonesForNew, hasLength(1));

        final links = await db.query(
          'user_phones',
          where: 'user_id = ?',
          whereArgs: [userId],
        );
        expect(links, hasLength(2));
      },
    );

    test('link-delta audit: σύνδεση τηλεφώνου μέσω insertUser', () async {
      const phoneNumber = '2345999904';

      final userId = await users.insertUser(
        firstName: 'Link',
        lastName: 'Phone',
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

      final rows = await db.query(
        'audit_log',
        where:
            'action = ? AND entity_type = ? AND entity_id = ? AND details = ?',
        whereArgs: [
          'ΤΡΟΠΟΠΟΙΗΣΗ',
          AuditEntityTypes.phone,
          phoneId,
          'phones id=$phoneId (σύνδεση χρήστη)',
        ],
      );
      expect(rows, hasLength(1));
      final oldV = decodeJson(rows.single['old_values_json'] as String?);
      final newV = decodeJson(rows.single['new_values_json'] as String?);
      expect(oldV, {'linked_user_id': null});
      expect(newV, {'linked_user_id': userId});
    });

    test('link-delta audit: αποσύνδεση εξοπλισμού μέσω deleteUsers', () async {
      const code = 'PC-SUPPORT-UNLINK';

      final equipmentId = await db.insert('equipment', {
        'code_equipment': code,
        'is_deleted': 0,
      });
      final userId = await db.insert('users', {
        'first_name': 'Unlink',
        'last_name': 'Equipment',
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': equipmentId,
      });

      await db.delete('audit_log');
      await users.deleteUsers([userId]);

      final rows = await db.query(
        'audit_log',
        where:
            'action = ? AND entity_type = ? AND entity_id = ? AND details = ?',
        whereArgs: [
          'ΤΡΟΠΟΠΟΙΗΣΗ',
          AuditEntityTypes.equipment,
          equipmentId,
          'equipment id=$equipmentId (αποσύνδεση χρήστη)',
        ],
      );
      expect(rows, hasLength(1));
      expect(rows.single['entity_name'], code);
      final oldV = decodeJson(rows.single['old_values_json'] as String?);
      final newV = decodeJson(rows.single['new_values_json'] as String?);
      expect(oldV, {'linked_user_id': userId});
      expect(newV, {'linked_user_id': null});
    });

    test(
      'department audit snapshot: updatePhoneDepartment → σωστά old/new department',
      () async {
        const phoneNumber = '2310999905';
        final oldDeptId = await insertDepartment('Παλιό Τμήμα Snapshot');
        final newDeptId = await insertDepartment('Νέο Τμήμα Snapshot');

        final phoneId = await db.insert('phones', {
          'number': phoneNumber,
          'department_id': oldDeptId,
          'is_deleted': 0,
        });
        await db.insert('department_phones', {
          'department_id': oldDeptId,
          'phone_id': phoneId,
        });

        await db.delete('audit_log');
        await phones.updatePhoneDepartment(phoneNumber, newDeptId);

        final rows = await db.query(
          'audit_log',
          where: 'entity_type = ? AND entity_id = ? AND action = ?',
          whereArgs: [AuditEntityTypes.phone, phoneId, 'ΤΡΟΠΟΠΟΙΗΣΗ'],
        );
        expect(rows, hasLength(1));

        final oldV = decodeJson(rows.single['old_values_json'] as String?);
        final newV = decodeJson(rows.single['new_values_json'] as String?);
        expect(oldV?['department_id'], oldDeptId);
        expect(oldV?['department_text'], 'Παλιό Τμήμα Snapshot');
        expect(newV?['department_id'], newDeptId);
        expect(newV?['department_text'], 'Νέο Τμήμα Snapshot');
      },
    );
  });
}
