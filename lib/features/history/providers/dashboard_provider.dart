import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/calls_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_repository.dart';
import '../../../core/database/settings_repository.dart';
import '../../calls/models/call_model.dart';
import '../models/dashboard_filter_model.dart';
import '../models/dashboard_summary_model.dart';

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

/// Ρυθμιζόμενο URL Lansweeper αποθηκευμένο μόνιμα σε `app_settings`.
class LansweeperUrlNotifier extends Notifier<String> {
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
    final raw = await repo.getSetting(kLansweeperUrlSettingKey);
    final normalized = raw?.trim() ?? '';
    if (normalized.isNotEmpty) {
      state = normalized;
      return;
    }
    await repo.saveSetting(kLansweeperUrlSettingKey, kDefaultLansweeperUrl);
    state = kDefaultLansweeperUrl;
  }

  Future<void> setUrl(String value) async {
    final normalized = value.trim();
    final next = normalized.isEmpty ? kDefaultLansweeperUrl : normalized;
    state = next;
    final db = await DatabaseHelper.instance.database;
    await SettingsRepository(db).saveSetting(kLansweeperUrlSettingKey, next);
  }

  Future<void> resetToDefault() => setUrl(kDefaultLansweeperUrl);
}

final lansweeperUrlProvider =
    NotifierProvider.autoDispose<LansweeperUrlNotifier, String>(
  LansweeperUrlNotifier.new,
);

/// Κλήσεις dashboard με τα τρέχοντα φίλτρα, για αναφορά Lansweeper.
final dashboardCallsForReportProvider =
    FutureProvider.autoDispose<List<CallModel>>((ref) async {
  final filter = ref.watch(dashboardFilterProvider);
  final db = await DatabaseHelper.instance.database;
  return CallsRepository(db).getDashboardCalls(filter);
});

/// Ονόματα τμημάτων για dropdown φίλτρου (ταξινόμηση όπως στη βάση).
final dashboardDepartmentsProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await DirectoryRepository(db).getDepartments();
  return rows
      .map((r) => (r['name'] as String?)?.trim() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();
});
