import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/app_config.dart';
import '../services/dictionary_service.dart';
import '../services/settings_service.dart';
import '../utils/department_display_utils.dart';
import '../utils/name_parser.dart';
import '../utils/phone_list_parser.dart';
import '../utils/search_text_normalizer.dart';
import '../../features/calls/models/call_model.dart';
import '../errors/department_exists_exception.dart';
import 'database_init_result.dart';
import 'database_init_progress_provider.dart';
import 'lock_diagnostic_service.dart';
import 'database_path_resolution.dart';
import 'database_v1_schema.dart';

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

  /// Squashed schema ([_onCreate] + [_onUpgradeSquashed] για v1→v2). Παλιά αρχεία: `dart run tool/migrate_to_v1.dart`.
  static const int _kDatabaseSchemaVersion = databaseSchemaVersionV1;

  static final DatabaseHelper _instance = DatabaseHelper._();

  static DatabaseHelper get instance => _instance;

  /// Αποκλειστικά για δοκιμές: όταν οριστεί, η [database] ανοίγει μόνο αυτό το αρχείο
  /// (δημιουργείται κενό σχήμα αν λείπει). Κλήση [releaseTestDatabaseBinding] μετά τα τεστ.
  static String? _testOverrideDatabasePath;

  /// Κλείνει τυχόν σύνδεση και δεσμεύει όλες οι επόμενες συνδέσεις στο [absoluteFilePath].
  static Future<void> bindTestDatabaseFile(String absoluteFilePath) async {
    await instance.closeConnection();
    _testOverrideDatabasePath = absoluteFilePath;
  }

  /// Αφαιρεί τη δέσμευση διαδρομής δοκιμών (επόμενη σύνδεση = κανονική λογική εφαρμογής).
  static void releaseTestDatabaseBinding() {
    _testOverrideDatabasePath = null;
  }

  Database? _database;
  Future<Database>? _databaseInitializingFuture;
  bool _isUsingLocalDb = false;

  /// True αν η εφαρμογή χρησιμοποιεί την τοπική βάση (Dev Mode).
  bool get isUsingLocalDb => _isUsingLocalDb;

  /// Επιστρέφει την ενεργή σύνδεση. Κάνει αρχικοποίηση αν χρειάζεται.
  Future<Database> get database async {
    return initializeDatabase();
  }

  /// Αρχικοποιεί βάση με προαιρετικό notifier προόδου.
  Future<Database> initializeDatabase({
    DatabaseInitProgressNotifier? progressNotifier,
  }) async {
    if (_database != null && _database!.isOpen) return _database!;
    final inFlight = _databaseInitializingFuture;
    if (inFlight != null) {
      return await inFlight;
    }
    _databaseInitializingFuture = _initDatabase(
      progressNotifier: progressNotifier,
    );
    try {
      _database = await _databaseInitializingFuture!;
    } finally {
      _databaseInitializingFuture = null;
    }
    return _database!;
  }

  /// Κλείνει την τρέχουσα σύνδεση και επαναφέρει την κατάσταση.
  /// Στην επόμενη κλήση [database] θα γίνει νέα σύνδεση (π.χ. με νέα διαδρομή από ρυθμίσεις).
  Future<void> closeConnection() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    _databaseInitializingFuture = null;
    _isUsingLocalDb = false;
  }

  Future<Database> _openTestOverrideDatabase(
    String dbPath, {
    DatabaseInitProgressNotifier? progressNotifier,
  }) async {
    final file = File(dbPath);
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    if (!await file.exists()) {
      await createNewDatabaseFile(dbPath);
    }
    _isUsingLocalDb = true;
    final timeoutSeconds = await _resolveDatabaseOpenTimeoutSeconds();
    Database db;
    try {
      db = await _openWithTimeout(
        targetPath: dbPath,
        singleInstance: false,
        timeoutSeconds: timeoutSeconds,
        progressNotifier: progressNotifier,
        attempt: 1,
        maxAttempts: 1,
      );
    } catch (e, st) {
      throw DatabaseInitException(
        DatabaseInitResult.fromException(e, dbPath, st),
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

  /// Best-effort WAL checkpoint για μείωση pending WAL writes.
  Future<void> tryWalCheckpoint({String mode = 'PASSIVE'}) async {
    final db = _database;
    if (db == null || !db.isOpen) return;
    try {
      final normalized = mode.trim().toUpperCase();
      final effective = normalized.isEmpty ? 'PASSIVE' : normalized;
      await db.rawQuery('PRAGMA wal_checkpoint($effective)');
    } catch (_) {}
  }

  Future<String> forceReleaseLock(
    String dbPath, {
    DatabaseInitProgressNotifier? progressNotifier,
  }) async {
    final buffer = StringBuffer();
    try {
      progressNotifier?.setStep('Απελευθέρωση lock');
      await tryWalCheckpoint(mode: 'FULL');
      await closeConnection();
    } catch (e) {
      buffer.writeln('Checkpoint/close warning: $e');
    }

    try {
      progressNotifier?.setStep('Εντοπισμός διεργασίας');
      final diagnostic = await const LockDiagnosticService()
          .detectLockingProcess(dbPath);
      if (diagnostic.trim().isNotEmpty) {
        buffer.writeln(diagnostic.trim());
      }
    } catch (e) {
      buffer.writeln('Lock diagnostic warning: $e');
    }

    for (final suffix in const <String>['-wal', '-shm']) {
      final sidecarPath = '$dbPath$suffix';
      try {
        final f = File(sidecarPath);
        if (await f.exists()) {
          await f.delete();
          buffer.writeln('Deleted sidecar file: $sidecarPath');
        }
      } catch (e) {
        buffer.writeln('Failed to delete $sidecarPath: $e');
      }
    }

    final message = buffer.toString().trim();
    return message.isEmpty
        ? 'Δεν προέκυψε επιπλέον διαγνωστική πληροφορία.'
        : message;
  }

  Future<String> aggressiveCleanupBeforeOpen(
    String dbPath, {
    DatabaseInitProgressNotifier? progressNotifier,
  }) async {
    progressNotifier?.setStep('Απελευθέρωση lock');
    final diagnostic = await forceReleaseLock(
      dbPath,
      progressNotifier: progressNotifier,
    );
    progressNotifier?.setDiagnostic(diagnostic);
    return diagnostic;
  }

  /// Αρχικοποίηση βάσης: επίλυση διαδρομής (UNC fallback), ύπαρξη αρχείου, WAL, σχήμα (fail-fast).
  /// Δεν δημιουργεί αυτόματα αρχείο· ρίχνει [DatabaseInitException] σε αποτυχία.
  /// Σε δοκιμές με [bindTestDatabaseFile] δημιουργείται το αρχείο αν λείπει.
  Future<Database> _initDatabase({
    DatabaseInitProgressNotifier? progressNotifier,
  }) async {
    if (_testOverrideDatabasePath != null) {
      return _openTestOverrideDatabase(
        _testOverrideDatabasePath!,
        progressNotifier: progressNotifier,
      );
    }

    progressNotifier?.setStep('Έλεγχος διαδρομής');
    final configured = await SettingsService().getDatabasePath();
    final resolved = await resolveEffectiveDatabasePath(configured);
    final dbPath = resolved.path;
    _isUsingLocalDb = resolved.usedUncFallback;

    if (!await File(dbPath).exists()) {
      throw DatabaseInitException(DatabaseInitResult.fileNotFound(dbPath));
    }

    final timeoutSeconds = await _resolveDatabaseOpenTimeoutSeconds();
    const maxAttempts = 3;
    String? lastDiagnostic;
    Object? lastError;
    StackTrace? lastStack;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
        lastDiagnostic = await aggressiveCleanupBeforeOpen(
          dbPath,
          progressNotifier: progressNotifier,
        );
      }

      try {
        final db = await _openWithTimeout(
          targetPath: dbPath,
          singleInstance: false,
          timeoutSeconds: timeoutSeconds,
          progressNotifier: progressNotifier,
          attempt: attempt,
          maxAttempts: maxAttempts,
        );
        try {
          await _validateSchema(db, dbPath);
        } catch (_) {
          await db.close();
          _database = null;
          rethrow;
        }
        await db.execute('PRAGMA journal_mode = WAL;');
        progressNotifier?.setStep(
          'Η βάση άνοιξε επιτυχώς',
          clearSecondsRemaining: true,
        );
        return db;
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        final retriable = e is TimeoutException || _looksLikeLockError(e);
        if (!retriable || attempt >= maxAttempts) {
          var result = DatabaseInitResult.fromException(e, dbPath, st);
          if (lastDiagnostic != null && lastDiagnostic.trim().isNotEmpty) {
            result = result.copyWith(
              details: _mergeDetails(result.details, lastDiagnostic),
            );
          }
          throw DatabaseInitException(result);
        }
      }
    }

    final fallbackResult = DatabaseInitResult.fromException(
      lastError ?? TimeoutException('Unknown database open timeout'),
      dbPath,
      lastStack,
    );
    throw DatabaseInitException(fallbackResult);
  }

  Future<int> _resolveDatabaseOpenTimeoutSeconds() async {
    try {
      final value = await SettingsService().getDatabaseOpenTimeoutSeconds();
      if (value <= 0) return AppConfig.databaseOpenTimeoutSeconds;
      return value;
    } catch (_) {
      return AppConfig.databaseOpenTimeoutSeconds;
    }
  }

  Future<Database> _openWithTimeout({
    required String targetPath,
    required bool singleInstance,
    required int timeoutSeconds,
    required int attempt,
    required int maxAttempts,
    DatabaseInitProgressNotifier? progressNotifier,
  }) async {
    final safeTimeout = timeoutSeconds <= 0
        ? AppConfig.databaseOpenTimeoutSeconds
        : timeoutSeconds;
    var remaining = safeTimeout;
    progressNotifier?.setStep(
      'Άνοιγμα βάσης... ($remaining s)',
      secondsRemaining: remaining,
    );

    Timer? countdownTimer;
    if (safeTimeout > 1 && progressNotifier != null) {
      countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        remaining -= 1;
        if (remaining < 0) {
          remaining = 0;
        }
        progressNotifier.setStep(
          'Άνοιγμα βάσης... ($remaining s)',
          secondsRemaining: remaining,
        );
      });
    }

    try {
      return await openDatabase(
        targetPath,
        version: _kDatabaseSchemaVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgradeSquashed,
        onDowngrade: _onDowngradeSquashed,
        singleInstance: singleInstance,
      ).timeout(
        Duration(seconds: safeTimeout),
        onTimeout: () {
          throw TimeoutException(
            'openDatabase timed out after ${safeTimeout}s '
            '(attempt $attempt/$maxAttempts)',
          );
        },
      );
    } finally {
      countdownTimer?.cancel();
      progressNotifier?.clearCountdown();
    }
  }

  bool _looksLikeLockError(Object error) {
    final lower = error.toString().toLowerCase();
    return lower.contains('database is locked') ||
        lower.contains('sqlite_busy') ||
        lower.contains('sharing violation') ||
        lower.contains('unable to open database file');
  }

  String _mergeDetails(String? current, String diagnostic) {
    final c = current?.trim() ?? '';
    final d = diagnostic.trim();
    if (d.isEmpty) return c;
    if (c.isEmpty) return d;
    return '$c\n\n--- Lock diagnostics ---\n$d';
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
      version: _kDatabaseSchemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgradeSquashed,
      onDowngrade: _onDowngradeSquashed,
      singleInstance: false,
    );
    await db.execute('PRAGMA journal_mode = WAL;');
    await db.close();
  }

  /// Δημιουργία σχήματος v1 (squashed): όλοι οι πίνακες σε μία δημιουργία.
  Future<void> _onCreate(Database db, int version) async {
    await applyDatabaseV1Schema(db);
  }

  /// Μήνυμα αναντιστοιχίας user_version (αρχείο) έναντι έκδοσης σχήματος εφαρμογής.
  static String _schemaVersionMismatchUserMessage(
    Database db,
    int fileUserVersion,
    int appSchemaVersion,
  ) {
    final fileName = p.basename(db.path);
    return 'Το αρχείο της βάσης σας $fileName είναι στην έκδοση '
        '$fileUserVersion. Η εφαρμογή τρέχει την έκδοση '
        '$appSchemaVersion.\n\n'
        'Μπορείτε να:\n'
        '• Μετασχηματίσετε την βάση σας στη σωστή έκδοση με κάποιο script.\n'
        '• Να εντοπίσετε το σωστό αρχείο βάσης (μέσα από τις ρυθμίσεις).\n'
        '• Να δημιουργήσετε μια νέα βάση χωρίς δεδομένα (μέσα από τις ρυθμίσεις).';
  }

  /// Αναβάθμιση squashed σχήματος (π.χ. v1 → v2: στήλες `equipment.department_id`, `location`).
  Future<void> _onUpgradeSquashed(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion >= newVersion) return;
    if (oldVersion == 0) return;
    // Sequential, idempotent migrations για άλματα εκδόσεων (π.χ. 2 -> 5).
    if (oldVersion < 2 && newVersion >= 2) {
      await _migrateEquipmentDepartmentLocationColumns(db);
    }
    if (oldVersion < 3 && newVersion >= 3) {
      await _migrateDepartmentPhonesTable(db);
    }
    if (oldVersion < 4 && newVersion >= 4) {
      await _migrateDepartmentNameKey(db);
    }
    if (oldVersion < 5 && newVersion >= 5) {
      await _migratePhonesDepartmentColumn(db);
    }
    if (oldVersion < 6 && newVersion >= 6) {
      await _migrateUserDictionaryTable(db);
    }
  }

  /// Πίνακας προσωπικών λέξεων ορθογραφίας (Windows / custom lexicon).
  static Future<void> _migrateUserDictionaryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_dictionary (
        word TEXT PRIMARY KEY
      )
    ''');
  }

  /// Προσθέτει στήλες τμήμα/τοποθεσία στον πίνακα `equipment` αν λείπουν (idempotent).
  static Future<void> _migrateEquipmentDepartmentLocationColumns(
    Database db,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info(equipment)');
    final names = info.map((r) => r['name'] as String).toSet();
    if (!names.contains('department_id')) {
      await db.execute(
        'ALTER TABLE equipment ADD COLUMN department_id INTEGER',
      );
    }
    if (!names.contains('location')) {
      await db.execute('ALTER TABLE equipment ADD COLUMN location TEXT');
    }
  }

  /// Δημιουργεί πίνακα `department_phones` αν λείπει (idempotent).
  static Future<void> _migrateDepartmentPhonesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS department_phones (
        department_id INTEGER NOT NULL,
        phone_id INTEGER NOT NULL,
        PRIMARY KEY (department_id, phone_id)
      )
    ''');
  }

  static const String _kDepartmentsNameKeyColumn = 'name_key';

  /// Προσθέτει `departments.name_key` και το γεμίζει για υπάρχουσες εγγραφές.
  /// Στόχος: `name` = εμφανίσιμο, `name_key` = κανονικοποιημένο μοναδικό κλειδί.
  static Future<void> _migrateDepartmentNameKey(Database db) async {
    const tableName = 'departments';
    final info = await db.rawQuery('PRAGMA table_info($tableName)');
    if (info.isEmpty) {
      throw Exception(
        'Μετάβαση σχήματος: δεν υπάρχει ο πίνακας `$tableName` (PRAGMA table_info '
        'επέστρεψε κενό). no such table: $tableName',
      );
    }
    final names = info.map((r) => r['name'] as String).toSet();
    if (!names.contains(_kDepartmentsNameKeyColumn)) {
      const stmt = 'ALTER TABLE departments ADD COLUMN name_key TEXT';
      try {
        await db.execute(stmt);
      } catch (e) {
        throw Exception(
          'Μετάβαση σχήματος απέτυχε: πίνακας `$tableName`, εντολή: `$stmt`. $e',
        );
      }
    }

    // Backfill name_key για παλιές εγγραφές.
    final rows = await db.query(
      'departments',
      columns: ['id', 'name', 'name_key'],
    );
    for (final r in rows) {
      final id = r['id'] as int?;
      if (id == null) continue;
      final existing = (r['name_key'] as String?)?.trim() ?? '';
      if (existing.isNotEmpty) continue;
      final name = (r['name'] as String?)?.trim() ?? '';
      final key = SearchTextNormalizer.normalizeForSearch(name);
      if (key.isEmpty) continue;
      await db.update(
        'departments',
        {_kDepartmentsNameKeyColumn: key},
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    // Unique index για το name_key (πλήρης μοναδικότητα).
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_departments_name_key ON departments(name_key)',
    );
  }

  /// Προσθέτει `phones.department_id` για πολιτική shared-location.
  static Future<void> _migratePhonesDepartmentColumn(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(phones)');
    final names = info.map((r) => r['name'] as String).toSet();
    if (!names.contains('department_id')) {
      await db.execute('ALTER TABLE phones ADD COLUMN department_id INTEGER');
    }
  }

  Future<void> _ensurePhonesDepartmentColumn(DatabaseExecutor db) async {
    final info = await db.rawQuery('PRAGMA table_info(phones)');
    final names = info.map((r) => r['name'] as String).toSet();
    if (!names.contains('department_id')) {
      await db.execute('ALTER TABLE phones ADD COLUMN department_id INTEGER');
    }
  }

  /// Αρχείο με νεότερο user_version (π.χ. 17) ενώ η εφαρμογή αναμένει v1.
  Future<void> _onDowngradeSquashed(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    throw DatabaseInitException(
      DatabaseInitResult(
        status: DatabaseStatus.applicationError,
        message: _schemaVersionMismatchUserMessage(db, oldVersion, newVersion),
      ),
    );
  }

  /// Συγκεντρώνει κείμενα κλήσης + συσχετισμένου χρήστη/εξοπλισμού για `search_index` (σχήμα v1).
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
      final userRows = await db.rawQuery(
        '''
        SELECT u.first_name, u.last_name, d.name AS department_name
        FROM users u
        LEFT JOIN departments d ON u.department_id = d.id
        WHERE u.id = ?
        LIMIT 1
        ''',
        [callerId],
      );
      if (userRows.isNotEmpty) {
        final u = userRows.first;
        addNonEmpty(parts, u['first_name']);
        addNonEmpty(parts, u['last_name']);
        addNonEmpty(parts, u['department_name']);
      }
      final phoneRows = await db.rawQuery(
        '''
        SELECT p.number FROM user_phones up
        JOIN phones p ON p.id = up.phone_id
        WHERE up.user_id = ?
        ORDER BY p.number
        ''',
        [callerId],
      );
      for (final pr in phoneRows) {
        addNonEmpty(parts, pr['number']);
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

  Future<void> _replaceUserPhonesInTxn(
    Transaction txn,
    int userId,
    List<String> numbers,
  ) async {
    await txn.delete('user_phones', where: 'user_id = ?', whereArgs: [userId]);
    for (final raw in numbers) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      await txn.insert('phones', {
        'number': t,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final r = await txn.query(
        'phones',
        columns: ['id'],
        where: 'number = ?',
        whereArgs: [t],
        limit: 1,
      );
      if (r.isEmpty) continue;
      final pid = r.first['id'] as int;
      await txn.insert('user_phones', {
        'user_id': userId,
        'phone_id': pid,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _addDepartmentPhoneInTxn(
    Transaction txn,
    int departmentId,
    String phoneNumber,
  ) async {
    final t = phoneNumber.trim();
    if (t.isEmpty) return;
    await txn.insert('phones', {
      'number': t,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final r = await txn.query(
      'phones',
      columns: ['id'],
      where: 'number = ?',
      whereArgs: [t],
      limit: 1,
    );
    if (r.isEmpty) return;
    final pid = r.first['id'] as int;
    await txn.update(
      'phones',
      {'department_id': departmentId},
      where: 'id = ?',
      whereArgs: [pid],
    );
    await txn.delete(
      'department_phones',
      where: 'phone_id = ?',
      whereArgs: [pid],
    );
    await txn.insert('department_phones', {
      'department_id': departmentId,
      'phone_id': pid,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Προσθέτει “ορφανό” τηλέφωνο σε τμήμα (M2M: `department_phones` ↔ `phones`).
  Future<void> addDepartmentDirectPhone(
    int departmentId,
    String phoneNumber,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await _addDepartmentPhoneInTxn(txn, departmentId, phoneNumber);
    });
  }

  /// Αφαιρεί “ορφανό” τηλέφωνο από τμήμα (δεν διαγράφει την εγγραφή από `phones`).
  Future<void> removeDepartmentDirectPhone(
    int departmentId,
    String phoneNumber,
  ) async {
    final t = phoneNumber.trim();
    if (t.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final r = await txn.query(
        'phones',
        columns: ['id'],
        where: 'number = ?',
        whereArgs: [t],
        limit: 1,
      );
      if (r.isEmpty) return;
      final pid = r.first['id'] as int?;
      if (pid == null) return;
      await txn.delete(
        'department_phones',
        where: 'department_id = ? AND phone_id = ?',
        whereArgs: [departmentId, pid],
      );
    });
  }

  /// Επιστρέφει map: department_id → λίστα phone numbers (ταξινομημένα).
  Future<Map<int, List<String>>> getDepartmentDirectPhonesMap() async {
    final db = await database;
    await _ensurePhonesDepartmentColumn(db);
    final rows = await db.rawQuery('''
      SELECT src.department_id AS department_id, src.number AS number
      FROM (
        SELECT dp.department_id AS department_id, p.number AS number
        FROM department_phones dp
        JOIN phones p ON p.id = dp.phone_id
        UNION
        SELECT p.department_id AS department_id, p.number AS number
        FROM phones p
        WHERE p.department_id IS NOT NULL
      ) src
      ORDER BY src.department_id, src.number
    ''');
    final out = <int, List<String>>{};
    for (final row in rows) {
      final did = row['department_id'] as int?;
      final num = row['number'] as String?;
      if (did == null || num == null) continue;
      out.putIfAbsent(did, () => []).add(num);
    }
    return out;
  }

  Future<bool> phoneNumberExists(String phoneNumber) async {
    final t = phoneNumber.trim();
    if (t.isEmpty) return false;
    final db = await database;
    final rows = await db.query(
      'phones',
      columns: ['id'],
      where: 'number = ?',
      whereArgs: [t],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> equipmentCodeExists(String equipmentCode) async {
    final t = equipmentCode.trim();
    if (t.isEmpty) return false;
    final db = await database;
    final rows = await db.query(
      'equipment',
      columns: ['id'],
      where: 'code_equipment = ? AND COALESCE(is_deleted, 0) = 0',
      whereArgs: [t],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Θέτει/ενημερώνει το `phones.department_id` χωρίς να αγγίζει `user_phones`.
  Future<void> updatePhoneDepartment(
    String phoneNumber,
    int departmentId,
  ) async {
    final t = phoneNumber.trim();
    if (t.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      await _ensurePhonesDepartmentColumn(txn);
      await txn.insert('phones', {
        'number': t,
        'department_id': departmentId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final rows = await txn.query(
        'phones',
        columns: ['id'],
        where: 'number = ?',
        whereArgs: [t],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final pid = rows.first['id'] as int;
      await txn.update(
        'phones',
        {'department_id': departmentId},
        where: 'id = ?',
        whereArgs: [pid],
      );
      await txn.delete(
        'department_phones',
        where: 'phone_id = ?',
        whereArgs: [pid],
      );
      await txn.insert('department_phones', {
        'department_id': departmentId,
        'phone_id': pid,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  /// Θέτει/ενημερώνει το `equipment.department_id` χωρίς να αγγίζει `user_equipment`.
  Future<void> updateEquipmentDepartment(
    String equipmentCode,
    int departmentId,
  ) async {
    final code = equipmentCode.trim();
    if (code.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'equipment',
        columns: ['id'],
        where: 'code_equipment = ? AND COALESCE(is_deleted, 0) = 0',
        whereArgs: [code],
        limit: 1,
      );
      if (rows.isEmpty) {
        await txn.insert('equipment', {
          'code_equipment': code,
          'department_id': departmentId,
          'is_deleted': 0,
        });
        return;
      }
      final id = rows.first['id'] as int;
      await txn.update(
        'equipment',
        {'department_id': departmentId},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Αφαιρεί το τηλέφωνο από όλους τους κατόχους (`user_phones`) με βάση τον αριθμό.
  Future<void> removePhoneFromAllUsers(String phoneNumber) async {
    final t = phoneNumber.trim();
    if (t.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'phones',
        columns: ['id'],
        where: 'number = ?',
        whereArgs: [t],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final pid = rows.first['id'] as int?;
      if (pid == null) return;
      await txn.delete('user_phones', where: 'phone_id = ?', whereArgs: [pid]);
    });
  }

  /// Αφαιρεί τον εξοπλισμό από όλους τους κατόχους (`user_equipment`) με βάση τον κωδικό.
  Future<void> removeEquipmentFromAllUsers(String equipmentCode) async {
    final code = equipmentCode.trim();
    if (code.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'equipment',
        columns: ['id'],
        where: 'code_equipment = ? AND COALESCE(is_deleted, 0) = 0',
        whereArgs: [code],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final eid = rows.first['id'] as int?;
      if (eid == null) return;
      await txn.delete(
        'user_equipment',
        where: 'equipment_id = ?',
        whereArgs: [eid],
      );
    });
  }

  /// Αντικαθιστά πλήρως τα τηλέφωνα του χρήστη [userId] (κανονικοποιημένα).
  Future<void> replaceUserPhones(int userId, List<String> numbers) async {
    final db = await database;
    await db.transaction(
      (txn) => _replaceUserPhonesInTxn(txn, userId, numbers),
    );
  }

  /// Ενεργοί χρήστες (`is_deleted = 0`) με λίστα `phones` ανά χρήστη (για [UserModel.fromMap]).
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final db = await database;
    final users = await db.query(
      'users',
      where: 'COALESCE(is_deleted, 0) = ?',
      whereArgs: [0],
    );
    final links = await db.rawQuery('''
      SELECT up.user_id AS user_id, p.number AS number
      FROM user_phones up
      JOIN phones p ON p.id = up.phone_id
      ORDER BY p.number
    ''');
    final byUser = <int, List<String>>{};
    for (final row in links) {
      final uid = row['user_id'] as int?;
      final num = row['number'] as String?;
      if (uid == null || num == null) continue;
      byUser.putIfAbsent(uid, () => []).add(num);
    }
    return users.map((m) {
      final copy = Map<String, dynamic>.from(m);
      final id = m['id'] as int?;
      copy['phones'] = id != null
          ? List<String>.from(byUser[id] ?? const [])
          : <String>[];
      return copy;
    }).toList();
  }

  /// Εισάγει χρήστη από map (π.χ. [UserModel.toMap]). Αφαιρεί [id], `phones`, `phone` πριν insert στο `users`.
  Future<int> insertUserFromMap(Map<String, dynamic> row) async {
    final map = Map<String, dynamic>.from(row);
    map.remove('id');
    final phonesRaw = map.remove('phones');
    map.remove('phone');
    List<String> phones = const [];
    if (phonesRaw is List) {
      phones = phonesRaw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    final db = await database;
    final id = await db.insert('users', map);
    if (phones.isNotEmpty) {
      await replaceUserPhones(id, phones);
    }
    return id;
  }

  /// Ενημερώνει χρήστη. Αφαιρεί [id]· αν υπάρχει `phones` στη map, ενημερώνει `user_phones`.
  Future<int> updateUser(int id, Map<String, dynamic> values) async {
    final map = Map<String, dynamic>.from(values);
    map.remove('id');
    final phonesRaw = map.remove('phones');
    map.remove('phone');
    final db = await database;
    var n = 0;
    if (map.isNotEmpty) {
      n = await db.update('users', map, where: 'id = ?', whereArgs: [id]);
    }
    if (phonesRaw != null) {
      final phones = phonesRaw is List
          ? phonesRaw
                .map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList()
          : <String>[];
      await replaceUserPhones(id, phones);
    }
    return n;
  }

  /// Μαζική ενημέρωση: εφαρμόζει τα ίδια [changes] σε όλα τα [ids]. Transaction.
  /// Το κλειδί `phone` (string) ερμηνεύεται ως λίστα μέσω [PhoneListParser.splitPhones] και γράφεται στο M2M.
  Future<void> bulkUpdateUsers(
    List<int> ids,
    Map<String, dynamic> changes,
  ) async {
    if (ids.isEmpty || changes.isEmpty) return;
    final map = Map<String, dynamic>.from(changes);
    map.remove('id');
    final phoneBulk = map.remove('phone') as String?;
    if (map.isEmpty && phoneBulk == null) return;
    final db = await database;
    await db.transaction((txn) async {
      if (map.isNotEmpty) {
        for (final id in ids) {
          await txn.update('users', map, where: 'id = ?', whereArgs: [id]);
        }
      }
      if (phoneBulk != null) {
        final list = PhoneListParser.splitPhones(phoneBulk);
        for (final id in ids) {
          await _replaceUserPhonesInTxn(txn, id, list);
        }
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
        await _appendAuditLog(txn, user, auditActionDelete, 'users id=$id');
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
        await _appendAuditLog(txn, user, auditActionRestore, 'users id=$id');
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

  /// Προσθήκη λέξης στο προσωπικό λεξικό ορθογραφίας ([DictionaryService.canonicalLexiconKey]).
  Future<void> insertUserWord(String word) async {
    final key = DictionaryService.canonicalLexiconKey(word);
    if (key.length < 2) return;
    final db = await database;
    await db.insert(AppConfig.userDictionaryTable, {
      'word': key,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> addUserWord(String word) => insertUserWord(word);

  /// Όλες οι προσωπικές λέξεις (κανονικοποιημένα κλειδιά), ταξινομημένες.
  Future<List<String>> getUserWords() async {
    final db = await database;
    final rows = await db.query(
      AppConfig.userDictionaryTable,
      columns: ['word'],
      orderBy: 'word COLLATE NOCASE',
    );
    return rows
        .map((r) => (r['word'] as String?)?.trim() ?? '')
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// True αν υπάρχει ενεργό τμήμα με ίδιο κανονικοποιημένο όνομα
  /// ([SearchTextNormalizer] — όπως στην οθόνη κλήσεων / [LookupService]).
  Future<bool> departmentNameExists(String? name) async {
    final trimmed = stripDepartmentDeletedDisplaySuffix(name);
    if (trimmed.isEmpty) return false;
    final key = SearchTextNormalizer.normalizeForSearch(trimmed);
    if (key.isEmpty) return false;
    final db = await database;
    final rows = await db.query(
      'departments',
      columns: ['id'],
      where: 'COALESCE(is_deleted, 0) = 0 AND name_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Επιστρέφει department_id για το [name].
  /// Αν δεν υπάρχει, δημιουργεί νέο τμήμα (display `name` + normalized `name_key`) και επιστρέφει id.
  Future<int?> getOrCreateDepartmentIdByName(String? name) async {
    final displayName = stripDepartmentDeletedDisplaySuffix(name).trim();
    if (displayName.isEmpty) return null;
    final key = SearchTextNormalizer.normalizeForSearch(displayName);
    if (key.isEmpty) return null;
    final db = await database;
    return db.transaction<int?>((txn) async {
      Future<int?> findId() async {
        final rows = await txn.query(
          'departments',
          columns: ['id'],
          where: 'COALESCE(is_deleted, 0) = 0 AND name_key = ?',
          whereArgs: [key],
          limit: 1,
        );
        if (rows.isEmpty) return null;
        return rows.first['id'] as int?;
      }

      final existingId = await findId();
      if (existingId != null) return existingId;

      await txn.insert('departments', {
        'name': displayName,
        'name_key': key,
        'is_deleted': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      return findId();
    });
  }

  /// Όλα τα τμήματα (ενεργά και soft-deleted), ταξινόμηση κατά όνομα.
  Future<List<Map<String, dynamic>>> getDepartments() async {
    final db = await database;
    return db.query('departments', orderBy: 'name COLLATE NOCASE ASC');
  }

  /// Εισαγωγή τμήματος. Αφαιρεί [id] πριν το insert.
  /// Σε αποτυχία UNIQUE: ρίχνει [DepartmentExistsException] (όχι μηνύματα UI).
  Future<int> insertDepartment(Map<String, dynamic> row) async {
    final map = Map<String, dynamic>.from(row);
    map.remove('id');
    map['is_deleted'] = map['is_deleted'] ?? 0;
    final name = (map['name'] as String?)?.trim() ?? '';
    final key = SearchTextNormalizer.normalizeForSearch(name);
    if (key.isNotEmpty) {
      map['name_key'] = map['name_key'] ?? key;
    }
    final db = await database;
    try {
      return await db.insert('departments', map);
    } catch (e) {
      if (_isSqliteUniqueConstraintFailure(e)) {
        final existing = await _findDepartmentRowByKey(
          (map['name_key'] as String?)?.trim() ?? key,
        );
        if (existing != null) {
          final deleted = (existing['is_deleted'] as int?) == 1;
          throw DepartmentExistsException(isDeleted: deleted);
        }
        throw DepartmentExistsException(isDeleted: false);
      }
      rethrow;
    }
  }

  static bool _isSqliteUniqueConstraintFailure(Object e) {
    final s = e.toString().toUpperCase();
    return s.contains('UNIQUE') && s.contains('CONSTRAINT');
  }

  /// Γραμμή τμήματος με ακριβές ταίριασμα στη στήλη `name_key`.
  Future<Map<String, dynamic>?> _findDepartmentRowByKey(String key) async {
    final k = key.trim();
    if (k.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'departments',
      where: 'name_key = ?',
      whereArgs: [k],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Επαναφορά soft-deleted τμήματος με ακριβές [name] + προαιρετική ενημέρωση πεδίων από τη φόρμα.
  Future<void> restoreDepartmentByName(
    String name, {
    String? building,
    String? color,
    String? notes,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('Κενό όνομα τμήματος.');
    }
    final key = SearchTextNormalizer.normalizeForSearch(trimmed);
    final row = await _findDepartmentRowByKey(key);
    if (row == null) {
      throw StateError('Δεν βρέθηκε τμήμα με αυτό το όνομα.');
    }
    final id = row['id'] as int?;
    if (id == null) {
      throw StateError('Μη έγκυρο id τμήματος.');
    }
    if ((row['is_deleted'] as int?) != 1) {
      throw StateError('Το τμήμα δεν είναι διαγραμμένο.');
    }
    await restoreDepartments([id]);
    final updates = <String, dynamic>{};
    // Ενημέρωση εμφανίσιμου ονόματος κατά την επαναφορά.
    updates['name'] = trimmed;
    updates['name_key'] = key;
    if (building != null) {
      updates['building'] = building.trim().isEmpty ? null : building.trim();
    }
    if (color != null) {
      updates['color'] = color.trim().isEmpty ? null : color.trim();
    }
    if (notes != null) {
      updates['notes'] = notes.trim().isEmpty ? null : notes.trim();
    }
    if (updates.isNotEmpty) {
      await updateDepartment(id, updates);
    }
  }

  /// Ενημέρωση τμήματος. Αφαιρεί [id] από τις τιμές.
  Future<int> updateDepartment(int id, Map<String, dynamic> values) async {
    final map = Map<String, dynamic>.from(values);
    map.remove('id');
    if (map.isEmpty) return 0;
    final db = await database;
    return db.update('departments', map, where: 'id = ?', whereArgs: [id]);
  }

  /// Μαζική ενημέρωση τμημάτων: ίδια [changes] για όλα τα [ids].
  Future<void> bulkUpdateDepartments(
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
        await txn.update('departments', map, where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  /// Soft delete ενός τμήματος (`is_deleted = 1`) + audit.
  Future<void> softDeleteDepartment(int id) async {
    await softDeleteDepartments([id]);
  }

  /// Soft delete πολλαπλών τμημάτων + audit ανά id.
  Future<void> softDeleteDepartments(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final user = await _auditPerformingUser(db);
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'departments',
          {'is_deleted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await _appendAuditLog(
          txn,
          user,
          auditActionDelete,
          'departments id=$id',
        );
      }
    });
  }

  /// Επαναφορά τμημάτων μετά από soft delete + audit.
  Future<void> restoreDepartments(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final user = await _auditPerformingUser(db);
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'departments',
          {'is_deleted': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
        await _appendAuditLog(
          txn,
          user,
          auditActionRestore,
          'departments id=$id',
        );
      }
    });
  }

  /// True αν υπάρχει **άλλο** ενεργό τμήμα με ίδιο κανονικοποιημένο όνομα
  /// (εξαιρείται το [excludeId] για φόρμα επεξεργασίας).
  Future<bool> departmentNameExistsExcluding(
    String? name,
    int excludeId,
  ) async {
    final trimmed = stripDepartmentDeletedDisplaySuffix(name);
    if (trimmed.isEmpty) return false;
    final key = SearchTextNormalizer.normalizeForSearch(trimmed);
    if (key.isEmpty) return false;
    final db = await database;
    final rows = await db.query(
      'departments',
      columns: ['id'],
      where: 'COALESCE(is_deleted, 0) = 0 AND id != ? AND name_key = ?',
      whereArgs: [excludeId, key],
      limit: 1,
    );
    return rows.isNotEmpty;
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

  /// Όλες οι εγγραφές συσχέτισης χρήστη–εξοπλισμού (πίνακας `user_equipment`).
  Future<List<Map<String, dynamic>>> getAllUserEquipmentLinks() async {
    final db = await database;
    return db.query('user_equipment');
  }

  /// Πλήθος χρηστών συνδεδεμένων με τον εξοπλισμό [equipmentId] (M2M).
  Future<int> countUsersLinkedToEquipment(int equipmentId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM user_equipment WHERE equipment_id = ?',
      [equipmentId],
    );
    if (rows.isEmpty) return 0;
    final raw = rows.first['c'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw') ?? 0;
  }

  /// Αφαιρεί μόνο τη συσχέτιση χρήστη–εξοπλισμού (χωρίς soft delete εγγραφής equipment).
  Future<void> unlinkUserFromEquipment(int userId, int equipmentId) async {
    final db = await database;
    await db.delete(
      'user_equipment',
      where: 'user_id = ? AND equipment_id = ?',
      whereArgs: [userId, equipmentId],
    );
  }

  /// Επαναφορά συσχέτισης (π.χ. μετά από αναίρεση αφαίρεσης μόνο από χρήστη).
  Future<void> linkUserToEquipment(int userId, int equipmentId) async {
    final db = await database;
    await db.insert(
      'user_equipment',
      {'user_id': userId, 'equipment_id': equipmentId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Όνομα τμήματος για εμφάνιση (μη διαγραμμένα).
  Future<String?> getDepartmentNameById(int departmentId) async {
    final db = await database;
    final rows = await db.query(
      'departments',
      columns: ['name'],
      where: 'id = ? AND COALESCE(is_deleted, 0) = 0',
      whereArgs: [departmentId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['name'] as String?;
  }

  /// Αντιγράφει συνδέσεις `user_equipment` από [fromUserId] στον [toUserId]
  /// (ίδια `equipment_id`, χωρίς αφαίρεση από την πηγή).
  Future<void> copyUserEquipmentLinks(int fromUserId, int toUserId) async {
    if (fromUserId == toUserId) return;
    final db = await database;
    final rows = await db.query(
      'user_equipment',
      columns: ['equipment_id'],
      where: 'user_id = ?',
      whereArgs: [fromUserId],
    );
    if (rows.isEmpty) return;
    await db.transaction((txn) async {
      for (final r in rows) {
        final eid = r['equipment_id'] as int?;
        if (eid == null) continue;
        await txn.insert('user_equipment', {
          'user_id': toUserId,
          'equipment_id': eid,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  /// Αντικαθιστά πλήρως τους χρήστες που συνδέονται με τον εξοπλισμό [equipmentId].
  Future<void> replaceEquipmentUsers(int equipmentId, List<int> userIds) async {
    final db = await database;
    final unique = userIds.toSet().toList();
    await db.transaction((txn) async {
      await txn.delete(
        'user_equipment',
        where: 'equipment_id = ?',
        whereArgs: [equipmentId],
      );
      for (final uid in unique) {
        await txn.insert('user_equipment', {
          'user_id': uid,
          'equipment_id': equipmentId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
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
        await _appendAuditLog(txn, user, auditActionDelete, 'equipment id=$id');
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
  /// 2. Insert equipment + γραμμή στο `user_equipment` όταν υπάρχει κάτοχος
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

    final deptNameToId = <String, int?>{};
    for (final u in ownersList) {
      final dn = (u['department'] as String?)?.trim() ?? '';
      if (dn.isNotEmpty) {
        deptNameToId.putIfAbsent(dn, () => null);
      }
    }
    for (final name in deptNameToId.keys.toList()) {
      deptNameToId[name] = await getOrCreateDepartmentIdByName(name);
    }

    await db.transaction((txn) async {
      final ownerCodeToDbId = <int, int>{};
      for (final u in ownersList) {
        final ownerId = u['ownerId'] as int? ?? 0;
        final fullName = u['fullName'] as String? ?? '';
        final parsed = NameParserUtility.parse(fullName);
        final dn = (u['department'] as String?)?.trim() ?? '';
        final did = dn.isEmpty ? null : deptNameToId[dn];
        final id = await txn.insert('users', {
          'last_name': parsed.lastName,
          'first_name': parsed.firstName,
          'location': null,
          'notes': null,
          'is_deleted': 0,
          'department_id': did,
        });
        final importPhones = PhoneListParser.splitPhones(
          u['phones'] as String?,
        );
        if (importPhones.isNotEmpty) {
          await _replaceUserPhonesInTxn(txn, id, importPhones);
        }
        ownerCodeToDbId[ownerId] = id;
      }
      usersInserted = ownerCodeToDbId.length;

      for (final e in equipmentList) {
        final ownerCodeTemp = e['ownerCodeTemp'] as int? ?? 0;
        final userId = ownerCodeToDbId[ownerCodeTemp];
        final eqId = await txn.insert('equipment', {
          'code_equipment': e['code'] as String?,
          'is_deleted': 0,
        });
        if (userId != null) {
          await txn.insert('user_equipment', {
            'user_id': userId,
            'equipment_id': eqId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        equipmentInserted++;
      }
    });

    return (usersInserted: usersInserted, equipmentInserted: equipmentInserted);
  }

  /// Εισάγει νέο χρήστη. Το Data Layer δέχεται ήδη διαχωρισμένα firstName/lastName (parsing γίνεται στο Domain/UI).
  /// [departmentId] αντιστοιχεί στον πίνακα departments (schema με department_id).
  /// [phones]: αποθηκεύονται στο M2M `phones` / `user_phones`.
  Future<int> insertUser({
    required String firstName,
    required String lastName,
    List<String>? phones,
    String? department,
    String? location,
    String? notes,
    int? departmentId,
  }) async {
    final db = await database;
    var resolvedDeptId = departmentId;
    if (resolvedDeptId == null &&
        department != null &&
        department.trim().isNotEmpty) {
      resolvedDeptId = await getOrCreateDepartmentIdByName(department);
    }
    final map = <String, dynamic>{
      'last_name': lastName,
      'first_name': firstName,
      'location': location,
      'notes': notes,
      'is_deleted': 0,
    };
    if (resolvedDeptId != null) {
      map['department_id'] = resolvedDeptId;
    }
    final id = await db.insert('users', map);
    final list = phones ?? const <String>[];
    if (list.isNotEmpty) {
      await replaceUserPhones(id, list);
    }
    return id;
  }

  /// Ενημερώνει συσχετίσεις χρήστη: τηλέφωνο (M2M `phones`/`user_phones`) και/ή `user_equipment`.
  Future<void> updateAssociationsIfNeeded(
    int? userId,
    String? phone,
    String? equipmentCode,
  ) async {
    if (userId == null) return;
    final db = await database;
    await db.transaction((txn) async {
      if (phone != null && phone.trim().isNotEmpty) {
        final trimmed = phone.trim();
        final existingRows = await txn.rawQuery(
          '''
          SELECT p.number AS number FROM user_phones up
          JOIN phones p ON p.id = up.phone_id
          WHERE up.user_id = ?
          ''',
          [userId],
        );
        final existing = existingRows
            .map((r) => r['number'] as String?)
            .whereType<String>()
            .toList();
        if (!existing.contains(trimmed)) {
          await _replaceUserPhonesInTxn(txn, userId, [...existing, trimmed]);
        }
      }
      if (equipmentCode != null && equipmentCode.isNotEmpty) {
        final code = equipmentCode.trim();
        if (code.isNotEmpty) {
          final existing = await txn.query(
            'equipment',
            columns: ['id'],
            where: 'code_equipment = ? AND COALESCE(is_deleted, 0) = 0',
            whereArgs: [code],
            limit: 1,
          );
          final int equipmentId;
          if (existing.isEmpty) {
            equipmentId = await txn.insert('equipment', {
              'code_equipment': code,
              'is_deleted': 0,
            });
          } else {
            equipmentId = existing.first['id'] as int;
          }
          await txn.insert('user_equipment', {
            'user_id': userId,
            'equipment_id': equipmentId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
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

  /// Επιστρέφει συμβολοσειρά σχήματος πίνακα: `όνομα ΤΥΠΟΣ, ...` (από PRAGMA table_info).
  Future<String> getTableSchema(String tableName) async {
    final db = await database;
    final quoted = _sqliteQuoteIdentifier(tableName);
    final info = await db.rawQuery('PRAGMA table_info($quoted)');
    if (info.isEmpty) return '';
    final parts = <String>[];
    for (final row in info) {
      final colName = row['name'] as String? ?? '';
      final rawType = (row['type'] as String?)?.trim();
      final typeSuffix = (rawType == null || rawType.isEmpty)
          ? ''
          : ' $rawType';
      parts.add('$colName$typeSuffix');
    }
    return parts.join(', ');
  }

  static String _sqliteQuoteIdentifier(String identifier) {
    return '"${identifier.replaceAll('"', '""')}"';
  }

  /// Προεπισκόπηση πίνακα: στήλες + γραμμές (μέγ. [rowLimit]). Για προβολή τύπου Excel.
  Future<TablePreviewResult> getTablePreview(
    String tableName, {
    int rowLimit = 500,
  }) async {
    final db = await database;
    final quoted = _sqliteQuoteIdentifier(tableName);
    final info = await db.rawQuery('PRAGMA table_info($quoted)');
    final columns = (info
        .map((e) => e['name'] as String?)
        .whereType<String>()
        .toList());
    if (columns.isEmpty) return TablePreviewResult(columns: [], rows: []);

    final rows = await db.rawQuery('SELECT * FROM $quoted LIMIT $rowLimit');
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
    } catch (e, st) {
      return DatabaseInitResult.fromException(e, null, st);
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
      await _appendAuditLog(txn, user, auditActionDelete, 'tasks id=$id');
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
    const userPhoneExpr =
        "COALESCE(NULLIF(TRIM(calls.phone_text), ''), upl.phone_list, '-')";
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
             $userPhoneExpr AS user_phone,
             COALESCE(departments.name, calls.department_text, '-') AS user_department,
             COALESCE(equipment.code_equipment, calls.equipment_text, '-') AS equipment_code
      FROM calls
      LEFT JOIN users ON calls.caller_id = users.id
      LEFT JOIN (
        SELECT up.user_id AS uid,
               GROUP_CONCAT(p.number, ', ') AS phone_list
        FROM user_phones up
        JOIN phones p ON p.id = up.phone_id
        GROUP BY up.user_id
      ) upl ON upl.uid = users.id
      LEFT JOIN equipment ON calls.equipment_id = equipment.id
      LEFT JOIN departments ON users.department_id = departments.id
      $whereSql
      ORDER BY calls.date DESC, calls.time DESC
    ''';

    return db.rawQuery(sql, args);
  }

  /// Επαληθεύει αν η διαδρομή είναι προσβάσιμη (ίδιο UNC fallback με το [_initDatabase]).
  Future<ConnectionCheckResult> checkConnection() async {
    String dbPath = AppConfig.defaultDbPath;
    try {
      final configured = await SettingsService().getDatabasePath();
      final resolved = await resolveEffectiveDatabasePath(configured);
      dbPath = resolved.path;
      if (!await File(dbPath).exists()) {
        return const ConnectionCheckResult(success: false, isLocalDev: false);
      }

      final db = await openDatabase(
        dbPath,
        version: _kDatabaseSchemaVersion,
        readOnly: true,
        singleInstance: false,
      );
      await db.rawQuery('PRAGMA quick_check;');
      await db.close();
      return ConnectionCheckResult(
        success: true,
        isLocalDev: resolved.usedUncFallback,
      );
    } catch (e, st) {
      debugPrint(
        '[DatabaseHelper] Δεν είναι δυνατή η σύνδεση με τη βάση: $dbPath',
      );
      debugPrint('[DatabaseHelper] Σφάλμα: $e');
      debugPrint('[DatabaseHelper] $st');
      return const ConnectionCheckResult(success: false, isLocalDev: false);
    }
  }
}
