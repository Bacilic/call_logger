import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/directory/services/equipment_deletion_summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('EquipmentDeletionSummary · deletionSummaries', () {
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'equipment_deletion_summary_test_',
      );
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/equipment_deletion_summary.db',
      );
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('calls');
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('equipment');
      await db.delete('phones');
      await db.delete('users');
      await db.delete('departments');
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<int> insertCallForEquipment(int equipmentId) async {
      final now = DateTime.now();
      return db.insert('calls', {
        'date': '${now.year.toString().padLeft(4, '0')}-01-01',
        'time': '10:00',
        'caller_id': null,
        'equipment_id': equipmentId,
        'caller_text': 'Test',
        'phone_text': '1000',
        'department_text': 'Support',
        'equipment_text': 'PC',
        'issue': null,
        'category_text': 'Κατηγορία',
        'category_id': null,
        'status': 'completed',
        'duration': 10,
        'is_priority': 0,
        'search_index': 'test',
        'lansweeper_state': 'unsent',
        'lansweeper_main_ticket_id': null,
        'lansweeper_last_sync_at': null,
        'is_deleted': 0,
      });
    }

    test('εξοπλισμός με κάτοχο, τηλέφωνο και 3 κλήσεις', () async {
      final deptId = await db.insert('departments', {
        'name': 'Τμήμα Α',
        'name_key': SearchTextNormalizer.normalizeForSearch('Τμήμα Α'),
        'is_deleted': 0,
      });
      final userId = await db.insert('users', {
        'first_name': 'Αναστασία',
        'last_name': 'Φούφα',
        'department_id': deptId,
        'is_deleted': 0,
      });
      final phoneId = await db.insert('phones', {
        'number': '2898',
        'is_deleted': 0,
      });
      await db.insert('user_phones', {'user_id': userId, 'phone_id': phoneId});
      final equipmentId = await db.insert('equipment', {
        'code_equipment': '2113',
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': equipmentId,
      });
      await insertCallForEquipment(equipmentId);
      await insertCallForEquipment(equipmentId);
      await insertCallForEquipment(equipmentId);

      final summaries = await deletionSummaries(db, [equipmentId]);
      expect(summaries, hasLength(1));
      final s = summaries.single;
      expect(s.code, '2113');
      expect(s.ownerName, 'Αναστασία Φούφα');
      expect(s.phone, '2898');
      expect(s.historyCount, 3);
    });

    test('εξοπλισμός χωρίς κάτοχο/τηλέφωνο και χωρίς ιστορικό', () async {
      final equipmentId = await db.insert('equipment', {
        'code_equipment': '3974',
        'is_deleted': 0,
      });

      final summaries = await deletionSummaries(db, [equipmentId]);
      expect(summaries, hasLength(1));
      final s = summaries.single;
      expect(s.code, '3974');
      expect(s.ownerName, isNull);
      expect(s.phone, isNull);
      expect(s.historyCount, 0);
    });
  });
}
