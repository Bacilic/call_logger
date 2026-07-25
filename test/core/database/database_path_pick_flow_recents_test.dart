import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/database/database_path_pick_flow.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathA =
      r'F:\flutter_projects\call_logger\Data Base\Δοκιμές\μόνο_κλήσεις.db';
  const pathB =
      r'C:\Users\Bacilic\Documents\call_logger\DB\call_logger.db';

  late SettingsService settings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
  });

  Future<DatabaseInitRunnerResult> successChecks({
    bool closeConnectionFirst = false,
    progressNotifier,
  }) async {
    return DatabaseInitRunnerResult(
      result: DatabaseInitResult.success(pathA),
      isLocalDevMode: false,
    );
  }

  Future<DatabaseInitRunnerResult> failureChecks({
    bool closeConnectionFirst = false,
    progressNotifier,
  }) async {
    return DatabaseInitRunnerResult(
      result: DatabaseInitResult.fileNotFound(pathA),
      isLocalDevMode: false,
    );
  }

  Future<DatabaseInitRunnerResult> schemaConsentChecks({
    bool closeConnectionFirst = false,
    progressNotifier,
  }) async {
    return DatabaseInitRunnerResult(
      result: DatabaseInitResult(
        status: DatabaseStatus.corruptedOrInvalid,
        message: 'Απαιτείται συγκατάθεση αναβάθμισης σχήματος.',
        path: pathA,
        recoveryKind: DatabaseInitRecoveryKind.schemaUpgradeConsent,
      ),
      isLocalDevMode: false,
    );
  }

  test('επιτυχία: η διαδρομή καταγράφεται στα πρόσφατα', () async {
    final outcome = await setAndVerifyDatabasePath(
      pathA,
      runInitChecks: successChecks,
    );

    expect(outcome.ok, isTrue);
    expect(await settings.getRecentDatabasePaths(), contains(pathA));
  });

  test(
    'αποτυχία: δεν καταγράφεται και αφαιρείται αν υπήρχε ήδη',
    () async {
      await settings.recordVerifiedDatabasePath(pathA);
      await settings.recordVerifiedDatabasePath(pathB);

      final outcome = await setAndVerifyDatabasePath(
        pathA,
        runInitChecks: failureChecks,
      );

      expect(outcome.ok, isFalse);
      final recent = await settings.getRecentDatabasePaths();
      expect(recent, isNot(contains(pathA)));
      expect(recent, contains(pathB));
    },
  );

  test(
    'αποτυχία συναίνεσης αναβάθμισης σχήματος: δεν αφαιρείται από τα πρόσφατα',
    () async {
      await settings.recordVerifiedDatabasePath(pathA);

      final outcome = await setAndVerifyDatabasePath(
        pathA,
        runInitChecks: schemaConsentChecks,
      );

      expect(outcome.ok, isFalse);
      expect(
        outcome.runner.result.recoveryKind,
        DatabaseInitRecoveryKind.schemaUpgradeConsent,
      );
      expect(await settings.getRecentDatabasePaths(), contains(pathA));
    },
  );
}
