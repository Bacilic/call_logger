// Εξοπλισμοί με χειροκίνητο στόχο ανά εργαλείο (στήλη JSON `remote_params`).
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/core/database/equipment_manual_remote_targets_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/equipment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Εξοπλισμοί με χειροκίνητο στόχο ανά εργαλείο', () {
    late EquipmentRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'equipment_manual_targets_test_',
      );
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/manual.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('user_equipment');
      await db.delete('equipment');
      repo = EquipmentRepository(db);
    });

    Future<void> insertEquipment(
      String code, {
      Map<String, String>? remoteParams,
      bool isDeleted = false,
      String? rawRemoteParams,
    }) async {
      await db.insert('equipment', {
        'code_equipment': code,
        'type': 'Desktop',
        'is_deleted': isDeleted ? 1 : 0,
        'remote_params':
            rawRemoteParams ??
            (remoteParams == null ? null : jsonEncode(remoteParams)),
      });
    }

    test(
      'επιστρέφει μόνο όσους έχουν τιμή για το συγκεκριμένο εργαλείο',
      () async {
        await insertEquipment('1001', remoteParams: {'7': '123456789'});
        await insertEquipment('1002', remoteParams: {'9': '10.0.0.5'});
        await insertEquipment('1003', remoteParams: {'7': '987654321'});

        final result = await repo.getEquipmentManualTargetsForTool(7);

        expect(result.map((e) => e.code), ['1001', '1003']);
        expect(result.map((e) => e.target), ['123456789', '987654321']);
      },
    );

    test('αγνοεί κενή τιμή και διαγραμμένο εξοπλισμό', () async {
      await insertEquipment('2001', remoteParams: {'7': '   '});
      await insertEquipment(
        '2002',
        remoteParams: {'7': '111'},
        isDeleted: true,
      );
      await insertEquipment('2003', remoteParams: {'7': '222'});

      final result = await repo.getEquipmentManualTargetsForTool(7);

      expect(result.map((e) => e.code), ['2003']);
    });

    test('χαλασμένο JSON σε μία γραμμή δεν ρίχνει τη λίστα', () async {
      await insertEquipment('3001', rawRemoteParams: '{όχι JSON');
      await insertEquipment('3002', remoteParams: {'7': '333'});

      final result = await repo.getEquipmentManualTargetsForTool(7);

      expect(result.map((e) => e.code), ['3002']);
    });

    test('κανένας εξοπλισμός για άγνωστο εργαλείο', () async {
      await insertEquipment('4001', remoteParams: {'7': '444'});

      final result = await repo.getEquipmentManualTargetsForTool(99);

      expect(result, isEmpty);
    });
  });
}
