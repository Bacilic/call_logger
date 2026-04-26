import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import '../utils/search_text_normalizer.dart';

/// User-visible schema version (squashed v1· v2 = στήλες τμήμα/τοποθεσία στον εξοπλισμό).
/// v4: departments.name = display, departments.name_key = normalized unique key.
/// v5: phones.department_id for shared-location policy.
/// v6: user_dictionary για προσωπικό λεξικό ορθογραφίας.
/// v7: full_dictionary master λεξικό.
/// v8: user_dictionary.language για φίλτρο γλώσσας στα πρόχειρα (combined lexicon).
/// v9: letters_count + diacritic_mark_count σε full_dictionary και user_dictionary.
/// v10: equipment.remote_params (JSON παραμέτρων απομακρυσμένης σύνδεσης).
/// v11: πίνακας remote_tools, στήλη remote_tool_args.remote_tool_id.
/// v12: remote_tools.arguments_json, remote_tools.test_target_ip (ορίσματα JSON ανά εργαλείο).
/// v13: remote_tools.password (κωδικός ανά εργαλείο για {PASSWORD}).
/// v14: αφαίρεση remote_tools.use_global_password (το {PASSWORD} ακολουθεί πάντα το πεδίο password).
/// v15: remote_tools.deleted_at (soft delete) + equipment.default_remote_tool ως id (TEXT).
/// v16: remote_tools.slug + detection_kind → στήλη role (ToolRole).
/// v17: remote_tools.is_exclusive (αποκλειστική εμφάνιση στο UI κλήσεων).
/// v18: audit_log entity columns + indexes για φίλτρα/side panel.
/// v19: remote_tools — αφαίρεση legacy στηλών (placeholders σε arguments_json).
/// v20: πίνακας `building_map_floors` (φύλλα κατόψης κτιρίου).
/// v21: `departments.group_name`, `departments.floor_id` (ομαδοποίηση στον χάρτη).
/// v22: `departments.map_label_offset_*`, `departments.map_anchor_offset_*`, `departments.map_custom_name`.
/// v23: `tasks.origin` (πηγή δημιουργίας εκκρεμότητας).
/// v24: `audit_log.search_text` για αναζήτηση τίτλου χωρίς action.
/// v25: backfill `search_text` με ρητές υποενέργειες (προσθήκη/αφαίρεση/αλλαγή).
/// v26: πλήρης στοίχιση `search_text` με UI αλλαγών (1:1 κανονικοποιημένα).
const int databaseSchemaVersionV1 = 26;

/// Προεπιλογές διαδρομών (ίδιες με SettingsService — χωρίς εξάρτηση Flutter εδώ).
const String kDefaultVncExecutablePath =
    r'C:\Program Files\TightVNC\tvnviewer.exe';
const String kDefaultAnydeskExecutablePath =
    r'C:\Program Files (x86)\AnyDesk\AnyDesk.exe';
const String kDefaultMstscExecutablePath = r'C:\Windows\System32\mstsc.exe';

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
        remote_params TEXT,
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
        map_rotation REAL DEFAULT 0.0,
        map_label_offset_x REAL,
        map_label_offset_y REAL,
        map_anchor_offset_x REAL,
        map_anchor_offset_y REAL,
        map_custom_name TEXT,
        group_name TEXT,
        floor_id INTEGER,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

  await db.execute('''
      CREATE TABLE building_map_floors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        label TEXT NOT NULL,
        floor_group TEXT,
        image_path TEXT NOT NULL,
        rotation_degrees REAL NOT NULL DEFAULT 0
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
        origin TEXT DEFAULT 'legacy',
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
        details TEXT,
        entity_type TEXT,
        entity_id INTEGER,
        entity_name TEXT,
        search_text TEXT,
        old_values_json TEXT,
        new_values_json TEXT
      )
    ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_audit_log_timestamp ON audit_log(timestamp)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_audit_log_action ON audit_log(action)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_audit_log_entity_type_entity_id ON audit_log(entity_type, entity_id)',
  );

  await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

  await db.execute('''
      CREATE TABLE IF NOT EXISTS remote_tools (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        executable_path TEXT NOT NULL,
        launch_mode TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        suggested_values TEXT,
        icon_asset_key TEXT,
        arguments_json TEXT,
        test_target_ip TEXT,
        is_exclusive INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT
      )
    ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_remote_tools_role ON remote_tools(role)',
  );

  await db.execute('''
      CREATE TABLE IF NOT EXISTS remote_tool_args (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        remote_tool_id INTEGER,
        tool_name TEXT,
        arg_flag TEXT,
        description TEXT,
        is_active INTEGER DEFAULT 0,
        FOREIGN KEY (remote_tool_id) REFERENCES remote_tools(id)
      )
    ''');
  await seedRemoteToolsAndArgsIfEmpty(db);

  await db.execute('''
      CREATE TABLE IF NOT EXISTS user_dictionary (
        word TEXT PRIMARY KEY,
        language TEXT,
        letters_count INTEGER NOT NULL DEFAULT 0,
        diacritic_mark_count INTEGER NOT NULL DEFAULT 0
      )
    ''');

  await db.execute('''
      CREATE TABLE IF NOT EXISTS full_dictionary (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word TEXT NOT NULL UNIQUE,
        normalized_word TEXT NOT NULL,
        source TEXT NOT NULL,
        language TEXT NOT NULL,
        category TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        letters_count INTEGER NOT NULL DEFAULT 0,
        diacritic_mark_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_full_dictionary_norm ON full_dictionary(normalized_word)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_full_dictionary_filters ON full_dictionary(language, source, category)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_full_dictionary_letters_count ON full_dictionary(letters_count)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_full_dictionary_diacritic_mark_count ON full_dictionary(diacritic_mark_count)',
  );
}

/// Σύνδεση `remote_tool_args` με `remote_tools` όταν υπάρχουν γραμμές.
/// Δεν γίνεται πλέον αυτόματο seed εγγραφών `remote_tools` — προστίθενται από τις ρυθμίσεις.
Future<void> seedRemoteToolsAndArgsIfEmpty(Database db) async {
  final result = await db.rawQuery('SELECT COUNT(*) AS c FROM remote_tools');
  final count = result.isNotEmpty ? (result.first['c'] as int? ?? 0) : 0;
  if (count == 0) return;

  final argsCount = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM remote_tool_args',
  );
  final ac = argsCount.isNotEmpty ? (argsCount.first['c'] as int? ?? 0) : 0;
  if (ac > 0) {
    await db.rawUpdate('''
UPDATE remote_tool_args
SET remote_tool_id = (
  SELECT id FROM remote_tools WHERE role = remote_tool_args.tool_name LIMIT 1
)
WHERE remote_tool_id IS NULL AND tool_name IS NOT NULL
''');
  }
}

/// Κλειδιά `app_settings` (ίδια με SettingsService).
const String kAppSettingKeyVncPaths = 'vnc_paths';
const String kAppSettingKeyAnydeskPath = 'anydesk_path';
const String kAppSettingKeyRemoteSurfaceApps = 'remote_surface_apps';

/// Αναβάθμιση σε v11: πίνακας `remote_tools`, στήλη `remote_tool_args.remote_tool_id`, μεταφορά διαδρομών.
Future<void> migrateDatabaseToV11(Database db) async {
  await db.execute('''
CREATE TABLE IF NOT EXISTS remote_tools (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  executable_path TEXT NOT NULL,
  launch_mode TEXT NOT NULL,
  config_template TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  detection_kind TEXT,
  vnc_host_prefix TEXT,
  suggested_values TEXT,
  icon_asset_key TEXT,
  default_username TEXT
)
''');

  final argInfo = await db.rawQuery('PRAGMA table_info(remote_tool_args)');
  final argNames = argInfo.map((r) => r['name'] as String).toSet();
  if (!argNames.contains('remote_tool_id')) {
    await db.execute(
      'ALTER TABLE remote_tool_args ADD COLUMN remote_tool_id INTEGER',
    );
  }

  await seedRemoteToolsAndArgsIfEmpty(db);

  Future<String?> appSetting(String key) async {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final v = rows.first['value'];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  final vncJson = await appSetting(kAppSettingKeyVncPaths);
  if (vncJson != null) {
    try {
      final decoded = jsonDecode(vncJson);
      if (decoded is List && decoded.isNotEmpty) {
        final first = decoded.first?.toString().trim();
        if (first != null && first.isNotEmpty) {
          await db.update(
            'remote_tools',
            {'executable_path': first},
            where: 'slug = ?',
            whereArgs: ['vnc'],
          );
        }
      }
    } catch (_) {}
  }

  final anydeskPath = await appSetting(kAppSettingKeyAnydeskPath);
  if (anydeskPath != null && anydeskPath.isNotEmpty) {
    await db.update(
      'remote_tools',
      {'executable_path': anydeskPath},
      where: 'slug = ?',
      whereArgs: ['anydesk'],
    );
  }

  final csvRaw = await appSetting(kAppSettingKeyRemoteSurfaceApps);
  if (csvRaw != null && csvRaw.isNotEmpty) {
    final parts = csvRaw
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isNotEmpty) {
      await db.update('remote_tools', {'is_active': 0});
      final tools = await db.query('remote_tools', columns: ['id', 'name']);
      for (final row in tools) {
        final name = (row['name'] as String?)?.trim().toLowerCase() ?? '';
        if (name.isEmpty) continue;
        if (parts.contains(name)) {
          await db.update(
            'remote_tools',
            {'is_active': 1},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
      final stillActive = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM remote_tools WHERE is_active = 1',
      );
      final n = stillActive.isNotEmpty
          ? (stillActive.first['c'] as int? ?? 0)
          : 0;
      if (n == 0) {
        await db.update('remote_tools', {'is_active': 1});
      }
    }
  }
}

/// Αναβάθμιση σε v12: στήλες `arguments_json`, `test_target_ip` + backfill από `remote_tool_args`.
Future<void> migrateDatabaseToV12(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(remote_tools)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('arguments_json')) {
    await db.execute('ALTER TABLE remote_tools ADD COLUMN arguments_json TEXT');
  }
  if (!names.contains('test_target_ip')) {
    await db.execute('ALTER TABLE remote_tools ADD COLUMN test_target_ip TEXT');
  }

  final tools = await db.query('remote_tools');
  for (final row in tools) {
    final id = row['id'] as int;
    final existing = row['arguments_json'] as String?;
    if (existing != null && existing.trim().isNotEmpty) continue;

    final args = await db.query(
      'remote_tool_args',
      where: 'remote_tool_id = ?',
      whereArgs: [id],
      orderBy: 'id ASC',
    );
    if (args.isEmpty) continue;
    final list = <Map<String, dynamic>>[];
    for (final a in args) {
      list.add({
        'value': a['arg_flag']?.toString() ?? '',
        'description': a['description']?.toString() ?? '',
        'is_active': ((a['is_active'] as int?) ?? 0) == 1,
      });
    }
    await db.update(
      'remote_tools',
      {'arguments_json': jsonEncode(list)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

/// Αναβάθμιση σε v13: στήλη `password` (ανά εργαλείο, NULL για υπάρχοντα rows).
Future<void> migrateDatabaseToV13(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(remote_tools)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('password')) {
    await db.execute('ALTER TABLE remote_tools ADD COLUMN password TEXT');
  }
}

/// Αναβάθμιση σε v14: αφαίρεση `use_global_password` (αν υπάρχει).
Future<void> migrateDatabaseToV14(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(remote_tools)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('use_global_password')) return;
  try {
    await db.execute(
      'ALTER TABLE remote_tools DROP COLUMN use_global_password',
    );
  } catch (_) {
    // Παλιό SQLite χωρίς DROP COLUMN: η στήλη παραμένει αχρησιμοποίητη.
  }
}

/// Αναβάθμιση σε v15: `remote_tools.deleted_at` + μετατροπή `equipment.default_remote_tool` σε id.
Future<void> migrateDatabaseToV15(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(remote_tools)');
  final rtNames = info.map((r) => r['name'] as String).toSet();
  if (!rtNames.contains('deleted_at')) {
    await db.execute('ALTER TABLE remote_tools ADD COLUMN deleted_at TEXT');
  }

  final tools = await db.query('remote_tools', columns: ['id', 'name', 'slug']);
  final toolById = {for (final r in tools) r['id'] as int: r};
  final equipmentRows = await db.query(
    'equipment',
    columns: ['id', 'default_remote_tool'],
  );

  int? resolveDefaultToId(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final asInt = int.tryParse(t);
    if (asInt != null) {
      return toolById.containsKey(asInt) ? asInt : null;
    }
    final lower = t.toLowerCase();
    for (final r in tools) {
      final id = r['id'] as int;
      final name = (r['name'] as String?)?.trim().toLowerCase() ?? '';
      final slug = (r['slug'] as String?)?.trim().toLowerCase() ?? '';
      if (name == lower || slug == lower) return id;
    }
    for (final r in tools) {
      final name = (r['name'] as String?)?.toLowerCase() ?? '';
      if (name.contains(lower) && lower.length >= 3) {
        final id = r['id'] as int;
        if (lower.contains('anydesk') && name.contains('anydesk')) return id;
        if (lower.contains('vnc') && name.contains('vnc')) return id;
        if ((lower.contains('rdp') || lower.contains('remote desktop')) &&
            (name.contains('rdp') || name.contains('remote'))) {
          return id;
        }
      }
    }
    return null;
  }

  for (final row in equipmentRows) {
    final idEq = row['id'] as int?;
    final raw = row['default_remote_tool'] as String?;
    if (idEq == null) continue;
    if (raw == null || raw.trim().isEmpty) continue;
    final newId = resolveDefaultToId(raw);
    await db.update(
      'equipment',
      {'default_remote_tool': newId != null ? '$newId' : null},
      where: 'id = ?',
      whereArgs: [idEq],
    );
  }
}

/// v16: `slug` + `detection_kind` → `role`· αναδημιουργία `remote_tools` με διατήρηση ids.
Future<void> migrateDatabaseToV16(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(remote_tools)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (names.contains('role') && !names.contains('slug')) {
    return;
  }
  if (!names.contains('slug')) {
    return;
  }

  final oldRows = await db.query('remote_tools');

  String mapRole(String? slug, String? detectionKind) {
    final s = slug?.trim().toLowerCase() ?? '';
    if (s == 'vnc' || s == 'rdp' || s == 'anydesk') {
      return s;
    }
    final dk = detectionKind?.trim().toLowerCase() ?? '';
    if (dk == 'anydesk_like') {
      return 'anydesk';
    }
    if (dk == 'vnc_host') {
      return 'vnc';
    }
    if (dk == 'rdp_host') {
      return 'rdp';
    }
    return 'generic';
  }

  await db.execute('PRAGMA foreign_keys = OFF');
  await db.execute('DROP TABLE IF EXISTS remote_tools');
  await db.execute('''
CREATE TABLE remote_tools (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  role TEXT NOT NULL,
  executable_path TEXT NOT NULL,
  launch_mode TEXT NOT NULL,
  config_template TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  vnc_host_prefix TEXT,
  suggested_values TEXT,
  icon_asset_key TEXT,
  default_username TEXT,
  password TEXT,
  arguments_json TEXT,
  test_target_ip TEXT,
  is_exclusive INTEGER NOT NULL DEFAULT 0,
  deleted_at TEXT
)
''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_remote_tools_role ON remote_tools(role)',
  );

  for (final row in oldRows) {
    final idRaw = row['id'];
    final id = idRaw is int ? idRaw : (idRaw as num).toInt();
    final role = mapRole(
      row['slug'] as String?,
      row['detection_kind'] as String?,
    );
    await db.insert('remote_tools', {
      'id': id,
      'name': row['name'] ?? '',
      'role': role,
      'executable_path': row['executable_path'] ?? '',
      'launch_mode': (row['launch_mode'] as String?)?.trim().isNotEmpty == true
          ? row['launch_mode']
          : 'direct_exec',
      'config_template': row['config_template'],
      'sort_order': row['sort_order'] ?? 0,
      'is_active': row['is_active'] ?? 1,
      'vnc_host_prefix': row['vnc_host_prefix'],
      'suggested_values': row['suggested_values'],
      'icon_asset_key': row['icon_asset_key'],
      'default_username': row['default_username'],
      'password': row['password'],
      'arguments_json': row['arguments_json'],
      'test_target_ip': row['test_target_ip'],
      'is_exclusive': row['is_exclusive'] ?? 0,
      'deleted_at': row['deleted_at'],
    });
  }

  await db.execute('PRAGMA foreign_keys = ON');
  await seedRemoteToolsAndArgsIfEmpty(db);
}

/// v17: `remote_tools.is_exclusive` (0/1) για καταστολή μη αποκλειστικών εργαλείων.
Future<void> migrateDatabaseToV17(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(remote_tools)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('is_exclusive')) {
    await db.execute(
      'ALTER TABLE remote_tools ADD COLUMN is_exclusive INTEGER NOT NULL DEFAULT 0',
    );
  }
}

/// v18: στήλες οντότητας + JSON στο `audit_log` και ευρετήρια απόδοσης.
Future<void> migrateDatabaseToV18(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(audit_log)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('entity_type')) {
    await db.execute('ALTER TABLE audit_log ADD COLUMN entity_type TEXT');
  }
  if (!names.contains('entity_id')) {
    await db.execute('ALTER TABLE audit_log ADD COLUMN entity_id INTEGER');
  }
  if (!names.contains('entity_name')) {
    await db.execute('ALTER TABLE audit_log ADD COLUMN entity_name TEXT');
  }
  if (!names.contains('old_values_json')) {
    await db.execute('ALTER TABLE audit_log ADD COLUMN old_values_json TEXT');
  }
  if (!names.contains('new_values_json')) {
    await db.execute('ALTER TABLE audit_log ADD COLUMN new_values_json TEXT');
  }
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_audit_log_timestamp ON audit_log(timestamp)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_audit_log_action ON audit_log(action)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_audit_log_entity_type_entity_id ON audit_log(entity_type, entity_id)',
  );
}

/// v19: αφαίρεση legacy στηλών από `remote_tools` (μετά migration σε arguments_json).
Future<void> migrateDatabaseToV19(Database db) async {
  try {
    Future<void> dropColumnIfExists(String column) async {
      final info = await db.rawQuery('PRAGMA table_info(remote_tools)');
      final names = info.map((r) => r['name'] as String).toSet();
      if (!names.contains(column)) return;
      await db.execute('ALTER TABLE remote_tools DROP COLUMN $column');
    }

    await dropColumnIfExists('vnc_host_prefix');
    await dropColumnIfExists('default_username');
    await dropColumnIfExists('password');
    await dropColumnIfExists('config_template');
  } catch (_) {
    // Παλαιότερο SQLite χωρίς DROP COLUMN: οι στήλες μπορεί να παραμείνουν· το [RemoteTool.fromMap] τις αγνοεί.
  }
}

/// v20: φύλλα κατόψης για χάρτη κτιρίου (`departments.map_floor` → `building_map_floors.id`).
Future<void> migrateDatabaseToV20(Database db) async {
  await db.execute('''
CREATE TABLE IF NOT EXISTS building_map_floors (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  label TEXT NOT NULL,
  floor_group TEXT,
  image_path TEXT NOT NULL,
  rotation_degrees REAL NOT NULL DEFAULT 0
)
''');
  await ensureDepartmentsMapRotationColumn(db);
}

Future<void> ensureDepartmentsMapRotationColumn(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(departments)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('map_rotation')) {
    await db.execute(
      'ALTER TABLE departments ADD COLUMN map_rotation REAL DEFAULT 0.0',
    );
  }
}

/// Προσθέτει (idempotent) τη στήλη `departments.map_hidden` (0/1) για απόκρυψη
/// τμήματος από τον χάρτη χωρίς απώλεια γεωμετρίας. Εκτελείται σε κάθε άνοιγμα
/// βάσης — δεν απαιτεί αλλαγή [_kDatabaseSchemaVersion].
Future<void> ensureDepartmentsMapHiddenColumn(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(departments)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('map_hidden')) {
    await db.execute(
      'ALTER TABLE departments ADD COLUMN map_hidden INTEGER NOT NULL DEFAULT 0',
    );
  }
}

/// v21: ομαδοποίηση τμημάτων στο HUD επιλογής (`group_name`, `floor_id` → `building_map_floors`).
Future<void> migrateDatabaseToV21(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(departments)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('group_name')) {
    await db.execute('ALTER TABLE departments ADD COLUMN group_name TEXT');
  }
  if (!names.contains('floor_id')) {
    await db.execute('ALTER TABLE departments ADD COLUMN floor_id INTEGER');
  }
}

/// v22: offsets ετικέτας/anchor και προσαρμοσμένο όνομα ετικέτας στον χάρτη.
Future<void> migrateDatabaseToV22(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(departments)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('map_label_offset_x')) {
    await db.execute(
      'ALTER TABLE departments ADD COLUMN map_label_offset_x REAL',
    );
  }
  if (!names.contains('map_label_offset_y')) {
    await db.execute(
      'ALTER TABLE departments ADD COLUMN map_label_offset_y REAL',
    );
  }
  if (!names.contains('map_anchor_offset_x')) {
    await db.execute(
      'ALTER TABLE departments ADD COLUMN map_anchor_offset_x REAL',
    );
  }
  if (!names.contains('map_anchor_offset_y')) {
    await db.execute(
      'ALTER TABLE departments ADD COLUMN map_anchor_offset_y REAL',
    );
  }
  if (!names.contains('map_custom_name')) {
    await db.execute('ALTER TABLE departments ADD COLUMN map_custom_name TEXT');
  }
}

/// v23: πηγή δημιουργίας εκκρεμότητας (`manual_fab`, `call_linked`, `quick_add`, `legacy`).
Future<void> migrateDatabaseToV23(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(tasks)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('origin')) {
    await db.execute('ALTER TABLE tasks ADD COLUMN origin TEXT');
  }
  await db.rawUpdate(
    "UPDATE tasks SET origin = 'legacy' WHERE origin IS NULL OR TRIM(origin) = ''",
  );
}

/// v24: `audit_log.search_text` για αναζήτηση σε subject/changes/details (χωρίς action).
Future<void> migrateDatabaseToV24(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(audit_log)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('search_text')) {
    await db.execute('ALTER TABLE audit_log ADD COLUMN search_text TEXT');
  }

  final rows = await db.query(
    'audit_log',
    columns: [
      'id',
      'details',
      'entity_type',
      'entity_name',
      'old_values_json',
      'new_values_json',
      'search_text',
    ],
  );
  if (rows.isEmpty) return;

  final batch = db.batch();
  for (final row in rows) {
    final idRaw = row['id'];
    if (idRaw == null) continue;
    final id = idRaw is int ? idRaw : (idRaw as num).toInt();
    final existing = (row['search_text'] as String?)?.trim() ?? '';
    if (existing.isNotEmpty) continue;
    final next = _buildAuditSearchTextForMigration(
      details: row['details'] as String?,
      entityType: row['entity_type'] as String?,
      entityName: row['entity_name'] as String?,
      oldValuesJson: row['old_values_json'] as String?,
      newValuesJson: row['new_values_json'] as String?,
    );
    batch.update(
      'audit_log',
      {'search_text': next},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  await batch.commit(noResult: true);
}

String _buildAuditSearchTextForMigration({
  String? details,
  String? entityType,
  String? entityName,
  String? oldValuesJson,
  String? newValuesJson,
}) {
  final parts = <String>[];
  final normalizedEntityType = (entityType ?? '').trim();
  void add(String? raw) {
    final t = raw?.trim() ?? '';
    if (t.isNotEmpty) parts.add(t);
  }

  add(entityName);
  add(_entityTypeGreekForMigration(entityType));
  add(details);

  final oldMap =
      _decodeMapForMigration(oldValuesJson) ?? const <String, dynamic>{};
  final newMap =
      _decodeMapForMigration(newValuesJson) ?? const <String, dynamic>{};
  final keys = oldMap.keys.toSet().union(newMap.keys.toSet()).toList()..sort();
  for (final key in keys) {
    final oldValue = oldMap[key];
    final newValue = newMap[key];
    if (_valuesEqualForMigration(oldValue, newValue)) continue;
    final label = _fieldLabelForMigration(normalizedEntityType, key);
    if (label.isNotEmpty) add(label);
    final oldText = _stringifyValueForMigration(key, oldValue);
    final newText = _stringifyValueForMigration(key, newValue);
    if (oldText.isNotEmpty) add(oldText);
    if (newText.isNotEmpty) add(newText);
    add(
      _subactionSearchTextForMigration(
        entityType: normalizedEntityType,
        field: key,
        label: label,
        oldValue: oldValue,
        oldText: oldText,
        newValue: newValue,
        newText: newText,
      ),
    );
  }

  return SearchTextNormalizer.normalizeForSearch(parts.join(' '));
}

/// v25: αναδόμηση `search_text` για όλες τις γραμμές ώστε να περιλαμβάνουν υποενέργειες.
Future<void> migrateDatabaseToV25(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(audit_log)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('search_text')) {
    await db.execute('ALTER TABLE audit_log ADD COLUMN search_text TEXT');
  }

  final rows = await db.query(
    'audit_log',
    columns: [
      'id',
      'details',
      'entity_type',
      'entity_name',
      'old_values_json',
      'new_values_json',
      'search_text',
    ],
  );
  if (rows.isEmpty) return;

  final batch = db.batch();
  for (final row in rows) {
    final idRaw = row['id'];
    if (idRaw == null) continue;
    final id = idRaw is int ? idRaw : (idRaw as num).toInt();
    final next = _buildAuditSearchTextForMigration(
      details: row['details'] as String?,
      entityType: row['entity_type'] as String?,
      entityName: row['entity_name'] as String?,
      oldValuesJson: row['old_values_json'] as String?,
      newValuesJson: row['new_values_json'] as String?,
    );
    final current = SearchTextNormalizer.normalizeForSearch(
      (row['search_text'] as String?) ?? '',
    );
    if (current == next) continue;
    batch.update(
      'audit_log',
      {'search_text': next},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  await batch.commit(noResult: true);
}

/// v26: πλήρης αναδόμηση `search_text` ώστε να ταιριάζει με UI διατυπώσεις.
Future<void> migrateDatabaseToV26(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(audit_log)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('search_text')) {
    await db.execute('ALTER TABLE audit_log ADD COLUMN search_text TEXT');
  }

  final rows = await db.query(
    'audit_log',
    columns: [
      'id',
      'details',
      'entity_type',
      'entity_name',
      'old_values_json',
      'new_values_json',
      'search_text',
    ],
  );
  if (rows.isEmpty) return;

  final batch = db.batch();
  for (final row in rows) {
    final idRaw = row['id'];
    if (idRaw == null) continue;
    final id = idRaw is int ? idRaw : (idRaw as num).toInt();
    final next = _buildAuditSearchTextForMigration(
      details: row['details'] as String?,
      entityType: row['entity_type'] as String?,
      entityName: row['entity_name'] as String?,
      oldValuesJson: row['old_values_json'] as String?,
      newValuesJson: row['new_values_json'] as String?,
    );
    final current = SearchTextNormalizer.normalizeForSearch(
      (row['search_text'] as String?) ?? '',
    );
    if (current == next) continue;
    batch.update(
      'audit_log',
      {'search_text': next},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  await batch.commit(noResult: true);
}

Map<String, dynamic>? _decodeMapForMigration(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final d = jsonDecode(raw);
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return Map<String, dynamic>.from(d);
  } catch (_) {}
  return null;
}

String _entityTypeGreekForMigration(String? type) {
  switch ((type ?? '').trim()) {
    case 'user':
      return 'χρηστης';
    case 'department':
      return 'τμημα';
    case 'equipment':
      return 'εξοπλισμος';
    case 'category':
      return 'κατηγορια';
    case 'task':
      return 'εκκρεμοτητα';
    case 'call':
      return 'κληση';
    case 'bulk_users':
      return 'μαζικη ενημερωση χρηστων';
    case 'bulk_departments':
      return 'μαζικη ενημερωση τμηματων';
    case 'bulk_equipment':
      return 'μαζικη ενημερωση εξοπλισμου';
    case 'import_data':
      return 'εισαγωγη δεδομενων';
    case 'maintenance':
      return 'συντηρηση βασης';
    case 'phone':
      return 'τηλεφωνο';
    default:
      return '';
  }
}

String _fieldLabelForMigration(String entityType, String field) {
  const labels = <String, String>{
    'name': 'ονομα',
    'email': 'email',
    'phone': 'τηλεφωνο',
    'status': 'κατασταση',
    'priority': 'προτεραιοτητα',
    'due_date': 'προθεσμια',
    'title': 'τιτλος',
    'description': 'περιγραφη',
    'solution_notes': 'λυση',
    'department_id': 'τμημα',
    'department_text': 'τμημα',
    'equipment_id': 'εξοπλισμος',
    'equipment_text': 'εξοπλισμος',
    'caller_id': 'χρηστης',
    'caller_text': 'χρηστης',
    'phone_text': 'τηλεφωνο',
    'category_text': 'κατηγορια',
    'category_id': 'κατηγορια',
    'issue': 'θεμα',
    'solution': 'λυση',
    'type': 'τυπος',
    'custom_ip': 'ip',
    'linked_users': 'συνδεδεμενοι χρηστες',
    'linked_equipment': 'συνδεδεμενος εξοπλισμος',
    'linked_phone_numbers': 'τηλεφωνα',
    'linked_user_id': 'χρηστης',
    'color': 'χρωμα',
    'building': 'κτηριο',
    'map_floor': 'οροφος',
    'floor_id': 'οροφος',
    'notes': 'σημειωσεις',
    'map_x': 'θεσης χ',
    'map_y': 'θεσης υ',
    'map_width': 'πλατους',
    'map_height': 'υψους',
    'map_rotation': 'περιστροφης',
    'map_label_offset_x': 'μετατοπισης ετικετας χ',
    'map_label_offset_y': 'μετατοπισης ετικετας υ',
    'map_anchor_offset_x': 'μετατοπισης αγκυρας χ',
    'map_anchor_offset_y': 'μετατοπισης αγκυρας υ',
    'map_custom_name': 'προσαρμοσμενου ονοματος',
    'map_hidden': 'ορατοτητας',
  };
  final label = labels[field];
  if (label != null) return label;
  if (entityType.trim().isEmpty) return 'πεδιου $field';
  return 'πεδιου $field';
}

String _stringifyValueForMigration(String field, dynamic value) {
  if (value == null) return '';
  if (field == 'status') {
    final raw = value.toString().trim().toLowerCase();
    const map = <String, String>{
      'pending': 'εκκρεμης',
      'completed': 'ολοκληρωμενη',
      'closed': 'κλειστη',
      'open': 'ανοιχτη',
      'in_progress': 'σε εξελιξη',
    };
    return map[raw] ?? raw;
  }
  if (field == 'priority') {
    final raw = value.toString().trim().toLowerCase();
    const map = <String, String>{
      'low': 'χαμηλη',
      'normal': 'κανονικη',
      'medium': 'μεσαια',
      'high': 'υψηλη',
      'urgent': 'επειγουσα',
    };
    return map[raw] ?? raw;
  }
  if (field == 'color') {
    return _friendlyColorForMigration(value.toString());
  }
  if (field == 'map_floor') {
    return _formatFloorValueForMigration(value) ?? 'χωρις οροφο';
  }
  if (value is List) {
    return '${value.length} στοιχεια';
  }
  if (value is Map) {
    return 'δομημενα δεδομενα';
  }
  return '$value'.trim();
}

String _subactionSearchTextForMigration({
  required String entityType,
  required String field,
  required String label,
  required dynamic oldValue,
  required String oldText,
  required dynamic newValue,
  required String newText,
}) {
  if (entityType == 'department' && field == 'map_floor') {
    final oldFloor = _formatFloorValueForMigration(oldValue);
    final newFloor = _formatFloorValueForMigration(newValue);
    if ((oldFloor == null || oldFloor == 'χωρις οροφο') &&
        newFloor != null &&
        newFloor != 'χωρις οροφο') {
      return 'προσθηκη στον οροφο $newFloor';
    }
    if (oldFloor != null &&
        oldFloor != 'χωρις οροφο' &&
        (newFloor == null || newFloor == 'χωρις οροφο')) {
      return 'αφαιρεση απο οροφο $oldFloor';
    }
    if (oldFloor != null && newFloor != null) {
      return 'αλλαγη οροφου απο $oldFloor σε $newFloor';
    }
  }

  if (entityType == 'phone' && field == 'linked_user_id') {
    final oldUser = _hasMeaningfulValueForMigration(oldValue)
        ? '#$oldValue'
        : null;
    final newUser = _hasMeaningfulValueForMigration(newValue)
        ? '#$newValue'
        : null;
    if (oldUser == null && newUser != null) return 'συνδεση σε χρηστη $newUser';
    if (oldUser != null && newUser == null) {
      return 'αποσυνδεση απο χρηστη $oldUser';
    }
    if (oldUser != null && newUser != null) {
      return 'μεταφορα απο χρηστη $oldUser σε $newUser';
    }
  }
  if (entityType == 'phone' && field == 'department_id') {
    final oldDepartment = _hasMeaningfulValueForMigration(oldValue)
        ? '#$oldValue'
        : null;
    final newDepartment = _hasMeaningfulValueForMigration(newValue)
        ? '#$newValue'
        : null;
    if (oldDepartment == null && newDepartment != null) {
      return 'συνδεση σε τμημα $newDepartment';
    }
    if (oldDepartment != null && newDepartment == null) {
      return 'αποσυνδεση απο τμημα $oldDepartment';
    }
    if (oldDepartment != null && newDepartment != null) {
      return 'μεταφορα απο τμημα $oldDepartment σε $newDepartment';
    }
  }

  final hasOld = _hasMeaningfulValueForMigration(oldValue);
  final hasNew = _hasMeaningfulValueForMigration(newValue);
  if (!hasOld && hasNew) {
    return 'προσθηκη $label $newText';
  }
  if (hasOld && !hasNew) {
    return 'αφαιρεση $label $oldText';
  }
  if (hasOld && hasNew) {
    return 'αλλαγη $label απο $oldText σε $newText';
  }
  return '';
}

bool _hasMeaningfulValueForMigration(dynamic value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is List) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return '$value'.trim().isNotEmpty;
}

bool _valuesEqualForMigration(dynamic a, dynamic b) {
  if (a == null && b == null) return true;
  if (a is List || a is Map || b is List || b is Map) {
    try {
      return jsonEncode(a) == jsonEncode(b);
    } catch (_) {
      return '$a' == '$b';
    }
  }
  return '${a ?? ''}' == '${b ?? ''}';
}

String _friendlyColorForMigration(String raw) {
  final normalized = raw.trim().toUpperCase();
  const known = <String, String>{
    '#1976D2': 'μπλε',
    '#EF5350': 'κοκκινο',
    '#4CAF50': 'πρασινο',
    '#FFC107': 'κιτρινο',
    '#9C27B0': 'μωβ',
  };
  return known[normalized] ?? raw.trim();
}

String? _formatFloorValueForMigration(dynamic value) {
  if (value == null) return 'χωρις οροφο';
  final text = value.toString().trim();
  if (text.isEmpty) return 'χωρις οροφο';
  return text;
}
