// Συμμετρία κλειδιών προφίλ: ό,τι γράφεται με πρόθεμα προφίλ πρέπει να
// διαβάζεται με το ίδιο πρόθεμα — και να ΜΗΝ μολύνει το παραγωγικό κλειδί.
//
//   flutter test test/core/services/settings_service_profile_key_symmetry_test.dart

import 'package:call_logger/core/config/app_config.dart';
import 'package:call_logger/core/config/audit_retention_config.dart';
import 'package:call_logger/core/services/app_instance_registry.dart';
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

  tearDown(() {
    AppConfig.activeProfile = null;
  });

  // Το μητρώο αντιγράφων απαντά «ποιοι μοιράζονται ΑΥΤΑ τα κλειδιά» — άρα
  // πρέπει να είναι κι αυτό ανά προφίλ, αλλιώς δύο απομονωμένες εκτελέσεις θα
  // κατηγορούσαν η μία την άλλη.
  group('Μητρώο αντιγράφων εφαρμογής', () {
    test('με ενεργό προφίλ, η αποθήκευση διαβάζεται πίσω', () async {
      AppConfig.activeProfile = 'dev';
      final settings = SettingsService();

      await settings.setKnownAppInstances([
        AppInstanceRecord(
          executablePath: r'C:\app\call_logger.exe',
          version: '0.22.1',
          lastSeen: DateTime(2026, 8, 3, 10),
        ),
      ]);

      final read = await settings.getKnownAppInstances();
      expect(read.single.executablePath, r'C:\app\call_logger.exe');
    });

    test('το προφίλ δεν μολύνει το παραγωγικό μητρώο', () async {
      final settings = SettingsService();

      AppConfig.activeProfile = 'dev';
      await settings.setKnownAppInstances([
        AppInstanceRecord(
          executablePath: r'F:\build\call_logger.exe',
          version: '0.22.1',
          lastSeen: DateTime(2026, 8, 3, 10),
        ),
      ]);
      await settings.setDismissedAppInstancesSignature('υπογραφή-dev');

      AppConfig.activeProfile = null;
      expect(
        await settings.getKnownAppInstances(),
        isEmpty,
        reason:
            'Η παραγωγική εκτέλεση δεν βλέπει τα αντίγραφα του προφίλ «dev»',
      );
      expect(await settings.getDismissedAppInstancesSignature(), isNull);
    });
  });

  group('Φίλτρο ημερομηνιών αναφορών εκκρεμοτήτων', () {
    test('με ενεργό προφίλ, η αποθήκευση διαβάζεται πίσω', () async {
      AppConfig.activeProfile = 'dev';
      final settings = SettingsService();
      final from = DateTime(2026, 3, 1);
      final to = DateTime(2026, 3, 31);

      await settings.analyticsFilters.setTaskAnalyticsDateFilter(
        preset: 'custom',
        customFrom: from,
        customTo: to,
      );

      expect(
        await settings.analyticsFilters.getTaskAnalyticsCustomDateFrom(),
        from,
        reason:
            'Η ανάγνωση χρησιμοποιεί το πρόθεμα προφίλ — το ίδιο πρέπει '
            'να κάνει και η εγγραφή',
      );
      expect(
        await settings.analyticsFilters.getTaskAnalyticsCustomDateTo(),
        to,
      );
    });

    test('με ενεργό προφίλ δεν μολύνεται το παραγωγικό κλειδί', () async {
      AppConfig.activeProfile = 'dev';
      final settings = SettingsService();

      await settings.analyticsFilters.setTaskAnalyticsDateFilter(
        preset: 'custom',
        customFrom: DateTime(2026, 3, 1),
        customTo: DateTime(2026, 3, 31),
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey('task_analytics_date_from_v1'),
        isFalse,
        reason:
            'Η εκτέλεση με προφίλ δεν επιτρέπεται να γράφει πάνω στη '
            'ρύθμιση της παραγωγικής εκτέλεσης',
      );
      expect(
        prefs.containsKey('profile_dev_task_analytics_date_from_v1'),
        isTrue,
      );
    });

    test(
      'χωρίς προφίλ (παραγωγή) γράφει και διαβάζει το σκέτο κλειδί',
      () async {
        final settings = SettingsService();
        await settings.analyticsFilters.setTaskAnalyticsDateFilter(
          preset: 'custom',
          customFrom: DateTime(2026, 5, 4),
          customTo: DateTime(2026, 5, 5),
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('task_analytics_date_from_v1'), '2026-05-04');
        expect(
          await settings.analyticsFilters.getTaskAnalyticsCustomDateFrom(),
          DateTime(2026, 5, 4),
        );
      },
    );
  });

  group('Πολιτική εκκαθάρισης ιστορικού ενεργειών', () {
    test('με ενεργό προφίλ, η αποθήκευση διαβάζεται πίσω', () async {
      AppConfig.activeProfile = 'dev';
      final settings = SettingsService();
      const config = AuditRetentionConfig(maxAgeDays: 45, maxRows: 5000);

      await settings.catalogs.setAuditRetentionConfig(config);

      final read = await settings.catalogs.getAuditRetentionConfig();
      expect(read.maxAgeDays, 45);
      expect(read.maxRows, 5000);
    });

    test('με ενεργό προφίλ δεν μολύνεται το παραγωγικό κλειδί', () async {
      AppConfig.activeProfile = 'dev';
      final settings = SettingsService();

      await settings.catalogs.setAuditRetentionConfig(
        const AuditRetentionConfig(maxAgeDays: 45, maxRows: 5000),
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey('audit_retention_config_v1'),
        isFalse,
        reason:
            'Η εκτέλεση με προφίλ δεν επιτρέπεται να γράφει πάνω στη '
            'ρύθμιση της παραγωγικής εκτέλεσης',
      );
      expect(
        prefs.containsKey('profile_dev_audit_retention_config_v1'),
        isTrue,
      );
    });

    test(
      'χωρίς προφίλ (παραγωγή) γράφει και διαβάζει το σκέτο κλειδί',
      () async {
        final settings = SettingsService();
        await settings.catalogs.setAuditRetentionConfig(
          const AuditRetentionConfig(maxAgeDays: 10, maxRows: 100),
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('audit_retention_config_v1'), isTrue);
        final read = await settings.catalogs.getAuditRetentionConfig();
        expect(read.maxAgeDays, 10);
      },
    );
  });
}
