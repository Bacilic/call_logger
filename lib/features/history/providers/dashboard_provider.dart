import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/calls_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_repository.dart';
import '../../../core/database/settings_repository.dart';
import '../../../core/services/gemini_ticket_service.dart';
import '../../../core/services/settings_service.dart';
import '../../calls/models/call_model.dart';
import '../models/dashboard_date_preset.dart';
import '../models/dashboard_filter_model.dart';
import '../models/dashboard_summary_model.dart';
import '../widgets/lansweeper/lansweeper_url_rules.dart';

/// Notifier για τα κριτήρια φίλτρου του dashboard στατιστικών.
class DashboardFilterNotifier extends Notifier<DashboardFilterModel> {
  bool _hydrated = false;
  DashboardDatePreset _activePreset = DashboardDatePreset.defaultPreset;
  DateTime? _storedCustomFrom;
  DateTime? _storedCustomTo;

  DashboardDatePreset get activeDatePreset => _activePreset;

  @override
  DashboardFilterModel build() {
    if (!_hydrated) {
      _hydrated = true;
      Future<void>(_hydrateFromSettings);
    }
    return DashboardDatePreset.applyToFilter(
      const DashboardFilterModel(),
      DashboardDatePreset.defaultPreset,
    );
  }

  Future<void> _hydrateFromSettings() async {
    final settings = SettingsService();
    final rawPreset = await settings.getDashboardDatePreset();
    final preset =
        DashboardDatePreset.fromStorage(rawPreset) ??
        DashboardDatePreset.defaultPreset;
    DateTime? customFrom;
    DateTime? customTo;
    if (preset == DashboardDatePreset.custom) {
      customFrom = await settings.getDashboardCustomDateFrom();
      customTo = await settings.getDashboardCustomDateTo();
      if (customFrom == null || customTo == null) {
        await _applyPreset(DashboardDatePreset.defaultPreset, persist: false);
        return;
      }
      _storedCustomFrom = customFrom;
      _storedCustomTo = customTo;
    }
    if (!ref.mounted) return;
    _activePreset = preset;
    state = DashboardDatePreset.applyToFilter(
      state,
      preset,
      customFrom: customFrom,
      customTo: customTo,
    );
  }

  Future<void> _persistPreset(
    DashboardDatePreset preset, {
    DateTime? customFrom,
    DateTime? customTo,
  }) async {
    await SettingsService().setDashboardDateFilter(
      preset: preset.storageValue,
      customFrom: customFrom,
      customTo: customTo,
    );
  }

  Future<void> _applyPreset(
    DashboardDatePreset preset, {
    DateTime? customFrom,
    DateTime? customTo,
    bool persist = true,
  }) async {
    _activePreset = preset;
    if (preset == DashboardDatePreset.custom) {
      _storedCustomFrom = customFrom;
      _storedCustomTo = customTo;
    }
    state = DashboardDatePreset.applyToFilter(
      state,
      preset,
      customFrom: customFrom,
      customTo: customTo,
    );
    if (persist) {
      await _persistPreset(
        preset,
        customFrom: customFrom ?? state.dateFrom,
        customTo: customTo ?? state.dateTo,
      );
    }
  }

  void update(DashboardFilterModel Function(DashboardFilterModel) fn) {
    state = fn(state);
    final detected = DashboardDatePreset.detect(state);
    if (detected != null) {
      _activePreset = detected;
    }
  }

  Future<void> setDatePreset(DashboardDatePreset preset) async {
    await _applyPreset(preset);
  }

  Future<void> setCustomDateRange(DateTime from, DateTime to) async {
    final start = DashboardFilterModel.dayOnly(from);
    final end = DashboardFilterModel.dayOnly(to);
    await _applyPreset(
      DashboardDatePreset.custom,
      customFrom: start,
      customTo: end,
    );
  }

  Future<void> clearDateRange() async {
    await _applyPreset(DashboardDatePreset.all);
  }

  Future<void> clearAllFilters() async {
    final preset = _activePreset;
    final customFrom = _storedCustomFrom;
    final customTo = _storedCustomTo;
    state = DashboardDatePreset.applyToFilter(
      const DashboardFilterModel(),
      preset,
      customFrom: customFrom,
      customTo: customTo,
    );
  }
}

final dashboardFilterProvider =
    NotifierProvider.autoDispose<DashboardFilterNotifier, DashboardFilterModel>(
      DashboardFilterNotifier.new,
    );

/// Στατιστικά κλήσεων με βάση το τρέχον [DashboardFilterModel].
final dashboardStatsProvider =
    FutureProvider.autoDispose<DashboardSummaryModel>((ref) async {
      final filter = ref.watch(dashboardFilterProvider);
      final db = await DatabaseHelper.instance.database;
      return CallsRepository(db).getDashboardStatistics(filter);
    });

/// URL τελικού σημείου API Lansweeper (`api.aspx`) — μόνο για Άμεση καταχώρηση.
class LansweeperApiUrlNotifier extends Notifier<String> {
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
    final repo = SettingsRepository(db);
    final apiRaw =
        (await repo.getSetting(kLansweeperApiUrlSettingKey))?.trim() ?? '';
    if (!ref.mounted) return;
    if (apiRaw.isNotEmpty && LansweeperUrlRules.isApiEndpointUrl(apiRaw)) {
      state = apiRaw;
      return;
    }
    final legacy =
        (await repo.getSetting(kLansweeperUrlSettingKey))?.trim() ?? '';
    if (!ref.mounted) return;
    if (legacy.isNotEmpty && LansweeperUrlRules.isApiEndpointUrl(legacy)) {
      state = legacy;
      return;
    }
    state = '';
  }

  Future<void> setApiUrl(String value) async {
    final normalized = value.trim();
    state = normalized;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(
      db,
    ).saveSetting(kLansweeperApiUrlSettingKey, normalized);
  }
}

final lansweeperApiUrlProvider =
    NotifierProvider.autoDispose<LansweeperApiUrlNotifier, String>(
      LansweeperApiUrlNotifier.new,
    );

/// URL φόρμας νέου αιτήματος (browser) — για «Αντιγραφή & άνοιγμα».
class LansweeperTicketFormUrlNotifier extends Notifier<String> {
  bool _hydrated = false;

  @override
  String build() {
    if (!_hydrated) {
      _hydrated = true;
      Future<void>(_hydrateFromDb);
    }
    return kDefaultLansweeperUrl;
  }

  Future<void> _hydrateFromDb() async {
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    final repo = SettingsRepository(db);
    final ticketRaw =
        (await repo.getSetting(kLansweeperUrlSettingKey))?.trim() ?? '';
    if (!ref.mounted) return;
    if (ticketRaw.isNotEmpty) {
      state = ticketRaw;
      return;
    }
    final apiRaw =
        (await repo.getSetting(kLansweeperApiUrlSettingKey))?.trim() ?? '';
    if (!ref.mounted) return;
    if (apiRaw.isNotEmpty && !LansweeperUrlRules.isApiEndpointUrl(apiRaw)) {
      state = apiRaw;
      return;
    }
    state = kDefaultLansweeperUrl;
  }

  Future<void> setTicketFormUrl(String value) async {
    final normalized = value.trim();
    final next = normalized.isEmpty ? kDefaultLansweeperUrl : normalized;
    state = next;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(db).saveSetting(kLansweeperUrlSettingKey, next);
  }

  Future<void> resetToDefault() => setTicketFormUrl(kDefaultLansweeperUrl);
}

final lansweeperTicketFormUrlProvider =
    NotifierProvider.autoDispose<LansweeperTicketFormUrlNotifier, String>(
      LansweeperTicketFormUrlNotifier.new,
    );

/// URL προβολής υπάρχοντος ticket στον browser (`{tid}` placeholder).
class LansweeperTicketViewUrlNotifier extends Notifier<String> {
  bool _hydrated = false;

  @override
  String build() {
    if (!_hydrated) {
      _hydrated = true;
      Future<void>(_hydrateFromDb);
    }
    return kDefaultLansweeperTicketViewUrl;
  }

  Future<void> _hydrateFromDb() async {
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    final saved =
        (await SettingsRepository(db).getSetting(kLansweeperTicketViewUrlSettingKey))
            ?.trim() ??
        '';
    if (!ref.mounted) return;
    state = saved.isNotEmpty ? saved : kDefaultLansweeperTicketViewUrl;
  }

  Future<void> setTicketViewUrl(String value) async {
    final normalized = value.trim();
    final next = normalized.isEmpty
        ? kDefaultLansweeperTicketViewUrl
        : normalized;
    state = next;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(
      db,
    ).saveSetting(kLansweeperTicketViewUrlSettingKey, next);
  }
}

final lansweeperTicketViewUrlProvider =
    NotifierProvider.autoDispose<LansweeperTicketViewUrlNotifier, String>(
      LansweeperTicketViewUrlNotifier.new,
    );

class LansweeperApiKeyNotifier extends Notifier<String> {
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
    final repo = SettingsRepository(db);
    final raw = await repo.getSetting(kLansweeperApiKeySettingKey);
    if (!ref.mounted) return;
    state = raw?.trim() ?? '';
  }

  Future<void> setApiKey(String value) async {
    final normalized = value.trim();
    state = normalized;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(
      db,
    ).saveSetting(kLansweeperApiKeySettingKey, normalized);
  }
}

final lansweeperApiKeyProvider =
    NotifierProvider.autoDispose<LansweeperApiKeyNotifier, String>(
      LansweeperApiKeyNotifier.new,
    );

/// Μόνιμο όνομα χρήστη πράκτορα Lansweeper (`app_settings`).
class LansweeperAgentUsernameNotifier extends Notifier<String> {
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
    final repo = SettingsRepository(db);
    final raw = await repo.getSetting(kLansweeperAgentUsernameSettingKey);
    if (!ref.mounted) return;
    state = raw?.trim() ?? '';
  }

  Future<void> setAgentUsername(String value) async {
    final normalized = value.trim();
    state = normalized;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(
      db,
    ).saveSetting(kLansweeperAgentUsernameSettingKey, normalized);
  }
}

final lansweeperAgentUsernameProvider =
    NotifierProvider.autoDispose<LansweeperAgentUsernameNotifier, String>(
      LansweeperAgentUsernameNotifier.new,
    );

bool parseBoolAppSetting(String? raw) {
  final t = (raw ?? '').trim().toLowerCase();
  return t == '1' || t == 'true' || t == 'yes';
}

/// Ανάγνωση ρύθμισης από βάση — αξιόπιστη μετά κλείσιμο διαλόγου ρυθμίσεων
/// (αποφυγή race του autoDispose provider πριν το async hydrate).
Future<bool> readLansweeperOpenTicketAfterApiSubmitSetting() async {
  final db = await DatabaseHelper.instance.database;
  final raw = await SettingsRepository(
    db,
  ).getSetting(kLansweeperOpenTicketAfterApiSubmitSettingKey);
  return parseBoolAppSetting(raw);
}

/// Αυτόματο άνοιγμα σελίδας σύνδεσης πριν τη φόρμα αιτήματος (ίδιος host).
class LansweeperHelpdeskAutoLoginNotifier extends Notifier<bool> {
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
    ).getSetting(kLansweeperHelpdeskAutoLoginSettingKey);
    if (!ref.mounted) return;
    state = parseBoolAppSetting(raw);
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(db).saveSetting(
      kLansweeperHelpdeskAutoLoginSettingKey,
      value ? '1' : '0',
    );
  }
}

final lansweeperHelpdeskAutoLoginProvider =
    NotifierProvider.autoDispose<LansweeperHelpdeskAutoLoginNotifier, bool>(
      LansweeperHelpdeskAutoLoginNotifier.new,
    );

/// Μετά επιτυχή «Άμεση Καταχώρηση», άνοιγμα ticket στον περιηγητή (URL προβολής).
class LansweeperOpenTicketAfterApiSubmitNotifier extends Notifier<bool> {
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
    ).getSetting(kLansweeperOpenTicketAfterApiSubmitSettingKey);
    if (!ref.mounted) return;
    state = parseBoolAppSetting(raw);
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(db).saveSetting(
      kLansweeperOpenTicketAfterApiSubmitSettingKey,
      value ? '1' : '0',
    );
  }
}

final lansweeperOpenTicketAfterApiSubmitProvider =
    NotifierProvider<LansweeperOpenTicketAfterApiSubmitNotifier, bool>(
      LansweeperOpenTicketAfterApiSubmitNotifier.new,
    );

/// URL σελίδας σύνδεσης Help Desk (`login.aspx`).
class LansweeperHelpdeskLoginUrlNotifier extends Notifier<String> {
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
    final repo = SettingsRepository(db);
    final saved =
        (await repo.getSetting(kLansweeperHelpdeskLoginUrlSettingKey))?.trim() ??
        '';
    if (!ref.mounted) return;
    if (saved.isNotEmpty &&
        LansweeperUrlRules.isBrowserLaunchableUrl(saved)) {
      state = saved;
      return;
    }
    final ticket =
        (await repo.getSetting(kLansweeperUrlSettingKey))?.trim() ?? '';
    if (!ref.mounted) return;
    state = LansweeperUrlRules.loginUrlDerivedFromTicketFormUrl(
      ticket.isNotEmpty ? ticket : kDefaultLansweeperUrl,
    );
  }

  Future<void> setLoginUrl(String value) async {
    final normalized = value.trim();
    state = normalized;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(
      db,
    ).saveSetting(kLansweeperHelpdeskLoginUrlSettingKey, normalized);
  }
}

final lansweeperHelpdeskLoginUrlProvider =
    NotifierProvider.autoDispose<LansweeperHelpdeskLoginUrlNotifier, String>(
      LansweeperHelpdeskLoginUrlNotifier.new,
    );

/// Όνομα χρήστη web console Lansweeper (όχι πράκτορας API).
class LansweeperHelpdeskWebUsernameNotifier extends Notifier<String> {
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
    final raw = await SettingsRepository(
      db,
    ).getSetting(kLansweeperHelpdeskWebUsernameSettingKey);
    if (!ref.mounted) return;
    state = raw?.trim() ?? '';
  }

  Future<void> setUsername(String value) async {
    final normalized = value.trim();
    state = normalized;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(
      db,
    ).saveSetting(kLansweeperHelpdeskWebUsernameSettingKey, normalized);
  }
}

final lansweeperHelpdeskWebUsernameProvider = NotifierProvider.autoDispose<
    LansweeperHelpdeskWebUsernameNotifier,
    String
>(LansweeperHelpdeskWebUsernameNotifier.new);

/// Κωδικός web console Lansweeper (αποθηκεύεται όπως το API key, τοπικά).
class LansweeperHelpdeskWebPasswordNotifier extends Notifier<String> {
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
    final raw = await SettingsRepository(
      db,
    ).getSetting(kLansweeperHelpdeskWebPasswordSettingKey);
    if (!ref.mounted) return;
    state = raw ?? '';
  }

  Future<void> setPassword(String value) async {
    state = value;
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(
      db,
    ).saveSetting(kLansweeperHelpdeskWebPasswordSettingKey, value);
  }
}

final lansweeperHelpdeskWebPasswordProvider = NotifierProvider.autoDispose<
    LansweeperHelpdeskWebPasswordNotifier,
    String
>(LansweeperHelpdeskWebPasswordNotifier.new);

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
    return kDefaultGeminiPromptTemplate;
  }

  Future<void> _hydrateFromDb() async {
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    final raw =
        (await SettingsRepository(db).getSetting(kGeminiPromptTemplateSettingKey))
            ?.trim() ??
        '';
    if (!ref.mounted) return;
    state = raw.isEmpty ? kDefaultGeminiPromptTemplate : raw;
  }

  Future<void> setPromptTemplate(String value) async {
    final normalized = value.trim();
    final next = normalized.isEmpty ? kDefaultGeminiPromptTemplate : normalized;
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

/// Κλήσεις dashboard με τα τρέχοντα φίλτρα, για αναφορά Lansweeper.
final dashboardCallsForReportProvider =
    FutureProvider.autoDispose<List<CallModel>>((ref) async {
      final filter = ref.watch(dashboardFilterProvider);
      final db = await DatabaseHelper.instance.database;
      return CallsRepository(db).getDashboardCalls(filter);
    });

/// Ονόματα τμημάτων για dropdown φίλτρου (ταξινόμηση όπως στη βάση).
final dashboardDepartmentsProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await DirectoryRepository(db).getActiveDepartments();
  return rows
      .map((r) => (r['name'] as String?)?.trim() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();
});
