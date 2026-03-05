import 'dart:async';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/app_config.dart';
import '../services/settings_service.dart';
import '../../features/calls/models/call_model.dart';

/// Αποτέλεσμα ελέγχου σύνδεσης (success + αν χρησιμοποιείται τοπική βάση).
class ConnectionCheckResult {
  const ConnectionCheckResult({required this.success, required this.isLocalDev});

  final bool success;
  final bool isLocalDev;
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

  /// Αρχικοποίηση βάσης: έλεγχος δικτύου, fallback σε τοπική, WAL, πίνακες.
  Future<Database> _initDatabase() async {
    String dbPath = await SettingsService().getDatabasePath();
    if (dbPath.trim().isEmpty) {
      dbPath = AppConfig.defaultDbPath;
    }

    final accessible = await _isNetworkPathAccessible(dbPath);
    if (!accessible) {
      // ignore: avoid_print
      print('Δίκτυο μη διαθέσιμο. Ενεργοποίηση Dev Mode (Τοπική Βάση).');
      dbPath = AppConfig.localDevDbPath;
      _isUsingLocalDb = true;
      final dir = File(dbPath).parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      singleInstance: false,
    );
    await db.execute('PRAGMA journal_mode = WAL;');
    return db;
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
        name TEXT,
        department TEXT,
        phone TEXT,
        location TEXT,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE equipment (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT,
        brand TEXT,
        model TEXT,
        serial_number TEXT,
        user_id INTEGER,
        buy_date TEXT
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

  /// Σκελετός για μελλοντικές αναβαθμίσεις σχήματος (migrations).
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Εδώ θα προστεθούν migrations όταν αλλάξει το schema.
  }

  /// Επιστρέφει όλους τους χρήστες.
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final db = await database;
    return db.query('users');
  }

  /// Επιστρέφει όλο τον εξοπλισμό.
  Future<List<Map<String, dynamic>>> getAllEquipment() async {
    final db = await database;
    return db.query('equipment');
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

  /// Εισάγει νέα κλήση. date/time τίθενται από τώρα αν δεν δοθούν.
  Future<int> insertCall(CallModel call) async {
    final db = await database;
    final now = DateTime.now();
    final row = {
      'date': call.date ?? DateFormat('yyyy-MM-dd').format(now),
      'time': call.time ?? DateFormat('HH:mm').format(now),
      'caller_id': call.callerId,
      'equipment_id': call.equipmentId,
      'issue': call.issue,
      'solution': call.solution,
      'category': call.category,
      'status': call.status ?? 'open',
      'duration': call.duration,
      'is_priority': call.isPriority ?? 0,
    };
    return db.insert('calls', row);
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
        // ignore: avoid_print
        print('Δίκτυο μη διαθέσιμο. Ενεργοποίηση Dev Mode (Τοπική Βάση).');
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
      // ignore: avoid_print
      print('[DatabaseHelper] Δεν είναι δυνατή η σύνδεση με τη βάση: $dbPath');
      // ignore: avoid_print
      print('[DatabaseHelper] Σφάλμα: $e');
      // ignore: avoid_print
      print('[DatabaseHelper] $st');
      return const ConnectionCheckResult(success: false, isLocalDev: false);
    }
  }
}
