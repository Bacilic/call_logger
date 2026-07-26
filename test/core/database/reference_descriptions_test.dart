import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/equipment_repository.dart';
import 'package:call_logger/core/database/phone_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('phoneReferenceDescriptions / equipmentReferenceDescriptions', () {
    late Database db;
    late PhoneRepository phones;
    late EquipmentRepository equipment;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'reference_descriptions_',
      );
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/reference_descriptions.db',
      );
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('calls');
      await db.delete('tasks');
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('department_phones');
      await db.delete('equipment');
      await db.delete('phones');
      await db.delete('users');
      await db.delete('departments');
      phones = PhoneRepository(db);
      equipment = EquipmentRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<int> insertCall({
      int? equipmentId,
      String? phoneText,
      String? equipmentText,
    }) async {
      final now = DateTime.now();
      return db.insert('calls', {
        'date': '${now.year.toString().padLeft(4, '0')}-01-01',
        'time': '10:00',
        'caller_id': null,
        'equipment_id': equipmentId,
        'caller_text': 'Test',
        'phone_text': phoneText ?? '1000',
        'department_text': 'Support',
        'equipment_text': equipmentText ?? 'PC',
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

    test('τηλέφωνο με κάτοχο → περιέχει «Άννα Πατσαρίκα»', () async {
      final deptId = await db.insert('departments', {
        'name': 'Πληροφορική',
        'name_key': SearchTextNormalizer.normalizeForSearch('Πληροφορική'),
        'is_deleted': 0,
      });
      final userId = await db.insert('users', {
        'first_name': 'Άννα',
        'last_name': 'Πατσαρίκα',
        'department_id': deptId,
        'is_deleted': 0,
      });
      final phoneId = await db.insert('phones', {
        'number': '2851',
        'is_deleted': 0,
      });
      await db.insert('user_phones', {'user_id': userId, 'phone_id': phoneId});

      final descriptions = await phones.phoneReferenceDescriptions(
        phoneId,
        '2851',
      );
      expect(descriptions, contains('Άννα Πατσαρίκα'));
    });

    test('τηλέφωνο με 3 κλήσεις → «3 κλήσεις ιστορικού»', () async {
      final phoneId = await db.insert('phones', {
        'number': '2851',
        'is_deleted': 0,
      });
      await insertCall(phoneText: '2851');
      await insertCall(phoneText: '2851');
      await insertCall(phoneText: '2851');

      final descriptions = await phones.phoneReferenceDescriptions(
        phoneId,
        '2851',
      );
      expect(descriptions, contains('3 κλήσεις ιστορικού'));
    });

    test('εξοπλισμός με κάτοχο → περιέχει το όνομα κατόχου', () async {
      final deptId = await db.insert('departments', {
        'name': 'Πληροφορική',
        'name_key': SearchTextNormalizer.normalizeForSearch('Πληροφορική'),
        'is_deleted': 0,
      });
      final userId = await db.insert('users', {
        'first_name': 'Βλάσης',
        'last_name': 'Οικονόμου',
        'department_id': deptId,
        'is_deleted': 0,
      });
      final equipmentId = await db.insert('equipment', {
        'code_equipment': '3601',
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': equipmentId,
      });

      final descriptions = await equipment.equipmentReferenceDescriptions(
        equipmentId,
      );
      expect(descriptions, contains('Βλάσης Οικονόμου'));
    });
  });
}
