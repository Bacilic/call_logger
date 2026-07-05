import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/settings_repository.dart';
import '../../../core/services/gemini_ticket_service.dart';
import 'app_settings_bool.dart';

class GeminiApiKeyNotifier extends Notifier<String> {
  bool _hydrated = false;

  @override
  String build() {
    if (!_hydrated) {
      _hydrated = true;
      Future<void>(_hydrateFromDb);
    }
    return '';
  }

  Future<void> _hydrateFromDb() async {
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    final raw = await SettingsRepository(db).getSetting(kGeminiApiKeySettingKey);
    if (!ref.mounted) return;
    state = raw?.trim() ?? '';
  }

  Future<void> setApiKey(String value) async {
    final normalized = value.trim();
    state = normalized;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(db).saveSetting(kGeminiApiKeySettingKey, normalized);
  }
}

final geminiApiKeyProvider =
    NotifierProvider.autoDispose<GeminiApiKeyNotifier, String>(
      GeminiApiKeyNotifier.new,
    );

class GeminiPromptTemplateNotifier extends Notifier<String> {
  bool _hydrated = false;

  @override
  String build() {
    if (!_hydrated) {
      _hydrated = true;
      Future<void>(_hydrateFromDb);
    }
    return kDefaultAiPromptTemplate;
  }

  Future<void> _hydrateFromDb() async {
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    final raw =
        (await SettingsRepository(db).getSetting(kGeminiPromptTemplateSettingKey))
            ?.trim() ??
        '';
    if (!ref.mounted) return;
    state = raw.isEmpty ? kDefaultAiPromptTemplate : raw;
  }

  Future<void> setPromptTemplate(String value) async {
    final normalized = value.trim();
    final next = normalized.isEmpty ? kDefaultAiPromptTemplate : normalized;
    state = next;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(
      db,
    ).saveSetting(kGeminiPromptTemplateSettingKey, next);
  }
}

final geminiPromptTemplateProvider =
    NotifierProvider.autoDispose<GeminiPromptTemplateNotifier, String>(
      GeminiPromptTemplateNotifier.new,
    );

/// Προσωπική προεπιλογή προτύπου προτροπής Gemini (`app_settings`, null = δεν έχει οριστεί).
class GeminiPromptTemplateUserDefaultNotifier extends Notifier<String?> {
  bool _hydrated = false;

  @override
  String? build() {
    if (!_hydrated) {
      _hydrated = true;
      Future<void>(_hydrateFromDb);
    }
    return null;
  }

  Future<void> _hydrateFromDb() async {
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    final raw = (await SettingsRepository(db).getSetting(
      kGeminiPromptTemplateUserDefaultSettingKey,
    ))?.trim();
    if (!ref.mounted) return;
    state = raw == null || raw.isEmpty ? null : raw;
  }

  Future<void> setUserDefault(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      state = null;
      return;
    }
    state = normalized;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(db).saveSetting(
      kGeminiPromptTemplateUserDefaultSettingKey,
      normalized,
    );
  }
}

final geminiPromptTemplateUserDefaultProvider =
    NotifierProvider.autoDispose<GeminiPromptTemplateUserDefaultNotifier, String?>(
      GeminiPromptTemplateUserDefaultNotifier.new,
    );

class GeminiEndpointNotifier extends Notifier<String> {
  bool _hydrated = false;

  @override
  String build() {
    if (!_hydrated) {
      _hydrated = true;
      Future<void>(_hydrateFromDb);
    }
    return kDefaultGeminiEndpoint;
  }

  Future<void> _hydrateFromDb() async {
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    final raw =
        (await SettingsRepository(db).getSetting(kGeminiEndpointSettingKey))
            ?.trim() ??
        '';
    if (!ref.mounted) return;
    state = GeminiTicketService.normalizeEndpointTemplate(
      raw.isEmpty ? kDefaultGeminiEndpoint : raw,
    );
  }

  Future<void> setEndpoint(String value) async {
    final normalized = value.trim();
    final next = GeminiTicketService.normalizeEndpointTemplate(
      normalized.isEmpty ? kDefaultGeminiEndpoint : normalized,
    );
    state = next;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(db).saveSetting(kGeminiEndpointSettingKey, next);
  }
}

final geminiEndpointProvider =
    NotifierProvider.autoDispose<GeminiEndpointNotifier, String>(
      GeminiEndpointNotifier.new,
    );

/// Κύριο μοντέλο Gemini (αντικαθιστά το placeholder `{προτεύων μοντέλο}` στο endpoint).
class GeminiPrimaryModelNotifier extends Notifier<String> {
  bool _hydrated = false;

  @override
  String build() {
    if (!_hydrated) {
      _hydrated = true;
      Future<void>(_hydrateFromDb);
    }
    return kDefaultGeminiPrimaryModel;
  }

  Future<void> _hydrateFromDb() async {
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    final repo = SettingsRepository(db);
    var raw =
        (await repo.getSetting(kGeminiPrimaryModelSettingKey))?.trim() ?? '';
    if (raw.isEmpty) {
      final legacyEndpoint =
          (await repo.getSetting(kGeminiEndpointSettingKey))?.trim() ?? '';
      raw = GeminiTicketService.modelFromEndpoint(legacyEndpoint) ??
          kDefaultGeminiPrimaryModel;
    }
    if (!ref.mounted) return;
    state = raw.isEmpty ? kDefaultGeminiPrimaryModel : raw;
  }

  Future<void> setPrimaryModel(String value) async {
    final normalized = value.trim();
    final next =
        normalized.isEmpty ? kDefaultGeminiPrimaryModel : normalized;
    state = next;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(db).saveSetting(
      kGeminiPrimaryModelSettingKey,
      next,
    );
  }
}

final geminiPrimaryModelProvider =
    NotifierProvider.autoDispose<GeminiPrimaryModelNotifier, String>(
      GeminiPrimaryModelNotifier.new,
    );

/// Ενεργοποίηση υποβάθμισης σε εφεδρικό μοντέλο μετά από αποτυχία (503).
class GeminiFallbackEnabledNotifier extends Notifier<bool> {
  bool _hydrated = false;

  @override
  bool build() {
    if (!_hydrated) {
      _hydrated = true;
      Future<void>(_hydrateFromDb);
    }
    return true;
  }

  Future<void> _hydrateFromDb() async {
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    final raw = await SettingsRepository(
      db,
    ).getSetting(kGeminiFallbackEnabledSettingKey);
    if (!ref.mounted) return;
    state = raw == null ? true : parseBoolAppSetting(raw);
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(db).saveSetting(
      kGeminiFallbackEnabledSettingKey,
      value ? '1' : '0',
    );
  }
}

final geminiFallbackEnabledProvider =
    NotifierProvider.autoDispose<GeminiFallbackEnabledNotifier, bool>(
      GeminiFallbackEnabledNotifier.new,
    );

/// Όνομα εφεδρικού μοντέλου Gemini (π.χ. `gemini-2.0-flash`).
class GeminiFallbackModelNotifier extends Notifier<String> {
  bool _hydrated = false;

  @override
  String build() {
    if (!_hydrated) {
      _hydrated = true;
      Future<void>(_hydrateFromDb);
    }
    return kDefaultGeminiFallbackModel;
  }

  Future<void> _hydrateFromDb() async {
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    final raw =
        (await SettingsRepository(db).getSetting(kGeminiFallbackModelSettingKey))
            ?.trim() ??
        '';
    if (!ref.mounted) return;
    state = raw.isEmpty ? kDefaultGeminiFallbackModel : raw;
  }

  Future<void> setFallbackModel(String value) async {
    final normalized = value.trim();
    final next = normalized.isEmpty ? kDefaultGeminiFallbackModel : normalized;
    state = next;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(
      db,
    ).saveSetting(kGeminiFallbackModelSettingKey, next);
  }
}

final geminiFallbackModelProvider =
    NotifierProvider.autoDispose<GeminiFallbackModelNotifier, String>(
      GeminiFallbackModelNotifier.new,
    );

/// Αυτόματη επανυποβολή πρότασης ΤΝ μετά από cooldown ποσόστωσης.
class GeminiAutoResubmitEnabledNotifier extends Notifier<bool> {
  bool _hydrated = false;

  @override
  bool build() {
    if (!_hydrated) {
      _hydrated = true;
      Future<void>(_hydrateFromDb);
    }
    return false;
  }

  Future<void> _hydrateFromDb() async {
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    final raw = await SettingsRepository(
      db,
    ).getSetting(kGeminiAutoResubmitSettingKey);
    if (!ref.mounted) return;
    state = raw == null ? false : parseBoolAppSetting(raw);
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(db).saveSetting(
      kGeminiAutoResubmitSettingKey,
      value ? '1' : '0',
    );
  }
}

final geminiAutoResubmitEnabledProvider =
    NotifierProvider.autoDispose<GeminiAutoResubmitEnabledNotifier, bool>(
      GeminiAutoResubmitEnabledNotifier.new,
    );

/// Cache αποτελέσματος μαζικού ελέγχου ποσόστωσης μοντέλων Gemini.
class GeminiModelsProbeCacheNotifier extends Notifier<GeminiModelsProbeCache?> {
  bool _hydrated = false;

  @override
  GeminiModelsProbeCache? build() {
    if (!_hydrated) {
      _hydrated = true;
      Future<void>(_hydrateFromDb);
    }
    return null;
  }

  Future<void> _hydrateFromDb() async {
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    final raw = await SettingsRepository(db).getSetting(
      kGeminiModelsProbeCacheSettingKey,
    );
    if (!ref.mounted) return;
    state = GeminiModelsProbeCache.decode(raw);
  }

  Future<void> saveFromResult(GeminiModelsQuotaProbeResult result) async {
    final cache = GeminiModelsProbeCache(
      checkedAt: DateTime.now(),
      result: result,
    );
    state = cache;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(db).saveSetting(
      kGeminiModelsProbeCacheSettingKey,
      cache.encode(),
    );
  }
}

final geminiModelsProbeCacheProvider =
    NotifierProvider.autoDispose<GeminiModelsProbeCacheNotifier,
        GeminiModelsProbeCache?>(
  GeminiModelsProbeCacheNotifier.new,
);
