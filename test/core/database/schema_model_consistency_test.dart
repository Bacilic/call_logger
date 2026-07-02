import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_v1_schema.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/models/category_model.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Στήλες πίνακα που δεν αντιστοιχούν σε πεδία model (ευρετήρια, derived keys, κ.λπ.).
const _schemaOnlyColumns = <String, Set<String>>{
  // Υπολογίζεται από repository κατά insert/update — όχι πεδίο CallModel.
  'calls': {'search_index'},
  // Κανονικοποιημένο κλειδί μοναδικότητας — γράφεται από DepartmentRepository.
  'departments': {'name_key'},
  // Ευρετήριο αναζήτησης εκκρεμοτήτων — rebuild από repository layer.
  'tasks': {'search_index'},
};

/// Κλειδιά toMap() που δεν είναι στήλες του πίνακα (M2M / joins).
const _toMapOnlyKeys = <String, Set<String>>{
  'users': {'phones'},
};

/// Κλειδιά fromMap() από joins που δεν υπάρχουν στον πίνακα.
const _fromMapJoinKeys = <String, Set<String>>{
  'calls': {'caller_is_deleted', 'equipment_is_deleted', 'category'},
  'tasks': {
    'caller_is_deleted',
    'equipment_is_deleted',
    'department_is_deleted',
    'user_id',
  },
  'departments': {'direct_phones'},
};

typedef _ModelPair = ({
  String table,
  Map<String, dynamic> Function() sampleToMap,
  dynamic Function(Map<String, dynamic>) fromMap,
});

Future<Set<String>> _tableColumns(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows
      .map((row) => row['name'] as String)
      .toSet();
}

void main() {
  group('Schema ↔ model consistency', () {
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('schema_model_test_');
      await DatabaseHelper.bindTestDatabaseFile(
        p.join(dir.path, 'schema_model.db'),
      );
      db = await DatabaseHelper.instance.database;
      await ensureDepartmentsMapHiddenColumn(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    final pairs = <_ModelPair>[
      (
        table: 'calls',
        sampleToMap: () => CallModel(
          id: 1,
          date: '2026-01-01',
          time: '12:00',
          callerId: 2,
          equipmentId: 3,
          callerText: 'caller',
          phoneText: '1234',
          departmentText: 'dept',
          equipmentText: 'eq',
          issue: 'issue',
          category: 'cat',
          categoryId: 4,
          status: 'completed',
          duration: 60,
          isPriority: 0,
          lansweeperState: 'unsent',
          lansweeperMainTicketId: 'T1',
          lansweeperLastSyncAt: '2026-01-01T12:00:00',
          isDeleted: false,
        ).toMap(),
        fromMap: CallModel.fromMap,
      ),
      (
        table: 'tasks',
        sampleToMap: () => Task(
          id: 1,
          callId: 2,
          callerId: 3,
          equipmentId: 4,
          departmentId: 5,
          phoneId: 6,
          phoneText: '1234',
          userText: 'user',
          equipmentText: 'eq',
          departmentText: 'dept',
          title: 'title',
          description: 'desc',
          dueDate: '2026-01-02',
          snoozeUntil: '2026-01-03',
          snoozeHistoryJson: '[]',
          status: 'open',
          priority: 1,
          solutionNotes: 'done',
          createdAt: '2026-01-01',
          updatedAt: '2026-01-02',
          origin: Task.originManualFab,
          isDeleted: false,
        ).toMap(),
        fromMap: Task.fromMap,
      ),
      (
        table: 'equipment',
        sampleToMap: () => EquipmentModel(
          id: 1,
          code: 'PC-1',
          type: 'Desktop',
          notes: 'n',
          remoteParams: const {'1': 'host'},
          defaultRemoteTool: '2',
          departmentId: 3,
          location: 'room',
          isDeleted: false,
        ).toMap(),
        fromMap: EquipmentModel.fromMap,
      ),
      (
        table: 'users',
        sampleToMap: () => UserModel(
          id: 1,
          firstName: 'A',
          lastName: 'B',
          phones: const ['1234'],
          departmentId: 2,
          location: 'office',
          notes: 'n',
          isDeleted: false,
        ).toMap(),
        fromMap: UserModel.fromMap,
      ),
      (
        table: 'departments',
        sampleToMap: () => DepartmentModel(
          id: 1,
          name: 'Dept',
          building: 'A',
          color: '#1976D2',
          notes: 'n',
          mapFloor: '1',
          mapX: 1.0,
          mapY: 2.0,
          mapWidth: 10.0,
          mapHeight: 20.0,
          mapRotation: 0.0,
          mapLabelOffsetX: 1.0,
          mapLabelOffsetY: 2.0,
          mapAnchorOffsetX: 3.0,
          mapAnchorOffsetY: 4.0,
          mapCustomName: 'label',
          mapLabelFontScale: 1.2,
          mapLabelWidth: 150.0,
          mapLabelHeight: 50.0,
          groupName: 'group',
          floorId: 1,
          isDeleted: false,
          isHiddenOnMap: false,
        ).toMap(),
        fromMap: DepartmentModel.fromMap,
      ),
      (
        table: 'categories',
        sampleToMap: () => const CategoryModel(id: 1, name: 'Cat', isDeleted: false).toMap(),
        fromMap: CategoryModel.fromMap,
      ),
    ];

    for (final pair in pairs) {
      test('${pair.table}: στήλες ↔ toMap/fromMap', () async {
        final columns = await _tableColumns(db, pair.table);
        final columnTypes = await _columnTypes(db, pair.table);
        final schemaOnly = _schemaOnlyColumns[pair.table] ?? const {};
        final toMapOnly = _toMapOnlyKeys[pair.table] ?? const {};
        final joinKeys = _fromMapJoinKeys[pair.table] ?? const {};

        final modelColumns = columns.difference(schemaOnly);
        final toMapKeys = pair.sampleToMap().keys.toSet().difference(toMapOnly);

        final missingFromToMap =
            modelColumns.difference(toMapKeys);
        final missingFromSchema =
            toMapKeys.difference(columns);

        expect(
          missingFromToMap,
          isEmpty,
          reason:
              'Στήλες χωρίς αντίστοιχο κλειδί toMap() στο ${pair.table}: '
              '$missingFromToMap',
        );
        expect(
          missingFromSchema,
          isEmpty,
          reason:
              'Κλειδιά toMap() χωρίς στήλη στο ${pair.table}: '
              '$missingFromSchema',
        );

        final row = <String, dynamic>{
          for (final col in columns) col: null,
        };
        for (final col in modelColumns) {
          row[col] = _sampleValueForColumn(
            col,
            columnType: columnTypes[col] ?? 'TEXT',
          );
        }
        for (final key in joinKeys) {
          row[key] = null;
        }

        expect(() => pair.fromMap(row), returnsNormally);

        final fromMapKeys = row.keys.toSet();
        final tableReadable = modelColumns.every(fromMapKeys.contains);
        expect(
          tableReadable,
          isTrue,
          reason:
              'fromMap() δεν καλύπτει στήλες του ${pair.table}: '
              '${modelColumns.difference(fromMapKeys)}',
        );
      });
    }
  });
}

Future<Map<String, String>> _columnTypes(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return {
    for (final row in rows)
      row['name'] as String: (row['type'] as String?)?.toUpperCase() ?? 'TEXT',
  };
}

dynamic _sampleValueForColumn(String column, {String columnType = 'TEXT'}) {
  final type = columnType.toUpperCase();
  if (type.contains('INT')) {
    if (column == 'is_deleted' || column == 'map_hidden') return 0;
    if (column == 'is_priority') return 0;
    return 1;
  }
  if (type.contains('REAL')) return 1.0;
  if (column == 'lansweeper_state') return 'unsent';
  if (column == 'origin') return Task.originLegacy;
  if (column == 'status') return 'open';
  if (column == 'due_date' ||
      column == 'date' ||
      column == 'time' ||
      column == 'created_at' ||
      column == 'updated_at' ||
      column == 'snooze_until' ||
      column == 'lansweeper_last_sync_at') {
    return '2026-01-01T00:00:00';
  }
  if (column == 'name') return 'sample';
  return 'sample';
}
