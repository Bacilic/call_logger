// Ο εκτελεστής μαζικής διαγραφής υπαλλήλων, χωρίς widgets και χωρίς διαλόγους.
//
//   flutter test test/features/directory/services/user_bulk_deletion_runner_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/services/asset_disconnect_models.dart';
import 'package:call_logger/features/directory/services/user_bulk_deletion_runner.dart';
import 'package:call_logger/features/directory/services/user_deletion_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_setup.dart';

void main() {
  late Database db;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('user_bulk_del_test_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/user_bulk_del.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    for (final t in const [
      'audit_log',
      'user_equipment',
      'user_phones',
      'department_phones',
      'phones',
      'equipment',
      'users',
      'departments',
    ]) {
      await db.delete(t);
    }
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  Future<int> insertDept(String name) => db.insert('departments', {
    'name': name,
    'name_key': SearchTextNormalizer.normalizeForSearch(name),
    'is_deleted': 0,
  });

  /// Ένας υπάλληλος με ένα προσωπικό τηλέφωνο και έναν εξοπλισμό χωρίς τμήμα.
  Future<({int userId, int deptId, UserModel model})> seedUser({
    required String lastName,
    required String phone,
    required String equipmentCode,
    required int deptId,
  }) async {
    final userId = await db.insert('users', {
      'first_name': 'Δοκιμή',
      'last_name': lastName,
      'department_id': deptId,
      'is_deleted': 0,
    });
    final phoneId = await db.insert('phones', {'number': phone});
    await db.insert('user_phones', {'user_id': userId, 'phone_id': phoneId});
    final equipmentId = await db.insert('equipment', {
      'code_equipment': equipmentCode,
      'type': 'PC',
      'department_id': null,
      'is_deleted': 0,
    });
    await db.insert('user_equipment', {
      'user_id': userId,
      'equipment_id': equipmentId,
    });
    return (
      userId: userId,
      deptId: deptId,
      model: UserModel(
        id: userId,
        firstName: 'Δοκιμή',
        lastName: lastName,
        departmentId: deptId,
      ),
    );
  }

  group('προετοιμασία', () {
    test('διαβάζει τα αρχικά στοιχεία πριν χαθούν οι συνδέσεις', () async {
      final deptId = await insertDept('Γραμματεία');
      final seeded = await seedUser(
        lastName: 'Παπαδόπουλος',
        phone: '2530',
        equipmentCode: '4120',
        deptId: deptId,
      );

      final plan = await prepareUserBulkDeletion(db: db, users: [seeded.model]);

      expect(plan.userIds, [seeded.userId]);
      expect(plan.hasAssetsToResolve, isTrue);
      expect(plan.originalUserPhones[seeded.userId], ['2530']);
      expect(plan.originalUserEquipmentIds[seeded.userId], hasLength(1));
    });

    test('τα στοιχεία κουβαλούν κάτοχο και τμήμα για τον διάλογο', () async {
      final deptId = await insertDept('Ακτινολογικό');
      final seeded = await seedUser(
        lastName: 'Ιωάννου',
        phone: '2540',
        equipmentCode: '4130',
        deptId: deptId,
      );

      final plan = await prepareUserBulkDeletion(db: db, users: [seeded.model]);
      final items = plan.disconnectItems();

      expect(items, hasLength(2));
      expect(items.first.value, '2540');
      expect(items.first.ownerName, 'Δοκιμή Ιωάννου');
      expect(items.first.departmentName, 'Ακτινολογικό');
      expect(items.last.value, '4130');
      expect(items.last.isPhone, isFalse);
    });

    test('η συνεδρία μετρά τηλέφωνα και εξοπλισμούς όλων μαζί', () async {
      final deptId = await insertDept('Άδειες');
      final a = await seedUser(
        lastName: 'Α',
        phone: '2551',
        equipmentCode: '4141',
        deptId: deptId,
      );
      final b = await seedUser(
        lastName: 'Β',
        phone: '2552',
        equipmentCode: '4142',
        deptId: deptId,
      );

      final plan = await prepareUserBulkDeletion(
        db: db,
        users: [a.model, b.model],
      );
      final session = plan.createDisconnectSession();

      expect(session.totalSteps, 4);
      expect(
        session.cancelScopeDescription,
        userDeletionCancelScopeDescription(2),
      );
    });
  });

  group('εκτέλεση', () {
    test('διαγράφει και εφαρμόζει τις αποφάσεις σε μία κίνηση', () async {
      final deptId = await insertDept('Γραμματεία');
      final target = await insertDept('Αποθήκη');
      final seeded = await seedUser(
        lastName: 'Κορδαλή',
        phone: '2560',
        equipmentCode: '4150',
        deptId: deptId,
      );

      final plan = await prepareUserBulkDeletion(db: db, users: [seeded.model]);

      final undo = await applyUserBulkDeletion(
        db: db,
        plan: plan,
        phoneBatches: [
          (
            batch: const SharedAssetDisconnectBatchResult(
              phonesToKeep: ['2560'],
            ),
            sourceDepartmentId: deptId,
          ),
        ],
        equipmentBatches: [
          (
            batch: SharedAssetDisconnectBatchResult(
              equipmentTransfers: {
                '4150': SharedAssetTransferTarget.existing(target),
              },
            ),
            sourceDepartmentId: deptId,
          ),
        ],
      );

      final remaining = await db.query(
        'users',
        where: 'id = ? AND COALESCE(is_deleted, 0) = 0',
        whereArgs: [seeded.userId],
      );
      expect(remaining, isEmpty, reason: 'ο υπάλληλος διαγράφηκε');

      expect(undo.deletedUserIds, [seeded.userId]);
      expect(undo.originalUserPhones[seeded.userId], ['2560']);
      expect(undo.phoneDeptAdds, hasLength(1));
      expect(undo.phoneDeptAdds.single.phoneNumber, '2560');
      expect(undo.phoneDeptAdds.single.departmentId, deptId);
      expect(undo.equipmentDeptSets, hasLength(1));
      expect(undo.equipmentDeptSets.single.departmentId, target);
    });

    test('η εγγραφή αναίρεσης κρατά τα σβησμένα στοιχεία', () async {
      final deptId = await insertDept('Άδειες');
      final seeded = await seedUser(
        lastName: 'Δημητριάδη',
        phone: '2570',
        equipmentCode: '4160',
        deptId: deptId,
      );

      final plan = await prepareUserBulkDeletion(db: db, users: [seeded.model]);

      final undo = await applyUserBulkDeletion(
        db: db,
        plan: plan,
        phoneBatches: [
          (
            batch: const SharedAssetDisconnectBatchResult(
              phonesToDelete: ['2570'],
            ),
            sourceDepartmentId: deptId,
          ),
        ],
        equipmentBatches: [
          (
            batch: const SharedAssetDisconnectBatchResult(
              equipmentToDelete: ['4160'],
            ),
            sourceDepartmentId: deptId,
          ),
        ],
      );

      expect(undo.softDeletedPhoneNumbers, ['2570']);
      expect(undo.softDeletedEquipmentCodes, ['4160']);
    });
  });

  group('σύνοψη ενεργειών', () {
    test('κάθε στοιχείο εμφανίζεται με τη σωστή ενέργεια', () {
      final actions = userDeletionAssetActions(
        phoneBatches: [
          (
            batch: SharedAssetDisconnectBatchResult(
              phonesToKeep: const ['2510'],
              phonesToDelete: const ['2511'],
              phoneTransfers: {
                '2512': const SharedAssetTransferTarget.existing(3),
              },
            ),
            sourceDepartmentId: 1,
          ),
        ],
        equipmentBatches: [
          (
            batch: const SharedAssetDisconnectBatchResult(
              equipmentToDelete: ['EQ1'],
            ),
            sourceDepartmentId: 1,
          ),
        ],
      );

      expect(actions, hasLength(4));
      expect(
        actions
            .where((a) => a.kind == UserDeletionAssetActionKind.transfer)
            .single
            .identifier,
        '2512',
      );
      expect(actions.where((a) => !a.isPhone).single.identifier, 'EQ1');
    });

    test('χωρίς αποφάσεις δεν παράγεται καμία ενέργεια', () {
      expect(
        userDeletionAssetActions(phoneBatches: [], equipmentBatches: []),
        isEmpty,
      );
    });
  });
}
