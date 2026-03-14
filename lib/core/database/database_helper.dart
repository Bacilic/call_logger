import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/app_config.dart';
import '../services/settings_service.dart';
import '../utils/name_parser.dart';
import '../../features/calls/models/call_model.dart';
import 'database_init_result.dart';

/// Αποτέλεσμα ελέγχου σύνδεσης (success + αν χρησιμοποιείται τοπική βάση).
class ConnectionCheckResult {
  const ConnectionCheckResult({required this.success, required this.isLocalDev});

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
      final exists = await File(dbPath).exists().timeout(
            const Duration(seconds: 2),
            onTimeout: () => false,
          );
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
        version: 6,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        singleInstance: false,
      );
    } on DatabaseInitException {
      rethrow;
    } catch (e) {
      throw DatabaseInitException(
        DatabaseInitResult.fromException(e, dbPath),
      );
    }

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
      version: 6,
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
        issue TEXT,
        solution TEXT,
        category TEXT,
        status TEXT,
        duration INTEGER,
        is_priority INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE users (
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
      CREATE TABLE equipment (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code_equipment TEXT,
        type TEXT,
        user_id INTEGER,
        notes TEXT,
        custom_ip TEXT,
        anydesk_id TEXT,
        default_remote_tool TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        description TEXT,
        due_date TEXT,
        status TEXT,
        call_id INTEGER
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
  }

  /// Επιστρέφει true αν ο πίνακας [table] έχει τη στήλη [column].
  Future<bool> _tableHasColumn(Database db, String table, String column) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final names = (info.map((e) => e['name'] as String?)).whereType<String>();
    return names.contains(column);
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
        await db.execute('ALTER TABLE equipment ADD COLUMN default_remote_tool TEXT');
      }
    }
  }

  /// Μετεγκατάσταση πίνακα users από name σε last_name + first_name.
  /// Λογική split: last_name = τελευταία λέξη του name (trim & split by κενό), first_name = όλες οι άλλες (join με κενό).
  /// Τα πεδία department, location, notes δεν αλλάζουν.
  Future<void> _migrateUsersToFirstLastName(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(users)');
    final columns = (info.map((e) => e['name'] as String?)).whereType<String>().toSet();
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

  /// Επιστρέφει όλους τους χρήστες.
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final db = await database;
    return db.query('users');
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
  Future<void> bulkUpdateUsers(List<int> ids, Map<String, dynamic> changes) async {
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

  /// Διαγράφει χρήστες με τα δεδομένα ids. Transaction αν ids non-empty.
  Future<void> deleteUsers(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.transaction((txn) async {
      await txn.delete(
        'users',
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );
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
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Επιστρέφει όλο τον εξοπλισμό.
  Future<List<Map<String, dynamic>>> getAllEquipment() async {
    final db = await database;
    return db.query('equipment');
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
      List<int> ids, Map<String, dynamic> changes) async {
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

  /// Διαγράφει εξοπλισμό με τα δεδομένα ids. Transaction αν ids non-empty.
  Future<void> deleteEquipments(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.transaction((txn) async {
      await txn.delete(
        'equipment',
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );
    });
  }

  /// Επιστρέφει τις τελευταίες κλήσεις για χρήστη (κατά id DESC).
  Future<List<Map<String, dynamic>>> getRecentCallsByUserId(
    int userId, {
    int limit = 3,
  }) async {
    final db = await database;
    return db.query(
      'calls',
      where: 'caller_id = ?',
      whereArgs: [userId],
      orderBy: 'id DESC',
      limit: limit,
    );
  }

  /// Διαγράφει users + equipment πριν το νέο import.
  Future<void> clearImportedData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('equipment');
      await txn.delete('users');
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
        });
        equipmentInserted++;
      }
    });

    return (usersInserted: usersInserted, equipmentInserted: equipmentInserted);
  }

  /// Εισάγει νέο χρήστη. Το Data Layer δέχεται ήδη διαχωρισμένα firstName/lastName (parsing γίνεται στο Domain/UI).
  Future<int> insertUser({
    required String firstName,
    required String lastName,
    String? phone,
    String? department,
    String? location,
    String? notes,
  }) async {
    final db = await database;
    return db.insert('users', {
      'last_name': lastName,
      'first_name': firstName,
      'phone': phone,
      'department': department,
      'location': location,
      'notes': notes,
    });
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
        // Αντί να αντικαθιστούμε, καλύτερα να το προσθέτουμε στο τέλος αν έχει ήδη τηλέφωνα,
        // ή να το θέτουμε αν είναι null, αλλά η απαίτηση ήταν "ή != phone".
        // Εφόσον η εφαρμογή ψάχνει πλέον με contains, ας κάνουμε append.
        final userResult = await txn.query('users', columns: ['phone'], where: 'id = ?', whereArgs: [userId]);
        if (userResult.isNotEmpty) {
          final currentPhone = userResult.first['phone'] as String?;
          if (currentPhone == null || currentPhone.trim().isEmpty) {
            await txn.update('users', {'phone': phone}, where: 'id = ?', whereArgs: [userId]);
          } else if (!currentPhone.contains(phone)) {
            await txn.update('users', {'phone': '$currentPhone, $phone'}, where: 'id = ?', whereArgs: [userId]);
          }
        }
      }
      if (equipmentCode != null && equipmentCode.isNotEmpty) {
        // Υποθέτουμε ότι η στήλη είναι code_equipment (από create table)
        await txn.update(
          'equipment',
          {'user_id': userId},
          where: 'code_equipment = ? AND (user_id IS NULL OR user_id != ?)',
          whereArgs: [equipmentCode, userId],
        );
      }
    });
  }

  /// Εισάγει νέα κλήση. date/time τίθενται από τώρα αν δεν δοθούν.
  Future<int> insertCall(CallModel call) async {
    final db = await database;
    final now = DateTime.now();
    final row = {
      'date': call.date ?? DateFormat('yyyy-MM-dd').format(now),
      'time': call.time ?? DateFormat('HH:mm').format(now),
      'caller_id': call.callerId,
      'equipment_id': call.equipmentId,
      'caller_text': call.callerText,
      'issue': call.issue,
      'solution': call.solution,
      'category': call.category,
      'status': call.status ?? 'open',
      'duration': call.duration,
      'is_priority': call.isPriority ?? 0,
    };
    return db.insert('calls', row);
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
  Future<TablePreviewResult> getTablePreview(String tableName, {int rowLimit = 500}) async {
    final db = await database;
    final info = await db.rawQuery('PRAGMA table_info($tableName)');
    final columns = (info.map((e) => e['name'] as String?).whereType<String>().toList());
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
      debugPrint('[DatabaseHelper] Δεν είναι δυνατή η σύνδεση με τη βάση: $dbPath');
      debugPrint('[DatabaseHelper] Σφάλμα: $e');
      debugPrint('[DatabaseHelper] $st');
      return const ConnectionCheckResult(success: false, isLocalDev: false);
    }
  }
}
