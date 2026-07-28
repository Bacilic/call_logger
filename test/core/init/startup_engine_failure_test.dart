import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/init/startup_engine_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(clearStartupEngineFailure);

  group('resolveStartupFailureResult', () {
    test('Α: πρωτογενές sqlite3.dll κερδίζει το δευτερογενές '
        'databaseFactory not initialized', () {
      recordStartupEngineFailure(
        ArgumentError(
          "Failed to load dynamic library 'sqlite3.dll': "
          'The specified module could not be found. (error code: 126)',
        ),
        StackTrace.current,
      );

      final result = resolveStartupFailureResult(
        fallbackError: StateError('databaseFactory not initialized'),
      );

      expect(result.message, contains('sqlite3.dll'));
    });

    test('Β: πρωτογενές NativeAssetsManifest κερδίζει το δευτερογενές', () {
      recordStartupEngineFailure(
        StateError('Unable to load asset: NativeAssetsManifest.json'),
        StackTrace.current,
      );

      final result = resolveStartupFailureResult(
        fallbackError: StateError('databaseFactory not initialized'),
      );

      expect(result.message, contains('NativeAssetsManifest'));
    });

    test('Γ: recoveryKind missingApplicationFile και details με '
        'δευτερογενές σφάλμα', () {
      recordStartupEngineFailure(
        ArgumentError(
          "Failed to load dynamic library 'sqlite3.dll': "
          'The specified module could not be found. (error code: 126)',
        ),
        StackTrace.current,
      );
      final sqliteResult = resolveStartupFailureResult(
        fallbackError: StateError('databaseFactory not initialized'),
      );

      clearStartupEngineFailure();
      recordStartupEngineFailure(
        StateError('Unable to load asset: NativeAssetsManifest.json'),
        StackTrace.current,
      );
      final manifestResult = resolveStartupFailureResult(
        fallbackError: StateError('databaseFactory not initialized'),
      );

      expect(
        sqliteResult.recoveryKind,
        DatabaseInitRecoveryKind.missingApplicationFile,
      );
      expect(sqliteResult.details, contains('Δευτερογενές σφάλμα'));
      expect(
        manifestResult.recoveryKind,
        DatabaseInitRecoveryKind.missingApplicationFile,
      );
      expect(manifestResult.details, contains('Δευτερογενές σφάλμα'));
    });

    test('Δ: χωρίς καταγεγραμμένη αποτυχία → ίδιο με fromException', () {
      final fallback = StateError('No element');
      final resolved = resolveStartupFailureResult(fallbackError: fallback);
      final direct = DatabaseInitResult.fromException(fallback);

      expect(resolved.recoveryKind, DatabaseInitRecoveryKind.generic);
      expect(resolved.recoveryKind, direct.recoveryKind);
      expect(resolved.message, direct.message);
    });

    test('Ε: δύο διαδοχικές εγγραφές κρατούν την πρώτη αιτία', () {
      recordStartupEngineFailure(
        ArgumentError('πρώτη αιτία sqlite3.dll'),
        StackTrace.current,
      );
      recordStartupEngineFailure(
        StateError('δεύτερη αιτία NativeAssetsManifest.json'),
        StackTrace.current,
      );

      expect(
        startupEngineFailureOrNull!.error.toString(),
        contains('πρώτη αιτία'),
      );
      expect(
        startupEngineFailureOrNull!.error.toString(),
        isNot(contains('δεύτερη αιτία')),
      );
    });
  });
}
