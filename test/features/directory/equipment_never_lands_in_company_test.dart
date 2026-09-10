// Καμία ροή δεν χρεώνει εξοπλισμό σε τμήμα με Είδος «Εταιρεία».
//
// Η εταιρεία δεν κρατά δικά μας μηχανήματα (DepartmentKind.canOwnEquipment).
// Οι φόρμες που ρωτούν το Είδος το τηρούν ήδη· εδώ φυλάσσονται οι ροές που
// έγραφαν τμήμα χωρίς να το ρωτήσουν.
//
//   flutter test test/features/directory/equipment_never_lands_in_company_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/models/department_kind.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:call_logger/features/directory/services/bulk_user_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('equipment_company_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/kind_guard.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  Future<int> insertDepartment(String name, DepartmentKind kind) {
    return db.insert('departments', {
      'name': name,
      'name_key': SearchTextNormalizer.normalizeForSearch(name),
      'kind': kind.dbValue,
      'is_deleted': 0,
    });
  }

  Future<int> insertUser(String first, String last, int departmentId) {
    return db.insert('users', {
      'first_name': first,
      'last_name': last,
      'department_id': departmentId,
      'is_deleted': 0,
    });
  }

  Future<int> insertEquipment(String code, int departmentId, int ownerId) async {
    final id = await db.insert('equipment', {
      'code_equipment': code,
      'department_id': departmentId,
      'is_deleted': 0,
    });
    await db.insert('user_equipment', {'user_id': ownerId, 'equipment_id': id});
    return id;
  }

  group('Μαζική μεταφορά υπαλλήλων σε εταιρεία', () {
    test('ο εξοπλισμός δεν ακολουθεί — ζητά νέα στέγη', () async {
      final klinikh = await insertDepartment('Καρδιολογική', DepartmentKind.hospital);
      final dataMed = await insertDepartment('DataMed', DepartmentKind.company);
      final annaId = await insertUser('Άννα', 'Αντωνίου', klinikh);
      await insertEquipment('PC-5067', klinikh, annaId);

      final plan = buildBulkUserTransferPlan(
        selectedUsers: [
          UserModel(
            id: annaId,
            firstName: 'Άννα',
            lastName: 'Αντωνίου',
            departmentId: klinikh,
          ),
        ],
        target: SharedAssetTransferTarget.existing(dataMed),
        targetDisplayName: 'DataMed',
        targetKind: DepartmentKind.company,
        phoneFate: BulkTransferAssetFate.follow,
        equipmentFate: BulkTransferAssetFate.follow,
        equipmentByUserId: {
          annaId: [
            EquipmentModel(id: 1, code: 'PC-5067', departmentId: klinikh),
          ],
        },
      );

      expect(
        plan.equipmentToFollow,
        isEmpty,
        reason: 'Η εταιρεία δεν κρατά δικά μας μηχανήματα',
      );
      expect(
        plan.equipmentNeedingNewHome.map((e) => e.code),
        ['PC-5067'],
        reason: 'Το μηχάνημα ζητά ρητή απάντηση «πού πάει»',
      );
    });

    test('η απάντηση «πού πάει» γράφεται όντως στη βάση', () async {
      final klinikh = await insertDepartment(
        'Καρδιολογική',
        DepartmentKind.hospital,
      );
      final tep = await insertDepartment('ΤΕΠ', DepartmentKind.hospital);
      final dataMed = await insertDepartment('DataMed', DepartmentKind.company);
      final annaId = await insertUser('Άννα', 'Αντωνίου', klinikh);
      final eqId = await insertEquipment('PC-5067', klinikh, annaId);

      final plan =
          buildBulkUserTransferPlan(
            selectedUsers: [
              UserModel(
                id: annaId,
                firstName: 'Άννα',
                lastName: 'Αντωνίου',
                departmentId: klinikh,
              ),
            ],
            target: SharedAssetTransferTarget.existing(dataMed),
            targetDisplayName: 'DataMed',
            targetKind: DepartmentKind.company,
            phoneFate: BulkTransferAssetFate.follow,
            equipmentFate: BulkTransferAssetFate.follow,
            equipmentByUserId: {
              annaId: [
                EquipmentModel(id: eqId, code: 'PC-5067', departmentId: klinikh),
              ],
            },
          ).withEquipmentRehoming(
            SharedAssetDisconnectBatchResult(
              equipmentTransfers: {
                'PC-5067': SharedAssetTransferTarget.existing(tep),
              },
            ),
          );

      await db.transaction((txn) async {
        await applyBulkUserTransferInTxn(txn, db, plan);
      });

      final userRows = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [annaId],
      );
      expect(
        userRows.first['department_id'],
        dataMed,
        reason: 'Ο άνθρωπος μετακόμισε κανονικά στην εταιρεία',
      );

      final eqRows = await db.query(
        'equipment',
        where: 'id = ?',
        whereArgs: [eqId],
      );
      expect(
        eqRows.first['department_id'],
        tep,
        reason: 'Το μηχάνημα πήγε εκεί που είπε ο χρήστης, όχι στην εταιρεία',
      );

      final links = await db.query(
        'user_equipment',
        where: 'user_id = ? AND equipment_id = ?',
        whereArgs: [annaId, eqId],
      );
      expect(
        links,
        isEmpty,
        reason: 'Ο κάτοχος έφυγε σε τμήμα που δεν κρατά εξοπλισμό',
      );
    });

    test('σε τμήμα νοσοκομείου ο εξοπλισμός ακολουθεί κανονικά', () async {
      final klinikh = await insertDepartment('Καρδιολογική', DepartmentKind.hospital);
      final tep = await insertDepartment('ΤΕΠ', DepartmentKind.hospital);
      final annaId = await insertUser('Άννα', 'Αντωνίου', klinikh);
      await insertEquipment('PC-5067', klinikh, annaId);

      final plan = buildBulkUserTransferPlan(
        selectedUsers: [
          UserModel(
            id: annaId,
            firstName: 'Άννα',
            lastName: 'Αντωνίου',
            departmentId: klinikh,
          ),
        ],
        target: SharedAssetTransferTarget.existing(tep),
        targetDisplayName: 'ΤΕΠ',
        targetKind: DepartmentKind.hospital,
        phoneFate: BulkTransferAssetFate.follow,
        equipmentFate: BulkTransferAssetFate.follow,
        equipmentByUserId: {
          annaId: [
            EquipmentModel(id: 1, code: 'PC-5067', departmentId: klinikh),
          ],
        },
      );

      expect(plan.equipmentToFollow[annaId], hasLength(1));
      expect(plan.equipmentNeedingNewHome, isEmpty);
    });
  });

  group('Επιλογέας τμήματος-προορισμού', () {
    final departments = [
      DepartmentModel(id: 10, name: 'Καρδιολογική'),
      DepartmentModel(id: 20, name: 'DataMed', kind: DepartmentKind.company),
      DepartmentModel(
        id: 30,
        name: 'ΚΥ Σουφλίου',
        kind: DepartmentKind.externalUnit,
      ),
    ];

    Future<void> openPicker(
      WidgetTester tester, {
      required bool involvesEquipment,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showAssetTransferTargetPicker(
                  context: context,
                  headerLabel: 'Μεταφορά δοκιμής',
                  availableDepartments: departments,
                  involvesEquipment: involvesEquipment,
                ),
                child: const Text('Άνοιγμα'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Άνοιγμα'));
      await tester.pumpAndSettle();
    }

    testWidgets('για εξοπλισμό η εταιρεία δεν προτείνεται', (tester) async {
      await openPicker(tester, involvesEquipment: true);

      await tester.enterText(find.byType(TextField), 'Data');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('DataMed'), findsNothing);

      // Η εξωτερική μονάδα ΚΡΑΤΑ δικά μας μηχανήματα και μένει προορισμός.
      await tester.enterText(find.byType(TextField), 'ΚΥ');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('ΚΥ Σουφλίου'), findsWidgets);
    });

    testWidgets('η εταιρεία δεν περνά ούτε πληκτρολογημένη', (tester) async {
      await openPicker(tester, involvesEquipment: true);

      // Η λίστα δεν την προτείνει, αλλά το πεδίο δέχεται ό,τι γραφτεί — και ο
      // επιλυτής προορισμού είναι get-or-create: θα κατέληγε στην εταιρεία.
      await tester.enterText(find.byType(TextField), 'DataMed');
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('δεν κρατά δικά μας'), findsOneWidget);
    });

    testWidgets('για τηλέφωνα η εταιρεία προτείνεται κανονικά', (tester) async {
      await openPicker(tester, involvesEquipment: false);
      await tester.enterText(find.byType(TextField), 'Data');
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('DataMed'), findsWidgets);
    });
  });
}
