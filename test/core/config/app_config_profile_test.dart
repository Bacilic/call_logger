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

  group('AppConfig.validateCliArguments — --restarted-after-crash', () {
    tearDown(() {
      AppConfig.wasRestartedAfterCrash = false;
      AppConfig.activeProfile = null;
    });

    test('--restarted-after-crash μόνο του είναι έγκυρο', () {
      final result = AppConfig.validateCliArguments(['--restarted-after-crash']);
      expect(result.isValid, isTrue);
      expect(result.restartedAfterCrash, isTrue);
      expect(result.profile, isNull);
    });

    test('--profile test1 --restarted-after-crash έγκυρος συνδυασμός', () {
      final result = AppConfig.validateCliArguments([
        '--profile',
        'test1',
        '--restarted-after-crash',
      ]);
      expect(result.isValid, isTrue);
      expect(result.profile, 'test1');
      expect(result.restartedAfterCrash, isTrue);
    });

    test('--restarted-after-crash --profile=test1 έγκυρος συνδυασμός', () {
      final result = AppConfig.validateCliArguments([
        '--restarted-after-crash',
        '--profile=test1',
      ]);
      expect(result.isValid, isTrue);
      expect(result.profile, 'test1');
      expect(result.restartedAfterCrash, isTrue);
    });

    test('άγνωστα ορίσματα εξακολουθούν να απορρίπτονται', () {
      final result = AppConfig.validateCliArguments([
        '--restarted-after-crash',
        '--foo',
      ]);
      expect(result.isValid, isFalse);
      expect(result.invalidParameter, '--foo');
    });

    test('χωρίς flag το wasRestartedAfterCrash μένει false', () async {
      AppConfig.wasRestartedAfterCrash = true;
      await AppConfig.configureFromCliArguments(const []);
      expect(AppConfig.wasRestartedAfterCrash, isFalse);
    });

    test('configureFromCliArguments θέτει wasRestartedAfterCrash', () async {
      await AppConfig.configureFromCliArguments(['--restarted-after-crash']);
      expect(AppConfig.wasRestartedAfterCrash, isTrue);
    });

    test('διπλό --restarted-after-crash επιτρέπεται', () {
      final result = AppConfig.validateCliArguments([
        '--restarted-after-crash',
        '--restarted-after-crash',
      ]);
      expect(result.isValid, isTrue);
      expect(result.restartedAfterCrash, isTrue);
    });

    test('buildErrorMessage αναφέρει --restarted-after-crash', () {
      final result = AppConfig.validateCliArguments(['--foo']);
      expect(result.buildErrorMessage(), contains('--restarted-after-crash'));
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
