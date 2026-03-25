import 'package:sqflite_common/sqlite_api.dart';

/// User-visible schema version (squashed v1· v2 = στήλες τμήμα/τοποθεσία στον εξοπλισμό).
/// v4: departments.name = display, departments.name_key = normalized unique key.
/// v5: phones.department_id for shared-location policy.
/// v6: user_dictionary για προσωπικό λεξικό ορθογραφίας.
const int databaseSchemaVersionV1 = 6;

/// Δημιουργία σχήματος v1 + seed `remote_tool_args`.
/// Χωρίς εξαρτήσεις Flutter — ασφαλές για `dart run tool/migrate_to_v1.dart`.
Future<void> applyDatabaseV1Schema(Database db) async {
  await db.execute('''
      CREATE TABLE calls (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT,
        time TEXT,
        caller_id INTEGER,
        equipment_id INTEGER,
        caller_text TEXT,
        phone_text TEXT,
        department_text TEXT,
        equipment_text TEXT,
        issue TEXT,
        solution TEXT,
        category_text TEXT,
        category_id INTEGER,
        status TEXT,
        duration INTEGER,
        is_priority INTEGER DEFAULT 0,
        search_index TEXT,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

  await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        last_name TEXT NOT NULL,
        first_name TEXT NOT NULL,
        department_id INTEGER,
        location TEXT,
        notes TEXT,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

  await db.execute('''
      CREATE TABLE phones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        number TEXT UNIQUE NOT NULL,
        department_id INTEGER
      )
    ''');

  await db.execute('''
      CREATE TABLE department_phones (
        department_id INTEGER NOT NULL,
        phone_id INTEGER NOT NULL,
        PRIMARY KEY (department_id, phone_id)
      )
    ''');

  await db.execute('''
      CREATE TABLE user_phones (
        user_id INTEGER NOT NULL,
        phone_id INTEGER NOT NULL,
        PRIMARY KEY (user_id, phone_id)
      )
    ''');

  await db.execute('''
      CREATE TABLE equipment (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code_equipment TEXT,
        type TEXT,
        notes TEXT,
        custom_ip TEXT,
        anydesk_id TEXT,
        default_remote_tool TEXT,
        department_id INTEGER,
        location TEXT,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

  await db.execute('''
      CREATE TABLE user_equipment (
        user_id INTEGER NOT NULL,
        equipment_id INTEGER NOT NULL,
        PRIMARY KEY (user_id, equipment_id)
      )
    ''');

  await db.execute('''
      CREATE TABLE departments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        name_key TEXT UNIQUE NOT NULL,
        building TEXT,
        color TEXT DEFAULT '#1976D2',
        notes TEXT,
        map_floor TEXT,
        map_x REAL DEFAULT 0.0,
        map_y REAL DEFAULT 0.0,
        map_width REAL DEFAULT 0.0,
        map_height REAL DEFAULT 0.0,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

  await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

  await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        description TEXT,
        due_date TEXT,
        snooze_history_json TEXT,
        status TEXT,
        call_id INTEGER,
        priority INTEGER,
        solution_notes TEXT,
        snooze_until TEXT,
        caller_id INTEGER,
        equipment_id INTEGER,
        department_id INTEGER,
        phone_id INTEGER,
        phone_text TEXT,
        user_text TEXT,
        equipment_text TEXT,
        department_text TEXT,
        created_at TEXT,
        updated_at TEXT,
        search_index TEXT,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

  await db.execute('''
      CREATE TABLE knowledge_base (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        topic TEXT,
        content TEXT,
        tags TEXT
      )
    ''');

  await db.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT,
        timestamp TEXT,
        user_performing TEXT,
        details TEXT
      )
    ''');

  await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

  await db.execute('''
      CREATE TABLE IF NOT EXISTS remote_tool_args (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tool_name TEXT,
        arg_flag TEXT,
        description TEXT,
        is_active INTEGER DEFAULT 0
      )
    ''');
  await seedRemoteToolArgsIfEmpty(db);

  await db.execute('''
      CREATE TABLE IF NOT EXISTS user_dictionary (
        word TEXT PRIMARY KEY
      )
    ''');
}

/// Προεπιλεγμένα ορίσματα VNC/AnyDesk αν ο πίνακας είναι άδειος.
Future<void> seedRemoteToolArgsIfEmpty(Database db) async {
  final result = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM remote_tool_args',
  );
  final count = result.isNotEmpty ? (result.first['c'] as int? ?? 0) : 0;
  if (count > 0) return;

  final defaults = <Map<String, dynamic>>[
    {
      'tool_name': 'vnc',
      'arg_flag': '-host={TARGET}',
      'description': 'Host/IP στόχου',
      'is_active': 1,
    },
    {
      'tool_name': 'vnc',
      'arg_flag': '-password={PASSWORD}',
      'description': 'Κωδικός VNC',
      'is_active': 1,
    },
    {
      'tool_name': 'vnc',
      'arg_flag': '-fullscreen',
      'description': 'Πλήρης οθόνη',
      'is_active': 0,
    },
    {
      'tool_name': 'vnc',
      'arg_flag': '-viewonly',
      'description': 'Μόνο προβολή',
      'is_active': 0,
    },
    {
      'tool_name': 'anydesk',
      'arg_flag': '{TARGET}',
      'description': 'AnyDesk ID στόχου',
      'is_active': 1,
    },
    {
      'tool_name': 'anydesk',
      'arg_flag': '--fullscreen',
      'description': 'Πλήρης οθόνη',
      'is_active': 0,
    },
  ];
  for (final row in defaults) {
    await db.insert('remote_tool_args', row);
  }
}
