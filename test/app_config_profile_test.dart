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

  group('AppConfig.validateCliArguments', () {
    test('accepts empty arguments', () {
      final result = AppConfig.validateCliArguments(const []);
      expect(result.isValid, isTrue);
      expect(result.profile, isNull);
    });

    test('accepts valid --profile', () {
      final result = AppConfig.validateCliArguments(['--profile', 'test1']);
      expect(result.isValid, isTrue);
      expect(result.profile, 'test1');
    });

    test('rejects unknown flag', () {
      final result = AppConfig.validateCliArguments(['--help']);
      expect(result.isValid, isFalse);
      expect(result.invalidParameter, '--help');
    });

    test('rejects --profile without value', () {
      final result = AppConfig.validateCliArguments(['--profile']);
      expect(result.isValid, isFalse);
      expect(result.invalidParameter, '--profile');
    });

    test('rejects invalid profile value', () {
      final result = AppConfig.validateCliArguments(['--profile', '../evil']);
      expect(result.isValid, isFalse);
      expect(result.invalidParameter, '../evil');
    });

    test('rejects duplicate --profile', () {
      final result = AppConfig.validateCliArguments([
        '--profile',
        'a',
        '--profile',
        'b',
      ]);
      expect(result.isValid, isFalse);
      expect(result.invalidParameter, '--profile');
    });

    test('rejects extra arguments after valid profile', () {
      final result = AppConfig.validateCliArguments([
        '--profile',
        'test1',
        '--foo',
      ]);
      expect(result.isValid, isFalse);
      expect(result.invalidParameter, '--foo');
    });

    test('buildErrorMessage includes invalid token', () {
      final result = AppConfig.validateCliArguments(['--profil', 'test']);
      expect(
        result.buildErrorMessage(),
        contains('Άκυρη παράμετρος γραμμής εντολών: --profil'),
      );
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
