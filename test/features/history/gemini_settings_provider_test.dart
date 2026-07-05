// Χαρακτηρισμός συμπεριφοράς Gemini notifiers πριν τη μετακίνηση από dashboard_provider.
//
//   flutter test test/features/history/gemini_settings_provider_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/services/gemini_ticket_service.dart';
import 'package:call_logger/features/history/providers/gemini_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

const _kCustomPromptTemplate = 'Προσαρμοσμένο πρότυπο {Τίτλος}';

const _kLegacyEndpointRaw =
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent?key={apiKey}';

final _kLegacyEndpointNormalized = GeminiTicketService.normalizeEndpointTemplate(
  _kLegacyEndpointRaw,
);

const _kLegacyFixedModelEndpoint =
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={κλειδί API}';

Future<void> _clearGeminiSettings() async {
  final db = await DatabaseHelper.instance.database;
  await db.delete(
    'app_settings',
    where: 'key LIKE ?',
    whereArgs: ['gemini_%'],
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

  group('Gemini settings providers — characterization', () {
    setUp(() async {
      await _clearGeminiSettings();
    });

    group('geminiPromptTemplateProvider', () {
      test('επιστρέφει kDefaultAiPromptTemplate όταν η βάση είναι κενή', () async {
        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(geminiPromptTemplateProvider, (_, _) {});
        container.read(geminiPromptTemplateProvider);
        await _pumpHydration();

        expect(container.read(geminiPromptTemplateProvider), kDefaultAiPromptTemplate);
        expect(
          await (await _settingsRepo()).getSetting(kGeminiPromptTemplateSettingKey),
          isNull,
        );
      });

      test('διατηρεί αποθηκευμένη τιμή μετά hydrate', () async {
        await (await _settingsRepo()).saveSetting(
          kGeminiPromptTemplateSettingKey,
          _kCustomPromptTemplate,
        );

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(geminiPromptTemplateProvider, (_, _) {});
        expect(container.read(geminiPromptTemplateProvider), kDefaultAiPromptTemplate);

        await _pumpUntil(
          () => container.read(geminiPromptTemplateProvider) == _kCustomPromptTemplate,
        );

        expect(container.read(geminiPromptTemplateProvider), _kCustomPromptTemplate);
      });

      test('setPromptTemplate με κενό αποθηκεύει default', () async {
        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(geminiPromptTemplateProvider, (_, _) {});
        container.read(geminiPromptTemplateProvider);
        await _pumpHydration();
        await container.read(geminiPromptTemplateProvider.notifier).setPromptTemplate('');

        expect(container.read(geminiPromptTemplateProvider), kDefaultAiPromptTemplate);
        expect(
          await (await _settingsRepo()).getSetting(kGeminiPromptTemplateSettingKey),
          kDefaultAiPromptTemplate,
        );
      });
    });

    group('geminiEndpointProvider', () {
      test('hydrate κανονικοποιεί legacy endpoint με {apiKey}', () async {
        await (await _settingsRepo()).saveSetting(
          kGeminiEndpointSettingKey,
          _kLegacyEndpointRaw,
        );

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(geminiEndpointProvider, (_, _) {});
        await _pumpUntil(
          () =>
              container.read(geminiEndpointProvider) == _kLegacyEndpointNormalized,
        );

        expect(container.read(geminiEndpointProvider), _kLegacyEndpointNormalized);
      });

      test('setEndpoint κανονικοποιεί legacy input', () async {
        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(geminiEndpointProvider, (_, _) {});
        container.read(geminiEndpointProvider);
        await _pumpHydration();
        await container
            .read(geminiEndpointProvider.notifier)
            .setEndpoint(_kLegacyEndpointRaw);

        expect(container.read(geminiEndpointProvider), _kLegacyEndpointNormalized);
        expect(
          await (await _settingsRepo()).getSetting(kGeminiEndpointSettingKey),
          _kLegacyEndpointNormalized,
        );
      });
    });

    group('geminiPrimaryModelProvider', () {
      test('legacy fallback μέσω modelFromEndpoint όταν λείπει ρητή τιμή', () async {
        await (await _settingsRepo()).saveSetting(
          kGeminiEndpointSettingKey,
          _kLegacyFixedModelEndpoint,
        );

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(geminiPrimaryModelProvider, (_, _) {});
        await _pumpUntil(
          () => container.read(geminiPrimaryModelProvider) == 'gemini-2.0-flash',
        );

        expect(container.read(geminiPrimaryModelProvider), 'gemini-2.0-flash');
        expect(
          await (await _settingsRepo()).getSetting(kGeminiPrimaryModelSettingKey),
          isNull,
        );
      });

      test('χρησιμοποιεί ρητή τιμή primary model όταν υπάρχει', () async {
        const explicitModel = 'gemini-2.5-pro';
        await (await _settingsRepo()).saveSetting(
          kGeminiPrimaryModelSettingKey,
          explicitModel,
        );
        await (await _settingsRepo()).saveSetting(
          kGeminiEndpointSettingKey,
          _kLegacyFixedModelEndpoint,
        );

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(geminiPrimaryModelProvider, (_, _) {});
        await _pumpUntil(
          () => container.read(geminiPrimaryModelProvider) == explicitModel,
        );

        expect(container.read(geminiPrimaryModelProvider), explicitModel);
      });
    });

    group('geminiFallbackEnabledProvider', () {
      test('προεπιλογή true όταν δεν υπάρχει ρύθμιση', () async {
        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(geminiFallbackEnabledProvider, (_, _) {});
        container.read(geminiFallbackEnabledProvider);
        await _pumpHydration();

        expect(container.read(geminiFallbackEnabledProvider), isTrue);
      });

      test('hydrate διαβάζει false από "0"', () async {
        await (await _settingsRepo()).saveSetting(
          kGeminiFallbackEnabledSettingKey,
          '0',
        );

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(geminiFallbackEnabledProvider, (_, _) {});
        await _pumpUntil(
          () => container.read(geminiFallbackEnabledProvider) == false,
        );

        expect(container.read(geminiFallbackEnabledProvider), isFalse);
      });

      test('hydrate διαβάζει true από "1"', () async {
        await (await _settingsRepo()).saveSetting(
          kGeminiFallbackEnabledSettingKey,
          '1',
        );

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(geminiFallbackEnabledProvider, (_, _) {});
        await _pumpUntil(
          () => container.read(geminiFallbackEnabledProvider) == true,
        );

        expect(container.read(geminiFallbackEnabledProvider), isTrue);
      });
    });

    group('geminiAutoResubmitEnabledProvider', () {
      test('προεπιλογή false όταν δεν υπάρχει ρύθμιση', () async {
        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(geminiAutoResubmitEnabledProvider, (_, _) {});
        container.read(geminiAutoResubmitEnabledProvider);
        await _pumpHydration();

        expect(container.read(geminiAutoResubmitEnabledProvider), isFalse);
      });

      test('αποθηκεύει και επαναφορτώνει true', () async {
        await (await _settingsRepo()).saveSetting(
          kGeminiAutoResubmitSettingKey,
          '1',
        );

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(geminiAutoResubmitEnabledProvider, (_, _) {});
        await _pumpUntil(
          () => container.read(geminiAutoResubmitEnabledProvider) == true,
        );

        expect(container.read(geminiAutoResubmitEnabledProvider), isTrue);
      });

      test('setEnabled(false) αποθηκεύει "0"', () async {
        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(geminiAutoResubmitEnabledProvider, (_, _) {});
        container.read(geminiAutoResubmitEnabledProvider);
        await _pumpHydration();
        await container
            .read(geminiAutoResubmitEnabledProvider.notifier)
            .setEnabled(true);
        await container
            .read(geminiAutoResubmitEnabledProvider.notifier)
            .setEnabled(false);

        expect(container.read(geminiAutoResubmitEnabledProvider), isFalse);
        expect(
          await (await _settingsRepo()).getSetting(kGeminiAutoResubmitSettingKey),
          '0',
        );
      });
    });

    group('geminiModelsProbeCacheProvider', () {
      test('saveFromResult κάνει σωστό round-trip encode/decode', () async {
        const probeResult = GeminiModelsQuotaProbeResult(
          availableModels: [
            GeminiTextModel(id: 'gemini-flash-latest', displayName: 'Flash'),
          ],
          totalChecked: 3,
          message: '1 διαθέσιμο μοντέλο.',
        );

        final container = _testContainer();
        addTearDown(container.dispose);

        container.listen(geminiModelsProbeCacheProvider, (_, _) {});
        container.read(geminiModelsProbeCacheProvider);
        await _pumpHydration();
        await container
            .read(geminiModelsProbeCacheProvider.notifier)
            .saveFromResult(probeResult);

        final savedState = container.read(geminiModelsProbeCacheProvider);
        expect(savedState, isNotNull);
        expect(savedState!.result.availableModels.length, 1);
        expect(savedState.result.availableModels.first.id, 'gemini-flash-latest');
        expect(savedState.result.totalChecked, 3);
        expect(savedState.result.message, '1 διαθέσιμο μοντέλο.');

        final raw = await (await _settingsRepo()).getSetting(
          kGeminiModelsProbeCacheSettingKey,
        );
        expect(raw, isNotNull);
        final decoded = GeminiModelsProbeCache.decode(raw);
        expect(decoded, isNotNull);
        expect(decoded!.result.availableModels.first.id, 'gemini-flash-latest');
        expect(decoded.result.totalChecked, 3);
        expect(decoded.result.message, '1 διαθέσιμο μοντέλο.');

        container.dispose();
        final container2 = _testContainer();
        addTearDown(container2.dispose);

        container2.listen(geminiModelsProbeCacheProvider, (_, _) {});
        await _pumpUntil(
          () => container2.read(geminiModelsProbeCacheProvider) != null,
        );

        final hydrated = container2.read(geminiModelsProbeCacheProvider);
        expect(hydrated!.result.availableModels.first.id, 'gemini-flash-latest');
        expect(hydrated.result.totalChecked, 3);
      });
    });
  });
}
