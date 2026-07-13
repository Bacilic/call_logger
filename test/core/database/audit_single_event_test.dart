import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/department_repository.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Φάση 1 audit: ένα γεγονός = μία εγγραφή (χρήστης↔τηλέφωνο/εξοπλισμός, τμήμα).
void main() {
  group('audit single event — repository write path', () {
    late Database db;
    late UserRepository users;
    late DepartmentRepository departments;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('audit_single_event_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/audit_single.db');
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
      await db.delete('departments');
      users = UserRepository(db);
      departments = DepartmentRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<List<Map<String, dynamic>>> allAuditRows() =>
        db.query('audit_log', orderBy: 'id ASC');

    Map<String, dynamic>? decodeJson(String? raw) {
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    }

    test(
      'updateUser με νέο τηλέφωνο: μία εγγραφή audit (χρήστης), όχι ΤΡΟΠΟΠΟΙΗΣΗ τηλεφώνου',
      () async {
        const existingPhone = '2101111111';
        const newPhone = '2102222222';

        final userId = await users.insertUser(
          firstName: 'Έλεγχος',
          lastName: 'Audit',
          phones: [existingPhone],
          skipPhonePolicyValidation: true,
        );

        await db.delete('audit_log');

        await users.updateUser(
          userId,
          {'phones': [existingPhone, newPhone]},
          skipPhonePolicyValidation: true,
        );

        final rows = await allAuditRows();
        expect(rows, hasLength(1));
        expect(rows.single['entity_type'], AuditEntityTypes.user);
        expect(rows.single['action'], 'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ');

        final phoneEntityAudits = await db.query(
          'audit_log',
          where: 'entity_type = ? AND action = ?',
          whereArgs: [AuditEntityTypes.phone, 'ΤΡΟΠΟΠΟΙΗΣΗ'],
        );
        expect(phoneEntityAudits, isEmpty);

        final details = rows.single['details'] as String? ?? '';
        expect(details, contains(newPhone));
      },
    );

    test(
      'σύνδεση εξοπλισμού σε χρήστη: μία εγγραφή audit (χρήστης), όχι ΤΡΟΠΟΠΟΙΗΣΗ εξοπλισμού',
      () async {
        const code = '5068';

        final userId = await db.insert('users', {
          'first_name': 'Σύνδεση',
          'last_name': 'Εξοπλισμού',
          'is_deleted': 0,
        });

        await db.delete('audit_log');

        await users.updateAssociationsIfNeeded(userId, null, code);

        final rows = await allAuditRows();
        expect(rows, hasLength(1));
        expect(rows.single['entity_type'], AuditEntityTypes.user);

        final equipmentEntityAudits = await db.query(
          'audit_log',
          where: 'entity_type = ? AND action = ?',
          whereArgs: [AuditEntityTypes.equipment, 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΞΟΠΛΙΣΜΟΥ'],
        );
        expect(equipmentEntityAudits, isEmpty);

        final details = rows.single['details'] as String? ?? '';
        expect(details, contains(code));
      },
    );

    test(
      'αποσύνδεση εξοπλισμού από χρήστη (deleteUsers): μία εγγραφή, όχi ΤΡΟΠΟΠΟΙΗΣΗ εξοπλισμού',
      () async {
        const code = '5069';

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

        await users.deleteUsers([userId]);

        final rows = await allAuditRows();
        expect(rows, hasLength(1));
        expect(rows.single['entity_type'], AuditEntityTypes.user);
        expect(rows.single['action'], DatabaseHelper.auditActionDelete);

        final equipmentEntityAudits = await db.query(
          'audit_log',
          where: 'entity_type = ?',
          whereArgs: [AuditEntityTypes.equipment],
        );
        expect(equipmentEntityAudits, isEmpty);

        final details = rows.single['details'] as String? ?? '';
        expect(details, contains(code));
      },
    );

    test(
      'updateDepartment ταυτόχρονα χρώμα + θέση: μία εγγραφή, old/new μόνο τα πεδία που άλλαξαν',
      () async {
        final deptId = await db.insert('departments', {
          'name': 'Τμήμα Audit',
          'name_key': SearchTextNormalizer.normalizeForSearch('Τμήμα Audit'),
          'color': '#1976D2',
          'map_x': 10.0,
          'map_y': 20.0,
          'is_deleted': 0,
        });

        await db.delete('audit_log');

        await departments.updateDepartment(deptId, {
          'color': '#33691E',
          'map_x': 50.0,
        });

        final rows = await allAuditRows();
        expect(rows, hasLength(1));
        expect(rows.single['entity_type'], AuditEntityTypes.department);
        expect(rows.single['action'], 'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ');

        final oldV = decodeJson(rows.single['old_values_json'] as String?);
        final newV = decodeJson(rows.single['new_values_json'] as String?);
        expect(oldV, isNotNull);
        expect(newV, isNotNull);
        expect(oldV!.keys.toSet(), {'color', 'map_x'});
        expect(newV!.keys.toSet(), {'color', 'map_x'});
        expect(oldV['color'], '#1976D2');
        expect(newV['color'], '#33691E');
        expect(oldV['map_x'], 10.0);
        expect(newV['map_x'], 50.0);
      },
    );

    test(
      'saveDepartmentWithFloorContext: μία εγγραφή audit ανά αποθήκευση',
      () async {
        final deptId = await db.insert('departments', {
          'name': 'Τμήμα Χάρτη',
          'name_key': SearchTextNormalizer.normalizeForSearch('Τμήμα Χάρτη'),
          'color': '#1976D2',
          'map_x': 0.0,
          'map_y': 0.0,
          'is_deleted': 0,
        });

        await db.delete('audit_log');

        await departments.saveDepartmentWithFloorContext(
          deptId,
          {
            'color': '#EF5350',
            'map_x': 100.0,
          },
          drawingFloorId: 3,
        );

        final rows = await allAuditRows();
        expect(rows, hasLength(1));

        final oldV = decodeJson(rows.single['old_values_json'] as String?);
        final newV = decodeJson(rows.single['new_values_json'] as String?);
        expect(oldV, isNotNull);
        expect(newV, isNotNull);
        expect(oldV!.containsKey('map_y'), isFalse);
        expect(newV!.containsKey('map_y'), isFalse);
        expect(oldV.containsKey('color'), isTrue);
        expect(oldV.containsKey('map_x'), isTrue);
      },
    );
  });
}
