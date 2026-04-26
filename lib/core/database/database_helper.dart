import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/app_config.dart';
import '../services/settings_service.dart';
import '../utils/lexicon_word_metrics.dart';
import '../utils/search_text_normalizer.dart';
import 'database_access_probe.dart';
import 'database_init_result.dart';
import 'database_init_progress_provider.dart';
import 'lock_diagnostic_service.dart';
import 'database_path_resolution.dart';
import 'database_v1_schema.dart';
import 'dictionary_repository.dart';

class DatabaseOpeningAbortedException implements Exception {
  const DatabaseOpeningAbortedException([
    this.message =
        'Η προσπάθεια ανοίγματος της βάσης ακυρώθηκε από τον χρήστη.',
  ]);

  final String message;

  @override
  String toString() => message;
}

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
  Completer<Never>? _userAbortCompleter;
  bool _isUsingLocalDb = false;

  /// True αν η εφαρμογή χρησιμοποιεί την τοπική βάση (Dev Mode).
  bool get isUsingLocalDb => _isUsingLocalDb;

  /// True όταν εκτελείται προσπάθεια ανοίγματος βάσης.
  bool get isOpening => _databaseInitializingFuture != null;

  /// Ζητά άμεση διακοπή της τρέχουσας προσπάθειας ανοίγματος.
  void requestOpeningAbort() {
    final completer = _userAbortCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.completeError(const DatabaseOpeningAbortedException());
  }

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
      _userAbortCompleter = null;
    }
    return _database!;
  }

  /// Κλείνει την τρέχουσα σύνδεση και επαναφέρει την κατάσταση.
  /// Στην επόμενη κλήση [database] θα γίνει νέα σύνδεση (π.χ. με νέα διαδρομή από ρυθμίσεις).
  Future<void> closeConnection() async {
    requestOpeningAbort();
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    _databaseInitializingFuture = null;
    _userAbortCompleter = null;
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
      await validateSchema(db, dbPath);
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
    final maxAttempts = await _resolveDatabaseOpenMaxAttempts();
    String? lastDiagnostic;
    String? probeDiagnostic;
    Object? lastError;
    StackTrace? lastStack;

    _userAbortCompleter = Completer<Never>();

    progressNotifier?.setStep('Διαγνωστικός έλεγχος πρόσβασης');
    final probeReport = await const DatabaseAccessProbe().probe(dbPath);
    if (probeReport.hasFindings) {
      probeDiagnostic = probeReport.humanReadable;
      progressNotifier?.setDiagnostic(probeDiagnostic);
    }
    final fatalProbeResult = probeReport.fatalResult;
    if (fatalProbeResult != null) {
      var result = fatalProbeResult;
      if (probeDiagnostic != null && probeDiagnostic.trim().isNotEmpty) {
        result = result.copyWith(
          details: _mergeDetails(result.details, probeDiagnostic),
        );
      }
      throw DatabaseInitException(result);
    }
    final staleCleanupDiagnostic = await _cleanStaleSidecarsIfSafe(
      dbPath,
      progressNotifier: progressNotifier,
    );
    if (staleCleanupDiagnostic != null &&
        staleCleanupDiagnostic.trim().isNotEmpty) {
      probeDiagnostic = _mergeDetails(probeDiagnostic, staleCleanupDiagnostic);
      progressNotifier?.setDiagnostic(probeDiagnostic);
    }

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
          await validateSchema(db, dbPath);
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
        if (e is DatabaseOpeningAbortedException) {
          final abortDiagnostic = await forceReleaseLock(
            dbPath,
            progressNotifier: progressNotifier,
          );
          var result = DatabaseInitResult(
            status: DatabaseStatus.applicationError,
            message:
                'Η προσπάθεια ανοίγματος της βάσης ακυρώθηκε άμεσα από τον χρήστη.',
            details:
                'Η λειτουργία σταμάτησε πριν ολοκληρωθεί το timeout της τρέχουσας προσπάθειας.',
            path: dbPath,
            originalExceptionText: e.toString(),
            stackTraceText: st.toString(),
          );
          if (probeDiagnostic != null && probeDiagnostic.trim().isNotEmpty) {
            result = result.copyWith(
              details: _mergeDetails(result.details, probeDiagnostic),
            );
          }
          if (abortDiagnostic.trim().isNotEmpty) {
            result = result.copyWith(
              details: _mergeDetails(result.details, abortDiagnostic),
            );
          }
          throw DatabaseInitException(result);
        }
        final retriable = e is TimeoutException || _looksLikeLockError(e);
        if (!retriable || attempt >= maxAttempts) {
          var result = DatabaseInitResult.fromException(e, dbPath, st);
          if (probeDiagnostic != null && probeDiagnostic.trim().isNotEmpty) {
            result = result.copyWith(
              details: _mergeDetails(result.details, probeDiagnostic),
            );
          }
          if (lastDiagnostic != null && lastDiagnostic.trim().isNotEmpty) {
            result = result.copyWith(
              details: _mergeDetails(result.details, lastDiagnostic),
            );
          }
          throw DatabaseInitException(result);
        }
      }
    }

    var fallbackResult = DatabaseInitResult.fromException(
      lastError ?? TimeoutException('Unknown database open timeout'),
      dbPath,
      lastStack,
    );
    if (probeDiagnostic != null && probeDiagnostic.trim().isNotEmpty) {
      fallbackResult = fallbackResult.copyWith(
        details: _mergeDetails(fallbackResult.details, probeDiagnostic),
      );
    }
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

  Future<int> _resolveDatabaseOpenMaxAttempts() async {
    try {
      final value = await SettingsService().getDatabaseOpenMaxAttempts();
      if (value <= 0) return AppConfig.databaseOpenMaxAttempts;
      return value;
    } catch (_) {
      return AppConfig.databaseOpenMaxAttempts;
    }
  }

  Future<String?> _cleanStaleSidecarsIfSafe(
    String dbPath, {
    DatabaseInitProgressNotifier? progressNotifier,
  }) async {
    if (AppConfig.isUncDatabasePath(dbPath)) return null;
    progressNotifier?.setStep('Προληπτικός καθαρισμός WAL');
    final messages = <String>[];
    for (final suffix in const <String>['-wal', '-shm']) {
      final sidecarPath = '$dbPath$suffix';
      final file = File(sidecarPath);
      try {
        if (!await file.exists()) continue;
        final stat = await file.stat();
        if (stat.size <= 0) continue;

        RandomAccessFile? raf;
        try {
          raf = await file.open(mode: FileMode.append);
          await raf.close();
          raf = null;
        } catch (_) {
          await raf?.close();
          messages.add(
            'Παραλείφθηκε διαγραφή $sidecarPath: το αρχείο φαίνεται ενεργά κλειδωμένο.',
          );
          continue;
        }

        await file.delete();
        messages.add('Διαγράφηκε stale sidecar: $sidecarPath');
      } catch (e) {
        messages.add('Αποτυχία καθαρισμού $sidecarPath: $e');
      }
    }
    if (messages.isEmpty) return null;
    return messages.join('\n');
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
      'Προσπάθεια άνοιγμα βάσης σε $remaining δευτερόλεπτα',
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
          'Προσπάθεια άνοιγμα βάσης σε $remaining δευτερόλεπτα',
          secondsRemaining: remaining,
        );
      });
    }

    try {
      final openFuture = openDatabase(
        targetPath,
        version: _kDatabaseSchemaVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgradeSquashed,
        onDowngrade: _onDowngradeSquashed,
        singleInstance: singleInstance,
        onOpen: (db) => _applyLexiconOpenNormalizations(db),
      );
      final timeoutFuture = openFuture.timeout(
        Duration(seconds: safeTimeout),
        onTimeout: () {
          throw TimeoutException(
            'openDatabase timed out after ${safeTimeout}s '
            '(attempt $attempt/$maxAttempts)',
          );
        },
      );
      final abortFuture = (_userAbortCompleter ??= Completer<Never>()).future;
      return await Future.any<Database>(<Future<Database>>[
        timeoutFuture,
        abortFuture,
      ]);
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
    return '$c\n\n--- Diagnostics ---\n$d';
  }

  /// Επαληθεύει ότι υπάρχει ο πίνακας `calls`. Αλλιώς ρίχνει [DatabaseInitException].
  static Future<void> validateSchema(Database db, String dbPath) async {
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

  static Future<void> _applyLexiconOpenNormalizations(Database db) async {
    await _normalizeLexiconSourceOnOpen(db);
    await _normalizeLexiconCategoryLegacyOnOpen(db);
    await ensureDepartmentsMapRotationColumn(db);
    await ensureDepartmentsMapHiddenColumn(db);
  }

  /// Παλιά τιμή πηγής `system` (asset) → `imported` (ίδια κατηγορία με TXT).
  static Future<void> _normalizeLexiconSourceOnOpen(Database db) async {
    try {
      await db.rawUpdate(
        'UPDATE ${AppConfig.fullDictionaryTable} SET source = ? WHERE source = ?',
        ['imported', 'system'],
      );
    } catch (_) {
      // Πίνακας μπορεί να λείπει σε ασυνήθιστα σενάρια.
    }
  }

  /// Παλιές ετικέτες κατηγορίας `general` / `user` → `Γενική`.
  static Future<void> _normalizeLexiconCategoryLegacyOnOpen(Database db) async {
    try {
      await db.rawUpdate(
        'UPDATE ${AppConfig.fullDictionaryTable} SET category = ? WHERE category = ?',
        ['Γενική', 'general'],
      );
      await db.rawUpdate(
        'UPDATE ${AppConfig.fullDictionaryTable} SET category = ? WHERE category = ?',
        ['Γενική', 'user'],
      );
    } catch (_) {
      // Πίνακας μπορεί να λείπει σε ασυνήθιστα σενάρια.
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
      onOpen: (db) => _applyLexiconOpenNormalizations(db),
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
    if (oldVersion < 7 && newVersion >= 7) {
      await _migrateFullDictionaryTable(db);
    }
    if (oldVersion < 8 && newVersion >= 8) {
      await _migrateUserDictionaryLanguageColumn(db);
    }
    if (oldVersion < 9 && newVersion >= 9) {
      await _migrateLexiconWordMetricsColumns(db);
    }
    if (oldVersion < 10 && newVersion >= 10) {
      await _migrateEquipmentRemoteParamsColumn(db);
    }
    if (oldVersion < 11 && newVersion >= 11) {
      await migrateDatabaseToV11(db);
    }
    if (oldVersion < 12 && newVersion >= 12) {
      await migrateDatabaseToV12(db);
    }
    if (oldVersion < 13 && newVersion >= 13) {
      await migrateDatabaseToV13(db);
    }
    if (oldVersion < 14 && newVersion >= 14) {
      await migrateDatabaseToV14(db);
    }
    if (oldVersion < 15 && newVersion >= 15) {
      await migrateDatabaseToV15(db);
    }
    if (oldVersion < 16 && newVersion >= 16) {
      await migrateDatabaseToV16(db);
    }
    if (oldVersion < 17 && newVersion >= 17) {
      await migrateDatabaseToV17(db);
    }
    if (oldVersion < 18 && newVersion >= 18) {
      await migrateDatabaseToV18(db);
    }
    if (oldVersion < 19 && newVersion >= 19) {
      await migrateDatabaseToV19(db);
    }
    if (oldVersion < 20 && newVersion >= 20) {
      await migrateDatabaseToV20(db);
    }
    if (oldVersion < 21 && newVersion >= 21) {
      await migrateDatabaseToV21(db);
    }
    if (oldVersion < 22 && newVersion >= 22) {
      await migrateDatabaseToV22(db);
    }
    if (oldVersion < 23 && newVersion >= 23) {
      await migrateDatabaseToV23(db);
    }
    if (oldVersion < 24 && newVersion >= 24) {
      await migrateDatabaseToV24(db);
    }
    if (oldVersion < 25 && newVersion >= 25) {
      await migrateDatabaseToV25(db);
    }
    if (oldVersion < 26 && newVersion >= 26) {
      await migrateDatabaseToV26(db);
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

  /// v8: στήλη `language` + backfill με [detectDictionaryLanguage].
  static Future<void> _migrateUserDictionaryLanguageColumn(Database db) async {
    final info = await db.rawQuery(
      'PRAGMA table_info(${AppConfig.userDictionaryTable})',
    );
    final names = info.map((r) => r['name'] as String).toSet();
    if (!names.contains('language')) {
      await db.execute(
        'ALTER TABLE ${AppConfig.userDictionaryTable} ADD COLUMN language TEXT',
      );
    }
    final rows = await db.query(
      AppConfig.userDictionaryTable,
      columns: ['word', 'language'],
    );
    final batch = db.batch();
    var pending = 0;
    for (final r in rows) {
      final w = (r['word'] as String?)?.trim() ?? '';
      if (w.isEmpty) continue;
      final next = DictionaryRepository.detectDictionaryLanguage(w);
      final cur = r['language'] as String? ?? '';
      if (cur == next) continue;
      batch.update(
        AppConfig.userDictionaryTable,
        {'language': next},
        where: 'word = ?',
        whereArgs: [w],
      );
      pending++;
    }
    if (pending > 0) await batch.commit(noResult: true);
  }

  /// v9: `letters_count`, `diacritic_mark_count` + backfill + ευρετήρια.
  static Future<void> _migrateLexiconWordMetricsColumns(Database db) async {
    Future<void> ensureColumns(String table) async {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      final names = info.map((r) => r['name'] as String).toSet();
      if (!names.contains('letters_count')) {
        await db.execute(
          'ALTER TABLE $table ADD COLUMN letters_count INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (!names.contains('diacritic_mark_count')) {
        await db.execute(
          'ALTER TABLE $table ADD COLUMN diacritic_mark_count INTEGER NOT NULL DEFAULT 0',
        );
      }
    }

    await ensureColumns(AppConfig.fullDictionaryTable);
    await ensureColumns(AppConfig.userDictionaryTable);

    Future<void> backfillTable(String table, {required bool hasRowId}) async {
      final rows = await db.query(
        table,
        columns: hasRowId ? ['id', 'word'] : ['word'],
      );
      const chunk = 400;
      for (var i = 0; i < rows.length; i += chunk) {
        final end = (i + chunk > rows.length) ? rows.length : i + chunk;
        final slice = rows.sublist(i, end);
        final batch = db.batch();
        for (final r in slice) {
          final w = (r['word'] as String?) ?? '';
          final m = LexiconWordMetrics.compute(w);
          if (hasRowId) {
            final idRaw = r['id'];
            final id = idRaw is int ? idRaw : (idRaw as num).toInt();
            batch.update(
              table,
              {
                'letters_count': m.lettersCount,
                'diacritic_mark_count': m.diacriticMarkCount,
              },
              where: 'id = ?',
              whereArgs: [id],
            );
          } else {
            batch.update(
              table,
              {
                'letters_count': m.lettersCount,
                'diacritic_mark_count': m.diacriticMarkCount,
              },
              where: 'word = ?',
              whereArgs: [w],
            );
          }
        }
        await batch.commit(noResult: true);
      }
    }

    await backfillTable(AppConfig.fullDictionaryTable, hasRowId: true);
    await backfillTable(AppConfig.userDictionaryTable, hasRowId: false);

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_full_dictionary_letters_count ON ${AppConfig.fullDictionaryTable}(letters_count)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_full_dictionary_diacritic_mark_count ON ${AppConfig.fullDictionaryTable}(diacritic_mark_count)',
    );
  }

  /// Πίνακας master λεξικού (v7).
  static Future<void> _migrateFullDictionaryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS full_dictionary (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word TEXT NOT NULL UNIQUE,
        normalized_word TEXT NOT NULL,
        source TEXT NOT NULL,
        language TEXT NOT NULL,
        category TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_full_dictionary_norm ON full_dictionary(normalized_word)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_full_dictionary_filters ON full_dictionary(language, source, category)',
    );
  }

  /// v10: στήλη `equipment.remote_params` για JSON παραμέτρων ανά εργαλείο.
  static Future<void> _migrateEquipmentRemoteParamsColumn(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(equipment)');
    final names = info.map((r) => r['name'] as String).toSet();
    if (!names.contains('remote_params')) {
      await db.execute('ALTER TABLE equipment ADD COLUMN remote_params TEXT');
    }
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

  /// Κανονικοποίηση ονόματος κατηγορίας για σύγκριση διπλοτύπων (τόνοι/κεφαλαία).
  static String normalizeCategoryNameForLookup(String value) =>
      SearchTextNormalizer.normalizeForSearch(value);

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

/// Μήνυμα SnackBar όταν επαναφέρεται διαγραμμένη κατηγορία αντί νέας εγγραφής.
const String kCategoryRestoredFromDeletedUserMessage =
    'Η κατηγορία επαναφέρθηκε (υπήρχε ήδη ως διαγραμμένη).';
