import 'dart:io';

import '../services/settings_service.dart';
import 'database_helper.dart';
import 'remote_tools_repository.dart';
import 'directory_repository.dart';
import 'database_init_result.dart';
import 'database_init_progress_provider.dart';
import 'lock_diagnostic_service.dart';
import 'database_path_resolution.dart';

Future<String?> _appSettingsGet(String key) async {
  final db = await DatabaseHelper.instance.database;
  return DirectoryRepository(db).getSetting(key);
}

Future<void> _appSettingsSet(String key, String value) async {
  final db = await DatabaseHelper.instance.database;
  return DirectoryRepository(db).setSetting(key, value);
}

/// Αποτέλεσμα ελέγχου αρχικοποίησης (αποτέλεσμα + τρόπος λειτουργίας).
class DatabaseInitRunnerResult {
  const DatabaseInitRunnerResult({
    required this.result,
    required this.isLocalDevMode,
  });

  final DatabaseInitResult result;
  final bool isLocalDevMode;
}

/// Εκτελεί τους ελέγχους βάσης (ύπαρξη αρχείου, δικαιώματα, σύνδεση, υγεία).
/// Χρησιμοποιείται στην εκκίνηση και κατά την επιστροφή από Ρυθμίσεις.
/// Αν [closeConnectionFirst] είναι true, κλείνει την τρέχουσα σύνδεση ώστε να
/// χρησιμοποιηθεί η τρέχουσα διαδρομή από ρυθμίσεις (π.χ. μετά αλλαγή path).
Future<DatabaseInitRunnerResult> runDatabaseInitChecks({
  bool closeConnectionFirst = false,
  DatabaseInitProgressNotifier? progressNotifier,
}) async {
  progressNotifier?.setStep('Έλεγχος διαδρομής', clearDiagnosticInfo: true);
  final configured = await SettingsService().getDatabasePath();
  final resolved = await resolveEffectiveDatabasePath(configured);
  String dbPath = resolved.path;

  DatabaseInitResult? result;
  bool isLocalDevMode = false;

  try {
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      result = DatabaseInitResult.fileNotFound(dbPath);
    } else {
      try {
        await dbFile.readAsBytes();
      } catch (_) {
        result = DatabaseInitResult.accessDenied(dbPath);
      }

      if (result == null) {
        if (closeConnectionFirst) {
          progressNotifier?.setStep('Κλείσιμο σύνδεσης');
          await DatabaseHelper.instance.closeConnection();
        }
        try {
          await DatabaseHelper.instance.initializeDatabase(
            progressNotifier: progressNotifier,
          );
          SettingsService.registerAppSettingsProvider(
            _appSettingsGet,
            _appSettingsSet,
          );
          try {
            await RemoteToolsRepository(
              DatabaseHelper.instance,
            ).migrateLegacyFieldsToArguments();
          } catch (_) {}
          isLocalDevMode = DatabaseHelper.instance.isUsingLocalDb;
          progressNotifier?.setStep('Έλεγχος υγείας βάσης');
          final health = await DatabaseHelper.instance.checkDatabaseHealth();
          result = health.isSuccess
              ? DatabaseInitResult.success(dbPath)
              : health;
        } on DatabaseInitException catch (e) {
          result = await _attachLockDiagnostic(
            e.result,
            dbPath,
            progressNotifier: progressNotifier,
          );
        } catch (e, st) {
          final base = DatabaseInitResult.fromException(e, dbPath, st);
          result = await _attachLockDiagnostic(
            base,
            dbPath,
            progressNotifier: progressNotifier,
          );
        }
      }
    }
  } catch (e, st) {
    final base = DatabaseInitResult.fromException(e, dbPath, st);
    result = await _attachLockDiagnostic(
      base,
      dbPath,
      progressNotifier: progressNotifier,
    );
  }

  final finalResult = result;

  progressNotifier?.setStep(
    finalResult.isSuccess
        ? 'Η αρχικοποίηση ολοκληρώθηκε'
        : 'Αποτυχία αρχικοποίησης',
    clearSecondsRemaining: true,
    diagnosticInfo: finalResult.details,
  );

  return DatabaseInitRunnerResult(
    result: finalResult,
    isLocalDevMode: isLocalDevMode,
  );
}

Future<DatabaseInitResult> _attachLockDiagnostic(
  DatabaseInitResult result,
  String dbPath, {
  DatabaseInitProgressNotifier? progressNotifier,
}) async {
  final shouldAppend =
      result.status == DatabaseStatus.accessDenied ||
      result.status == DatabaseStatus.applicationError;
  if (!shouldAppend) return result;

  try {
    progressNotifier?.setStep('Εντοπισμός διεργασίας');
    final diagnostic = await const LockDiagnosticService().detectLockingProcess(
      dbPath,
    );
    if (diagnostic.trim().isEmpty) return result;
    final merged = _mergeDetails(result.details, diagnostic);
    progressNotifier?.setDiagnostic(diagnostic);
    return result.copyWith(details: merged);
  } catch (_) {
    return result;
  }
}

String _mergeDetails(String? current, String diagnostic) {
  final c = current?.trim() ?? '';
  final d = diagnostic.trim();
  if (d.isEmpty) return c;
  if (c.isEmpty) return d;
  return '$c\n\n--- Lock diagnostics ---\n$d';
}
