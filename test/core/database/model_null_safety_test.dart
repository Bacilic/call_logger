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

typedef _NullSafetyPair = ({
  String table,
  dynamic Function(Map<String, dynamic> map) fromMap,
  Map<String, dynamic> Function(dynamic model) toMap,
  dynamic Function() emptyModel,
  Set<String> nullableColumns,
});

Future<Set<String>> _nullableColumns(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows
      .where((row) => (row['notnull'] as int? ?? 0) == 0)
      .map((row) => row['name'] as String)
      .toSet();
}

Map<String, dynamic> _allNullRow(
  Set<String> columns,
  Set<String> nullable,
) {
  return {
    for (final col in columns)
      col: nullable.contains(col) ? null : _nonNullPlaceholder(col),
  };
}

dynamic _nonNullPlaceholder(String column) {
  if (column == 'id' ||
      column.endsWith('_id') ||
      column == 'duration' ||
      column == 'priority' ||
      column == 'is_priority' ||
      column == 'is_deleted' ||
      column == 'map_hidden') {
    return 1;
  }
  if (column == 'lansweeper_state') return 'unsent';
  if (column == 'origin') return Task.originLegacy;
  if (column == 'status') return 'open';
  if (column == 'due_date') return '2026-01-01';
  if (column == 'name') return 'sample';
  if (column.startsWith('map_') && column.contains('rotation')) return 0.0;
  if (column.startsWith('map_') &&
      (column.contains('width') || column.contains('height'))) {
    return 150.0;
  }
  return 'sample';
}

void main() {
  group('Model null safety', () {
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('model_null_test_');
      await DatabaseHelper.bindTestDatabaseFile(
        p.join(dir.path, 'model_null.db'),
      );
      db = await DatabaseHelper.instance.database;
      await ensureDepartmentsMapHiddenColumn(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    late Map<String, Set<String>> nullableByTable;

    setUp(() async {
      nullableByTable = {
        'calls': await _nullableColumns(db, 'calls'),
        'tasks': await _nullableColumns(db, 'tasks'),
        'equipment': await _nullableColumns(db, 'equipment'),
        'users': await _nullableColumns(db, 'users'),
        'departments': await _nullableColumns(db, 'departments'),
        'categories': await _nullableColumns(db, 'categories'),
      };
    });

    final pairs = <_NullSafetyPair>[
      (
        table: 'calls',
        fromMap: CallModel.fromMap,
        toMap: (m) => (m as CallModel).toMap(),
        emptyModel: () => CallModel(),
        nullableColumns: const {},
      ),
      (
        table: 'tasks',
        fromMap: Task.fromMap,
        toMap: (m) => (m as Task).toMap(),
        emptyModel: () => Task(title: '', dueDate: '', status: 'open'),
        nullableColumns: const {},
      ),
      (
        table: 'equipment',
        fromMap: EquipmentModel.fromMap,
        toMap: (m) => (m as EquipmentModel).toMap(),
        emptyModel: () => EquipmentModel(),
        nullableColumns: const {},
      ),
      (
        table: 'users',
        fromMap: UserModel.fromMap,
        toMap: (m) => (m as UserModel).toMap(),
        emptyModel: () => UserModel(),
        nullableColumns: const {},
      ),
      (
        table: 'departments',
        fromMap: DepartmentModel.fromMap,
        toMap: (m) => (m as DepartmentModel).toMap(),
        emptyModel: () => DepartmentModel(name: ''),
        nullableColumns: const {},
      ),
      (
        table: 'categories',
        fromMap: CategoryModel.fromMap,
        toMap: (m) => (m as CategoryModel).toMap(),
        emptyModel: () => const CategoryModel(name: ''),
        nullableColumns: const {},
      ),
    ];

    for (final pair in pairs) {
      test('${pair.table}: fromMap με NULL nullable στήλες', () async {
        final nullable = nullableByTable[pair.table]!;
        final allColumns = nullable.union({
          for (final row in await db.rawQuery('PRAGMA table_info(${pair.table})'))
            row['name'] as String,
        });
        final row = _allNullRow(allColumns, nullable);

        late dynamic model;
        expect(() => model = pair.fromMap(row), returnsNormally);

        for (final col in nullable) {
          _expectModelFieldNull(model, pair.table, col);
        }
      });

      test('${pair.table}: toMap διατηρεί null χωρίς crash', () async {
        final model = pair.emptyModel();
        late Map<String, dynamic> map;
        expect(() => map = pair.toMap(model), returnsNormally);

        for (final entry in map.entries) {
          if (entry.value == null) {
            expect(entry.key, isNotEmpty);
          }
        }
      });
    }
  });
}

void _expectModelFieldNull(dynamic model, String table, String column) {
  switch (table) {
    case 'calls':
      final m = model as CallModel;
      switch (column) {
        case 'date':
          expect(m.date, isNull);
        case 'time':
          expect(m.time, isNull);
        case 'caller_id':
          expect(m.callerId, isNull);
        case 'equipment_id':
          expect(m.equipmentId, isNull);
        case 'caller_text':
          expect(m.callerText, isNull);
        case 'phone_text':
          expect(m.phoneText, isNull);
        case 'department_text':
          expect(m.departmentText, isNull);
        case 'equipment_text':
          expect(m.equipmentText, isNull);
        case 'issue':
          expect(m.issue, isNull);
        case 'category_text':
          expect(m.category, isNull);
        case 'category_id':
          expect(m.categoryId, isNull);
        case 'status':
          expect(m.status, isNull);
        case 'duration':
          expect(m.duration, isNull);
        case 'is_priority':
          expect(m.isPriority, isNull);
        case 'lansweeper_main_ticket_id':
          expect(m.lansweeperMainTicketId, isNull);
        case 'lansweeper_last_sync_at':
          expect(m.lansweeperLastSyncAt, isNull);
        case 'search_index':
          break;
        default:
          break;
      }
    case 'tasks':
      final m = model as Task;
      switch (column) {
        case 'call_id':
          expect(m.callId, isNull);
        case 'caller_id':
          expect(m.callerId, isNull);
        case 'equipment_id':
          expect(m.equipmentId, isNull);
        case 'department_id':
          expect(m.departmentId, isNull);
        case 'phone_id':
          expect(m.phoneId, isNull);
        case 'phone_text':
          expect(m.phoneText, isNull);
        case 'user_text':
          expect(m.userText, isNull);
        case 'equipment_text':
          expect(m.equipmentText, isNull);
        case 'department_text':
          expect(m.departmentText, isNull);
        case 'description':
          expect(m.description, isNull);
        case 'snooze_until':
          expect(m.snoozeUntil, isNull);
        case 'snooze_history_json':
          expect(m.snoozeHistoryJson, isNull);
        case 'priority':
          expect(m.priority, isNull);
        case 'solution_notes':
          expect(m.solutionNotes, isNull);
        case 'created_at':
          expect(m.createdAt, isNull);
        case 'updated_at':
          expect(m.updatedAt, isNull);
        default:
          break;
      }
    case 'equipment':
      final m = model as EquipmentModel;
      switch (column) {
        case 'code_equipment':
          expect(m.code, isNull);
        case 'type':
          expect(m.type, isNull);
        case 'notes':
          expect(m.notes, isNull);
        case 'remote_params':
          expect(m.remoteParams, isEmpty);
        case 'default_remote_tool':
          expect(m.defaultRemoteTool, isNull);
        case 'department_id':
          expect(m.departmentId, isNull);
        case 'location':
          expect(m.location, isNull);
        default:
          break;
      }
    case 'users':
      final m = model as UserModel;
      switch (column) {
        case 'department_id':
          expect(m.departmentId, isNull);
        case 'location':
          expect(m.location, isNull);
        case 'notes':
          expect(m.notes, isNull);
        case 'first_name':
          expect(m.firstName, isNull);
        case 'last_name':
          expect(m.lastName, isNull);
        default:
          break;
      }
    case 'departments':
      final m = model as DepartmentModel;
      switch (column) {
        case 'building':
          expect(m.building, isNull);
        case 'color':
          expect(m.color, isNull);
        case 'notes':
          expect(m.notes, isNull);
        case 'map_floor':
          expect(m.mapFloor, isNull);
        case 'map_x':
          expect(m.mapX, isNull);
        case 'map_y':
          expect(m.mapY, isNull);
        case 'map_width':
          expect(m.mapWidth, isNull);
        case 'map_height':
          expect(m.mapHeight, isNull);
        case 'map_label_offset_x':
          expect(m.mapLabelOffsetX, isNull);
        case 'map_label_offset_y':
          expect(m.mapLabelOffsetY, isNull);
        case 'map_anchor_offset_x':
          expect(m.mapAnchorOffsetX, isNull);
        case 'map_anchor_offset_y':
          expect(m.mapAnchorOffsetY, isNull);
        case 'map_custom_name':
          expect(m.mapCustomName, isNull);
        case 'map_label_font_scale':
          expect(m.mapLabelFontScale, isNull);
        case 'group_name':
          expect(m.groupName, isNull);
        case 'floor_id':
          expect(m.floorId, isNull);
        default:
          break;
      }
    case 'categories':
      final m = model as CategoryModel;
      switch (column) {
        case 'name':
          expect(m.name, isEmpty);
        default:
          break;
      }
  }
}
