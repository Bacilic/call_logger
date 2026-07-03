import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/app_config.dart';
import '../services/settings_service.dart';
import '../utils/search_text_normalizer.dart';
import 'database_access_probe.dart';
import 'database_init_result.dart';
import 'database_init_progress_provider.dart';
import 'database_lexicon_open_normalizations.dart';
import 'database_lock_recovery.dart';
import 'database_schema_migrations.dart';
import 'lock_diagnostic_service.dart';
import 'database_path_resolution.dart';

part 'database_table_inspection.dart';

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
class DatabaseHelper with DatabaseTableInspectionMixin {
  DatabaseHelper._();

  /// Κλειδί `app_settings` για το όνομα χρήστη στις εγγραφές audit (προαιρετικό).
  static const String auditUserPerformingSettingsKey = 'audit_user_performing';

  static const String auditActionDelete = 'ΔΙΑΓΡΑΦΗ';
  static const String auditActionRestore = 'ΕΠΑΝΑΦΟΡΑ';
  static const String auditActionBulkDelete = 'ΜΑΖΙΚΗ ΔΙΑΓΡΑΦΗ';

  /// Επιδιόρθωση ευρημάτων ακεραιότητας (Integrity Fixer Engine).
  static const String auditActionIntegrityFix = 'ΕΠΙΔΙΟΡΘΩΣΗ ΑΚΕΡΑΙΟΤΗΤΑΣ';

  /// Αποτυχίες ανοίγματος προς προσομοίωση (δοκιμές retry χωρίς πραγματικό lock).
  @visibleForTesting
  static int testSimulatedRetriableOpenFailures = 0;

  @visibleForTesting
  static void resetTestOpenSimulation() {
    testSimulatedRetriableOpenFailures = 0;
  }

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
  /// Περιμένει τυχόν εκκρεμές άνοιγμα, checkpoint (best-effort) και κλείσιμο sqflite.
  Future<void> closeConnection() async {
    requestOpeningAbort();

    final opening = _databaseInitializingFuture;
    if (opening != null) {
      try {
        await opening;
      } catch (_) {
        // Ακυρώθηκε ή απέτυχε — συνεχίζουμε προς κλείσιμο ό,τι υπάρχει.
      }
    }

    final db = _database;
    if (db != null && db.isOpen) {
      try {
        final mode = _isUsingLocalDb ? 'FULL' : 'PASSIVE';
        await db
            .rawQuery('PRAGMA wal_checkpoint($mode)')
            .timeout(
              Duration(seconds: databaseWalCheckpointTimeoutSeconds),
              onTimeout: () => throw TimeoutException(
                'wal_checkpoint($mode) timed out after '
                '${databaseWalCheckpointTimeoutSeconds}s',
              ),
            );
      } catch (_) {}
      await db.close();
    }
    _database = null;
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
    final normalized = mode.trim().toUpperCase();
    final effective = normalized.isEmpty ? 'PASSIVE' : normalized;
    final db = _database;
    if (db == null || !db.isOpen) return;
    try {
      await db
          .rawQuery('PRAGMA wal_checkpoint($effective)')
          .timeout(
            Duration(seconds: databaseWalCheckpointTimeoutSeconds),
            onTimeout: () => throw TimeoutException(
              'wal_checkpoint($effective) timed out after '
              '${databaseWalCheckpointTimeoutSeconds}s',
            ),
          );
    } catch (_) {}
  }

  Future<String> forceReleaseLock(
    String dbPath, {
    DatabaseInitProgressNotifier? progressNotifier,
  }) {
    return _forceReleaseLockCore(
      dbPath,
      progressNotifier: progressNotifier,
      allowCloseConnection: true,
    );
  }

  Future<String> _forceReleaseLockCore(
    String dbPath, {
    DatabaseInitProgressNotifier? progressNotifier,
    required bool allowCloseConnection,
  }) async {
    final buffer = StringBuffer();
    progressNotifier?.setStep('Απελευθέρωση lock');
    if (allowCloseConnection) {
      try {
        await tryWalCheckpoint(mode: 'FULL');
        await closeConnection();
      } catch (e) {
        buffer.writeln('Checkpoint/close warning: $e');
      }
    }

    final mergedOnDisk = await tryEphemeralWalCheckpoint(dbPath);
    if (!mergedOnDisk) {
      buffer.writeln(
        'Παραλείφθηκε διαγραφή WAL sidecars: αποτυχία checkpoint στο δίσκο.',
      );
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
      if (!mergedOnDisk && sidecarPath.endsWith('-wal')) {
        continue;
      }
      final outcome = await tryDeleteStaleSidecarIfSafe(sidecarPath);
      if (outcome.message != null) {
        buffer.writeln(outcome.message);
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
    final diagnostic = await _forceReleaseLockCore(
      dbPath,
      progressNotifier: progressNotifier,
      allowCloseConnection: false,
    );
    progressNotifier?.setDiagnostic(diagnostic);
    return diagnostic;
  }

  /// Αρχικοποίηση βάσης: επίλυση διαδρομής (UNC fallback), ύπαρξη αρχείου, WAL, σχήμα (fail-fast).
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
    final staleCleanupDiagnostic = await cleanStaleSidecarsIfSafe(
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
          final abortDiagnostic = await _forceReleaseLockCore(
            dbPath,
            progressNotifier: progressNotifier,
            allowCloseConnection: false,
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
      if (testSimulatedRetriableOpenFailures > 0) {
        testSimulatedRetriableOpenFailures--;
        throw TimeoutException(
          'simulated retriable open failure (attempt $attempt/$maxAttempts)',
        );
      }
      final openFuture = openDatabase(
        targetPath,
        version: kDatabaseSchemaVersion,
        onCreate: onDatabaseCreate,
        onUpgrade: onDatabaseUpgradeSquashed,
        onDowngrade: onDatabaseDowngradeSquashed,
        singleInstance: singleInstance,
        onOpen: applyLexiconOpenNormalizations,
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
    return validateDatabaseSchema(db, dbPath);
  }

  /// Δημιουργεί νέο αρχείο βάσης στο [filePath] με το τρέχον σχήμα.
  Future<void> createNewDatabaseFile(String filePath) async {
    final db = await openDatabase(
      filePath,
      version: kDatabaseSchemaVersion,
      onCreate: onDatabaseCreate,
      onUpgrade: onDatabaseUpgradeSquashed,
      onDowngrade: onDatabaseDowngradeSquashed,
      singleInstance: false,
      onOpen: applyLexiconOpenNormalizations,
    );
    await db.execute('PRAGMA journal_mode = WAL;');
    await db.close();
  }

  /// Ελέγχει υγεία βάσης: ύπαρξη πίνακα 'calls' (και βασικών πινάκων).
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
        version: kDatabaseSchemaVersion,
        readOnly: true,
        singleInstance: false,
      );
      await db.rawQuery('PRAGMA quick_check;');
      await db.close();
      return ConnectionCheckResult(
        success: true,
        isLocalDev: resolved.usedUncFallback,
      );
    } catch (_, _) {
      return const ConnectionCheckResult(success: false, isLocalDev: false);
    }
  }
}

/// Μήνυμα SnackBar όταν επαναφέρεται διαγραμμένη κατηγορία αντί νέας εγγραφής.
const String kCategoryRestoredFromDeletedUserMessage =
    'Η κατηγορία επαναφέρθηκε (υπήρχε ήδη ως διαγραμμένη).';
