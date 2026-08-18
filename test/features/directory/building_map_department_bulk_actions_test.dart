// Μαζικές ενέργειες τμημάτων στην κάτοψη: ΜΙΑ συναλλαγή, όχι μία ανά τμήμα.
//
// Πριν: ο διάλογος καλούσε το repository μέσα σε βρόχο, οπότε κάθε τμήμα
// άνοιγε δική του συναλλαγή. Τοπικά με WAL αόρατο· σε βάση δικτύου ~76 ms ανά
// εγγραφή, και —το σοβαρότερο— μια αποτυχία στη μέση άφηνε τα μισά τμήματα
// αλλαγμένα και τα μισά όχι.
//
//   flutter test test/features/directory/building_map_department_bulk_actions_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/department_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/directory/building_map/services/building_map_department_bulk_actions.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late DepartmentRepository repo;
  late Database db;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('bm_bulk_actions_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/bm_bulk.db');
    db = await DatabaseHelper.instance.database;
  });

  late int floorId;

  setUp(() async {
    await seedIsolatedTestDatabase();
    await db.delete('audit_log');
    await db.delete('departments');
    await db.delete('building_map_floors');
    repo = DepartmentRepository(db);
    // Τα ξένα κλειδιά είναι ενεργά: το floor_id πρέπει να δείχνει σε
    // υπαρκτό φύλλο κατόψης.
    floorId = await db.insert('building_map_floors', {
      'label': 'Ισόγειο',
      'image_path': 'katopsi.png',
    });
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  Future<int> addDepartment(
    String name, {
    String? color,
    int? floorId,
  }) async {
    return db.insert('departments', {
      'name': name,
      'name_key': SearchTextNormalizer.normalizeForSearch(name),
      'color': ?color,
      'floor_id': ?floorId,
    });
  }

  Future<int?> hiddenOf(int id) async {
    final rows = await db.query(
      'departments',
      columns: ['map_hidden'],
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : rows.first['map_hidden'] as int?;
  }

  group('μαζική απόκρυψη στην κάτοψη', () {
    test('κρύβει όλα τα επιλεγμένα τμήματα', () async {
      final a = await addDepartment('Ακτινολογικό');
      final b = await addDepartment('Βιοχημικό');
      final c = await addDepartment('Καρδιολογικό');

      await db.transaction(
        (txn) => setDepartmentsHiddenOnMapInTxn(
          txn,
          repository: repo,
          departmentIds: <int>[a, b, c],
          hidden: true,
        ),
      );

      expect(await hiddenOf(a), 1);
      expect(await hiddenOf(b), 1);
      expect(await hiddenOf(c), 1);
    });

    test('όλα ή τίποτα: αποτυχία δεν αφήνει μισές αλλαγές', () async {
      // Αυτό ακριβώς δεν ίσχυε πριν: με μία συναλλαγή ανά τμήμα, μια αποτυχία
      // στη μέση άφηνε τα προηγούμενα γραμμένα.
      final a = await addDepartment('Ακτινολογικό');
      final b = await addDepartment('Βιοχημικό');

      await expectLater(
        db.transaction((txn) async {
          await setDepartmentsHiddenOnMapInTxn(
            txn,
            repository: repo,
            departmentIds: <int>[a, b],
            hidden: true,
          );
          throw StateError('σκόπιμη αποτυχία μετά τις εγγραφές');
        }),
        throwsA(isA<StateError>()),
      );

      expect(await hiddenOf(a), isNot(1));
      expect(await hiddenOf(b), isNot(1));
    });

    test('κενή επιλογή δεν κάνει τίποτα', () async {
      final a = await addDepartment('Ακτινολογικό');
      await db.transaction(
        (txn) => setDepartmentsHiddenOnMapInTxn(
          txn,
          repository: repo,
          departmentIds: const <int>[],
          hidden: true,
        ),
      );
      expect(await hiddenOf(a), isNot(1));
    });
  });

  group('μαζική αφαίρεση από φύλλο κατόψης', () {
    test('καθαρίζει τη θέση και επιστρέφει τα χρώματα που ελευθερώθηκαν', () async {
      final a = await addDepartment('Ακτινολογικό', color: '#FF0000', floorId: floorId);
      final b = await addDepartment('Βιοχημικό', color: '#00FF00', floorId: floorId);
      final rows = await db.query('departments', where: 'id IN (?, ?)', whereArgs: [a, b]);
      final models = rows.map(DepartmentModel.fromMap).toList();

      final released = await db.transaction(
        (txn) => removeDepartmentsFromFloorInTxn(
          txn,
          repository: repo,
          departments: models,
        ),
      );

      // Τα χρώματα επιστρέφονται στον καλούντα — δεν τα αποδεσμεύει η υπηρεσία.
      expect(released, hasLength(2));
      expect(released, everyElement(isA<Color>()));

      final after = await db.query(
        'departments',
        columns: ['floor_id'],
        where: 'id IN (?, ?)',
        whereArgs: [a, b],
      );
      for (final row in after) {
        expect(row['floor_id'], isNull);
      }
    });

    test('τμήμα με άκυρο χρώμα δεν προσθέτει τίποτα στη λίστα', () async {
      // Το σχήμα δίνει προεπιλεγμένο χρώμα, οπότε «χωρίς χρώμα» στην πράξη
      // σημαίνει κενή ή αναγνώσιμη τιμή — εδώ ελέγχεται ο φρουρός ανάγνωσης.
      final a = await addDepartment('Ακτινολογικό', color: '', floorId: floorId);
      final rows = await db.query('departments', where: 'id = ?', whereArgs: [a]);
      final models = rows.map(DepartmentModel.fromMap).toList();

      final released = await db.transaction(
        (txn) => removeDepartmentsFromFloorInTxn(
          txn,
          repository: repo,
          departments: models,
        ),
      );

      expect(released, isEmpty);
    });

    test('όλα ή τίποτα: αποτυχία αφήνει τα τμήματα στο φύλλο τους', () async {
      final a = await addDepartment('Ακτινολογικό', color: '#FF0000', floorId: floorId);
      final rows = await db.query('departments', where: 'id = ?', whereArgs: [a]);
      final models = rows.map(DepartmentModel.fromMap).toList();

      await expectLater(
        db.transaction((txn) async {
          await removeDepartmentsFromFloorInTxn(
            txn,
            repository: repo,
            departments: models,
          );
          throw StateError('σκόπιμη αποτυχία μετά τις εγγραφές');
        }),
        throwsA(isA<StateError>()),
      );

      final after = await db.query(
        'departments',
        columns: ['floor_id'],
        where: 'id = ?',
        whereArgs: [a],
      );
      expect(after.first['floor_id'], floorId);
    });
  });
}
