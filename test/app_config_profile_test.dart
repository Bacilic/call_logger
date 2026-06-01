import 'package:call_logger/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig.parseCliProfile', () {
    test('parses --profile name', () {
      expect(
        AppConfig.parseCliProfile(['--profile', 'test1']),
        'test1',
      );
    });

    test('parses --profile=name', () {
      expect(
        AppConfig.parseCliProfile(['--profile=dev_env']),
        'dev_env',
      );
    });

    test('rejects invalid characters', () {
      expect(
        AppConfig.parseCliProfile(['--profile', '../evil']),
        isNull,
      );
    });

    test('returns null without flag', () {
      expect(AppConfig.parseCliProfile(const []), isNull);
    });
  });

  group('AppConfig.prefixedPreferencesKey', () {
    tearDown(() {
      AppConfig.activeProfile = null;
    });

    test('no prefix in production mode', () {
      AppConfig.activeProfile = null;
      expect(
        AppConfig.prefixedPreferencesKey('database_path'),
        'database_path',
      );
    });

    test('prefix when profile active', () {
      AppConfig.activeProfile = 'test1';
      expect(
        AppConfig.prefixedPreferencesKey('database_path'),
        'profile_test1_database_path',
      );
    });
  });
}
