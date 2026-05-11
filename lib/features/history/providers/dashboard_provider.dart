import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/calls_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_repository.dart';
import '../../../core/database/settings_repository.dart';
import '../../calls/models/call_model.dart';
import '../models/dashboard_filter_model.dart';
import '../models/dashboard_summary_model.dart';
import '../widgets/lansweeper/lansweeper_url_rules.dart';

/// Notifier για τα κριτήρια φίλτρου του dashboard στατιστικών.
class DashboardFilterNotifier extends Notifier<DashboardFilterModel> {
  @override
  DashboardFilterModel build() => const DashboardFilterModel();

  void update(DashboardFilterModel Function(DashboardFilterModel) fn) {
    state = fn(state);
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
    final repo = SettingsRepository(db);
    final apiRaw =
        (await repo.getSetting(kLansweeperApiUrlSettingKey))?.trim() ?? '';
    if (apiRaw.isNotEmpty && LansweeperUrlRules.isApiEndpointUrl(apiRaw)) {
      state = apiRaw;
      return;
    }
    final legacy =
        (await repo.getSetting(kLansweeperUrlSettingKey))?.trim() ?? '';
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
    final repo = SettingsRepository(db);
    final ticketRaw =
        (await repo.getSetting(kLansweeperUrlSettingKey))?.trim() ?? '';
    if (ticketRaw.isNotEmpty) {
      state = ticketRaw;
      return;
    }
    final apiRaw =
        (await repo.getSetting(kLansweeperApiUrlSettingKey))?.trim() ?? '';
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
    await SettingsRepository(db).saveSetting(kLansweeperUrlSettingKey, next);
  }

  Future<void> resetToDefault() => setTicketFormUrl(kDefaultLansweeperUrl);
}

final lansweeperTicketFormUrlProvider =
    NotifierProvider.autoDispose<LansweeperTicketFormUrlNotifier, String>(
      LansweeperTicketFormUrlNotifier.new,
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
    final repo = SettingsRepository(db);
    final raw = await repo.getSetting(kLansweeperApiKeySettingKey);
    state = raw?.trim() ?? '';
  }

  Future<void> setApiKey(String value) async {
    final normalized = value.trim();
    state = normalized;
    final db = await DatabaseHelper.instance.database;
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
    final repo = SettingsRepository(db);
    final raw = await repo.getSetting(kLansweeperAgentUsernameSettingKey);
    state = raw?.trim() ?? '';
  }

  Future<void> setAgentUsername(String value) async {
    final normalized = value.trim();
    state = normalized;
    final db = await DatabaseHelper.instance.database;
    await SettingsRepository(
      db,
    ).saveSetting(kLansweeperAgentUsernameSettingKey, normalized);
  }
}

final lansweeperAgentUsernameProvider =
    NotifierProvider.autoDispose<LansweeperAgentUsernameNotifier, String>(
      LansweeperAgentUsernameNotifier.new,
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
  final rows = await DirectoryRepository(db).getDepartments();
  return rows
      .map((r) => (r['name'] as String?)?.trim() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();
});
