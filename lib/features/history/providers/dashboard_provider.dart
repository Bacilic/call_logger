// Providers πίνακα ελέγχου στατιστικών κλήσεων: φίλτρο ημερομηνιών/κριτήρια,
// KPI στατιστικά, κλήσεις αναφοράς Lansweeper, λίστα τμημάτων φίλτρου.
//
// Ρυθμίσεις Lansweeper: lansweeper_settings_provider.dart
// Ρυθμίσεις Gemini: gemini_settings_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/calls_dashboard_repository.dart';

import '../../../core/database/database_helper.dart';

import '../../../core/database/department_repository.dart';

import '../../../core/services/settings_service.dart';

import '../../../core/services/settings_service_analytics_filters.dart';

import '../models/dashboard_date_preset.dart';

import '../models/dashboard_filter_model.dart';

import '../models/dashboard_summary_model.dart';

import '../utils/issue_distribution.dart';

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

    final rawPreset = await settings.analyticsFilters.getDashboardDatePreset();

    final preset =
        DashboardDatePreset.fromStorage(rawPreset) ??
        DashboardDatePreset.defaultPreset;

    DateTime? customFrom;

    DateTime? customTo;

    if (preset == DashboardDatePreset.custom) {
      customFrom = await settings.analyticsFilters.getDashboardCustomDateFrom();

      customTo = await settings.analyticsFilters.getDashboardCustomDateTo();

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
    await SettingsService().analyticsFilters.setDashboardDateFilter(
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

/// Τοπική εμφάνιση γραφήματος «Κατανομή Βλαβών» — δεν επηρεάζει [dashboardStatsProvider].

/// Διακόπτης εμφάνισης του Πίνακα Ελέγχου που θυμάται την επιλογή του χρήστη.
///
/// Κοινός σκελετός: ξεκινά κλειστός ώστε η πρώτη σχεδίαση να μη σταματά στον
/// δίσκο, και παίρνει την αποθηκευμένη τιμή μόλις τη διαβάσουν οι ρυθμίσεις.
/// Κάθε διακόπτης δηλώνει μόνο πού διαβάζει και πού γράφει.
abstract class PersistedDashboardToggle extends Notifier<bool> {
  bool _hydrated = false;

  Future<bool> readSetting(SettingsServiceAnalyticsFilters filters);

  Future<void> writeSetting(
    SettingsServiceAnalyticsFilters filters,
    bool value,
  );

  @override
  bool build() {
    if (!_hydrated) {
      _hydrated = true;
      Future<void>(_hydrateFromSettings);
    }
    return false;
  }

  Future<void> _hydrateFromSettings() async {
    final value = await readSetting(SettingsService().analyticsFilters);
    if (!ref.mounted) return;
    state = value;
  }

  Future<void> set(bool value) async {
    if (state == value) return;
    state = value;
    await writeSetting(SettingsService().analyticsFilters, value);
  }
}

class DashboardExcludeCallsWithoutCategoryNotifier
    extends PersistedDashboardToggle {
  @override
  Future<bool> readSetting(SettingsServiceAnalyticsFilters filters) =>
      filters.getDashboardExcludeCallsWithoutCategory();

  @override
  Future<void> writeSetting(
    SettingsServiceAnalyticsFilters filters,
    bool value,
  ) => filters.setDashboardExcludeCallsWithoutCategory(value);
}

final dashboardExcludeCallsWithoutCategoryProvider =
    NotifierProvider.autoDispose<
      DashboardExcludeCallsWithoutCategoryNotifier,

      bool
    >(DashboardExcludeCallsWithoutCategoryNotifier.new);

/// Απόκρυψη του συγκεντρωτικού «Άγνωστου» στην όψη «χρόνος ανά άτομο» —
/// τοπική εμφάνιση, δεν επηρεάζει τα δεδομένα του [dashboardStatsProvider].
class DashboardHideUnknownCallerNotifier extends PersistedDashboardToggle {
  @override
  Future<bool> readSetting(SettingsServiceAnalyticsFilters filters) =>
      filters.getDashboardHideUnknownCaller();

  @override
  Future<void> writeSetting(
    SettingsServiceAnalyticsFilters filters,
    bool value,
  ) => filters.setDashboardHideUnknownCaller(value);
}

final dashboardHideUnknownCallerProvider =
    NotifierProvider.autoDispose<DashboardHideUnknownCallerNotifier, bool>(
      DashboardHideUnknownCallerNotifier.new,
    );

/// Απόκρυψη του «Άγνωστου» στην κατάταξη «Κορυφαίοι Καλούντες» — χωριστός
/// διακόπτης από την όψη «χρόνος ανά άτομο», αφού οι δύο κάρτες μετρούν άλλο
/// πράγμα (πλήθος κλήσεων έναντι συνολικού χρόνου).
class DashboardHideUnknownTopCallerNotifier extends PersistedDashboardToggle {
  @override
  Future<bool> readSetting(SettingsServiceAnalyticsFilters filters) =>
      filters.getDashboardHideUnknownTopCaller();

  @override
  Future<void> writeSetting(
    SettingsServiceAnalyticsFilters filters,
    bool value,
  ) => filters.setDashboardHideUnknownTopCaller(value);
}

final dashboardHideUnknownTopCallerProvider =
    NotifierProvider.autoDispose<DashboardHideUnknownTopCallerNotifier, bool>(
      DashboardHideUnknownTopCallerNotifier.new,
    );

/// Ποια όψη δείχνει η κάρτα χρόνου — μεμονωμένες κλήσεις ή σύνολο ανά άτομο.
class DashboardLongestCallsModeNotifier extends Notifier<LongestCallsMode> {
  @override
  LongestCallsMode build() => LongestCallsMode.perCall;

  void set(LongestCallsMode value) => state = value;
}

final dashboardLongestCallsModeProvider =
    NotifierProvider.autoDispose<
      DashboardLongestCallsModeNotifier,
      LongestCallsMode
    >(DashboardLongestCallsModeNotifier.new);

/// Τι μετράει η «Κατανομή Βλαβών» — πλήθος κλήσεων ή συνολικός χρόνος.
class DashboardIssueMetricNotifier extends Notifier<IssueDistributionMetric> {
  @override
  IssueDistributionMetric build() => IssueDistributionMetric.count;

  void set(IssueDistributionMetric value) => state = value;
}

final dashboardIssueMetricProvider =
    NotifierProvider.autoDispose<
      DashboardIssueMetricNotifier,
      IssueDistributionMetric
    >(DashboardIssueMetricNotifier.new);

/// Κριτήριο ταξινόμησης της όψης «χρόνος ανά άτομο» (κλικ στις κεφαλίδες).
class DashboardCallerTimeSortNotifier extends Notifier<CallerTimeSort> {
  @override
  CallerTimeSort build() => CallerTimeSort.total;

  void set(CallerTimeSort value) => state = value;
}

final dashboardCallerTimeSortProvider =
    NotifierProvider.autoDispose<
      DashboardCallerTimeSortNotifier,
      CallerTimeSort
    >(DashboardCallerTimeSortNotifier.new);

/// Στατιστικά κλήσεων με βάση το τρέχον [DashboardFilterModel].

final dashboardStatsProvider =
    FutureProvider.autoDispose<DashboardSummaryModel>((ref) async {
      ref.watch(
        dashboardFilterProvider.select(
          (filter) => (
            filter.keyword,

            filter.dateFrom,

            filter.dateTo,

            filter.department,

            filter.userName,

            filter.equipmentCode,
          ),
        ),
      );

      final filter = ref.read(dashboardFilterProvider);

      final db = await DatabaseHelper.instance.database;

      return CallsDashboardRepository(db).getDashboardStatistics(filter);
    });

/// Ονόματα τμημάτων για dropdown φίλτρου (ταξινόμηση όπως στη βάση).

final dashboardDepartmentsProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  final db = await DatabaseHelper.instance.database;

  final rows = await DepartmentRepository(db).getActiveDepartments();

  return rows
      .map((r) => (r['name'] as String?)?.trim() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();
});
