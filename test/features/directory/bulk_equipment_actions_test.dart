// Μαζικές ενέργειες εξοπλισμού: σχέδια με εξαιρέσεις, ατομική εφαρμογή
// (μεταφορά, κάτοχος, πεδία, καθαρισμός) και ΠΛΗΡΗΣ αναίρεση.
//
//   flutter test test/features/directory/bulk_equipment_actions_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/models/equipment_column.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:call_logger/features/directory/services/bulk_action_undo_record.dart';
import 'package:call_logger/features/directory/services/bulk_equipment_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('bulk_equipment_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/bulk_equipment.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  Future<int> insertDepartment(String name) => db.insert('departments', {
    'name': name,
    'name_key': SearchTextNormalizer.normalizeForSearch(name),
    'is_deleted': 0,
  });

  Future<int> insertUser(String first, String last, {int? departmentId}) =>
      db.insert('users', {
        'first_name': first,
        'last_name': last,
        'department_id': departmentId,
        'is_deleted': 0,
      });

  Future<int> insertEquipment(
    String code, {
    int? departmentId,
    String? type,
    String? notes,
    String? location,
    Map<String, String>? remoteParams,
    String? defaultRemoteTool,
    List<int> ownerIds = const [],
  }) async {
    final id = await db.insert('equipment', {
      'code_equipment': code,
      'department_id': departmentId,
      'type': type,
      'notes': notes,
      'location': location,
      'remote_params': remoteParams == null ? null : jsonEncode(remoteParams),
      'default_remote_tool': defaultRemoteTool,
      'is_deleted': 0,
    });
    for (final ownerId in ownerIds) {
      await db.insert('user_equipment', {
        'user_id': ownerId,
        'equipment_id': id,
      });
    }
    return id;
  }

  Future<Map<String, dynamic>> equipmentRow(int id) async {
    final rows = await db.query(
      'equipment',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.first;
  }

  Future<List<int>> ownerIds(int equipmentId) async {
    final rows = await db.query(
      'user_equipment',
      columns: ['user_id'],
      where: 'equipment_id = ?',
      whereArgs: [equipmentId],
    );
    return [for (final r in rows) r['user_id'] as int];
  }

  EquipmentRow row(EquipmentModel eq, [UserModel? owner]) => (eq, owner);

  UserModel user(int id, String first, String last, {int? deptId}) =>
      UserModel(id: id, firstName: first, lastName: last, departmentId: deptId);

  group('Μεταφορά σε τμήμα', () {
    test('εξοπλισμός με κάτοχο αποδεσμεύεται και δηλώνεται ονομαστικά', () {
      final plan = buildBulkEquipmentTransferPlan(
        selectedRows: [
          row(EquipmentModel(id: 1, code: '3564', departmentId: 10)),
        ],
        target: const SharedAssetTransferTarget.existing(20),
        targetDisplayName: 'Αιμοδοσία',
        ownersByEquipmentId: {
          1: [user(7, 'Γιάννης', 'Γ', deptId: 10)],
        },
      );
      expect(plan.ownersToDetach[1], [7]);
      final text = bulkEquipmentTransferConfirmationText(plan);
      expect(text, contains('3564'));
      expect(text, contains('Γιάννης'));
      expect(text, contains('αποδεσμεύεται'));
    });

    test('χωρίς κάτοχο και ήδη στο τμήμα-προορισμό → δεν μετακινείται', () {
      final plan = buildBulkEquipmentTransferPlan(
        selectedRows: [
          row(EquipmentModel(id: 1, code: 'A', departmentId: 20)),
          row(EquipmentModel(id: 2, code: 'B', departmentId: 10)),
        ],
        target: const SharedAssetTransferTarget.existing(20),
        targetDisplayName: 'Αιμοδοσία',
      );
      expect(plan.rowsToMove.map((r) => r.$1.id), [2]);
      expect(plan.rowsAlreadyInTarget.map((r) => r.$1.id), [1]);
    });

    test('εφαρμογή σε νέο τμήμα + πλήρης αναίρεση', () async {
      final oldDept = await insertDepartment('Γραμματεία');
      final ownerId = await insertUser('Γιάννης', 'Γ', departmentId: oldDept);
      final eqId = await insertEquipment(
        'EQ-1',
        departmentId: oldDept,
        ownerIds: [ownerId],
      );

      final plan = buildBulkEquipmentTransferPlan(
        selectedRows: [
          row(EquipmentModel(id: eqId, code: 'EQ-1', departmentId: oldDept)),
        ],
        target: const SharedAssetTransferTarget.createNew('Νέο Παράρτημα'),
        targetDisplayName: 'Νέο Παράρτημα',
        ownersByEquipmentId: {
          eqId: [user(ownerId, 'Γιάννης', 'Γ', deptId: oldDept)],
        },
      );

      late BulkActionUndoRecord record;
      await db.transaction((txn) async {
        record = await applyBulkEquipmentTransferInTxn(txn, db, plan);
      });

      final newDept = await db.query(
        'departments',
        where: 'name = ? AND COALESCE(is_deleted, 0) = 0',
        whereArgs: ['Νέο Παράρτημα'],
      );
      expect(newDept, hasLength(1));
      final newDeptId = newDept.first['id'] as int;
      expect((await equipmentRow(eqId))['department_id'], newDeptId);
      expect(await ownerIds(eqId), isEmpty, reason: 'Αποδεσμεύτηκε');

      await applyBulkActionUndo(db, record);

      expect((await equipmentRow(eqId))['department_id'], oldDept);
      expect(await ownerIds(eqId), [ownerId], reason: 'Ο κάτοχος επανήλθε');
      final deptAfter = await db.query(
        'departments',
        where: 'id = ?',
        whereArgs: [newDeptId],
        limit: 1,
      );
      expect(
        deptAfter.first['is_deleted'],
        1,
        reason: 'Η αναίρεση σβήνει και το τμήμα που δημιούργησε',
      );
    });
  });

  group('Αλλαγή κατόχου', () {
    test('εξοπλισμός με πολλούς κατόχους εξαιρείται ονομαστικά', () {
      final plan = buildBulkEquipmentOwnerPlan(
        selectedRows: [row(EquipmentModel(id: 1, code: '4040'))],
        newOwner: user(9, 'Νέος', 'Κάτοχος'),
        ownersByEquipmentId: {
          1: [user(3, 'Νίκος', 'Ζ'), user(4, 'Μαρία', 'Κ')],
        },
      );
      expect(plan.hasWork, isFalse);
      expect(plan.exclusions.single.reason, contains('2 κατόχους'));
      expect(plan.exclusions.single.reason, contains('4040'));
    });

    test('το τμήμα ακολουθεί τον νέο κάτοχο + αναίρεση', () async {
      final oldDept = await insertDepartment('Γραμματεία');
      final newDept = await insertDepartment('Αιμοδοσία');
      final oldOwner = await insertUser('Παλιός', 'Κ', departmentId: oldDept);
      final newOwner = await insertUser('Νέος', 'Κ', departmentId: newDept);
      final eqId = await insertEquipment(
        'EQ-2',
        departmentId: oldDept,
        ownerIds: [oldOwner],
      );

      final plan = buildBulkEquipmentOwnerPlan(
        selectedRows: [
          row(EquipmentModel(id: eqId, code: 'EQ-2', departmentId: oldDept)),
        ],
        newOwner: user(newOwner, 'Νέος', 'Κ', deptId: newDept),
        ownersByEquipmentId: {
          eqId: [user(oldOwner, 'Παλιός', 'Κ', deptId: oldDept)],
        },
      );

      late BulkActionUndoRecord record;
      await db.transaction((txn) async {
        record = await applyBulkEquipmentOwnerInTxn(txn, db, plan);
      });

      expect(await ownerIds(eqId), [newOwner]);
      expect(
        (await equipmentRow(eqId))['department_id'],
        newDept,
        reason: 'Το τμήμα ακολούθησε τον νέο κάτοχο',
      );

      await applyBulkActionUndo(db, record);
      expect(await ownerIds(eqId), [oldOwner]);
      expect((await equipmentRow(eqId))['department_id'], oldDept);
    });
  });

  group('Κύριο εργαλείο απομακρυσμένης', () {
    RemoteTool tool(int id, String name) => RemoteTool(
      id: id,
      name: name,
      role: ToolRole.anydesk,
      executablePath: r'C:\Tools\anydesk.exe',
      sortOrder: 1,
      isActive: true,
    );

    test('εξοπλισμός χωρίς παράμετρο εξαιρείται ονομαστικά', () {
      final anydesk = tool(5, 'AnyDesk');
      final plan = buildBulkEquipmentPrimaryToolPlan(
        selectedRows: [
          row(
            EquipmentModel(
              id: 1,
              code: 'WITH',
              remoteParams: const {'5': '123456789'},
            ),
          ),
          row(EquipmentModel(id: 2, code: 'WITHOUT')),
        ],
        tool: anydesk,
      );
      expect(plan.rowsToApply.map((r) => r.$1.code), ['WITH']);
      expect(plan.exclusions.single.reason, contains('WITHOUT'));
      expect(plan.exclusions.single.reason, contains('AnyDesk'));
    });
  });

  group('Πεδία και σημειώσεις', () {
    test('προσθήκη σημειώσεων σε νέα γραμμή + αναίρεση', () async {
      final eqId = await insertEquipment('EQ-3', notes: 'παλιά');
      final rows = [
        row(EquipmentModel(id: eqId, code: 'EQ-3', notes: 'παλιά')),
      ];

      late BulkActionUndoRecord record;
      await db.transaction((txn) async {
        record = await applyBulkEquipmentFieldInTxn(
          txn,
          db,
          rows: rows,
          column: 'notes',
          value: 'νέα γραμμή',
          notesMode: BulkEquipmentNotesMode.append,
        );
      });
      expect((await equipmentRow(eqId))['notes'], 'παλιά\nνέα γραμμή');

      await applyBulkActionUndo(db, record);
      expect((await equipmentRow(eqId))['notes'], 'παλιά');
    });

    test('μαζική τοποθεσία + αναίρεση', () async {
      final eqId = await insertEquipment('EQ-4', location: 'Γραφείο 1');
      final rows = [row(EquipmentModel(id: eqId, code: 'EQ-4'))];

      late BulkActionUndoRecord record;
      await db.transaction((txn) async {
        record = await applyBulkEquipmentFieldInTxn(
          txn,
          db,
          rows: rows,
          column: 'location',
          value: 'Γραφείο 3',
        );
      });
      expect((await equipmentRow(eqId))['location'], 'Γραφείο 3');

      await applyBulkActionUndo(db, record);
      expect((await equipmentRow(eqId))['location'], 'Γραφείο 1');
    });
  });

  group('Καθαρισμός πεδίου', () {
    test(
      'αποδέσμευση κατόχου γράφει τμήμα ώστε να μη μείνει ορφανός',
      () async {
        final dept = await insertDepartment('Γραμματεία');
        final ownerId = await insertUser('Γιάννης', 'Γ', departmentId: dept);
        final eqId = await insertEquipment('EQ-5', ownerIds: [ownerId]);

        final plan = buildBulkEquipmentClearPlan(
          selectedRows: [row(EquipmentModel(id: eqId, code: 'EQ-5'))],
          field: BulkEquipmentClearField.owner,
          ownersByEquipmentId: {
            eqId: [user(ownerId, 'Γιάννης', 'Γ', deptId: dept)],
          },
        );
        expect(plan.departmentFallbackByEquipmentId[eqId], dept);

        late BulkActionUndoRecord record;
        await db.transaction((txn) async {
          record = await applyBulkEquipmentClearInTxn(txn, db, plan);
        });

        expect(await ownerIds(eqId), isEmpty);
        expect(
          (await equipmentRow(eqId))['department_id'],
          dept,
          reason: 'Ο κανόνας «ποτέ ορφανός» τηρήθηκε',
        );

        await applyBulkActionUndo(db, record);
        expect(await ownerIds(eqId), [ownerId]);
        expect((await equipmentRow(eqId))['department_id'], isNull);
      },
    );

    test('κάτοχος χωρίς τμήμα → εξαίρεση αντί για ορφανό', () {
      final plan = buildBulkEquipmentClearPlan(
        selectedRows: [row(EquipmentModel(id: 1, code: 'EQ-6'))],
        field: BulkEquipmentClearField.owner,
        ownersByEquipmentId: {
          1: [user(7, 'Ορφανός', 'Χ')],
        },
      );
      expect(plan.hasWork, isFalse);
      expect(plan.exclusions.single.reason, contains('ορφανός'));
    });

    test(
      'καθαρισμός παραμέτρων σβήνει και το κύριο εργαλείο + αναίρεση',
      () async {
        final eqId = await insertEquipment(
          'EQ-7',
          remoteParams: const {'5': '123456789'},
          defaultRemoteTool: '5',
        );
        final plan = buildBulkEquipmentClearPlan(
          selectedRows: [
            row(
              EquipmentModel(
                id: eqId,
                code: 'EQ-7',
                remoteParams: const {'5': '123456789'},
                defaultRemoteTool: '5',
              ),
            ),
          ],
          field: BulkEquipmentClearField.remoteParams,
        );
        expect(plan.hasWork, isTrue);
        expect(
          bulkEquipmentClearConfirmationText(plan),
          contains('ΠΡΟΣΟΧΗ'),
          reason: 'Οι παράμετροι είναι μοναδικές ανά μηχάνημα',
        );

        late BulkActionUndoRecord record;
        await db.transaction((txn) async {
          record = await applyBulkEquipmentClearInTxn(txn, db, plan);
        });
        final cleared = await equipmentRow(eqId);
        expect(cleared['remote_params'], isNull);
        expect(cleared['default_remote_tool'], isNull);

        await applyBulkActionUndo(db, record);
        final restored = await equipmentRow(eqId);
        expect(restored['remote_params'], jsonEncode({'5': '123456789'}));
        expect(restored['default_remote_tool'], '5');
      },
    );
  });

  group('Ταυτότητα: ο κωδικός δεν αλλάζει ποτέ μαζικά', () {
    test('η υπηρεσία δεν εκθέτει καμία ενέργεια για code_equipment', () {
      // Τα πεδία-στόχοι είναι ρητά απαριθμημένα: κανένα δεν αγγίζει τον κωδικό.
      expect(BulkEquipmentClearField.values, hasLength(4));
      expect(
        BulkEquipmentClearField.values.map((f) => f.name),
        isNot(contains('code')),
      );
    });
  });
}
