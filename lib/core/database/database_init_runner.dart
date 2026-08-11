import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../init/startup_engine_failure.dart';
import '../init/startup_structural_check.dart';
import '../services/settings_service.dart';
import '../services/startup_asset_integrity_service.dart';
import 'database_file_classifier.dart';
import 'database_helper.dart';
import 'remote_tools_repository.dart';
import 'settings_repository.dart';
import 'database_init_result.dart';
import 'database_init_progress_provider.dart';
import 'lock_diagnostic_service.dart';
import 'database_path_resolution.dart';

Future<String?> _appSettingsGet(String key) async {
  final db = await DatabaseHelper.instance.database;
  return SettingsRepository(db).getSetting(key);
}

Future<void> _appSettingsSet(String key, String value) async {
  final db = await DatabaseHelper.instance.database;
  return SettingsRepository(db).saveSetting(key, value);
}

/// Αλυσίδα σειριοποίησης: νέες κλήσεις περιμένουν την προηγούμενη να τελειώσει.
Future<void> _runDatabaseInitChecksGate = Future<void>.value();

/// Το τελευταίο **επιτυχές** αποτέλεσμα, μαζί με το πότε ισχύει.
class _RememberedInitResult {
  const _RememberedInitResult({
    required this.result,
    required this.path,
    required this.generation,
  });

  final DatabaseInitRunnerResult result;
  final String path;
  final int generation;
}

_RememberedInitResult? _rememberedInitResult;

/// Ξεχνά το τελευταίο αποτέλεσμα, ώστε ο επόμενος έλεγχος να τρέξει από την αρχή.
///
/// Χρειάζεται μόνο για ρητή επαναδοκιμή· το κλείσιμο σύνδεσης και η αλλαγή
/// διαδρομής ακυρώνουν τη μνήμη μόνα τους.
void forgetDatabaseInitResult() {
  _rememberedInitResult = null;
}

/// Μόνο για τεστ — πόσες φορές έτρεξαν όντως οι έλεγχοι (χωρίς επαναχρήση).
@visibleForTesting
int debugDatabaseInitChecksRunCount = 0;

/// Αποτέλεσμα ελέγχου αρχικοποίησης (αποτέλεσμα + τρόπος λειτουργίας).
class DatabaseInitRunnerResult {
  const DatabaseInitRunnerResult({
    required this.result,
    required this.isLocalDevMode,
    this.databaseProfile,
    this.missingApplicationFiles = const <String>[],
  });

  final DatabaseInitResult result;
  final bool isLocalDevMode;
  final DatabaseFileProfile? databaseProfile;

  /// Ελλείποντα κρίσιμα αρχεία της εφαρμογής, από τον δομικό έλεγχο που
  /// προηγήθηκε των ελέγχων βάσης. Κενή λίστα όταν όλα είναι στη θέση τους.
  final List<String> missingApplicationFiles;
}

/// Εκτελεί τους ελέγχους βάσης (ύπαρξη αρχείου, δικαιώματα, σύνδεση, υγεία).
/// Χρησιμοποιείται στην εκκίνηση και κατά την επιστροφή από Ρυθμίσεις.
/// Αν [closeConnectionFirst] είναι true, κλείνει την τρέχουσα σύνδεση ώστε να
/// χρησιμοποιηθεί η τρέχουσα διαδρομή από ρυθμίσεις (π.χ. μετά αλλαγή path).
///
/// Οι κλήσεις σειριοποιούνται: αν τρέχει ήδη άλλη, η νέα περιμένει να ολοκληρωθεί.
///
/// Με [reuseIfFresh] η κλήση επιστρέφει το ήδη επαληθευμένο αποτέλεσμα, εφόσον
/// αφορά την ίδια διαδρομή και η σύνδεση δεν έχει κλείσει στο μεταξύ. Έτσι μία
/// αλλαγή διαδρομής ανοίγει τη βάση **μία** φορά αντί για τρεις: ο κρίκος που
/// επαληθεύει τη νέα διαδρομή παράγει ήδη ό,τι χρειάζονται οι επόμενοι.
/// Όταν είναι `true`, υπερισχύει του [closeConnectionFirst] — δεν έχει νόημα να
/// κλείσουμε μια σύνδεση που μόλις ανοίξαμε και επαληθεύσαμε.
///
/// Το [assetIntegrity] είναι εγχύσιμο για τεστ· στην παραγωγή χρησιμοποιείται ο
/// φάκελος `flutter_assets` δίπλα στο εκτελέσιμο.
Future<DatabaseInitRunnerResult> runDatabaseInitChecks({
  bool closeConnectionFirst = false,
  bool reuseIfFresh = false,
  DatabaseInitProgressNotifier? progressNotifier,
  StartupAssetIntegrityService? assetIntegrity,
}) async {
  final previous = _runDatabaseInitChecksGate;
  final gate = Completer<void>();
  _runDatabaseInitChecksGate = gate.future;
  try {
    await previous;

    progressNotifier?.setStep('Έλεγχος διαδρομής', clearDiagnosticInfo: true);
    final configured = await SettingsService().getDatabasePath();
    final resolved = await resolveEffectiveDatabasePath(configured);
    final dbPath = resolved.path;

    if (reuseIfFresh) {
      final remembered = _rememberedResultFor(dbPath);
      if (remembered != null) {
        progressNotifier?.setStep(
          'Η αρχικοποίηση ολοκληρώθηκε',
          clearSecondsRemaining: true,
        );
        return remembered;
      }
    }

    debugDatabaseInitChecksRunCount++;
    final result = await _runDatabaseInitChecksUnlocked(
      dbPath: dbPath,
      closeConnectionFirst: closeConnectionFirst,
      progressNotifier: progressNotifier,
      assetIntegrity: assetIntegrity,
    );
    _rememberResult(result, dbPath);
    return result;
  } finally {
    gate.complete();
  }
}

/// Το αποθηκευμένο αποτέλεσμα, μόνο αν αφορά ακόμα την τρέχουσα κατάσταση.
DatabaseInitRunnerResult? _rememberedResultFor(String dbPath) {
  final remembered = _rememberedInitResult;
  if (remembered == null) return null;
  if (remembered.path != dbPath) return null;
  if (remembered.generation != DatabaseHelper.instance.connectionGeneration) {
    return null;
  }
  return remembered.result;
}

/// Θυμάται μόνο επιτυχίες: μια αποτυχία πρέπει να ξαναδοκιμάζεται πάντα.
void _rememberResult(DatabaseInitRunnerResult result, String dbPath) {
  if (!result.result.isSuccess) {
    _rememberedInitResult = null;
    return;
  }
  _rememberedInitResult = _RememberedInitResult(
    result: result,
    path: dbPath,
    generation: DatabaseHelper.instance.connectionGeneration,
  );
}

Future<DatabaseInitRunnerResult> _runDatabaseInitChecksUnlocked({
  required String dbPath,
  required bool closeConnectionFirst,
  DatabaseInitProgressNotifier? progressNotifier,
  StartupAssetIntegrityService? assetIntegrity,
}) async {
  // Ο δομικός έλεγχος αρχείων προηγείται κάθε ελέγχου βάσης: κοστίζει λίγους
  // ελέγχους ύπαρξης αρχείου, ενώ οι έλεγχοι βάσης κοστίζουν δευτερόλεπτα.
  progressNotifier?.setStep('Έλεγχος αρχείων εφαρμογής');
  final missingApplicationFiles = detectMissingApplicationFiles(assetIntegrity);

  // Αν η μηχανή SQLite δεν φορτώθηκε στην εκκίνηση (π.χ. λείπει το sqlite3.dll),
  // κανένας έλεγχος βάσης δεν έχει νόημα: τα file probes πετυχαίνουν και κρύβουν
  // την πραγματική αιτία πίσω από «databaseFactory not initialized».
  final engineFailure = startupEngineFailureResultOrNull(pathHint: dbPath);
  if (engineFailure != null) {
    final ranked = withMissingApplicationFilesFirst(
      engineFailure,
      missingApplicationFiles,
    );
    progressNotifier?.setStep(
      'Αποτυχία αρχικοποίησης',
      clearSecondsRemaining: true,
      diagnosticInfo: ranked.details,
    );
    return DatabaseInitRunnerResult(
      result: ranked,
      isLocalDevMode: false,
      missingApplicationFiles: missingApplicationFiles,
    );
  }

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

  final finalResult = withMissingApplicationFilesFirst(
    result,
    missingApplicationFiles,
  );

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
    databaseProfile: DatabaseHelper.instance.lastDatabaseProfile,
    missingApplicationFiles: missingApplicationFiles,
  );
}

Future<DatabaseInitResult> _attachLockDiagnostic(
  DatabaseInitResult result,
  String dbPath, {
  DatabaseInitProgressNotifier? progressNotifier,
}) async {
  // Η αναντιστοιχία έκδοσης δεν είναι κλείδωμα: η αναζήτηση «ποια διεργασία
  // κρατά το αρχείο» θα πρόσθετε μόνο χρόνο και άσχετο θόρυβο στο μήνυμα.
  if (result.recoveryKind == DatabaseInitRecoveryKind.databaseNewerThanApp) {
    return result;
  }
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

    final foundProcess = _lockDiagnosticFoundProcess(diagnostic);
    if (!foundProcess) {
      // Χωρίς εντοπισμένη διεργασία: μην ισχυριζόμαστε κλείδωμα από άλλη εφαρμογή.
      progressNotifier?.setDiagnostic(diagnostic);
      return result.copyWith(
        details: _mergeDetails(result.details, diagnostic),
      );
    }

    var details = result.details;
    if (!_detailsMentionOtherAppLock(details)) {
      details = _mergeDetails(
        details,
        'Ελέγξτε αν άλλη εφαρμογή κρατά το ίδιο αρχείο .db.',
      );
    }
    final merged = _mergeDetails(details, diagnostic);
    progressNotifier?.setDiagnostic(diagnostic);
    return result.copyWith(details: merged);
  } catch (_) {
    return result;
  }
}

bool _lockDiagnosticFoundProcess(String diagnostic) {
  final d = diagnostic.trim();
  if (d.isEmpty) return false;
  if (d.contains('Δεν εντοπίστηκε διεργασία')) return false;
  if (d.startsWith('Αποτυχία lock diagnostics')) return false;
  return true;
}

bool _detailsMentionOtherAppLock(String? details) {
  final d = details?.toLowerCase() ?? '';
  return d.contains('άλλη εφαρμογή κρατά') ||
      (d.contains('άλλη διεργασία') && d.contains('αρχείο'));
}

String _mergeDetails(String? current, String diagnostic) {
  final c = current?.trim() ?? '';
  final d = diagnostic.trim();
  if (d.isEmpty) return c;
  if (c.isEmpty) return d;
  return '$c\n\n--- Lock diagnostics ---\n$d';
}
