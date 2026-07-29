// Μαζικές ενέργειες τμημάτων: εγγραφή πεδίων, ομάδα, ορατότητα χάρτη,
// καθαρισμός μόνο δικών του πεδίων και ΠΛΗΡΗΣ αναίρεση.
//
//   flutter test test/features/directory/bulk_department_actions_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/services/bulk_action_undo_record.dart';
import 'package:call_logger/features/directory/services/bulk_department_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('bulk_department_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/bulk_dept.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  Future<int> insertDepartment(
    String name, {
    String? building,
    String? color,
    String? notes,
    String? groupName,
    int mapHidden = 0,
  }) => db.insert('departments', {
    'name': name,
    'name_key': SearchTextNormalizer.normalizeForSearch(name),
    'building': building,
    'color': color,
    'notes': notes,
    'group_name': groupName,
    'map_hidden': mapHidden,
    'is_deleted': 0,
  });

  Future<Map<String, dynamic>> departmentRow(int id) async {
    final rows = await db.query(
      'departments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.first;
  }

  DepartmentModel model(
    int id,
    String name, {
    String? building,
    String? notes,
    String? groupName,
    bool hidden = false,
  }) => DepartmentModel(
    id: id,
    name: name,
    building: building,
    notes: notes,
    groupName: groupName,
    isHiddenOnMap: hidden,
  );

  group('Ομάδα τμημάτων', () {
    test('προτάσεις: μοναδικές, ταξινομημένες, χωρίς κενές', () {
      final groups = existingDepartmentGroups([
        model(1, 'Α', groupName: 'Κλινικές'),
        model(2, 'Β', groupName: 'Εργαστήρια'),
        model(3, 'Γ', groupName: '  '),
        model(4, 'Δ'),
        model(5, 'Ε', groupName: 'κλινικές'),
      ]);
      expect(groups, ['Εργαστήρια', 'Κλινικές']);
    });

    test('μαζικός ορισμός ομάδας + αναίρεση', () async {
      final a = await insertDepartment('Αιματολογικό');
      final b = await insertDepartment('Βιοχημικό');

      late BulkActionUndoRecord record;
      await db.transaction((txn) async {
        record = await applyBulkDepartmentFieldInTxn(
          txn,
          departments: [model(a, 'Αιματολογικό'), model(b, 'Βιοχημικό')],
          column: 'group_name',
          value: 'Εργαστήρια',
        );
      });
      expect((await departmentRow(a))['group_name'], 'Εργαστήρια');
      expect((await departmentRow(b))['group_name'], 'Εργαστήρια');

      await applyBulkActionUndo(db, record);
      expect((await departmentRow(a))['group_name'], isNull);
      expect((await departmentRow(b))['group_name'], isNull);
    });
  });

  group('Πεδία και σημειώσεις', () {
    test('προσθήκη σημειώσεων σε νέα γραμμή + αναίρεση', () async {
      final id = await insertDepartment('Γραμματεία', notes: 'παλιά');

      late BulkActionUndoRecord record;
      await db.transaction((txn) async {
        record = await applyBulkDepartmentFieldInTxn(
          txn,
          departments: [model(id, 'Γραμματεία', notes: 'παλιά')],
          column: 'notes',
          value: 'νέα γραμμή',
          notesMode: BulkDepartmentNotesMode.append,
        );
      });
      expect((await departmentRow(id))['notes'], 'παλιά\nνέα γραμμή');

      await applyBulkActionUndo(db, record);
      expect((await departmentRow(id))['notes'], 'παλιά');
    });

    test('χρώμα: μόνο αλλαγή, με επαναφορά της παλιάς τιμής', () async {
      final id = await insertDepartment('Αιμοδοσία', color: '#111111');

      late BulkActionUndoRecord record;
      await db.transaction((txn) async {
        record = await applyBulkDepartmentFieldInTxn(
          txn,
          departments: [model(id, 'Αιμοδοσία')],
          column: 'color',
          value: '#22AA33',
        );
      });
      expect((await departmentRow(id))['color'], '#22AA33');

      await applyBulkActionUndo(db, record);
      expect((await departmentRow(id))['color'], '#111111');
    });

    test('ορατότητα χάρτη: απόκρυψη και επαναφορά', () async {
      final id = await insertDepartment('Ακτινολογικό');
      expect((await departmentRow(id))['map_hidden'], 0);

      late BulkActionUndoRecord record;
      await db.transaction((txn) async {
        record = await applyBulkDepartmentFieldInTxn(
          txn,
          departments: [model(id, 'Ακτινολογικό')],
          column: 'map_hidden',
          value: 1,
        );
      });
      expect((await departmentRow(id))['map_hidden'], 1);

      await applyBulkActionUndo(db, record);
      expect((await departmentRow(id))['map_hidden'], 0);
    });
  });

  group('Καθαρισμός — μόνο δικά του πεδία', () {
    test('τα ήδη κενά τμήματα δεν μετράνε στο σχέδιο', () {
      final plan = buildBulkDepartmentClearPlan(
        selectedDepartments: [
          model(1, 'Α', building: 'Β1'),
          model(2, 'Β'),
          model(3, 'Γ', building: '   '),
        ],
        field: BulkDepartmentClearField.building,
      );
      expect(plan.departments.map((d) => d.id), [1]);
      expect(bulkDepartmentClearConfirmationText(plan), contains('1 τμήματα'));
    });

    test('καθαρισμός κτιρίου + αναίρεση', () async {
      final id = await insertDepartment('Φαρμακείο', building: 'Β2');
      final plan = buildBulkDepartmentClearPlan(
        selectedDepartments: [model(id, 'Φαρμακείο', building: 'Β2')],
        field: BulkDepartmentClearField.building,
      );
      expect(plan.hasWork, isTrue);

      late BulkActionUndoRecord record;
      await db.transaction((txn) async {
        record = await applyBulkDepartmentClearInTxn(txn, plan);
      });
      expect((await departmentRow(id))['building'], isNull);

      await applyBulkActionUndo(db, record);
      expect((await departmentRow(id))['building'], 'Β2');
    });

    test('τα πεδία καθαρισμού είναι μόνο κτίριο, ομάδα, σημειώσεις', () {
      // Καμία ενέργεια πάνω σε μέλη: υπάλληλοι/εξοπλισμός/τηλέφωνα δεν είναι
      // χαρακτηριστικά του τμήματος και δεν καθαρίζονται ποτέ από εδώ.
      expect(BulkDepartmentClearField.values, hasLength(3));
      expect(BulkDepartmentClearField.values.map(bulkDepartmentClearColumn), [
        'building',
        'group_name',
        'notes',
      ]);
      expect(
        BulkDepartmentClearField.values.map((f) => f.name),
        isNot(anyElement(anyOf('users', 'equipment', 'phones', 'color'))),
      );
    });
  });
}
