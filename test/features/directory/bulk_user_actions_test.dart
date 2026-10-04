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
import 'package:call_logger/features/directory/models/department_kind.dart';
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

  group('judgePhoneStayBehind — ο κοινός κανόνας των δύο ροών', () {
    test('καθαρά προσωπικός αριθμός: αποδεσμεύεται', () {
      final d = judgePhoneStayBehind(
        phone: '2200',
        userName: 'Σοφία Σπυροπούλου',
        oldDepartmentId: 46,
      );
      expect(d.releases, isTrue);
      expect(d.blockedReason, isNull);
    });

    test('ήδη κοινόχρηστο ΤΟΥ ΠΑΛΙΟΥ τμήματος: αποδεσμεύεται', () {
      final d = judgePhoneStayBehind(
        phone: '2511',
        userName: 'Σοφία Σπυροπούλου',
        oldDepartmentId: 46,
        sharedDepartment: (id: 46, name: 'Αιμοδοσία'),
      );
      expect(d.releases, isTrue);
    });

    test('κοινόχρηστο ΤΡΙΤΟΥ τμήματος: μένει στον υπάλληλο', () {
      final d = judgePhoneStayBehind(
        phone: '2511',
        userName: 'Σοφία Σπυροπούλου',
        oldDepartmentId: 46,
        sharedDepartment: (id: 99, name: 'Φαρμακείο'),
      );
      expect(d.releases, isFalse);
      expect(d.blockedReason, contains('Φαρμακείο'));
    });

    test('χωρίς τμήμα-αφετηρία: δεν υπάρχει πού να μείνει', () {
      final d = judgePhoneStayBehind(
        phone: '2200',
        userName: 'Σοφία Σπυροπούλου',
        oldDepartmentId: null,
      );
      expect(d.releases, isFalse);
      expect(d.blockedReason, contains('τμήμα-αφετηρία'));
    });
  });

  group('judgeEquipmentStayBehind — ο κοινός κανόνας του εξοπλισμού', () {
    test('μηχάνημα με τμήμα: αποδεσμεύεται από τον υπάλληλο', () {
      final d = judgeEquipmentStayBehind(
        code: '3564',
        userName: 'Σοφία Σπυροπούλου',
        oldDepartmentId: 46,
        equipmentDepartmentId: 46,
      );
      expect(d.releases, isTrue);
      expect(d.blockedReason, isNull);
    });

    test('μηχάνημα χωρίς τμήμα αλλά με τμήμα-αφετηρία: αποδεσμεύεται', () {
      final d = judgeEquipmentStayBehind(
        code: '3564',
        userName: 'Σοφία Σπυροπούλου',
        oldDepartmentId: 46,
        equipmentDepartmentId: null,
      );
      expect(d.releases, isTrue);
    });

    test('ούτε μηχάνημα ούτε υπάλληλος έχουν τμήμα: θα έμενε ορφανό', () {
      final d = judgeEquipmentStayBehind(
        code: '3564',
        userName: 'Σοφία Σπυροπούλου',
        oldDepartmentId: null,
        equipmentDepartmentId: null,
      );
      expect(d.releases, isFalse);
      expect(d.blockedReason, contains('ορφανός'));
    });
  });

  group('Σχέδιο μεταφοράς — εξαιρέσεις και μερική μεταφορά', () {
    // Ο προορισμός δεν κρατά εσωτερικά του νοσοκομείου: το 2534 μένει πίσω
    // ακόμη και με «Ακολουθούν» — αυτό λέει ήδη ο διάλογος (04/10).
    test('εταιρεία με «Ακολουθούν»: το εσωτερικό μένει στο παλιό τμήμα', () {
      final plan = buildBulkUserTransferPlan(
        selectedUsers: [
          user(
            1,
            'Μαρία',
            'Νακαστσή',
            deptId: 10,
            phones: ['2534', '6971234567'],
          ),
        ],
        target: const SharedAssetTransferTarget.existing(30),
        targetDisplayName: 'DataMed',
        targetKind: DepartmentKind.company,
        phoneFate: BulkTransferAssetFate.follow,
        equipmentFate: BulkTransferAssetFate.follow,
        equipmentByUserId: const {},
        phonesThatCannotFollow: const {'2534'},
      );
      expect(plan.phonesToRelease[1], ['2534']);
      expect(
        bulkTransferConfirmationText(plan),
        contains('Το 2534 είναι εσωτερικό του νοσοκομείου και δεν ακολουθεί'),
      );
    });

    test('κοινό εσωτερικό σε εταιρεία: μένει χωρίς ερώτηση', () {
      final plan = buildBulkUserTransferPlan(
        selectedUsers: [
          user(1, 'Μαρία', 'Νακαστσή', deptId: 10, phones: ['2534']),
        ],
        target: const SharedAssetTransferTarget.existing(30),
        targetDisplayName: 'DataMed',
        targetKind: DepartmentKind.company,
        phoneFate: BulkTransferAssetFate.follow,
        equipmentFate: BulkTransferAssetFate.follow,
        equipmentByUserId: const {},
        sharing: const BulkAssetSharingInfo(
          phoneOtherUserNames: {
            '2534': ['Διακομοπούλου'],
          },
        ),
        sharedPhoneFate: SharedAssetFate.movesWithOwner,
        phonesThatCannotFollow: const {'2534'},
      );
      expect(plan.sharedPhones, isEmpty, reason: 'Δεν ρωτιέται');
      expect(plan.phonesTakenFromCoOwners, isEmpty);
      expect(plan.phonesToRelease[1], ['2534']);
    });

    test('όσοι είναι ήδη στο τμήμα-προορισμό δεν μετακινούνται', () {
      final plan = buildBulkUserTransferPlan(
        selectedUsers: [
          user(1, 'Άννα', 'Α', deptId: 10),
          user(2, 'Βασίλης', 'Β', deptId: 20),
        ],
        target: const SharedAssetTransferTarget.existing(20),
        targetDisplayName: 'Αιμοδοσία',
        targetKind: DepartmentKind.hospital,
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

    // Κοινό τηλέφωνο (το κρατά και κάποιος που ΔΕΝ μεταφέρεται): ρωτιέται η
    // τύχη του ίδιου του αριθμού — απόφαση Διευθυντή 04/10.
    BulkUserTransferPlan sharedPhonePlan(
      SharedAssetFate fate, {
      BulkTransferAssetFate phoneFate = BulkTransferAssetFate.follow,
    }) => buildBulkUserTransferPlan(
      selectedUsers: [
        user(1, 'Μαρία', 'Νακαστσή', deptId: 10, phones: ['2534', '2200']),
      ],
      target: const SharedAssetTransferTarget.existing(20),
      targetDisplayName: 'Άδειες',
      targetKind: DepartmentKind.hospital,
      phoneFate: phoneFate,
      equipmentFate: BulkTransferAssetFate.follow,
      equipmentByUserId: const {},
      sharing: const BulkAssetSharingInfo(
        phoneOtherUserNames: {
          '2534': ['Διακομοπούλου'],
        },
      ),
      sharedPhoneFate: fate,
    );

    test('κοινό τηλέφωνο: δεν μπλοκάρεται, ρωτιέται', () {
      final plan = sharedPhonePlan(
        SharedAssetFate.staysInDepartment,
        phoneFate: BulkTransferAssetFate.stayInOldDepartment,
      );
      expect(plan.sharedPhones.single.phone, '2534');
      expect(plan.sharedPhones.single.otherOwnerNames, ['Διακομοπούλου']);
      expect(plan.exclusions, isEmpty);
      // Το δικό της τηλέφωνο κρίνεται κανονικά από τη γενική απάντηση.
      expect(plan.phonesToRelease[1], ['2200']);
    });

    test('κοινό τηλέφωνο «παραμένει»: φεύγει μόνο από τη μεταφερόμενη, '
        'και με «ακολουθούν» για τα υπόλοιπα', () {
      final plan = sharedPhonePlan(SharedAssetFate.staysInDepartment);
      expect(plan.phonesLeftWithCoOwners[1], ['2534']);
      expect(plan.phonesToRelease, isEmpty);
      expect(plan.phonesTakenFromCoOwners, isEmpty);
      expect(
        bulkTransferConfirmationText(plan),
        contains('Το κοινό τηλέφωνο (2534) παραμένει στο τμήμα του'),
      );
    });

    test('κοινό τηλέφωνο «μεταφέρεται»: μένει στη μεταφερόμενη, φεύγει από '
        'τους άλλους', () {
      final plan = sharedPhonePlan(SharedAssetFate.movesWithOwner);
      expect(plan.phonesLeftWithCoOwners, isEmpty);
      expect(plan.phonesTakenFromCoOwners, {'2534'});
      expect(
        bulkTransferConfirmationText(plan),
        contains('μεταφέρεται και φεύγει από: Διακομοπούλου'),
      );
    });

    test('τηλέφωνο ΗΔΗ κοινόχρηστο του παλιού τμήματος αποδεσμεύεται', () {
      final plan = buildBulkUserTransferPlan(
        selectedUsers: [
          user(1, 'Σοφία', 'Σπυροπούλου', deptId: 10, phones: ['2511']),
        ],
        target: const SharedAssetTransferTarget.existing(20),
        targetDisplayName: 'Μεσογειακή Αναιμία',
        targetKind: DepartmentKind.hospital,
        phoneFate: BulkTransferAssetFate.stayInOldDepartment,
        equipmentFate: BulkTransferAssetFate.follow,
        equipmentByUserId: const {},
        sharing: const BulkAssetSharingInfo(
          phoneSharedDepartments: {'2511': (id: 10, name: 'Αιμοδοσία')},
        ),
      );

      // «Μένει πίσω» σημαίνει ότι φεύγει από τον άνθρωπο. Το ότι ο αριθμός
      // είναι ήδη κοινόχρηστος του τμήματος δεν αναιρεί την αποδέσμευση —
      // απλώς δεν χρειάζεται να ξαναπροστεθεί εκεί.
      expect(plan.phonesToRelease[1], ['2511']);
      expect(plan.exclusions, isEmpty);
    });

    // Κοινό μηχάνημα (τα κρατά και κάποιος που ΔΕΝ μεταφέρεται): ρωτιέται η
    // τύχη του ίδιου του μηχανήματος — απόφαση Διευθυντή 03/10.
    BulkUserTransferPlan sharedPlan(SharedAssetFate fate) =>
        buildBulkUserTransferPlan(
          selectedUsers: [user(1, 'Μαρία', 'Νακαστσή', deptId: 10)],
          target: const SharedAssetTransferTarget.existing(20),
          targetDisplayName: 'Άδειες',
          targetKind: DepartmentKind.hospital,
          phoneFate: BulkTransferAssetFate.follow,
          // Η γενική απάντηση δεν αγγίζει τα κοινά μηχανήματα.
          equipmentFate: BulkTransferAssetFate.follow,
          equipmentByUserId: {
            1: [EquipmentModel(id: 7, code: '3140', departmentId: 10)],
          },
          sharing: const BulkAssetSharingInfo(
            equipmentOtherUserNames: {
              7: ['Διακομοπούλου'],
            },
          ),
          sharedEquipmentFate: fate,
        );

    test('κοινό μηχάνημα: δεν μπλοκάρεται, ρωτιέται', () {
      final plan = sharedPlan(SharedAssetFate.staysInDepartment);
      expect(plan.sharedEquipment.single.equipment.code, '3140');
      expect(plan.sharedEquipment.single.otherOwnerNames, ['Διακομοπούλου']);
      expect(plan.exclusions, isEmpty);
    });

    test('κοινό μηχάνημα «παραμένει»: φεύγει μόνο από τη μεταφερόμενη', () {
      final plan = sharedPlan(SharedAssetFate.staysInDepartment);
      expect(plan.equipmentToRelease[1]!.single.code, '3140');
      expect(plan.equipmentToFollow, isEmpty);
      expect(plan.equipmentTakenFromCoOwners, isEmpty);
      expect(
        bulkTransferConfirmationText(plan),
        contains('Ο κοινός εξοπλισμός (3140) παραμένει στο τμήμα του'),
      );
    });

    test('κοινό μηχάνημα «μεταφέρεται»: ακολουθεί, φεύγει από τους άλλους', () {
      final plan = sharedPlan(SharedAssetFate.movesWithOwner);
      expect(plan.equipmentToFollow[1]!.single.code, '3140');
      expect(plan.equipmentToRelease, isEmpty);
      expect(plan.equipmentTakenFromCoOwners, {7});
      expect(
        bulkTransferConfirmationText(plan),
        contains('μεταφέρεται και φεύγει από: Διακομοπούλου'),
      );
    });
  });

  group('Μεταφορά — εφαρμογή και πλήρης αναίρεση', () {
    // Το 2534 όπως στη βάση του σπιτιού: κοινόχρηστο της Γραμματείας και
    // προσωπικό δύο υπαλλήλων της.
    Future<({int secretariat, int leaves, int nakastsi, int diakomopoulou})>
    seedSharedPhone() async {
      final secretariat = await insertDepartment('Γραμματεία ΤΕΠ');
      final leaves = await insertDepartment('Άδειες');
      final nakastsi = await insertUser(
        firstName: 'Μαρία',
        lastName: 'Νακαστσή',
        departmentId: secretariat,
        phones: ['2534'],
      );
      final diakomopoulou = await insertUser(
        firstName: 'Ελένη',
        lastName: 'Διακομοπούλου',
        departmentId: secretariat,
        phones: ['2534'],
      );
      await PhoneRepository(db).addDepartmentDirectPhone(secretariat, '2534');
      return (
        secretariat: secretariat,
        leaves: leaves,
        nakastsi: nakastsi,
        diakomopoulou: diakomopoulou,
      );
    }

    Future<BulkActionUndoRecord> transferSharedPhone(
      ({int secretariat, int leaves, int nakastsi, int diakomopoulou}) ids,
      SharedAssetFate fate,
    ) async {
      final plan = buildBulkUserTransferPlan(
        selectedUsers: [
          user(
            ids.nakastsi,
            'Μαρία',
            'Νακαστσή',
            deptId: ids.secretariat,
            phones: ['2534'],
          ),
        ],
        target: SharedAssetTransferTarget.existing(ids.leaves),
        targetDisplayName: 'Άδειες',
        targetKind: DepartmentKind.hospital,
        phoneFate: BulkTransferAssetFate.follow,
        equipmentFate: BulkTransferAssetFate.follow,
        equipmentByUserId: const {},
        sharing: BulkAssetSharingInfo(
          phoneOtherUserNames: const {
            '2534': ['Διακομοπούλου'],
          },
          phoneSharedDepartments: {
            '2534': (id: ids.secretariat, name: 'Γραμματεία ΤΕΠ'),
          },
        ),
        sharedPhoneFate: fate,
      );
      late BulkActionUndoRecord record;
      await db.transaction((txn) async {
        record = await applyBulkUserTransferInTxn(txn, db, plan);
      });
      return record;
    }

    Future<Set<int>> phoneDepartments() =>
        PhoneRepository(db).sharedDepartmentIds('2534');

    test('κοινό τηλέφωνο «παραμένει»: φεύγει από τη μεταφερόμενη, μένει στη '
        'συνάδελφο και στο τμήμα, η αναίρεση το επιστρέφει', () async {
      final ids = await seedSharedPhone();
      final record = await transferSharedPhone(
        ids,
        SharedAssetFate.staysInDepartment,
      );

      expect(await userPhones(ids.nakastsi), isEmpty);
      expect(await userPhones(ids.diakomopoulou), ['2534']);
      expect(await phoneDepartments(), {ids.secretariat});

      await applyBulkActionUndo(db, record);
      expect(await userPhones(ids.nakastsi), ['2534']);
      expect(await userPhones(ids.diakomopoulou), ['2534']);
      expect(await phoneDepartments(), {ids.secretariat});
    });

    test(
      'κοινό τηλέφωνο «μεταφέρεται»: φεύγει από τη συνάδελφο, γίνεται '
      'κοινόχρηστο του νέου τμήματος, η αναίρεση τα επιστρέφει όλα',
      () async {
        final ids = await seedSharedPhone();
        final record = await transferSharedPhone(
          ids,
          SharedAssetFate.movesWithOwner,
        );

        expect(await userPhones(ids.nakastsi), ['2534']);
        expect(await userPhones(ids.diakomopoulou), isEmpty);
        expect(await phoneDepartments(), {ids.leaves});

        await applyBulkActionUndo(db, record);
        expect(await userPhones(ids.nakastsi), ['2534']);
        expect(await userPhones(ids.diakomopoulou), ['2534']);
        expect(await phoneDepartments(), {ids.secretariat});
      },
    );

    test(
      'κοινό μηχάνημα «μεταφέρεται»: φεύγει από τη συν-κάτοχο, η αναίρεση το επιστρέφει',
      () async {
        final secretariat = await insertDepartment('Γραμματεία');
        final leaves = await insertDepartment('Άδειες');
        final nakastsi = await insertUser(
          firstName: 'Μαρία',
          lastName: 'Νακαστσή',
          departmentId: secretariat,
        );
        final diakomopoulou = await insertUser(
          firstName: 'Ελένη',
          lastName: 'Διακομοπούλου',
          departmentId: secretariat,
        );
        final eqId = await insertEquipment(
          '3140',
          departmentId: secretariat,
          ownerIds: [nakastsi, diakomopoulou],
        );

        final plan = buildBulkUserTransferPlan(
          selectedUsers: [
            user(nakastsi, 'Μαρία', 'Νακαστσή', deptId: secretariat),
          ],
          target: SharedAssetTransferTarget.existing(leaves),
          targetDisplayName: 'Άδειες',
          targetKind: DepartmentKind.hospital,
          phoneFate: BulkTransferAssetFate.follow,
          equipmentFate: BulkTransferAssetFate.follow,
          equipmentByUserId: {
            nakastsi: [
              EquipmentModel(id: eqId, code: '3140', departmentId: secretariat),
            ],
          },
          sharing: BulkAssetSharingInfo(
            equipmentOtherUserNames: {
              eqId: ['Διακομοπούλου'],
            },
          ),
          sharedEquipmentFate: SharedAssetFate.movesWithOwner,
        );

        late BulkActionUndoRecord record;
        await db.transaction((txn) async {
          record = await applyBulkUserTransferInTxn(txn, db, plan);
        });

        Future<List<Object?>> owners() async => (await db.query(
          'user_equipment',
          where: 'equipment_id = ?',
          whereArgs: [eqId],
        )).map((r) => r['user_id']).toList();
        Future<Object?> department() async => (await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [eqId],
        )).single['department_id'];

        expect(await owners(), [nakastsi]);
        expect(await department(), leaves);

        await applyBulkActionUndo(db, record);
        expect((await owners())..sort(), [nakastsi, diakomopoulou]..sort());
        expect(await department(), secretariat);
      },
    );

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
          targetKind: DepartmentKind.hospital,
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
        targetKind: DepartmentKind.hospital,
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
