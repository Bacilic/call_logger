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
}
