import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/audit/models/audit_log_model.dart';
import 'package:call_logger/features/audit/services/audit_formatter_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Φάση 4 audit: αναδρομικός καθαρισμός ιστορικού audit (migration v35).
void main() {
  group('audit history cleanup migration v35', () {
    late Database db;
    late AuditService auditService;
    const formatter = AuditFormatterService();
    const ts = '2026-01-15T10:00:00.000';
    const tsLater = '2026-01-15T10:00:01.000';
    const tsFar = '2026-01-15T10:00:05.000';

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir =
          await Directory.systemTemp.createTemp('audit_history_cleanup_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/audit_v35.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      auditService = AuditService(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<void> runMigration() => migrateDatabaseToV35(db);

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
      '(a) δύο τροποποιήσεις τμήματος ίδιο entity/timestamp → μία εγγραφή',
      () async {
        const deptId = 42;
        const fullOld = {
          'name': 'Τμήμα Α',
          'color': '#1976D2',
          'map_x': 0.0,
          'map_y': 0.0,
        };
        const mid = {
          'name': 'Τμήμα Α',
          'color': '#EF5350',
          'map_x': 0.0,
          'map_y': 0.0,
        };
        const fullNew = {
          'name': 'Τμήμα Α',
          'color': '#EF5350',
          'map_x': 50.0,
          'map_y': 0.0,
        };

        await db.insert('audit_log', {
          'action': AuditActions.modifyDepartment,
          'timestamp': ts,
          'user_performing': 'tester',
          'entity_type': AuditEntityTypes.department,
          'entity_id': deptId,
          'entity_name': 'Τμήμα Α',
          'details': 'departments id=$deptId',
          'old_values_json': jsonEncode(fullOld),
          'new_values_json': jsonEncode(mid),
        });
        await db.insert('audit_log', {
          'action': AuditActions.modifyDepartment,
          'timestamp': ts,
          'user_performing': 'tester',
          'entity_type': AuditEntityTypes.department,
          'entity_id': deptId,
          'entity_name': 'Τμήμα Α',
          'details': 'departments id=$deptId',
          'old_values_json': jsonEncode(mid),
          'new_values_json': jsonEncode(fullNew),
        });

        await runMigration();

        final allRows = await db.query('audit_log');
        expect(allRows, hasLength(2)); // 1 τμήμα + 1 maintenance

        final rows = await db.query(
          'audit_log',
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: [AuditEntityTypes.department, deptId],
        );
        expect(rows, hasLength(1));

        final deptRows = rows;

        final merged = deptRows.single;
        final oldDiff = decodeJson(merged['old_values_json'] as String?);
        final newDiff = decodeJson(merged['new_values_json'] as String?);
        expect(oldDiff?['color'], '#1976D2');
        expect(newDiff?['color'], '#EF5350');
        expect(oldDiff?['map_x'], 0.0);
        expect(newDiff?['map_x'], 50.0);

        final details = merged['details'] as String? ?? '';
        expect(details, contains('2 αλλαγές'));
        expect(details, contains('χρώμα'));
        expect(details, contains('θέση'));
      },
    );

    test(
      '(b) χρήστης + τηλέφωνο ίδιο δευτερόλεπτο → διαγραφή πλευράς τηλεφώνου',
      () async {
        const userId = 7;
        const phoneId = 99;
        const phoneNumber = '2105554433';

        await db.insert('audit_log', {
          'action': AuditActions.modifyUser,
          'timestamp': ts,
          'user_performing': 'tester',
          'entity_type': AuditEntityTypes.user,
          'entity_id': userId,
          'entity_name': 'Δοκιμή Χρήστης',
          'details': 'users id=$userId · Προσθήκη τηλεφώνου $phoneNumber',
          'old_values_json': jsonEncode({
            'linked_phone_numbers': <String>[],
          }),
          'new_values_json': jsonEncode({
            'linked_phone_numbers': [phoneNumber],
          }),
        });
        await db.insert('audit_log', {
          'action': AuditActions.modifyPhone,
          'timestamp': ts,
          'user_performing': 'tester',
          'entity_type': AuditEntityTypes.phone,
          'entity_id': phoneId,
          'entity_name': phoneNumber,
          'details': 'phones id=$phoneId (σύνδεση χρήστη)',
          'old_values_json': jsonEncode({'linked_user_id': null}),
          'new_values_json': jsonEncode({'linked_user_id': userId}),
        });

        await runMigration();

        final phoneRows = await db.query(
          'audit_log',
          where: 'entity_type = ?',
          whereArgs: [AuditEntityTypes.phone],
        );
        expect(phoneRows, isEmpty);

        final userRows = await db.query(
          'audit_log',
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: [AuditEntityTypes.user, userId],
        );
        expect(userRows, hasLength(1));
        final details = userRows.single['details'] as String? ?? '';
        expect(details, contains('Προσθήκη τηλεφώνου'));
        expect(details, contains('σύνδεση χρήστη'));
      },
    );

    test(
      '(c) εξοπλισμός Remove+Add remote_params → μία γραμμή αλλαγής',
      () async {
        const eqId = 12;
        const oldParams = {'2': '10.0.0.1'};
        const newParams = {'2': '10.0.0.99'};

        await db.insert('audit_log', {
          'action': AuditActions.modifyEquipment,
          'timestamp': ts,
          'user_performing': 'tester',
          'entity_type': AuditEntityTypes.equipment,
          'entity_id': eqId,
          'entity_name': 'EQ-001',
          'details': 'equipment id=$eqId',
          'old_values_json': jsonEncode({'remote_params': oldParams}),
          'new_values_json': jsonEncode({'remote_params': null}),
        });
        await db.insert('audit_log', {
          'action': AuditActions.modifyEquipment,
          'timestamp': tsLater,
          'user_performing': 'tester',
          'entity_type': AuditEntityTypes.equipment,
          'entity_id': eqId,
          'entity_name': 'EQ-001',
          'details': 'equipment id=$eqId',
          'old_values_json': jsonEncode({'remote_params': null}),
          'new_values_json': jsonEncode({'remote_params': newParams}),
        });

        await runMigration();

        final eqRows = await db.query(
          'audit_log',
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: [AuditEntityTypes.equipment, eqId],
        );
        expect(eqRows, hasLength(1));

        final row = AuditLogModel(
          id: eqRows.single['id'] as int,
          action: eqRows.single['action'] as String?,
          entityType: eqRows.single['entity_type'] as String?,
          oldValuesJson: eqRows.single['old_values_json'] as String?,
          newValuesJson: eqRows.single['new_values_json'] as String?,
        );
        final lines = formatter.describeChanges(row);
        expect(lines, hasLength(1));
        expect(lines.single, contains('Αλλαγή'));
        expect(lines.single.toLowerCase(), contains('παραμέτρ'));
      },
    );

    test('idempotency: δεύτερη εκτέλεση δεν αλλάζει τίποτα', () async {
      await db.insert('audit_log', {
        'action': AuditActions.modifyDepartment,
        'timestamp': ts,
        'user_performing': 'tester',
        'entity_type': AuditEntityTypes.department,
        'entity_id': 1,
        'old_values_json': jsonEncode({'color': '#1976D2'}),
        'new_values_json': jsonEncode({'color': '#EF5350'}),
      });

      await runMigration();
      final afterFirst = await db.query('audit_log');
      final countFirst = afterFirst.length;

      await runMigration();
      final afterSecond = await db.query('audit_log');
      expect(afterSecond.length, countFirst);
    });

    test('maintenance row: καταγράφει merged/deleted counts', () async {
      const deptId = 5;
      await db.insert('audit_log', {
        'action': AuditActions.modifyDepartment,
        'timestamp': ts,
        'user_performing': 'tester',
        'entity_type': AuditEntityTypes.department,
        'entity_id': deptId,
        'old_values_json': jsonEncode({'color': '#1976D2'}),
        'new_values_json': jsonEncode({'color': '#EF5350'}),
      });
      await db.insert('audit_log', {
        'action': AuditActions.modifyDepartment,
        'timestamp': ts,
        'user_performing': 'tester',
        'entity_type': AuditEntityTypes.department,
        'entity_id': deptId,
        'old_values_json': jsonEncode({'color': '#EF5350'}),
        'new_values_json': jsonEncode({'color': '#4CAF50'}),
      });

      await runMigration();

      final maintenance = await db.query(
        'audit_log',
        where: 'entity_type = ? AND details = ?',
        whereArgs: [AuditEntityTypes.maintenance, 'auditHistoryCleanupV35'],
      );
      expect(maintenance, hasLength(1));
      final nv = decodeJson(maintenance.single['new_values_json'] as String?);
      expect(nv?['rows_merged'], greaterThan(0));
      expect(nv?['rows_deleted'], greaterThan(0));
    });

    test(
      'αναζήτηση «θεση» δεν επιστρέφει merged row αν άλλαξε μόνο χρώμα',
      () async {
        const deptId = 88;
        await db.insert('audit_log', {
          'action': AuditActions.modifyDepartment,
          'timestamp': ts,
          'user_performing': 'tester',
          'entity_type': AuditEntityTypes.department,
          'entity_id': deptId,
          'entity_name': 'Χρώμα Μόνο',
          'details': 'departments id=$deptId',
          'old_values_json': jsonEncode({
            'color': '#1976D2',
            'map_x': 10.0,
            'map_y': 20.0,
          }),
          'new_values_json': jsonEncode({
            'color': '#1976D2',
            'map_x': 10.0,
            'map_y': 20.0,
          }),
        });
        await db.insert('audit_log', {
          'action': AuditActions.modifyDepartment,
          'timestamp': ts,
          'user_performing': 'tester',
          'entity_type': AuditEntityTypes.department,
          'entity_id': deptId,
          'entity_name': 'Χρώμα Μόνο',
          'details': 'departments id=$deptId',
          'old_values_json': jsonEncode({
            'color': '#1976D2',
            'map_x': 10.0,
            'map_y': 20.0,
          }),
          'new_values_json': jsonEncode({
            'color': '#EF5350',
            'map_x': 10.0,
            'map_y': 20.0,
          }),
        });

        await runMigration();

        final keyword = SearchTextNormalizer.normalizeForSearch('θεση');
        final page = await auditService.queryPage(
          offset: 0,
          limit: 10,
          keywordNormalized: keyword,
        );
        final deptMatches = page.rows
            .where((r) => r['entity_type'] == AuditEntityTypes.department)
            .toList();
        expect(deptMatches, isEmpty);
      },
    );

    test('διαφορετικά entities δεν συγχωνεύονται', () async {
      await db.insert('audit_log', {
        'action': AuditActions.modifyDepartment,
        'timestamp': ts,
        'user_performing': 'tester',
        'entity_type': AuditEntityTypes.department,
        'entity_id': 1,
        'old_values_json': jsonEncode({'color': '#1976D2'}),
        'new_values_json': jsonEncode({'color': '#EF5350'}),
      });
      await db.insert('audit_log', {
        'action': AuditActions.modifyDepartment,
        'timestamp': ts,
        'user_performing': 'tester',
        'entity_type': AuditEntityTypes.department,
        'entity_id': 2,
        'old_values_json': jsonEncode({'color': '#1976D2'}),
        'new_values_json': jsonEncode({'color': '#EF5350'}),
      });

      await runMigration();

      final deptRows = await db.query(
        'audit_log',
        where: 'entity_type = ?',
        whereArgs: [AuditEntityTypes.department],
      );
      expect(deptRows, hasLength(2));
    });

    test('γραμμές >2s apart δεν συγχωνεύονται', () async {
      const deptId = 3;
      await db.insert('audit_log', {
        'action': AuditActions.modifyDepartment,
        'timestamp': ts,
        'user_performing': 'tester',
        'entity_type': AuditEntityTypes.department,
        'entity_id': deptId,
        'old_values_json': jsonEncode({'color': '#1976D2'}),
        'new_values_json': jsonEncode({'color': '#EF5350'}),
      });
      await db.insert('audit_log', {
        'action': AuditActions.modifyDepartment,
        'timestamp': tsFar,
        'user_performing': 'tester',
        'entity_type': AuditEntityTypes.department,
        'entity_id': deptId,
        'old_values_json': jsonEncode({'color': '#EF5350'}),
        'new_values_json': jsonEncode({'color': '#4CAF50'}),
      });

      await runMigration();

      final deptRows = await db.query(
        'audit_log',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [AuditEntityTypes.department, deptId],
      );
      expect(deptRows, hasLength(2));
    });
  });
}
