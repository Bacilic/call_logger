import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/equipment_repository.dart';
import 'package:call_logger/core/database/phone_repository.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/audit/models/audit_log_model.dart';
import 'package:call_logger/features/audit/services/audit_formatter_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Φάση 2 audit: ενιαίο λεξιλόγιο, ετικέτες πεδίων, απόκρυψη θορύβου.
void main() {
  group('audit vocabulary — repository & migration', () {
    late Database db;
    late PhoneRepository phones;
    late UserRepository users;
    late EquipmentRepository equipment;
    const formatter = AuditFormatterService();

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('audit_vocab_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/audit_vocab.db');
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
      phones = PhoneRepository(db);
      users = UserRepository(db);
      equipment = EquipmentRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test(
      'σύνδεση τηλεφώνου σε τμήμα: ενέργεια ΤΡΟΠΟΠΟΙΗΣΗ ΤΗΛΕΦΩΝΟΥ',
      () async {
        final deptId = await db.insert('departments', {
          'name': 'Τμήμα Τηλεφώνου',
          'name_key':
              SearchTextNormalizer.normalizeForSearch('Τμήμα Τηλεφώνου'),
          'is_deleted': 0,
        });

        await db.delete('audit_log');

        await phones.updatePhoneDepartment('2109998877', deptId);

        final rows = await db.query('audit_log');
        expect(rows, hasLength(1));
        expect(rows.single['action'], AuditActions.modifyPhone);
        expect(rows.single['entity_type'], AuditEntityTypes.phone);
      },
    );

    test(
      'migration v34: μετονομάζει παλιά ΤΡΟΠΟΠΟΙΗΣΗ τηλεφώνου — idempotent',
      () async {
        final id = await db.insert('audit_log', {
          'action': 'ΤΡΟΠΟΠΟΙΗΣΗ',
          'timestamp': '2026-01-01T00:00:00.000',
          'user_performing': 'tester',
          'entity_type': AuditEntityTypes.phone,
          'entity_id': 1,
          'entity_name': '2101111111',
        });

        await migrateDatabaseToV34(db);
        final afterFirst = await db.query(
          'audit_log',
          where: 'id = ?',
          whereArgs: [id],
        );
        expect(afterFirst.single['action'], AuditActions.modifyPhone);

        await migrateDatabaseToV34(db);
        final afterSecond = await db.query(
          'audit_log',
          where: 'id = ?',
          whereArgs: [id],
        );
        expect(afterSecond.single['action'], AuditActions.modifyPhone);
      },
    );

    test(
      'is_deleted στο snapshot δεν εμφανίζεται σε «Τι άλλαξε» ούτε στο search_text',
      () async {
        final userId = await db.insert('users', {
          'first_name': 'Θόρυβος',
          'last_name': 'Audit',
          'is_deleted': 0,
        });

        await db.delete('audit_log');

        await users.updateUser(userId, {
          'first_name': 'Καθαρό',
          'is_deleted': 0,
        });

        final row = AuditLogModel(
          id: 1,
          action: AuditActions.modifyUser,
          entityType: AuditEntityTypes.user,
          oldValuesJson: (await db.query('audit_log')).single['old_values_json']
              as String?,
          newValuesJson: (await db.query('audit_log')).single['new_values_json']
              as String?,
        );

        final lines = formatter.describeChanges(row);
        expect(lines.any((l) => l.contains('is_deleted')), isFalse);
        expect(lines.any((l) => l.toLowerCase().contains('διαγραμμέ')), isFalse);

        final searchText =
            (await db.query('audit_log')).single['search_text'] as String?;
        expect(searchText ?? '', isNot(contains('is_deleted')));
      },
    );

    test(
      'αλλαγή remote_params εξοπλισμού: μία γραμμή «Αλλαγή παραμέτρων»',
      () async {
        final eqId = await db.insert('equipment', {
          'code_equipment': 'EQ-REMOTE',
          'remote_params': jsonEncode({'2': '10.0.0.1'}),
          'default_remote_tool': '2',
          'is_deleted': 0,
        });

        await db.delete('audit_log');

        await equipment.updateEquipment(eqId, {
          'remote_params': jsonEncode({'2': '10.0.0.99'}),
          'default_remote_tool': null,
        });

        final auditRow = (await db.query('audit_log')).single;
        expect(auditRow['action'], AuditActions.modifyEquipment);

        final model = AuditLogModel(
          id: auditRow['id'] as int,
          action: auditRow['action'] as String?,
          entityType: auditRow['entity_type'] as String?,
          oldValuesJson: auditRow['old_values_json'] as String?,
          newValuesJson: auditRow['new_values_json'] as String?,
        );
        final lines = formatter.describeChanges(model);
        expect(lines, hasLength(1));
        expect(lines.single, contains('Αλλαγή'));
        expect(lines.single.toLowerCase(), contains('παραμέτρ'));
        expect(
          lines.where((l) => l.startsWith('Αφαίρεση') || l.startsWith('Προσθήκη')),
          isEmpty,
        );
      },
    );

    test(
      'ετικέτα map_label_offset_x — όχι γυμνό όνομα πεδίου',
      () async {
        final row = AuditLogModel(
          id: 1,
          action: AuditActions.modifyDepartment,
          entityType: AuditEntityTypes.department,
          oldValuesJson: '{"map_label_offset_x":0.0}',
          newValuesJson: '{"map_label_offset_x":12.5}',
        );
        final lines = formatter.describeChanges(row);
        expect(lines, hasLength(1));
        expect(lines.single, isNot(contains('map_label_offset_x')));
        expect(lines.single.toLowerCase(), contains('μετατόπιση'));
      },
    );

    test(
      'δίδυμο όροφος map_floor + floor_id: μία γραμμή στο «Τι άλλαξε»',
      () async {
        final row = AuditLogModel(
          id: 2,
          action: AuditActions.modifyDepartment,
          entityType: AuditEntityTypes.department,
          oldValuesJson: '{"map_floor":null,"floor_id":null}',
          newValuesJson: '{"map_floor":"2","floor_id":2}',
        );
        final lines = formatter.describeChanges(row);
        expect(lines, hasLength(1));
        expect(lines.single, contains('όροφο'));
        expect(lines.single, contains('2'));
      },
    );

    test(
      'ΕΠΙΔΙΟΡΘΩΣΗ ΑΚΕΡΑΙΟΤΗΤΑΣ: χωρίς γραμμή integrity_fix',
      () async {
        final row = AuditLogModel(
          id: 3,
          action: DatabaseHelper.auditActionIntegrityFix,
          entityType: AuditEntityTypes.maintenance,
          newValuesJson: '{"integrity_fix":true}',
        );
        final lines = formatter.describeChanges(row);
        expect(lines, isEmpty);
      },
    );
  });
}
