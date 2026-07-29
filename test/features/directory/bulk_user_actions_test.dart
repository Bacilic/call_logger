// Μαζικές ενέργειες υπαλλήλων: σχέδια με εξαιρέσεις κοινοχρησίας, ατομική
// εφαρμογή (μεταφορά, σημειώσεις, καθαρισμός) και ΠΛΗΡΗΣ αναίρεση.
//
//   flutter test test/features/directory/bulk_user_actions_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/phone_repository.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:call_logger/features/directory/services/bulk_action_undo_record.dart';
import 'package:call_logger/features/directory/services/bulk_user_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('bulk_user_actions_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/bulk_actions.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  Future<int> insertDepartment(String name) async {
    return db.insert('departments', {
      'name': name,
      'name_key': SearchTextNormalizer.normalizeForSearch(name),
      'is_deleted': 0,
    });
  }

  Future<int> insertUser({
    required String firstName,
    required String lastName,
    int? departmentId,
    List<String> phones = const [],
    String? notes,
  }) async {
    final userId = await db.insert('users', {
      'first_name': firstName,
      'last_name': lastName,
      'department_id': departmentId,
      'notes': notes,
      'is_deleted': 0,
    });
    for (final n in phones) {
      final existing = await db.query(
        'phones',
        columns: ['id'],
        where: 'number = ?',
        whereArgs: [n],
        limit: 1,
      );
      final phoneId = existing.isEmpty
          ? await db.insert('phones', {'number': n})
          : existing.first['id'] as int;
      await db.insert('user_phones', {'user_id': userId, 'phone_id': phoneId});
    }
    return userId;
  }

  Future<int> insertEquipment(
    String code, {
    int? departmentId,
    List<int> ownerIds = const [],
  }) async {
    final equipmentId = await db.insert('equipment', {
      'code_equipment': code,
      'department_id': departmentId,
      'is_deleted': 0,
    });
    for (final ownerId in ownerIds) {
      await db.insert('user_equipment', {
        'user_id': ownerId,
        'equipment_id': equipmentId,
      });
    }
    return equipmentId;
  }

  Future<Map<String, dynamic>> userRow(int id) async {
    final rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.first;
  }

  Future<List<String>> userPhones(int id) async {
    final rows = await db.rawQuery(
      '''
      SELECT p.number AS number FROM user_phones up
      JOIN phones p ON p.id = up.phone_id
      WHERE up.user_id = ? ORDER BY p.number
    ''',
      [id],
    );
    return [for (final r in rows) r['number'] as String];
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

  UserModel user(
    int id,
    String first,
    String last, {
    int? deptId,
    List<String> phones = const [],
    String? notes,
  }) {
    return UserModel(
      id: id,
      firstName: first,
      lastName: last,
      departmentId: deptId,
      phones: phones,
      notes: notes,
    );
  }

  group('Σχέδιο μεταφοράς — εξαιρέσεις και μερική μεταφορά', () {
    test('όσοι είναι ήδη στο τμήμα-προορισμό δεν μετακινούνται', () {
      final plan = buildBulkUserTransferPlan(
        selectedUsers: [
          user(1, 'Άννα', 'Α', deptId: 10),
          user(2, 'Βασίλης', 'Β', deptId: 20),
        ],
        target: const SharedAssetTransferTarget.existing(20),
        targetDisplayName: 'Αιμοδοσία',
        phoneFate: BulkTransferAssetFate.follow,
        equipmentFate: BulkTransferAssetFate.follow,
        equipmentByUserId: const {},
      );
      expect(plan.usersToMove.map((u) => u.id), [1]);
      expect(plan.usersAlreadyInTarget.map((u) => u.id), [2]);
      expect(
        bulkTransferConfirmationText(plan),
        contains('1 από τους επιλεγμένους'),
      );
    });

    test('τηλέφωνο κοινό με ΜΗ επιλεγμένο εξαιρείται ονομαστικά', () {
      final plan = buildBulkUserTransferPlan(
        selectedUsers: [
          user(1, 'Άννα', 'Α', deptId: 10, phones: ['2100', '2200']),
        ],
        target: const SharedAssetTransferTarget.existing(20),
        targetDisplayName: 'Αιμοδοσία',
        phoneFate: BulkTransferAssetFate.stayInOldDepartment,
        equipmentFate: BulkTransferAssetFate.follow,
        equipmentByUserId: const {},
        sharing: const BulkAssetSharingInfo(
          phoneOtherUserNames: {
            '2100': ['Γιάννης Γ'],
          },
        ),
      );
      expect(plan.phonesToRelease[1], ['2200']);
      expect(plan.exclusions, hasLength(1));
      expect(plan.exclusions.single.reason, contains('2100'));
      expect(plan.exclusions.single.reason, contains('Γιάννης Γ'));
      expect(bulkTransferConfirmationText(plan), contains('Γιάννης Γ'));
    });

    test('εξοπλισμός με ΜΗ επιλεγμένο συν-κάτοχο εξαιρείται και στις δύο '
        'τύχες', () {
      for (final fate in BulkTransferAssetFate.values) {
        final plan = buildBulkUserTransferPlan(
          selectedUsers: [user(1, 'Άννα', 'Α', deptId: 10)],
          target: const SharedAssetTransferTarget.existing(20),
          targetDisplayName: 'Αιμοδοσία',
          phoneFate: BulkTransferAssetFate.follow,
          equipmentFate: fate,
          equipmentByUserId: {
            1: [EquipmentModel(id: 7, code: '3564', departmentId: 10)],
          },
          sharing: const BulkAssetSharingInfo(
            equipmentOtherUserNames: {
              7: ['Γιάννης Γ'],
            },
          ),
        );
        expect(plan.equipmentToFollow, isEmpty, reason: '$fate');
        expect(plan.equipmentToRelease, isEmpty, reason: '$fate');
        expect(plan.exclusions.single.reason, contains('3564'));
        expect(plan.exclusions.single.reason, contains('Γιάννης Γ'));
      }
    });
  });

  group('Μεταφορά — εφαρμογή και πλήρης αναίρεση', () {
    test(
      'νέο τμήμα, τηλέφωνα μένουν κοινόχρηστα, εξοπλισμός ακολουθεί',
      () async {
        final oldDept = await insertDepartment('Γραμματεία');
        final annaId = await insertUser(
          firstName: 'Άννα',
          lastName: 'Α',
          departmentId: oldDept,
          phones: ['2100'],
        );
        final eqId = await insertEquipment(
          'EQ-1',
          departmentId: oldDept,
          ownerIds: [annaId],
        );

        final plan = buildBulkUserTransferPlan(
          selectedUsers: [
            user(annaId, 'Άννα', 'Α', deptId: oldDept, phones: ['2100']),
          ],
          target: const SharedAssetTransferTarget.createNew('Νέο Παράρτημα'),
          targetDisplayName: 'Νέο Παράρτημα',
          phoneFate: BulkTransferAssetFate.stayInOldDepartment,
          equipmentFate: BulkTransferAssetFate.follow,
          equipmentByUserId: {
            annaId: [
              EquipmentModel(id: eqId, code: 'EQ-1', departmentId: oldDept),
            ],
          },
        );

        late BulkActionUndoRecord record;
        await db.transaction((txn) async {
          record = await applyBulkUserTransferInTxn(txn, db, plan);
        });

        final newDeptRows = await db.query(
          'departments',
          where: 'name = ? AND COALESCE(is_deleted, 0) = 0',
          whereArgs: ['Νέο Παράρτημα'],
        );
        expect(newDeptRows, hasLength(1), reason: 'Δημιουργήθηκε ο προορισμός');
        final newDeptId = newDeptRows.first['id'] as int;
        expect(record.createdDepartmentId, newDeptId);

        expect((await userRow(annaId))['department_id'], newDeptId);
        expect(
          await userPhones(annaId),
          isEmpty,
          reason: 'Το 2100 αποδεσμεύτηκε',
        );
        final directPhones = await PhoneRepository(
          db,
        ).getDepartmentDirectPhonesMap();
        expect(
          directPhones[oldDept],
          contains('2100'),
          reason: 'Κοινόχρηστο του ΠΑΛΙΟΥ τμήματος',
        );
        expect((await equipmentRow(eqId))['department_id'], newDeptId);

        await applyBulkActionUndo(db, record);

        expect((await userRow(annaId))['department_id'], oldDept);
        expect(await userPhones(annaId), ['2100']);
        final directAfterUndo = await PhoneRepository(
          db,
        ).getDepartmentDirectPhonesMap();
        expect(directAfterUndo[oldDept] ?? const [], isNot(contains('2100')));
        expect((await equipmentRow(eqId))['department_id'], oldDept);
        final deptAfterUndo = await db.query(
          'departments',
          where: 'id = ?',
          whereArgs: [newDeptId],
          limit: 1,
        );
        expect(
          deptAfterUndo.first['is_deleted'],
          1,
          reason: 'Η αναίρεση σβήνει και το τμήμα που δημιούργησε',
        );
      },
    );

    test('εξοπλισμός «μένει»: αποδέσμευση από κάτοχο, παραμονή στο παλιό '
        'τμήμα', () async {
      final oldDept = await insertDepartment('Γραμματεία');
      final targetDept = await insertDepartment('Αιμοδοσία');
      final annaId = await insertUser(
        firstName: 'Άννα',
        lastName: 'Α',
        departmentId: oldDept,
      );
      final eqId = await insertEquipment(
        'EQ-2',
        departmentId: oldDept,
        ownerIds: [annaId],
      );

      final plan = buildBulkUserTransferPlan(
        selectedUsers: [user(annaId, 'Άννα', 'Α', deptId: oldDept)],
        target: SharedAssetTransferTarget.existing(targetDept),
        targetDisplayName: 'Αιμοδοσία',
        phoneFate: BulkTransferAssetFate.follow,
        equipmentFate: BulkTransferAssetFate.stayInOldDepartment,
        equipmentByUserId: {
          annaId: [
            EquipmentModel(id: eqId, code: 'EQ-2', departmentId: oldDept),
          ],
        },
      );

      late BulkActionUndoRecord record;
      await db.transaction((txn) async {
        record = await applyBulkUserTransferInTxn(txn, db, plan);
      });

      expect((await userRow(annaId))['department_id'], targetDept);
      final links = await db.query(
        'user_equipment',
        where: 'user_id = ? AND equipment_id = ?',
        whereArgs: [annaId, eqId],
      );
      expect(links, isEmpty, reason: 'Ο δεσμός κατόχου λύθηκε');
      expect(
        (await equipmentRow(eqId))['department_id'],
        oldDept,
        reason: 'Ο εξοπλισμός έμεινε στο παλιό τμήμα',
      );

      await applyBulkActionUndo(db, record);
      final linksAfter = await db.query(
        'user_equipment',
        where: 'user_id = ? AND equipment_id = ?',
        whereArgs: [annaId, eqId],
      );
      expect(linksAfter, hasLength(1), reason: 'Ο δεσμός επανήλθε');
      expect((await userRow(annaId))['department_id'], oldDept);
    });
  });

  group('Σημειώσεις — εφαρμογή και αναίρεση', () {
    test('προσθήκη σε νέα γραμμή και αντικατάσταση, με επαναφορά', () async {
      final deptId = await insertDepartment('Γραμματεία');
      final withNotes = await insertUser(
        firstName: 'Άννα',
        lastName: 'Α',
        departmentId: deptId,
        notes: 'παλιά σημείωση',
      );
      final withoutNotes = await insertUser(
        firstName: 'Βασίλης',
        lastName: 'Β',
        departmentId: deptId,
      );
      final models = [
        user(withNotes, 'Άννα', 'Α', deptId: deptId, notes: 'παλιά σημείωση'),
        user(withoutNotes, 'Βασίλης', 'Β', deptId: deptId),
      ];

      late BulkActionUndoRecord record;
      await db.transaction((txn) async {
        record = await applyBulkUserNotesInTxn(
          txn,
          db,
          users: models,
          text: 'μετακόμιση στο νέο κτίριο',
          mode: BulkNotesMode.append,
        );
      });
      expect(
        (await userRow(withNotes))['notes'],
        'παλιά σημείωση\nμετακόμιση στο νέο κτίριο',
      );
      expect(
        (await userRow(withoutNotes))['notes'],
        'μετακόμιση στο νέο κτίριο',
      );

      await applyBulkActionUndo(db, record);
      expect((await userRow(withNotes))['notes'], 'παλιά σημείωση');
      expect(
        ((await userRow(withoutNotes))['notes'] as String?) ?? '',
        isEmpty,
      );

      await db.transaction((txn) async {
        record = await applyBulkUserNotesInTxn(
          txn,
          db,
          users: models,
          text: 'ολική αντικατάσταση',
          mode: BulkNotesMode.replace,
        );
      });
      expect((await userRow(withNotes))['notes'], 'ολική αντικατάσταση');

      await applyBulkActionUndo(db, record);
      expect((await userRow(withNotes))['notes'], 'παλιά σημείωση');
    });
  });

  group('Καθαρισμός — τρίο τύχης και αναίρεση', () {
    test('διαγραφή τηλεφώνων: αποδέσμευση + soft delete + επαναφορά', () async {
      final deptId = await insertDepartment('Γραμματεία');
      final annaId = await insertUser(
        firstName: 'Άννα',
        lastName: 'Α',
        departmentId: deptId,
        phones: ['2100', '2200'],
      );
      final models = [
        user(annaId, 'Άννα', 'Α', deptId: deptId, phones: ['2100', '2200']),
      ];

      final plan = buildBulkUserClearPlan(
        selectedUsers: models,
        field: BulkClearField.phones,
        fate: BulkClearFate.deleteOutright,
      );
      expect(plan.phonesByUser[annaId], ['2100', '2200']);

      late BulkActionUndoRecord record;
      await db.transaction((txn) async {
        record = await applyBulkUserClearInTxn(txn, db, plan);
      });

      expect(await userPhones(annaId), isEmpty);
      final phoneRows = await db.query(
        'phones',
        where: 'number IN (?, ?)',
        whereArgs: ['2100', '2200'],
      );
      for (final row in phoneRows) {
        expect(row['is_deleted'], 1, reason: 'soft delete ${row['number']}');
      }

      await applyBulkActionUndo(db, record);
      expect(await userPhones(annaId), ['2100', '2200']);
    });

    test(
      'αποδέσμευση τηλεφώνων ως κοινόχρηστα στο τμήμα του υπαλλήλου',
      () async {
        final deptId = await insertDepartment('Γραμματεία');
        final annaId = await insertUser(
          firstName: 'Άννα',
          lastName: 'Α',
          departmentId: deptId,
          phones: ['2100'],
        );
        final plan = buildBulkUserClearPlan(
          selectedUsers: [
            user(annaId, 'Άννα', 'Α', deptId: deptId, phones: ['2100']),
          ],
          field: BulkClearField.phones,
          fate: BulkClearFate.shareInOwnDepartment,
        );

        late BulkActionUndoRecord record;
        await db.transaction((txn) async {
          record = await applyBulkUserClearInTxn(txn, db, plan);
        });

        expect(await userPhones(annaId), isEmpty);
        final direct = await PhoneRepository(db).getDepartmentDirectPhonesMap();
        expect(direct[deptId], contains('2100'));

        await applyBulkActionUndo(db, record);
        expect(await userPhones(annaId), ['2100']);
        final directAfter = await PhoneRepository(
          db,
        ).getDepartmentDirectPhonesMap();
        expect(directAfter[deptId] ?? const [], isNot(contains('2100')));
      },
    );

    test('εξαίρεση: τηλέφωνο κοινό με μη επιλεγμένο δεν καθαρίζεται', () {
      final plan = buildBulkUserClearPlan(
        selectedUsers: [
          user(1, 'Άννα', 'Α', deptId: 10, phones: ['2100']),
        ],
        field: BulkClearField.phones,
        fate: BulkClearFate.deleteOutright,
        sharing: const BulkAssetSharingInfo(
          phoneOtherUserNames: {
            '2100': ['Γιάννης Γ'],
          },
        ),
      );
      expect(plan.hasWork, isFalse);
      expect(plan.exclusions.single.reason, contains('Γιάννης Γ'));
    });

    test(
      'σημειώσεις: διαγραφή μόνο όσων έχουν περιεχόμενο + επαναφορά',
      () async {
        final deptId = await insertDepartment('Γραμματεία');
        final annaId = await insertUser(
          firstName: 'Άννα',
          lastName: 'Α',
          departmentId: deptId,
          notes: 'κάτι σημαντικό',
        );
        final models = [
          user(annaId, 'Άννα', 'Α', deptId: deptId, notes: 'κάτι σημαντικό'),
        ];
        final plan = buildBulkUserClearPlan(
          selectedUsers: models,
          field: BulkClearField.notes,
          fate: BulkClearFate.deleteOutright,
        );
        expect(plan.hasWork, isTrue);

        late BulkActionUndoRecord record;
        await db.transaction((txn) async {
          record = await applyBulkUserClearInTxn(txn, db, plan);
        });
        expect(((await userRow(annaId))['notes'] as String?) ?? '', isEmpty);

        await applyBulkActionUndo(db, record);
        expect((await userRow(annaId))['notes'], 'κάτι σημαντικό');
      },
    );
  });

  group(
    'Χαρακτηρισμός: η μαζική ενημέρωση πεδίων-ταυτότητας δεν υπάρχει πια',
    () {
      test('ο UserRepository διατηρεί bulkUpdateUsers για άλλες χρήσεις', () {
        // Ο νέος διάλογος δεν γράφει ποτέ Επώνυμο/Όνομα/Τηλέφωνο μαζικά — η
        // υπηρεσία εκθέτει ΜΟΝΟ μεταφορά, σημειώσεις και καθαρισμό.
        expect(UserRepository(db).bulkUpdateUsers, isNotNull);
        expect(BulkClearField.values, hasLength(3));
        expect(BulkTransferAssetFate.values, hasLength(2));
      });
    },
  );
}
