import 'package:call_logger/core/database/database_path_resolution.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('unconfigured skips portable default fallback on resolve', () async {
    final settings = SettingsService();
    await settings.markDatabaseUnconfigured();
    expect(await settings.isDatabaseUnconfigured(), isTrue);

    const placeholder = r'C:\AppData\unconfigured\pending_database_connection.db';
    final resolved = await resolveEffectiveDatabasePath(placeholder);
    expect(resolved.path, placeholder);
    expect(resolved.usedUncFallback, isFalse);
  });

  test('markDatabaseConfigured clears unconfigured state', () async {
    final settings = SettingsService();
    await settings.markDatabaseUnconfigured();
    expect(await settings.isDatabaseUnconfigured(), isTrue);

    await settings.setDatabasePath(r'C:\temp\test_reset.db');
    expect(await settings.isDatabaseUnconfigured(), isFalse);
    expect(await settings.getDatabasePath(), r'C:\temp\test_reset.db');
  });

  test(
    'markDatabaseUnconfigured σβήνει διαδρομή, σημαίνει μη ρυθμισμένη και καθαρίζει πρόσφατες',
    () async {
      const path =
          r'F:\flutter_projects\call_logger\Data Base\Δοκιμές\μόνο_κλήσεις.db';
      final settings = SettingsService();
      await settings.setDatabasePath(path);
      await settings.recordVerifiedDatabasePath(path);
      expect(await settings.getDatabasePath(), path);
      expect(await settings.getRecentDatabasePaths(), contains(path));
      expect(await settings.isDatabaseUnconfigured(), isFalse);

      await settings.markDatabaseUnconfigured();

      expect(await settings.isDatabaseUnconfigured(), isTrue);
      expect(await settings.getRecentDatabasePaths(), isEmpty);
      // Άμεσος έλεγχος prefs: το getDatabasePath() θα ζητούσε path_provider για την προεπιλογή.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('database_path'), isNull);
    },
  );
}
