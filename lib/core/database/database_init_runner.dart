import 'dart:io';

import '../config/app_config.dart';
import '../services/settings_service.dart';
import 'database_helper.dart';
import 'database_init_result.dart';

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
}) async {
  String dbPath = await SettingsService().getDatabasePath();
  if (dbPath.trim().isEmpty) {
    dbPath = AppConfig.defaultDbPath;
  }

  DatabaseInitResult? result;
  bool isLocalDevMode = false;

  try {
    if (dbPath.trim().isEmpty) {
      result = DatabaseInitResult.fileNotFound('');
    } else {
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
            await DatabaseHelper.instance.closeConnection();
          }
          try {
            await DatabaseHelper.instance.database;
            SettingsService.registerAppSettingsProvider(
              DatabaseHelper.instance.getSetting,
              DatabaseHelper.instance.setSetting,
            );
            isLocalDevMode = DatabaseHelper.instance.isUsingLocalDb;
            final health = await DatabaseHelper.instance.checkDatabaseHealth();
            result = health.isSuccess
                ? DatabaseInitResult.success(dbPath)
                : health;
          } on DatabaseInitException catch (e) {
            result = e.result;
          } catch (e) {
            result = DatabaseInitResult.fromException(e, dbPath);
          }
        }
      }
    }
  } catch (e) {
    result = DatabaseInitResult.fromException(e, dbPath);
  }

  return DatabaseInitRunnerResult(
    // ignore: unnecessary_non_null_assertion
    result: result!,
    isLocalDevMode: isLocalDevMode,
  );
}
