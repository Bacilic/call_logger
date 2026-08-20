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

  // Η πολιτική εκκαθάρισης Ιστορικού ΕΦΥΓΕ από τις τοπικές ρυθμίσεις στη
  // Φάση 2: καθαρίζει το ΚΟΙΝΟ Ιστορικό, οπότε ζει πλέον στη βάση και είναι
  // ίδια για όλους. Η απομόνωση ανά προφίλ CLI εξακολουθεί να ισχύει — μέσω
  // του ξεχωριστού αρχείου βάσης κάθε προφίλ, όχι μέσω προθέματος κλειδιού.
  group('Πολιτική εκκαθάρισης Ιστορικού — δεν είναι πια τοπική', () {
    test('η αποθήκευση ΔΕΝ αγγίζει τις τοπικές ρυθμίσεις', () async {
      AppConfig.activeProfile = 'dev';
      final settings = SettingsService();

      await settings.catalogs.setAuditRetentionConfig(
        const AuditRetentionConfig(maxAgeDays: 45, maxRows: 5000),
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('audit_retention_config_v1'), isFalse);
      expect(
        prefs.containsKey('profile_dev_audit_retention_config_v1'),
        isFalse,
        reason:
            'Η ρύθμιση ανήκει στα δεδομένα — μια τοπική εγγραφή θα ξαναγεννούσε '
            'το πρόβλημα που έλυσε η Φάση 2.',
      );
    });

    test('περνά από τον πάροχο κοινών ρυθμίσεων', () async {
      final store = <String, String>{};
      SettingsService.registerAppSettingsProvider(
        (key) async => store[key],
        (key, value) async => store[key] = value,
      );
      final settings = SettingsService();

      await settings.catalogs.setAuditRetentionConfig(
        const AuditRetentionConfig(maxAgeDays: 10, maxRows: 100),
      );

      expect(store.containsKey('audit_retention_config_v1'), isTrue);
      final read = await settings.catalogs.getAuditRetentionConfig();
      expect(read.maxAgeDays, 10);
    });
  });
}
