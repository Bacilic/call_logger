import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/*
 * Το όνομα τμήματος του χρήστη είναι ΚΑΝΟΝΙΚΟ πεδίο που γεμίζει το repository
 * στη φόρτωση — όχι κρυφή αναζήτηση στο singleton του καταλόγου.
 *
 * Σημασιολογία (ταυτόσημη με το παλιό cache):
 *   - null  → χρήστης χωρίς τμήμα
 *   - ''    → department_id χωρίς ενεργή εγγραφή (σβησμένο/ανύπαρκτο τμήμα)
 *   - όνομα → ενεργό τμήμα
 *
 *   flutter test test/core/database/user_repository_department_name_test.dart
 */

void main() {
  group('UserRepository.getAllUsers — department_name', () {
    late UserRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'user_repo_dept_name_test_',
      );
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/dept_name.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('user_phones');
      await db.delete('users');
      await db.delete('departments');
      repo = UserRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Map<String, dynamic> deptRow(String name, {bool deleted = false}) => {
      'name': name,
      'name_key': SearchTextNormalizer.normalizeForSearch(name),
      'is_deleted': deleted ? 1 : 0,
    };

    test('γεμίζει όνομα, κενό για σβησμένο τμήμα, null χωρίς τμήμα', () async {
      final activeId = await db.insert('departments', deptRow('Πληροφορική'));
      final deletedId = await db.insert(
        'departments',
        deptRow('Παλιό Τμήμα', deleted: true),
      );
      await db.insert('users', {
        'first_name': 'Βασίλης',
        'last_name': 'Δρόσος',
        'department_id': activeId,
        'is_deleted': 0,
      });
      await db.insert('users', {
        'first_name': 'Ορφανός',
        'last_name': 'Τμήματος',
        'department_id': deletedId,
        'is_deleted': 0,
      });
      await db.insert('users', {
        'first_name': 'Χωρίς',
        'last_name': 'Τμήμα',
        'is_deleted': 0,
      });

      final rows = await repo.getAllUsers();
      final byFirst = {
        for (final r in rows) r['first_name'] as String: UserModel.fromMap(r),
      };

      expect(byFirst['Βασίλης']!.departmentName, 'Πληροφορική');
      expect(
        byFirst['Ορφανός']!.departmentName,
        '',
        reason: 'Σβησμένο τμήμα → κενό όνομα, όπως το παλιό cache',
      );
      expect(byFirst['Χωρίς']!.departmentName, isNull);
    });

    test('το μοντέλο είναι αυτάρκες — καμία εξάρτηση από singleton', () {
      // Χειροκίνητη κατασκευή χωρίς φορτωμένο κατάλογο: το πεδίο απαντά μόνο του.
      final withName = UserModel(
        id: 1,
        firstName: 'Άννα',
        departmentId: 99,
        departmentName: 'Χρηματικό',
      );
      final withoutName = UserModel(id: 2, firstName: 'Άννα', departmentId: 99);

      expect(withName.departmentName, 'Χρηματικό');
      expect(withName.fullNameWithDepartment, 'Άννα (Χρηματικό)');
      expect(
        withoutName.departmentName,
        isNull,
        reason: 'Χωρίς γέμισμα από repository το πεδίο μένει null — όχι lookup',
      );
    });

    test('toMap δεν γράφει department_name (δεν είναι στήλη)', () {
      final u = UserModel(
        id: 1,
        firstName: 'Άννα',
        departmentId: 3,
        departmentName: 'Χρηματικό',
      );
      expect(u.toMap().containsKey('department_name'), isFalse);
    });

    test('copyWith διατηρεί και αντικαθιστά το όνομα τμήματος', () {
      final u = UserModel(id: 1, departmentId: 3, departmentName: 'Χρηματικό');
      expect(u.copyWith(notes: 'x').departmentName, 'Χρηματικό');
      expect(
        u.copyWith(departmentName: 'Πληροφορική').departmentName,
        'Πληροφορική',
      );
    });
  });
}
