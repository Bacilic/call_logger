// Η αναβάθμιση v38 βάζει τους κανόνες σε βάση που ζούσε χωρίς αυτούς.
//
// Συμβόλαιο: «η αναβάθμιση καθαρίζει ό,τι δεν στέκει και κρατά ό,τι στέκει —
// ούτε μία γραμμή δεδομένων δεν χάνεται επειδή άλλαξε το σχήμα».
//
//   flutter test test/core/database/foreign_keys_migration_v38_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_foreign_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('αναβάθμιση v38', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      initSqfliteFfiForTests();
      tempDir = await Directory.systemTemp.createTemp('fk_migration_v38_');
      db = await databaseFactory.openDatabase(
        '${tempDir.path}/pre_v38.db',
        options: OpenDatabaseOptions(version: 1),
      );
      await _createPreV38Schema(db);
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('τα υγιή δεδομένα επιβιώνουν ακέραια', () async {
      final floorId = await db.insert('building_map_floors', {
        'sort_order': 0,
        'label': 'Ισόγειο',
        'image_path': 'g.png',
        'rotation_degrees': 0.0,
      });
      final deptId = await db.insert('departments', {
        'name': 'Πληροφορική',
        'name_key': 'πληροφορικη',
        'floor_id': floorId,
        'notes': 'κρατά τις σημειώσεις της',
        'is_deleted': 0,
      });
      final userId = await db.insert('users', {
        'first_name': 'Ελένη',
        'last_name': 'Ψαρά',
        'department_id': deptId,
        'is_deleted': 0,
      });
      final callId = await db.insert('calls', {
        'date': '2026-08-04',
        'time': '09:40',
        'issue': 'υγιής κλήση',
        'status': 'completed',
        'search_index': 'υγιης',
        'is_deleted': 0,
      });
      await db.insert('tasks', {
        'title': 'υγιής εκκρεμότητα',
        'status': 'open',
        'call_id': callId,
        'is_deleted': 0,
      });
      await db.insert('call_external_links', {
        'call_id': callId,
        'external_id': '7001',
        'provider': 'lansweeper',
        'created_at': '2026-08-04T09:40:00.000',
      });

      final repaired = await migrateDatabaseToV38(db);

      expect(repaired, isEmpty, reason: 'υγιής βάση δεν χρειάζεται διόρθωση');
      final dept = await db.query(
        'departments',
        where: 'id = ?',
        whereArgs: [deptId],
      );
      expect(dept.single['floor_id'], floorId);
      expect(dept.single['notes'], 'κρατά τις σημειώσεις της');
      final user = await db.query('users', where: 'id = ?', whereArgs: [userId]);
      expect(user.single['department_id'], deptId);
      expect(await db.query('tasks'), hasLength(1));
      expect(await db.query('call_external_links'), hasLength(1));
      expect(await foreignKeyViolations(db), isEmpty);
    });

    test('οι σπασμένες αναφορές τακτοποιούνται κατά είδος', () async {
      final deptId = await db.insert('departments', {
        'name': 'Υπαρκτό',
        'name_key': 'υπαρκτο',
        'is_deleted': 0,
      });
      final phoneId = await db.insert('phones', {
        'number': '2001',
        'department_id': 987654,
        'is_deleted': 0,
      });
      await db.insert('users', {
        'first_name': 'Χωρίς',
        'last_name': 'Τμήμα',
        'department_id': 987654,
        'is_deleted': 0,
      });
      await db.insert('department_phones', {
        'department_id': 987654,
        'phone_id': phoneId,
      });
      await db.insert('department_phones', {
        'department_id': deptId,
        'phone_id': phoneId,
      });
      await db.insert('tasks', {
        'title': 'σε ανύπαρκτη κλήση',
        'status': 'open',
        'call_id': 987654,
        'is_deleted': 0,
      });
      await db.insert('call_external_links', {
        'call_id': 987654,
        'external_id': '7001',
        'provider': 'lansweeper',
        'created_at': '2026-08-04T09:40:00.000',
      });

      final repaired = await migrateDatabaseToV38(db);

      expect(repaired, isNotEmpty);
      // Οι ζωντανές αναφορές αποσυνδέονται — η εγγραφή επιβιώνει.
      final user = await db.query('users', columns: ['department_id']);
      expect(user.single['department_id'], isNull);
      final phone = await db.query('phones', columns: ['department_id']);
      expect(phone.single['department_id'], isNull);
      final task = await db.query('tasks', columns: ['title', 'call_id']);
      expect(task.single['title'], 'σε ανύπαρκτη κλήση');
      expect(task.single['call_id'], isNull);
      // Συσχετίσεις και παιδιά φεύγουν — δεν έχουν νόημα χωρίς γονιό.
      final links = await db.query('department_phones');
      expect(links, hasLength(1));
      expect(links.single['department_id'], deptId);
      expect(await db.query('call_external_links'), isEmpty);
      expect(await foreignKeyViolations(db), isEmpty);
    });

    test('η αναβάθμιση αφήνει τους κανόνες αναμμένους', () async {
      await migrateDatabaseToV38(db);

      expect(await areForeignKeysEnabled(db), isTrue);
      await expectLater(
        db.insert('users', {
          'first_name': 'Μετά',
          'last_name': 'Την Αναβάθμιση',
          'department_id': 987654,
          'is_deleted': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('τα ιστορικά στιγμιότυπα των κλήσεων δεν πειράζονται', () async {
      await db.insert('calls', {
        'date': '2026-08-04',
        'time': '09:40',
        'caller_id': 987654,
        'equipment_id': 987655,
        'caller_text': 'Στιγμιότυπο',
        'status': 'completed',
        'search_index': 'snapshot',
        'is_deleted': 0,
      });

      await migrateDatabaseToV38(db);

      final call = await db.query('calls', columns: ['caller_id', 'caller_text']);
      expect(call.single['caller_id'], 987654);
      expect(call.single['caller_text'], 'Στιγμιότυπο');
    });
  });
}

/// Το σχήμα όπως ήταν πριν την v38: ίδιοι πίνακες, καμία δήλωση κανόνα.
Future<void> _createPreV38Schema(Database db) async {
  const statements = <String>[
    '''
    CREATE TABLE calls (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT, time TEXT, caller_id INTEGER, equipment_id INTEGER,
      caller_text TEXT, phone_text TEXT, department_text TEXT,
      equipment_text TEXT, issue TEXT, category_text TEXT, category_id INTEGER,
      status TEXT, duration INTEGER, is_priority INTEGER, search_index TEXT,
      lansweeper_state TEXT, lansweeper_main_ticket_id TEXT,
      lansweeper_last_sync_at TEXT, is_deleted INTEGER DEFAULT 0
    )''',
    '''
    CREATE TABLE call_external_links (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      call_id INTEGER NOT NULL, external_id TEXT NOT NULL,
      provider TEXT NOT NULL, created_at TEXT NOT NULL, metadata TEXT
    )''',
    '''
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      last_name TEXT NOT NULL, first_name TEXT NOT NULL,
      department_id INTEGER, location TEXT, notes TEXT,
      is_deleted INTEGER DEFAULT 0
    )''',
    '''
    CREATE TABLE phones (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      number TEXT UNIQUE NOT NULL, department_id INTEGER,
      is_deleted INTEGER DEFAULT 0
    )''',
    '''
    CREATE TABLE department_phones (
      department_id INTEGER NOT NULL, phone_id INTEGER NOT NULL,
      PRIMARY KEY (department_id, phone_id)
    )''',
    '''
    CREATE TABLE user_phones (
      user_id INTEGER NOT NULL, phone_id INTEGER NOT NULL,
      PRIMARY KEY (user_id, phone_id)
    )''',
    '''
    CREATE TABLE equipment (
      id INTEGER PRIMARY KEY AUTOINCREMENT, code_equipment TEXT, type TEXT,
      notes TEXT, remote_params TEXT, default_remote_tool TEXT,
      department_id INTEGER, location TEXT, is_deleted INTEGER DEFAULT 0
    )''',
    '''
    CREATE TABLE user_equipment (
      user_id INTEGER NOT NULL, equipment_id INTEGER NOT NULL,
      PRIMARY KEY (user_id, equipment_id)
    )''',
    '''
    CREATE TABLE departments (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
      name_key TEXT UNIQUE NOT NULL, building TEXT, color TEXT, notes TEXT,
      map_floor TEXT, map_x REAL, map_y REAL, map_width REAL, map_height REAL,
      map_rotation REAL, map_label_offset_x REAL, map_label_offset_y REAL,
      map_anchor_offset_x REAL, map_anchor_offset_y REAL, map_custom_name TEXT,
      map_label_font_scale REAL, map_label_width REAL, map_label_height REAL,
      group_name TEXT, floor_id INTEGER, is_deleted INTEGER DEFAULT 0
    )''',
    '''
    CREATE TABLE building_map_floors (
      id INTEGER PRIMARY KEY AUTOINCREMENT, sort_order INTEGER NOT NULL,
      label TEXT NOT NULL, floor_group TEXT, image_path TEXT NOT NULL,
      rotation_degrees REAL NOT NULL DEFAULT 0
    )''',
    '''
    CREATE TABLE tasks (
      id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, description TEXT,
      due_date TEXT, snooze_history_json TEXT, status TEXT, call_id INTEGER,
      priority INTEGER, solution_notes TEXT, snooze_until TEXT,
      caller_id INTEGER, equipment_id INTEGER, department_id INTEGER,
      phone_id INTEGER, phone_text TEXT, user_text TEXT, equipment_text TEXT,
      department_text TEXT, created_at TEXT, updated_at TEXT, origin TEXT,
      search_index TEXT, is_deleted INTEGER DEFAULT 0
    )''',
    '''
    CREATE TABLE remote_tools (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL
    )''',
    '''
    CREATE TABLE remote_tool_args (
      id INTEGER PRIMARY KEY AUTOINCREMENT, remote_tool_id INTEGER,
      tool_name TEXT, arg_flag TEXT, description TEXT,
      is_active INTEGER DEFAULT 0
    )''',
  ];
  for (final sql in statements) {
    await db.execute(sql);
  }
}
