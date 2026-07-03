// Τεστ χαρακτηρισμού πριν τη διάσπαση του settings_service.dart.
//
//   flutter test test/core/services/settings_service_split_characterization_test.dart

import 'package:call_logger/core/config/app_config.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.activeProfile = null;
    SettingsService.registerAppSettingsProvider(
      (key) async => null,
      (key, value) async {},
    );
  });

  group('SettingsService split characterization', () {
    test('window_ui: get/set showActiveTimer', () async {
      final settings = SettingsService();
      expect(await settings.getShowActiveTimer(), isTrue);
      await settings.setShowActiveTimer(false);
      expect(await settings.getShowActiveTimer(), isFalse);
    });

    test('analytics_filters: get/set dashboard date preset', () async {
      final settings = SettingsService();
      expect(await settings.getDashboardDatePreset(), 'today');
      await settings.setDashboardDateFilter(preset: 'week');
      expect(await settings.getDashboardDatePreset(), 'week');
    });

    test('remote_lansweeper: get/set calls primary tool id', () async {
      final store = <String, String>{};
      SettingsService.registerAppSettingsProvider(
        (key) async => store[key],
        (key, value) async {
          store[key] = value;
        },
      );
      final settings = SettingsService();
      expect(await settings.getCallsPrimaryToolId(), isNull);
      await settings.setCallsPrimaryToolId(42);
      expect(await settings.getCallsPrimaryToolId(), 42);
    });

    test('catalogs: get/set database open timeout seconds', () async {
      final settings = SettingsService();
      final defaultTimeout = AppConfig.databaseOpenTimeoutSeconds;
      expect(await settings.getDatabaseOpenTimeoutSeconds(), defaultTimeout);
      await settings.setDatabaseOpenTimeoutSeconds(15);
      expect(await settings.getDatabaseOpenTimeoutSeconds(), 15);
    });

    test(
      'clearAllPreferencesForCurrentProfile: διατηρεί ξένα profile_ κλειδιά χωρίς ενεργό προφίλ',
      () async {
        SharedPreferences.setMockInitialValues({
          'show_active_timer': false,
          'database_path': r'C:\keep.db',
          'profile_other_show_active_timer': true,
        });
        final settings = SettingsService();
        await settings.clearAllPreferencesForCurrentProfile();
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('show_active_timer'), isFalse);
        expect(prefs.containsKey('database_path'), isFalse);
        expect(prefs.getBool('profile_other_show_active_timer'), isTrue);
      },
    );

    test(
      'clearAllPreferencesForCurrentProfile: με ενεργό προφίλ διαγράφει μόνο τα δικά του',
      () async {
        AppConfig.activeProfile = 'dev';
        SharedPreferences.setMockInitialValues({
          'profile_dev_show_active_timer': false,
          'profile_dev_database_path': r'C:\dev.db',
          'show_active_timer': true,
          'profile_other_show_active_timer': true,
        });
        final settings = SettingsService();
        await settings.clearAllPreferencesForCurrentProfile();
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('profile_dev_show_active_timer'), isFalse);
        expect(prefs.containsKey('profile_dev_database_path'), isFalse);
        expect(prefs.getBool('show_active_timer'), isTrue);
        expect(prefs.getBool('profile_other_show_active_timer'), isTrue);
      },
    );

    test('lansweeper API URL: έγκυρο api.aspx URL επιστρέφεται', () async {
      final store = <String, String>{
        'lansweeper_api_url': 'https://example.com/api.aspx',
      };
      SettingsService.registerAppSettingsProvider(
        (key) async => store[key],
        (key, value) async {
          store[key] = value;
        },
      );
      final settings = SettingsService();
      expect(
        await settings.getLansweeperApiUrl(),
        'https://example.com/api.aspx',
      );
    });

    test('lansweeper API URL: άκυρο URL αγνοείται', () async {
      final store = <String, String>{
        'lansweeper_api_url': 'not-a-valid-url',
        'lansweeper_url': 'ftp://legacy.example.com/page',
      };
      SettingsService.registerAppSettingsProvider(
        (key) async => store[key],
        (key, value) async {
          store[key] = value;
        },
      );
      final settings = SettingsService();
      expect(await settings.getLansweeperApiUrl(), isNull);
    });

    test('getEquipmentTypesList: CSV με κενά και άδειες τιμές', () async {
      final store = <String, String>{
        'equipment_types': '  PC , , Laptop ,  ',
      };
      SettingsService.registerAppSettingsProvider(
        (key) async => store[key],
        (key, value) async {
          store[key] = value;
        },
      );
      final settings = SettingsService();
      expect(await settings.getEquipmentTypesList(), ['PC', 'Laptop']);
    });
  });
}
