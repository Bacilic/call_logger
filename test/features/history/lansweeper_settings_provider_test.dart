// Χαρακτηρισμός συμπεριφοράς Lansweeper notifiers πριν τη μετακίνηση από dashboard_provider.
//
//   flutter test test/features/history/lansweeper_settings_provider_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/features/history/providers/lansweeper_settings_provider.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_url_rules.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

const _kTicketFormUrl =
    'http://10.10.201.22:81/helpdesk/NewTicket.aspx?tid=-7';

const _kNonApiUrl = 'http://10.10.201.22:81/helpdesk/NewTicket.aspx';

Future<void> _clearLansweeperSettings() async {
  final db = await DatabaseHelper.instance.database;
  await db.delete(
    'app_settings',
    where: 'key LIKE ?',
    whereArgs: ['lansweeper_%'],
  );
}

Future<SettingsRepository> _settingsRepo() async {
  final db = await DatabaseHelper.instance.database;
  return SettingsRepository(db);
}

ProviderContainer _testContainer() {
  return ProviderContainer(
    overrides: callLoggerTestProviderOverrides(),
  );
}

Future<void> _pumpUntil(
  bool Function() condition, {
  int maxAttempts = 50,
  Duration step = const Duration(milliseconds: 20),
}) async {
  for (var i = 0; i < maxAttempts; i++) {
    if (condition()) return;
    await Future<void>.delayed(step);
  }
  fail(
    'Timeout: η συνθήκη δεν ικανοποιήθηκε μετά από '
    '${maxAttempts * step.inMilliseconds}ms',
  );
}

Future<void> _pumpHydration() async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Lansweeper settings providers — characterization', () {
    setUp(() async {
      await _clearLansweeperSettings();
    });

    group('lansweeperApiUrlProvider', () {
      test('χρησιμοποιεί έγκυρο api url όταν υπάρχει στο κύριο κλειδί', () async {
        await (await _settingsRepo()).saveSetting(
          kLansweeperApiUrlSettingKey,
          kExampleLansweeperApiUrl,
        );

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(lansweeperApiUrlProvider, (_, _) {});
        await _pumpUntil(
          () => container.read(lansweeperApiUrlProvider) == kExampleLansweeperApiUrl,
        );

        expect(container.read(lansweeperApiUrlProvider), kExampleLansweeperApiUrl);
      });

      test('legacy fallback από kLansweeperUrlSettingKey όταν το api κλειδί είναι μη-endpoint', () async {
        await (await _settingsRepo()).saveSetting(
          kLansweeperApiUrlSettingKey,
          _kNonApiUrl,
        );
        await (await _settingsRepo()).saveSetting(
          kLansweeperUrlSettingKey,
          kExampleLansweeperApiUrl,
        );

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(lansweeperApiUrlProvider, (_, _) {});
        await _pumpUntil(
          () => container.read(lansweeperApiUrlProvider) == kExampleLansweeperApiUrl,
        );

        expect(container.read(lansweeperApiUrlProvider), kExampleLansweeperApiUrl);
      });

      test('setApiKey αποθηκεύει και επιστρέφει τιμή (ενδεικτικό hydrate/set/save)', () async {
        const apiKey = 'test-api-key-123';

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(lansweeperApiKeyProvider, (_, _) {});
        container.read(lansweeperApiKeyProvider);
        await _pumpHydration();

        await container.read(lansweeperApiKeyProvider.notifier).setApiKey(apiKey);

        expect(container.read(lansweeperApiKeyProvider), apiKey);
        expect(
          await (await _settingsRepo()).getSetting(kLansweeperApiKeySettingKey),
          apiKey,
        );
      });
    });

    group('lansweeperTicketFormUrlProvider', () {
      test('προτεραιότητα ticketRaw → apiRaw (μη-endpoint) → default', () async {
        await (await _settingsRepo()).saveSetting(
          kLansweeperUrlSettingKey,
          _kTicketFormUrl,
        );

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(lansweeperTicketFormUrlProvider, (_, _) {});
        await _pumpUntil(
          () => container.read(lansweeperTicketFormUrlProvider) == _kTicketFormUrl,
        );

        expect(container.read(lansweeperTicketFormUrlProvider), _kTicketFormUrl);
      });

      test('fallback σε apiRaw όταν λείπει ticketRaw και το api δεν είναι endpoint', () async {
        await (await _settingsRepo()).saveSetting(
          kLansweeperApiUrlSettingKey,
          _kNonApiUrl,
        );

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(lansweeperTicketFormUrlProvider, (_, _) {});
        await _pumpUntil(
          () => container.read(lansweeperTicketFormUrlProvider) == _kNonApiUrl,
        );

        expect(container.read(lansweeperTicketFormUrlProvider), _kNonApiUrl);
      });

      test('προεπιλογή kDefaultLansweeperUrl όταν λείπουν και τα δύο', () async {
        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(lansweeperTicketFormUrlProvider, (_, _) {});
        container.read(lansweeperTicketFormUrlProvider);
        await _pumpHydration();

        expect(container.read(lansweeperTicketFormUrlProvider), kDefaultLansweeperUrl);
      });
    });

    group('lansweeperHelpdeskLoginUrlProvider', () {
      test('παράγει login url από ticket form url όταν λείπει ρητή τιμή', () async {
        await (await _settingsRepo()).saveSetting(
          kLansweeperUrlSettingKey,
          _kTicketFormUrl,
        );

        final expected = LansweeperUrlRules.loginUrlDerivedFromTicketFormUrl(
          _kTicketFormUrl,
        );

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(lansweeperHelpdeskLoginUrlProvider, (_, _) {});
        await _pumpUntil(
          () => container.read(lansweeperHelpdeskLoginUrlProvider) == expected,
        );

        expect(container.read(lansweeperHelpdeskLoginUrlProvider), expected);
        expect(
          await (await _settingsRepo()).getSetting(
            kLansweeperHelpdeskLoginUrlSettingKey,
          ),
          isNull,
        );
      });

      test('διατηρεί ρητή τιμή login url όταν είναι browser-launchable', () async {
        const explicitLogin = 'http://10.10.201.22:81/login.aspx';
        await (await _settingsRepo()).saveSetting(
          kLansweeperHelpdeskLoginUrlSettingKey,
          explicitLogin,
        );

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(lansweeperHelpdeskLoginUrlProvider, (_, _) {});
        await _pumpUntil(
          () => container.read(lansweeperHelpdeskLoginUrlProvider) == explicitLogin,
        );

        expect(container.read(lansweeperHelpdeskLoginUrlProvider), explicitLogin);
      });
    });

    group('lansweeperHelpdeskAutoLoginProvider', () {
      test('προεπιλογή false όταν λείπει ρύθμιση', () async {
        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(lansweeperHelpdeskAutoLoginProvider, (_, _) {});
        container.read(lansweeperHelpdeskAutoLoginProvider);
        await _pumpHydration();

        expect(container.read(lansweeperHelpdeskAutoLoginProvider), isFalse);
      });

      test('hydrate true από "yes" μέσω parseBoolAppSetting', () async {
        await (await _settingsRepo()).saveSetting(
          kLansweeperHelpdeskAutoLoginSettingKey,
          'yes',
        );

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(lansweeperHelpdeskAutoLoginProvider, (_, _) {});
        await _pumpUntil(
          () => container.read(lansweeperHelpdeskAutoLoginProvider) == true,
        );

        expect(container.read(lansweeperHelpdeskAutoLoginProvider), isTrue);
      });
    });

    group('lansweeperOpenTicketAfterApiSubmitProvider', () {
      test('hydrate true από "1" μέσω parseBoolAppSetting', () async {
        await (await _settingsRepo()).saveSetting(
          kLansweeperOpenTicketAfterApiSubmitSettingKey,
          '1',
        );

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(lansweeperOpenTicketAfterApiSubmitProvider, (_, _) {});
        await _pumpUntil(
          () => container.read(lansweeperOpenTicketAfterApiSubmitProvider) == true,
        );

        expect(container.read(lansweeperOpenTicketAfterApiSubmitProvider), isTrue);
      });

      test('hydrate false από "0"', () async {
        await (await _settingsRepo()).saveSetting(
          kLansweeperOpenTicketAfterApiSubmitSettingKey,
          '0',
        );

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(lansweeperOpenTicketAfterApiSubmitProvider, (_, _) {});
        await _pumpUntil(
          () => container.read(lansweeperOpenTicketAfterApiSubmitProvider) == false,
        );

        expect(container.read(lansweeperOpenTicketAfterApiSubmitProvider), isFalse);
      });
    });

    group('readLansweeperOpenTicketAfterApiSubmitSetting', () {
      test('διαβάζει κατευθείαν από τη βάση με parseBoolAppSetting', () async {
        await (await _settingsRepo()).saveSetting(
          kLansweeperOpenTicketAfterApiSubmitSettingKey,
          'true',
        );

        expect(await readLansweeperOpenTicketAfterApiSubmitSetting(), isTrue);

        await (await _settingsRepo()).saveSetting(
          kLansweeperOpenTicketAfterApiSubmitSettingKey,
          '0',
        );

        expect(await readLansweeperOpenTicketAfterApiSubmitSetting(), isFalse);
      });

      test('επιστρέφει false όταν λείπει η ρύθμιση', () async {
        expect(await readLansweeperOpenTicketAfterApiSubmitSetting(), isFalse);
      });
    });
  });
}
