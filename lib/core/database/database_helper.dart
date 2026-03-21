import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/app_config.dart';
import '../services/settings_service.dart';
import '../utils/name_parser.dart';
import '../utils/phone_list_parser.dart';
import '../utils/search_text_normalizer.dart';
import '../../features/calls/models/call_model.dart';
import 'database_init_result.dart';

/// Αποτέλεσμα ελέγχου σύνδεσης (success + αν χρησιμοποιείται τοπική βάση).
class ConnectionCheckResult {
  const ConnectionCheckResult({
    required this.success,
    required this.isLocalDev,
  });

  final bool success;
  final bool isLocalDev;
}

/// Αποτέλεσμα προεπισκόπησης πίνακα: ονόματα στηλών και γραμμές (List<Map>).
class TablePreviewResult {
  const TablePreviewResult({required this.columns, required this.rows});

  final List<String> columns;
  final List<Map<String, dynamic>> rows;
}

/// Singleton helper για πρόσβαση στη SQLite βάση δεδομένων (sqflite_common_ffi).
/// Υποστηρίζει δυναμική διαδρομή, WAL και έξυπνο fallback σε τοπική βάση.
class DatabaseHelper {
  DatabaseHelper._();

  /// Κλειδί `app_settings` για το όνομα χρήστη στις εγγραφές audit (προαιρετικό).
  static const String auditUserPerformingSettingsKey = 'audit_user_performing';

  static const String auditActionDelete = 'ΔΙΑΓΡΑΦΗ';
  static const String auditActionRestore = 'ΕΠΑΝΑΦΟΡΑ';
  static const String auditActionBulkDelete = 'ΜΑΖΙΚΗ ΔΙΑΓΡΑΦΗ';

  static final DatabaseHelper _instance = DatabaseHelper._();

  static DatabaseHelper get instance => _instance;

  Database? _database;
  bool _isUsingLocalDb = false;

  /// True αν η εφαρμογή χρησιμοποιεί την τοπική βάση (Dev Mode).
  bool get isUsingLocalDb => _isUsingLocalDb;

  /// Επιστρέφει την ενεργή σύνδεση. Κάνει αρχικοποίηση αν χρειάζεται.
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Κλείνει την τρέχουσα σύνδεση και επαναφέρει την κατάσταση.
  /// Στην επόμενη κλήση [database] θα γίνει νέα σύνδεση (π.χ. με νέα διαδρομή από ρυθμίσεις).
  Future<void> closeConnection() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    _isUsingLocalDb = false;
  }

  /// Ελέγχει αν η διαδρομή δικτύου είναι προσβάσιμη (με timeout 2 s).
  Future<bool> _isNetworkPathAccessible(String dbPath) async {
    try {
      final exists = await File(
        dbPath,
      ).exists().timeout(const Duration(seconds: 2), onTimeout: () => false);
      return exists;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Αρχικοποίηση βάσης: έλεγχος δικτύου, ύπαρξη αρχείου, WAL, σχήμα (fail-fast).
  /// Δεν δημιουργεί αυτόματα αρχείο· ρίχνει [DatabaseInitException] σε αποτυχία.
  Future<Database> _initDatabase() async {
    String dbPath = await SettingsService().getDatabasePath();
    if (dbPath.trim().isEmpty) {
      dbPath = AppConfig.defaultDbPath;
    }

    final accessible = await _isNetworkPathAccessible(dbPath);
    if (!accessible) {
      debugPrint('Δίκτυο μη διαθέσιμο. Ενεργοποίηση Dev Mode (Τοπική Βάση).');
      dbPath = AppConfig.localDevDbPath;
      _isUsingLocalDb = true;
      final dir = File(dbPath).parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    if (!await File(dbPath).exists()) {
      throw DatabaseInitException(DatabaseInitResult.fileNotFound(dbPath));
    }

    Database db;
    try {
      db = await openDatabase(
        dbPath,
        version: 15,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        singleInstance: false,
      );
    } on DatabaseInitException {
      rethrow;
    } catch (e) {
      throw DatabaseInitException(DatabaseInitResult.fromException(e, dbPath));
    }

    await _ensureCallsSearchIndexColumnAndBackfill(db);
    await _ensureTasksSearchIndexColumnAndBackfill(db);

    try {
      await _validateSchema(db, dbPath);
    } catch (_) {
      await db.close();
      _database = null;
      rethrow;
    }

    await db.execute('PRAGMA journal_mode = WAL;');
    return db;
  }

  /// Επαληθεύει ότι υπάρχει ο πίνακας [calls]. Αλλιώς ρίχνει [DatabaseInitException].
  Future<void> _validateSchema(Database db, String dbPath) async {
    final r = await db.rawQuery('PRAGMA table_info(calls)');
    if (r.isEmpty) {
      throw DatabaseInitException(
        DatabaseInitResult.corruptedOrInvalid(
          dbPath,
          'Λείπει ο πίνακας calls· το αρχείο δεν φαίνεται έγκυρη βάση.',
        ),
      );
    }
  }

  /// Δημιουργεί νέο αρχείο βάσης στο [filePath] με το τρέχον σχήμα.
  /// Δεν αλλάζει την ενεργή σύνδεση (_database). Για χρήση από Ρυθμίσεις (δημιουργία από μηδέν).
  Future<void> createNewDatabaseFile(String filePath) async {
    final db = await openDatabase(
      filePath,
      version: 15,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      singleInstance: false,
    );
    await db.execute('PRAGMA journal_mode = WAL;');
    await db.close();
  }

  /// Δημιουργία σχήματος (πίνακες) στην πρώτη εγκατάσταση.
  /// Δημιουργεί τους πίνακες: calls, users, equipment, categories, tasks,
  /// knowledge_base, audit_log, app_settings.
  Future<void> _onCreate(Database db, int version) async {
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
        phone TEXT,
        department_id INTEGER,
        location TEXT,
        notes TEXT,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE equipment (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code_equipment TEXT,
        type TEXT,
        user_id INTEGER,
        notes TEXT,
        custom_ip TEXT,
        anydesk_id TEXT,
        default_remote_tool TEXT,
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
    await _seedRemoteToolArgsIfEmpty(db);
  }

  /// Εισάγει προεπιλεγμένα ορίσματα VNC/AnyDesk αν ο πίνακας remote_tool_args είναι άδειος.
  static Future<void> _seedRemoteToolArgsIfEmpty(Database db) async {
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

  /// Συγκεντρώνει κείμενα κλήσης + συσχετισμένου χρήστη/εξοπλισμού για `search_index`.
  /// Το όνομα τμήματος προέρχεται από `departments` (JOIN στο `users.department_id`)·
  /// η στήλη `users.department` δεν υπάρχει στο τρέχον CREATE TABLE.
  /// Ο κωδικός εξοπλισμού διαβάζεται από `equipment.code_equipment` (όχι από `code`).
  Future<String> _buildCallSearchIndex(
    Database db,
    Map<String, dynamic> callMap,
  ) async {
    void addNonEmpty(List<String> parts, dynamic v) {
      if (v == null) return;
      final s = v.toString().trim();
      if (s.isNotEmpty) parts.add(s);
    }

    final parts = <String>[];

    addNonEmpty(parts, callMap['issue']);
    addNonEmpty(parts, callMap['solution']);
    addNonEmpty(parts, callMap['caller_text']);
    addNonEmpty(parts, callMap['phone_text']);
    addNonEmpty(parts, callMap['department_text']);
    addNonEmpty(parts, callMap['equipment_text']);

    final callerId = callMap['caller_id'] as int?;
    if (callerId != null) {
      List<Map<String, Object?>> userRows;
      if (await _tableExists(db, 'departments')) {
        userRows = await db.rawQuery(
          '''
          SELECT u.first_name, u.last_name, u.phone, d.name AS department_name
          FROM users u
          LEFT JOIN departments d ON u.department_id = d.id
          WHERE u.id = ?
          LIMIT 1
          ''',
          [callerId],
        );
      } else {
        userRows = await db.query(
          'users',
          columns: ['first_name', 'last_name', 'phone'],
          where: 'id = ?',
          whereArgs: [callerId],
          limit: 1,
        );
      }
      if (userRows.isNotEmpty) {
        final u = userRows.first;
        addNonEmpty(parts, u['first_name']);
        addNonEmpty(parts, u['last_name']);
        addNonEmpty(parts, u['phone']);
        addNonEmpty(parts, u['department_name']);
      }
    }

    final equipmentId = callMap['equipment_id'] as int?;
    if (equipmentId != null) {
      final eqRows = await db.query(
        'equipment',
        columns: ['code_equipment'],
        where: 'id = ?',
        whereArgs: [equipmentId],
        limit: 1,
      );
      if (eqRows.isNotEmpty) {
        addNonEmpty(parts, eqRows.first['code_equipment']);
      }
    }

    return SearchTextNormalizer.normalizeForSearch(parts.join(' '));
  }

  /// Προσθέτει `calls.search_index` αν λείπει (χωρίς αλλαγή user_version) και γεμίζει γραμμές με NULL.
  Future<void> _ensureCallsSearchIndexColumnAndBackfill(Database db) async {
    if (!await _tableHasColumn(db, 'calls', 'search_index')) {
      await db.execute('ALTER TABLE calls ADD COLUMN search_index TEXT');
    }

    final rows = await db.rawQuery(
      'SELECT * FROM calls WHERE search_index IS NULL',
    );
    for (final row in rows) {
      final id = row['id'] as int?;
      if (id == null) continue;
      final index = await _buildCallSearchIndex(db, row);
      await db.rawUpdate(
        'UPDATE calls SET search_index = ? WHERE id = ?',
        [index, id],
      );
    }
  }

  /// Προσθέτει `tasks.search_index` αν λείπει (χωρίς αλλαγή user_version) και γεμίζει υπάρχουσες γραμμές.
  Future<void> _ensureTasksSearchIndexColumnAndBackfill(Database db) async {
    var added = false;
    if (!await _tableHasColumn(db, 'tasks', 'search_index')) {
      await db.execute('ALTER TABLE tasks ADD COLUMN search_index TEXT');
      added = true;
    }
    if (!added) return;

    final rows = await db.query('tasks');
    for (final row in rows) {
      final id = row['id'] as int?;
      if (id == null) continue;
      final combined = [
        row['title'] as String? ?? '',
        row['description'] as String? ?? '',
        row['user_text'] as String? ?? '',
        row['phone_text'] as String? ?? '',
        row['equipment_text'] as String? ?? '',
        row['department_text'] as String? ?? '',
      ].join(' ');
      final index = SearchTextNormalizer.normalizeForSearch(combined);
      await db.update(
        'tasks',
        {'search_index': index},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  /// Επιστρέφει true αν ο πίνακας [table] έχει τη στήλη [column].
  Future<bool> _tableHasColumn(Database db, String table, String column) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final names = (info.map((e) => e['name'] as String?)).whereType<String>();
    return names.contains(column);
  }

  Future<bool> _tableExists(Database db, String tableName) async {
    final r = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
      [tableName],
    );
    return r.isNotEmpty;
  }

  Future<String> _auditPerformingUser(Database db) async {
    final v = await getSetting(auditUserPerformingSettingsKey);
    final t = v?.trim();
    if (t != null && t.isNotEmpty) return t;
    return '—';
  }

  Future<void> _appendAuditLog(
    DatabaseExecutor executor,
    String performingUser,
    String action,
    String details,
  ) async {
    await executor.insert('audit_log', {
      'action': action,
      'timestamp': DateTime.now().toIso8601String(),
      'user_performing': performingUser,
      'details': details,
    });
  }

  /// Σκελετός για μελλοντικές αναβαθμίσεις σχήματος (migrations).
  /// users: phone δεν έχει UNIQUE ώστε να επιτρέπονται πολλαπλά τηλέφωνα ανά χρήστη (π.χ. comma-separated).
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      if (!await _tableHasColumn(db, 'equipment', 'notes')) {
        await db.execute('ALTER TABLE equipment ADD COLUMN notes TEXT');
      }
    }
    if (oldVersion < 3) {
      if (!await _tableHasColumn(db, 'equipment', 'code')) {
        await db.execute('ALTER TABLE equipment ADD COLUMN code TEXT');
      }
      if (!await _tableHasColumn(db, 'equipment', 'description')) {
        await db.execute('ALTER TABLE equipment ADD COLUMN description TEXT');
      }
    }
    if (oldVersion < 4) {
      if (!await _tableHasColumn(db, 'calls', 'caller_text')) {
        await db.execute('ALTER TABLE calls ADD COLUMN caller_text TEXT');
      }
    }
    // Migration users: name → last_name + first_name (split: last word = last_name, υπόλοιπο = first_name).
    if (oldVersion < 5) {
      await _migrateUsersToFirstLastName(db);
    }
    // Στήλες απομακρυσμένης σύνδεσης (exception-based).
    if (oldVersion < 6) {
      if (!await _tableHasColumn(db, 'equipment', 'custom_ip')) {
        await db.execute('ALTER TABLE equipment ADD COLUMN custom_ip TEXT');
      }
      if (!await _tableHasColumn(db, 'equipment', 'anydesk_id')) {
        await db.execute('ALTER TABLE equipment ADD COLUMN anydesk_id TEXT');
      }
      if (!await _tableHasColumn(db, 'equipment', 'default_remote_tool')) {
        await db.execute(
          'ALTER TABLE equipment ADD COLUMN default_remote_tool TEXT',
        );
      }
    }
    // Πίνακας tasks: στήλες για προτεραιότητα, σημειώσεις λύσης, αναβολή, timestamps.
    if (oldVersion < 7) {
      if (!await _tableHasColumn(db, 'tasks', 'priority')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN priority INTEGER');
      }
      if (!await _tableHasColumn(db, 'tasks', 'solution_notes')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN solution_notes TEXT');
      }
      if (!await _tableHasColumn(db, 'tasks', 'snooze_until')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN snooze_until TEXT');
      }
      if (!await _tableHasColumn(db, 'tasks', 'updated_at')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN updated_at TEXT');
      }
      if (!await _tableHasColumn(db, 'tasks', 'created_at')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN created_at TEXT');
      }
      if (!await _tableHasColumn(db, 'tasks', 'caller_id') &&
          !await _tableHasColumn(db, 'tasks', 'user_id')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN caller_id INTEGER');
      } else if (!await _tableHasColumn(db, 'tasks', 'caller_id') &&
          await _tableHasColumn(db, 'tasks', 'user_id')) {
        await db.execute('ALTER TABLE tasks RENAME COLUMN user_id TO caller_id');
      }
      if (!await _tableHasColumn(db, 'tasks', 'equipment_id')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN equipment_id INTEGER');
      }
    }
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS remote_tool_args (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tool_name TEXT,
          arg_flag TEXT,
          description TEXT,
          is_active INTEGER DEFAULT 0
        )
      ''');
      await _seedRemoteToolArgsIfEmpty(db);
    }
    // Στήλη department_id στον πίνακα users (συσχέτιση με πίνακα departments).
    if (oldVersion < 9) {
      if (!await _tableHasColumn(db, 'users', 'department_id')) {
        await db.execute('ALTER TABLE users ADD COLUMN department_id INTEGER');
      }
    }
    // Fallback (Hybrid Schema): ελεύθερο κείμενο τηλ./τμήματος/εξοπλισμού αν δεν υπάρχει στο join.
    if (oldVersion < 10) {
      if (!await _tableHasColumn(db, 'calls', 'phone_text')) {
        await db.execute('ALTER TABLE calls ADD COLUMN phone_text TEXT');
      }
      if (!await _tableHasColumn(db, 'calls', 'department_text')) {
        await db.execute('ALTER TABLE calls ADD COLUMN department_text TEXT');
      }
      if (!await _tableHasColumn(db, 'calls', 'equipment_text')) {
        await db.execute('ALTER TABLE calls ADD COLUMN equipment_text TEXT');
      }
    }
    // Κανονικοποίηση κατηγορίας: category → category_text + category_id (FK προς categories).
    if (oldVersion < 11) {
      if (!await _tableHasColumn(db, 'calls', 'category_text')) {
        if (await _tableHasColumn(db, 'calls', 'category')) {
          await db.execute(
            'ALTER TABLE calls RENAME COLUMN category TO category_text',
          );
        }
      }
      if (!await _tableHasColumn(db, 'calls', 'category_id')) {
        await db.execute('ALTER TABLE calls ADD COLUMN category_id INTEGER');
      }
    }
    if (oldVersion < 12) {
      if (!await _tableHasColumn(db, 'tasks', 'snooze_history_json')) {
        await db.execute(
          'ALTER TABLE tasks ADD COLUMN snooze_history_json TEXT',
        );
      }
    }
    // tasks: user_id → caller_id (συμβατό με calls.caller_id / καλών).
    if (oldVersion < 13) {
      if (await _tableHasColumn(db, 'tasks', 'user_id') &&
          !await _tableHasColumn(db, 'tasks', 'caller_id')) {
        await db.execute('ALTER TABLE tasks RENAME COLUMN user_id TO caller_id');
      }
    }
    // Soft delete: is_deleted σε κύριους πίνακες (όχι remote_tool_args).
    if (oldVersion < 14) {
      const tablesWithSoftDelete = <String>[
        'calls',
        'users',
        'equipment',
        'categories',
        'tasks',
      ];
      for (final t in tablesWithSoftDelete) {
        if (await _tableExists(db, t) &&
            !await _tableHasColumn(db, t, 'is_deleted')) {
          await db.execute(
            'ALTER TABLE $t ADD COLUMN is_deleted INTEGER DEFAULT 0',
          );
        }
      }
      if (await _tableExists(db, 'departments') &&
          !await _tableHasColumn(db, 'departments', 'is_deleted')) {
        await db.execute(
          'ALTER TABLE departments ADD COLUMN is_deleted INTEGER DEFAULT 0',
        );
      }
    }
    // remote_tool_args: αφαίρεση soft-deleted γραμμών αν υπήρχε παλιά στήλη is_deleted.
    if (oldVersion < 15) {
      if (await _tableExists(db, 'remote_tool_args') &&
          await _tableHasColumn(db, 'remote_tool_args', 'is_deleted')) {
        await db.execute(
          'DELETE FROM remote_tool_args WHERE COALESCE(is_deleted, 0) = 1',
        );
      }
    }
  }

  /// Μετεγκατάσταση πίνακα users από name σε last_name + first_name.
  /// Λογική split: last_name = τελευταία λέξη του name (trim & split by κενό), first_name = όλες οι άλλες (join με κενό).
  /// Τα πεδία department, location, notes δεν αλλάζουν.
  Future<void> _migrateUsersToFirstLastName(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(users)');
    final columns = (info.map(
      (e) => e['name'] as String?,
    )).whereType<String>().toSet();
    if (!columns.contains('name')) {
      return; // Ήδη μετεγκαταστάθηκε (π.χ. από εφάπαξ script).
    }

    // 1) Πρόσθεσε νέο πεδίο first_name (idempotent).
    if (!columns.contains('first_name')) {
      await db.execute('ALTER TABLE users ADD COLUMN first_name TEXT');
    }
    // 2) Πρόσθεσε last_name (idempotent).
    if (!columns.contains('last_name')) {
      await db.execute('ALTER TABLE users ADD COLUMN last_name TEXT');
    }

    // 3) Πλήρωσε first_name / last_name με split από name (Dart: πιο αξιόπιστο από pure SQL χωρίς REVERSE).
    final rows = await db.rawQuery('SELECT id, name FROM users');
    for (final row in rows) {
      final id = row['id'] as int?;
      final nameRaw = row['name'] as String?;
      if (id == null) continue;
      final parts = (nameRaw ?? '').trim().split(RegExp(r'\s+'));
      final String lastName;
      final String firstName;
      if (parts.isEmpty) {
        lastName = '';
        firstName = '';
      } else if (parts.length == 1) {
        lastName = parts.single;
        firstName = parts.single;
      } else {
        lastName = parts.last;
        firstName = parts.sublist(0, parts.length - 1).join(' ');
      }
      await db.rawUpdate(
        'UPDATE users SET first_name = ?, last_name = ? WHERE id = ?',
        [firstName, lastName, id],
      );
    }

    // 4) Αντικατάσταση name: δημιουργία πίνακα με νέο σχήμα (last_name NOT NULL, first_name NOT NULL), copy, drop παλιό, rename.
    await db.execute('''
      CREATE TABLE users_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        last_name TEXT NOT NULL,
        first_name TEXT NOT NULL,
        phone TEXT,
        department TEXT,
        location TEXT,
        notes TEXT
      )
    ''');
    await db.execute('''
      INSERT INTO users_new (id, last_name, first_name, phone, department, location, notes)
      SELECT id, last_name, first_name, phone, department, location, notes FROM users
    ''');
    await db.execute('DROP TABLE users');
    await db.execute('ALTER TABLE users_new RENAME TO users');
    final maxId = await db.rawQuery('SELECT MAX(id) AS m FROM users');
    final seq = (maxId.first['m'] as int?) ?? 0;
    await db.rawUpdate(
      "UPDATE sqlite_sequence SET seq = ? WHERE name = 'users'",
      [seq],
    );
  }

  /// Επιστρέφει ενεργούς χρήστες (`is_deleted = 0`).
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final db = await database;
    return db.query(
      'users',
      where: 'COALESCE(is_deleted, 0) = ?',
      whereArgs: [0],
    );
  }

  /// Εισάγει χρήστη από map (π.χ. UserModel.toMap()). Αφαιρεί [id] πριν το insert.
  Future<int> insertUserFromMap(Map<String, dynamic> row) async {
    final map = Map<String, dynamic>.from(row);
    map.remove('id');
    final db = await database;
    return db.insert('users', map);
  }

  /// Ενημερώνει χρήστη. Αφαιρεί [id] από [values] πριν το update.
  Future<int> updateUser(int id, Map<String, dynamic> values) async {
    final map = Map<String, dynamic>.from(values);
    map.remove('id');
    final db = await database;
    return db.update('users', map, where: 'id = ?', whereArgs: [id]);
  }

  /// Μαζική ενημέρωση: εφαρμόζει τα ίδια [changes] σε όλα τα [ids]. Transaction.
  Future<void> bulkUpdateUsers(
    List<int> ids,
    Map<String, dynamic> changes,
  ) async {
    if (ids.isEmpty || changes.isEmpty) return;
    final map = Map<String, dynamic>.from(changes);
    map.remove('id');
    if (map.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update('users', map, where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  /// Soft delete χρηστών (`is_deleted = 1`) + audit ανά id.
  Future<void> deleteUsers(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final user = await _auditPerformingUser(db);
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'users',
          {'is_deleted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await _appendAuditLog(
          txn,
          user,
          auditActionDelete,
          'users id=$id',
        );
      }
    });
  }

  /// Επαναφορά χρηστών μετά από soft delete (`is_deleted = 0`) + audit.
  Future<void> restoreUsers(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final user = await _auditPerformingUser(db);
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'users',
          {'is_deleted': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
        await _appendAuditLog(
          txn,
          user,
          auditActionRestore,
          'users id=$id',
        );
      }
    });
  }

  /// Αναγνώριση ρύθμισης από πίνακα app_settings. Επιστρέφει null αν δεν υπάρχει.
  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// Αποθήκευση ρύθμισης στον πίνακα app_settings (insert ή replace).
  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Επιστρέφει department_id για το [name].
  /// Αν δεν υπάρχει, δημιουργεί νέο τμήμα και επιστρέφει το νέο id.
  Future<int?> getOrCreateDepartmentIdByName(String? name) async {
    final normalized = name?.trim() ?? '';
    if (normalized.isEmpty) return null;
    final db = await database;
    return db.transaction<int?>((txn) async {
      final existing = await txn.rawQuery(
        'SELECT id FROM departments WHERE TRIM(name) = ? COLLATE NOCASE '
        'AND COALESCE(is_deleted, 0) = 0 LIMIT 1',
        [normalized],
      );
      if (existing.isNotEmpty) {
        return existing.first['id'] as int?;
      }

      await txn.insert('departments', {
        'name': normalized,
        'is_deleted': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      final rows = await txn.rawQuery(
        'SELECT id FROM departments WHERE TRIM(name) = ? COLLATE NOCASE '
        'AND COALESCE(is_deleted, 0) = 0 LIMIT 1',
        [normalized],
      );
      return rows.isNotEmpty ? rows.first['id'] as int? : null;
    });
  }

  /// Επιστρέφει ενεργό εξοπλισμό (`is_deleted = 0`).
  Future<List<Map<String, dynamic>>> getAllEquipment() async {
    final db = await database;
    return db.query(
      'equipment',
      where: 'COALESCE(is_deleted, 0) = ?',
      whereArgs: [0],
    );
  }

  /// Εισάγει εξοπλισμό από map (π.χ. EquipmentModel.toMap()). Αφαιρεί [id] πριν το insert.
  Future<int> insertEquipmentFromMap(Map<String, dynamic> row) async {
    final map = Map<String, dynamic>.from(row);
    map.remove('id');
    final db = await database;
    return db.insert('equipment', map);
  }

  /// Ενημερώνει εξοπλισμό. Αφαιρεί [id] από [values] πριν το update.
  Future<int> updateEquipment(int id, Map<String, dynamic> values) async {
    final map = Map<String, dynamic>.from(values);
    map.remove('id');
    final db = await database;
    return db.update('equipment', map, where: 'id = ?', whereArgs: [id]);
  }

  /// Μαζική ενημέρωση εξοπλισμού: εφαρμόζει τα ίδια [changes] σε όλα τα [ids]. Transaction.
  Future<void> bulkUpdateEquipments(
    List<int> ids,
    Map<String, dynamic> changes,
  ) async {
    if (ids.isEmpty || changes.isEmpty) return;
    final map = Map<String, dynamic>.from(changes);
    map.remove('id');
    if (map.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update('equipment', map, where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  /// Soft delete εξοπλισμού (`is_deleted = 1`) + audit ανά id.
  Future<void> deleteEquipments(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final user = await _auditPerformingUser(db);
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'equipment',
          {'is_deleted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await _appendAuditLog(
          txn,
          user,
          auditActionDelete,
          'equipment id=$id',
        );
      }
    });
  }

  /// Επαναφορά εξοπλισμού μετά από soft delete + audit.
  Future<void> restoreEquipment(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final user = await _auditPerformingUser(db);
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'equipment',
          {'is_deleted': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
        await _appendAuditLog(
          txn,
          user,
          auditActionRestore,
          'equipment id=$id',
        );
      }
    });
  }

  /// Επιστρέφει τις τελευταίες κλήσεις για καλούντα (calls.caller_id, κατά id DESC).
  Future<List<Map<String, dynamic>>> getRecentCallsByCallerId(
    int callerId, {
    int limit = 3,
  }) async {
    final db = await database;
    return db.query(
      'calls',
      where: 'caller_id = ? AND COALESCE(is_deleted, 0) = ?',
      whereArgs: [callerId, 0],
      orderBy: 'id DESC',
      limit: limit,
    );
  }

  /// Μαζικό soft delete users + equipment πριν νέο import + audit.
  Future<void> clearImportedData() async {
    final db = await database;
    final user = await _auditPerformingUser(db);
    await db.transaction((txn) async {
      await txn.rawUpdate('UPDATE equipment SET is_deleted = 1');
      await txn.rawUpdate('UPDATE users SET is_deleted = 1');
      await _appendAuditLog(
        txn,
        user,
        auditActionBulkDelete,
        'clearImportedData: users+equipment (soft)',
      );
    });
  }

  /// Εισαγωγή prepared δεδομένων σε ένα transaction:
  /// 1. Insert owners → map ownerId → db user_id
  /// 2. Insert equipment (μόνο code + user_id)
  Future<({int usersInserted, int equipmentInserted})> importPreparedData(
    List<Map<String, dynamic>> ownersList,
    List<Map<String, dynamic>> equipmentList,
  ) async {
    if (ownersList.isEmpty && equipmentList.isEmpty) {
      return (usersInserted: 0, equipmentInserted: 0);
    }
    final db = await database;
    int usersInserted = 0;
    int equipmentInserted = 0;

    await db.transaction((txn) async {
      final ownerCodeToDbId = <int, int>{};
      for (final u in ownersList) {
        final ownerId = u['ownerId'] as int? ?? 0;
        final fullName = u['fullName'] as String? ?? '';
        final parsed = NameParserUtility.parse(fullName);
        final id = await txn.insert('users', {
          'last_name': parsed.lastName,
          'first_name': parsed.firstName,
          'phone': u['phones'] as String? ?? '',
          'department': u['department'] as String? ?? '',
          'location': null,
          'notes': null,
          'is_deleted': 0,
        });
        ownerCodeToDbId[ownerId] = id;
      }
      usersInserted = ownerCodeToDbId.length;

      for (final e in equipmentList) {
        final ownerCodeTemp = e['ownerCodeTemp'] as int? ?? 0;
        final userId = ownerCodeToDbId[ownerCodeTemp];
        await txn.insert('equipment', {
          'code_equipment': e['code'] as String?,
          'user_id': userId,
          'is_deleted': 0,
        });
        equipmentInserted++;
      }
    });

    return (usersInserted: usersInserted, equipmentInserted: equipmentInserted);
  }

  /// Εισάγει νέο χρήστη. Το Data Layer δέχεται ήδη διαχωρισμένα firstName/lastName (parsing γίνεται στο Domain/UI).
  /// [departmentId] αντιστοιχεί στον πίνακα departments (schema με department_id).
  Future<int> insertUser({
    required String firstName,
    required String lastName,
    String? phone,
    String? department,
    String? location,
    String? notes,
    int? departmentId,
  }) async {
    final db = await database;
    final map = <String, dynamic>{
      'last_name': lastName,
      'first_name': firstName,
      'phone': phone,
      'department': department,
      'location': location,
      'notes': notes,
      'is_deleted': 0,
    };
    if (departmentId != null) {
      map['department_id'] = departmentId;
    }
    return db.insert('users', map);
  }

  /// Ενημερώνει συσχετίσεις χρήστη: τηλέφωνο (users.phone) και/ή εξοπλισμό (equipment.user_id) με βάση τον κωδικό του.
  Future<void> updateAssociationsIfNeeded(
    int? userId,
    String? phone,
    String? equipmentCode,
  ) async {
    if (userId == null) return;
    final db = await database;
    await db.transaction((txn) async {
      if (phone != null && phone.isNotEmpty) {
        final userResult = await txn.query(
          'users',
          columns: ['phone'],
          where: 'id = ?',
          whereArgs: [userId],
        );
        if (userResult.isNotEmpty) {
          final currentPhone = userResult.first['phone'] as String?;
          if (currentPhone == null || currentPhone.trim().isEmpty) {
            await txn.update(
              'users',
              {'phone': phone},
              where: 'id = ?',
              whereArgs: [userId],
            );
          } else if (!PhoneListParser.containsPhone(currentPhone, phone)) {
            final merged = PhoneListParser.joinPhones([
              ...PhoneListParser.splitPhones(currentPhone),
              phone,
            ]);
            await txn.update(
              'users',
              {'phone': merged},
              where: 'id = ?',
              whereArgs: [userId],
            );
          }
        }
      }
      if (equipmentCode != null && equipmentCode.isNotEmpty) {
        final code = equipmentCode.trim();
        if (code.isNotEmpty) {
          // Υποθέτουμε ότι η στήλη είναι code_equipment (από create table)
          var rows = await txn.update(
            'equipment',
            {'user_id': userId},
            where:
                'code_equipment = ? AND (user_id IS NULL OR user_id != ?) '
                'AND COALESCE(is_deleted, 0) = 0',
            whereArgs: [code, userId],
          );
          // Αν δεν υπάρχει γραμμή με αυτόν τον κωδικό, το UPDATE δεν αλλάζει τίποτα·
          // δημιουργούμε νέα εγγραφή εξοπλισμού συνδεδεμένη με τον χρήστη.
          if (rows == 0) {
            final existing = await txn.query(
              'equipment',
              columns: ['id', 'user_id'],
              where: 'code_equipment = ? AND COALESCE(is_deleted, 0) = 0',
              whereArgs: [code],
              limit: 1,
            );
            if (existing.isEmpty) {
              await txn.insert('equipment', {
                'code_equipment': code,
                'user_id': userId,
                'is_deleted': 0,
              });
            }
          }
        }
      }
    });
  }

  /// Εισάγει νέα κλήση. date/time τίθενται από τώρα αν δεν δοθούν.
  Future<int> insertCall(CallModel call) async {
    final db = await database;
    final now = DateTime.now();
    final map = <String, dynamic>{
      'date': call.date ?? DateFormat('yyyy-MM-dd').format(now),
      'time': call.time ?? DateFormat('HH:mm').format(now),
      'caller_id': call.callerId,
      'equipment_id': call.equipmentId,
      'caller_text': call.callerText,
      'phone_text': call.phoneText,
      'department_text': call.departmentText,
      'equipment_text': call.equipmentText,
      'issue': call.issue,
      'solution': call.solution,
      'category_text': call.category,
      'category_id': null,
      'status': call.status ?? 'completed',
      'duration': call.duration,
      'is_priority': call.isPriority ?? 0,
      'is_deleted': 0,
    };
    map['search_index'] = await _buildCallSearchIndex(db, map);
    return db.insert('calls', map);
  }

  /// Ενημερώνει υπάρχουσα κλήση. Απαιτείται μη-null [CallModel.id].
  Future<int> updateCall(CallModel call) async {
    final id = call.id;
    if (id == null) {
      throw ArgumentError('CallModel.id is required for updateCall');
    }
    final db = await database;
    final map = <String, dynamic>{
      'date': call.date,
      'time': call.time,
      'caller_id': call.callerId,
      'equipment_id': call.equipmentId,
      'caller_text': call.callerText,
      'phone_text': call.phoneText,
      'department_text': call.departmentText,
      'equipment_text': call.equipmentText,
      'issue': call.issue,
      'solution': call.solution,
      'category_text': call.category,
      'status': call.status,
      'duration': call.duration,
      'is_priority': call.isPriority ?? 0,
      'is_deleted': call.isDeleted ? 1 : 0,
    };
    map['search_index'] = await _buildCallSearchIndex(db, map);
    return db.update('calls', map, where: 'id = ?', whereArgs: [id]);
  }

  /// Λίστα ονομάτων πινάκων (χωρίς εσωτερικά sqlite_*). Για προβολή Βάσης Δεδομένων.
  Future<List<String>> getTableNames() async {
    final db = await database;
    final r = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return r.map((e) => e['name'] as String).toList();
  }

  /// Προεπισκόπηση πίνακα: στήλες + γραμμές (μέγ. [rowLimit]). Για προβολή τύπου Excel.
  Future<TablePreviewResult> getTablePreview(
    String tableName, {
    int rowLimit = 500,
  }) async {
    final db = await database;
    final info = await db.rawQuery('PRAGMA table_info($tableName)');
    final columns = (info
        .map((e) => e['name'] as String?)
        .whereType<String>()
        .toList());
    if (columns.isEmpty) return TablePreviewResult(columns: [], rows: []);

    final rows = await db.rawQuery('SELECT * FROM $tableName LIMIT $rowLimit');
    return TablePreviewResult(columns: columns, rows: rows);
  }

  /// Ελέγχει υγεία βάσης: ύπαρξη πίνακα 'calls' (και βασικών πινάκων).
  /// Καλείται αφού η σύνδεση είναι ανοιχτή. Επιστρέφει [DatabaseInitResult].
  Future<DatabaseInitResult> checkDatabaseHealth() async {
    try {
      final db = await database;
      final r = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='calls'",
      );
      if (r.isEmpty) {
        return const DatabaseInitResult(
          status: DatabaseStatus.corruptedOrInvalid,
          message: 'Η βάση φαίνεται κατεστραμμένη ή μη έγκυρη.',
          details: 'Λείπει ο πίνακας calls.',
        );
      }
      return DatabaseInitResult.success();
    } catch (e) {
      return DatabaseInitResult.fromException(e);
    }
  }

  /// Επιστρέφει ονόματα κατηγοριών από τον πίνακα categories (για dropdown φίλτρων).
  Future<List<String>> getCategoryNames() async {
    final db = await database;
    final rows = await db.query(
      'categories',
      columns: ['name'],
      where: 'COALESCE(is_deleted, 0) = ?',
      whereArgs: [0],
      orderBy: 'name',
    );
    return rows
        .map((r) => r['name'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Εισάγει νέα κατηγορία και επιστρέφει το row id (sqlite rowid).
  Future<int> insertCategoryAndGetId(String name) async {
    final db = await database;
    return db.insert('categories', {'name': name.trim(), 'is_deleted': 0});
  }

  /// Soft delete εργασίας (`tasks`) + audit.
  Future<void> softDeleteTask(int id) async {
    final db = await database;
    final user = await _auditPerformingUser(db);
    await db.transaction((txn) async {
      await txn.update(
        'tasks',
        {'is_deleted': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _appendAuditLog(
        txn,
        user,
        auditActionDelete,
        'tasks id=$id',
      );
    });
  }

  /// Ιστορικό κλήσεων με προαιρετικά φίλτρα. LEFT JOIN users και equipment.
  /// Προαιρετικό [keyword]: φιλτράρισμα σε `calls.search_index` (ήδη κανονικοποιημένο).
  /// [dateFrom] / [dateTo]: ημερομηνίες σε μορφή yyyy-MM-dd.
  Future<List<Map<String, dynamic>>> getHistoryCalls({
    String? dateFrom,
    String? dateTo,
    String? category,
    String? keyword,
  }) async {
    final db = await database;
    final whereClauses = <String>[];
    final args = <dynamic>[];

    if (dateFrom != null && dateFrom.isNotEmpty) {
      whereClauses.add('calls.date >= ?');
      args.add(dateFrom);
    }
    if (dateTo != null && dateTo.isNotEmpty) {
      whereClauses.add('calls.date <= ?');
      args.add(dateTo);
    }
    if (category != null && category.isNotEmpty) {
      whereClauses.add('calls.category_text = ?');
      args.add(category);
    }
    if (keyword != null && keyword.isNotEmpty) {
      whereClauses.add('calls.search_index LIKE ?');
      args.add('%$keyword%');
    }

    whereClauses.insert(0, 'COALESCE(calls.is_deleted, 0) = 0');

    final whereSql = whereClauses.isEmpty
        ? ''
        : 'WHERE ${whereClauses.join(' AND ')}';
    final sql =
        '''
      SELECT calls.id, calls.date, calls.time, calls.caller_id, calls.equipment_id,
             calls.issue, calls.solution, calls.caller_text, calls.phone_text, calls.department_text, calls.equipment_text,
             calls.category_text AS category, calls.status, calls.duration, calls.is_priority,
             COALESCE(users.first_name, calls.caller_text, '') AS user_first_name,
             COALESCE(users.last_name, '') AS user_last_name,
             COALESCE(NULLIF(TRIM(calls.phone_text), ''), users.phone, '-') AS user_phone,
             COALESCE(departments.name, calls.department_text, '-') AS user_department,
             COALESCE(equipment.code_equipment, calls.equipment_text, '-') AS equipment_code
      FROM calls
      LEFT JOIN users ON calls.caller_id = users.id
      LEFT JOIN equipment ON calls.equipment_id = equipment.id
      LEFT JOIN departments ON users.department_id = departments.id
      $whereSql
      ORDER BY calls.date DESC, calls.time DESC
    ''';

    return db.rawQuery(sql, args);
  }

  /// Επαληθεύει αν η διαδρομή είναι προσβάσιμη. Fallback σε τοπική όπως στο _initDatabase.
  Future<ConnectionCheckResult> checkConnection() async {
    String dbPath = AppConfig.defaultDbPath;
    try {
      dbPath = await SettingsService().getDatabasePath();
      if (dbPath.trim().isEmpty) {
        dbPath = AppConfig.defaultDbPath;
      }

      final accessible = await _isNetworkPathAccessible(dbPath);
      if (!accessible) {
        debugPrint('Δίκτυο μη διαθέσιμο. Ενεργοποίηση Dev Mode (Τοπική Βάση).');
        dbPath = AppConfig.localDevDbPath;
      }

      final db = await openDatabase(
        dbPath,
        version: 1,
        readOnly: true,
        singleInstance: false,
      );
      await db.rawQuery('PRAGMA quick_check;');
      await db.close();
      final isLocal = dbPath == AppConfig.localDevDbPath;
      return ConnectionCheckResult(success: true, isLocalDev: isLocal);
    } catch (e, st) {
      debugPrint(
        '[DatabaseHelper] Δεν είναι δυνατή η σύνδεση με τη βάση: $dbPath',
      );
      debugPrint('[DatabaseHelper] Σφάλμα: $e');
      debugPrint('[DatabaseHelper] $st');
      return const ConnectionCheckResult(success: false, isLocalDev: false);
    }
  }

  /// One-time migration: δημιουργεί πίνακα departments και τον γεμίζει από users.department & location.
  /// Idempotent: αν app_settings έχει key='departments_migration_done', value='1', δεν κάνει τίποτα.
  Future<void> migrateDepartmentsIfNeeded() async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT value FROM app_settings WHERE key = ? AND value = ?",
      ['departments_migration_done', '1'],
    );
    if (rows.isNotEmpty) return;

    try {
      await db.transaction((txn) async {
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS departments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
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
        await txn.execute(
          'INSERT OR IGNORE INTO departments (name, building) '
          "SELECT DISTINCT department, location FROM users WHERE department IS NOT NULL AND department != '' ORDER BY department",
        );
        await txn.execute(
          "UPDATE departments SET color = '#1976D2' WHERE color IS NULL",
        );
        await txn.execute(
          "INSERT OR REPLACE INTO app_settings (key, value) VALUES ('departments_migration_done', '1')",
        );
      });
      debugPrint(
        'Departments table created and populated from users.department & location.',
      );
    } catch (e, st) {
      debugPrint('migrateDepartmentsIfNeeded error: $e');
      debugPrint('$st');
    }
  }
}
