import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/directory/phone_department_policy.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('LampMigrationService.detectOwnerConflicts — phone policy', () {
    late LampMigrationService service;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lamp_phone_policy_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/lamp_phone_policy.db');
      await DatabaseHelper.instance.database;
      service = LampMigrationService();
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      await db.delete('user_equipment');
      await db.delete('department_phones');
      await db.delete('user_phones');
      await db.delete('phones');
      await db.delete('equipment');
      await db.delete('users');
      await db.delete('departments');
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<void> reloadLookup() async {
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    }

    Future<int> insertDepartment(String name) async {
      final db = await DatabaseHelper.instance.database;
      return db.insert('departments', {
        'name': name,
        'name_key': SearchTextNormalizer.normalizeForSearch(name),
        'is_deleted': 0,
      });
    }

    Future<int> insertUserWithPhone({
      required String firstName,
      required String lastName,
      required int departmentId,
      required String phone,
    }) async {
      final db = await DatabaseHelper.instance.database;
      final userId = await db.insert('users', {
        'first_name': firstName,
        'last_name': lastName,
        'department_id': departmentId,
        'is_deleted': 0,
      });
      final phoneId = await db.insert('phones', {'number': phone});
      await db.insert('user_phones', {
        'user_id': userId,
        'phone_id': phoneId,
      });
      return userId;
    }

    Future<int> insertPhoneForDepartment({
      required int departmentId,
      required String phone,
    }) async {
      final db = await DatabaseHelper.instance.database;
      final existing = await db.query(
        'phones',
        where: 'number = ?',
        whereArgs: [phone],
        limit: 1,
      );
      final phoneId = existing.isNotEmpty
          ? existing.first['id'] as int
          : await db.insert('phones', {'number': phone});
      await db.insert('department_phones', {
        'department_id': departmentId,
        'phone_id': phoneId,
      });
      return phoneId;
    }

    int? targetDepartmentIdForName(String name) {
      final deptKey = SearchTextNormalizer.normalizeForSearch(name);
      for (final d in LookupService.instance.departments) {
        if (d.isDeleted || d.id == null) continue;
        if (SearchTextNormalizer.normalizeForSearch(d.name) == deptKey) {
          return d.id;
        }
      }
      return null;
    }

    List<LampOwnerConflict> phoneConflictsFromPolicy({
      required List<String> phones,
      required String departmentName,
      int? editingUserId,
    }) {
      final targetDepartmentId = departmentName.isEmpty
          ? null
          : targetDepartmentIdForName(departmentName);
      final policyConflicts = PhoneDepartmentPolicy.findConflictsForUserAssignment(
        phones: phones,
        targetDepartmentId: targetDepartmentId,
        editingUserId: editingUserId,
      );
      final expected = <LampOwnerConflict>[];
      for (final c in policyConflicts) {
        if (c.hasOtherUserOwners) {
          expected.add(
            LampOwnerConflict(
              conflictId: 'phone:${SearchTextNormalizer.normalizeForSearch(c.phone)}',
              kind: LampOwnerConflictKind.phone,
              value: c.phone,
              currentOwners: c.otherUserOwnerLabels,
            ),
          );
        } else if (c.hasDepartmentLocationConflict) {
          expected.add(
            LampOwnerConflict(
              conflictId: 'phone:${SearchTextNormalizer.normalizeForSearch(c.phone)}',
              kind: LampOwnerConflictKind.phone,
              value: c.phone,
              currentOwners: [
                'Κοινόχρηστο: ${c.existingDepartmentName ?? c.existingDepartmentId}',
              ],
            ),
          );
        }
      }
      return expected;
    }

    Map<String, String> ownerForm({
      required String phones,
      String departmentName = '',
      String equipmentCodes = '',
    }) {
      return {
        'first_name': 'Νέος',
        'last_name': 'Χρήστης',
        'phones': phones,
        'equipment_codes': equipmentCodes,
        'department_name': departmentName,
        'location': '',
        'notes': '',
      };
    }

    test(
      'τηλέφωνο άλλου χρήστη → ετικέτες πολιτικής «όνομα (τμήμα)»',
      () async {
        const phone = '2105551001';
        final deptIt = await insertDepartment('Τμήμα IT');
        await insertDepartment('Τμήμα HR');
        await insertUserWithPhone(
          firstName: 'Γιάννης',
          lastName: 'Χριστού',
          departmentId: deptIt,
          phone: phone,
        );
        await reloadLookup();

        final conflicts = await service.detectOwnerConflicts(
          formValues: ownerForm(
            phones: phone,
            departmentName: 'Τμήμα HR',
          ),
          selectedCandidateId: null,
        );

        final phoneConflicts = conflicts
            .where((c) => c.kind == LampOwnerConflictKind.phone)
            .toList();
        expect(phoneConflicts, hasLength(1));
        expect(phoneConflicts.first.value, phone);
        expect(phoneConflicts.first.currentOwners, hasLength(1));
        expect(phoneConflicts.first.currentOwners.first, contains('Γιάννης'));
        expect(phoneConflicts.first.currentOwners.first, contains('Τμήμα IT'));
        expect(phoneConflicts.first.currentOwners.first, contains('('));
      },
    );

    test('κοινόχρηστο τηλέφωνο τμήματος → «Κοινόχρηστο: <τμήμα>»', () async {
      const phone = '2105552002';
      final deptA = await insertDepartment('Φαρμακείο');
      await insertDepartment('Γραμματεία');
      await insertPhoneForDepartment(departmentId: deptA, phone: phone);
      await reloadLookup();

      final conflicts = await service.detectOwnerConflicts(
        formValues: ownerForm(
          phones: phone,
          departmentName: 'Γραμματεία',
        ),
        selectedCandidateId: null,
      );

      final phoneConflict = conflicts.singleWhere(
        (c) => c.kind == LampOwnerConflictKind.phone,
      );
      expect(phoneConflict.currentOwners, ['Κοινόχρηστο: Φαρμακείο']);
    });

    test(
      'τηλέφωνο άλλου χρήστη ΚΑΙ κοινόχρηστο → προτεραιότητα στον κάτοχο',
      () async {
        const phone = '2105553003';
        final deptA = await insertDepartment('Τμήμα Α');
        final deptB = await insertDepartment('Τμήμα Β');
        await insertUserWithPhone(
          firstName: 'Μαρία',
          lastName: 'Παπαδοπούλου',
          departmentId: deptA,
          phone: phone,
        );
        await insertPhoneForDepartment(departmentId: deptB, phone: phone);
        await reloadLookup();

        final conflicts = await service.detectOwnerConflicts(
          formValues: ownerForm(
            phones: phone,
            departmentName: 'Τμήμα Γ',
          ),
          selectedCandidateId: null,
        );

        final phoneConflicts = conflicts
            .where((c) => c.kind == LampOwnerConflictKind.phone)
            .toList();
        expect(phoneConflicts, hasLength(1));
        expect(phoneConflicts.first.currentOwners.first, contains('Μαρία'));
        expect(
          phoneConflicts.first.currentOwners.first,
          isNot(startsWith('Κοινόχρηστο:')),
        );
      },
    );

    test('συνέπεια με PhoneDepartmentPolicy.findConflictsForUserAssignment', () async {
      const phone = '2105554004';
      final deptIt = await insertDepartment('Τμήμα IT');
      await insertDepartment('Τμήμα HR');
      await insertUserWithPhone(
        firstName: 'Νίκος',
        lastName: 'Αντωνίου',
        departmentId: deptIt,
        phone: phone,
      );
      await reloadLookup();

      const departmentName = 'Τμήμα HR';
      final formValues = ownerForm(phones: phone, departmentName: departmentName);
      final actual = await service.detectOwnerConflicts(
        formValues: formValues,
        selectedCandidateId: null,
      );
      final expected = phoneConflictsFromPolicy(
        phones: [phone],
        departmentName: departmentName,
      );

      final actualPhones = actual
          .where((c) => c.kind == LampOwnerConflictKind.phone)
          .toList();
      expect(actualPhones.length, expected.length);
      for (var i = 0; i < expected.length; i++) {
        expect(actualPhones[i].conflictId, expected[i].conflictId);
        expect(actualPhones[i].value, expected[i].value);
        expect(actualPhones[i].currentOwners, expected[i].currentOwners);
      }
    });

    test(
      'ενημέρωση υπάρχοντος: δικό του τηλέφωνο δεν παράγει σύγκρουση',
      () async {
        const phone = '2105555005';
        final deptIt = await insertDepartment('Τμήμα IT');
        final userId = await insertUserWithPhone(
          firstName: 'Ελένη',
          lastName: 'Δημητρίου',
          departmentId: deptIt,
          phone: phone,
        );
        await reloadLookup();

        final conflicts = await service.detectOwnerConflicts(
          formValues: ownerForm(
            phones: phone,
            departmentName: 'Τμήμα IT',
          ),
          selectedCandidateId: userId,
        );

        expect(
          conflicts.where((c) => c.kind == LampOwnerConflictKind.phone),
          isEmpty,
        );
      },
    );

    test('κλάδος εξοπλισμού παραμένει αμετάβλητος', () async {
      const code = 'PC-CONFLICT-GUARD';
      final db = await DatabaseHelper.instance.database;
      final deptId = await insertDepartment('Τμήμα IT');
      final ownerId = await db.insert('users', {
        'first_name': 'Πέτρος',
        'last_name': 'Νικολάου',
        'department_id': deptId,
        'is_deleted': 0,
      });
      final equipmentId = await db.insert('equipment', {
        'code_equipment': code,
        'is_deleted': 0,
      });
      await db.insert('user_equipment', {
        'user_id': ownerId,
        'equipment_id': equipmentId,
      });
      await reloadLookup();

      final conflicts = await service.detectOwnerConflicts(
        formValues: ownerForm(
          phones: '',
          equipmentCodes: code,
        ),
        selectedCandidateId: null,
      );

      final equipmentConflicts = conflicts
          .where((c) => c.kind == LampOwnerConflictKind.equipment)
          .toList();
      expect(equipmentConflicts, hasLength(1));
      expect(
        equipmentConflicts.first.conflictId,
        'equipment:${SearchTextNormalizer.normalizeForSearch(code)}',
      );
      expect(equipmentConflicts.first.currentOwners, ['Πέτρος Νικολάου']);
    });
  });
}
