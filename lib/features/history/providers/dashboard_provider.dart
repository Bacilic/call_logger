// Providers πίνακα ελέγχου στατιστικών κλήσεων: φίλτρο ημερομηνιών/κριτήρια,
// KPI στατιστικά, κλήσεις αναφοράς Lansweeper, λίστα τμημάτων φίλτρου.
//
// Ρυθμίσεις Lansweeper: lansweeper_settings_provider.dart
// Ρυθμίσεις Gemini: gemini_settings_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/calls_repository.dart';

import '../../../core/database/database_helper.dart';

import '../../../core/database/department_repository.dart';

import '../../../core/services/settings_service.dart';

import '../../calls/models/call_model.dart';

import '../models/dashboard_date_preset.dart';

import '../models/dashboard_filter_model.dart';

import '../models/dashboard_summary_model.dart';



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



/// Τοπική εμφάνιση γραφήματος «Κατανομή Βλαβών» — δεν επηρεάζει [dashboardStatsProvider].

class DashboardExcludeCallsWithoutCategoryNotifier extends Notifier<bool> {

  bool _hydrated = false;



  @override

  bool build() {

    if (!_hydrated) {

      _hydrated = true;

      Future<void>(_hydrateFromSettings);

    }

    return false;

  }



  Future<void> _hydrateFromSettings() async {

    final value =

        await SettingsService().getDashboardExcludeCallsWithoutCategory();

    if (!ref.mounted) return;

    state = value;

  }



  Future<void> set(bool value) async {

    if (state == value) return;

    state = value;

    await SettingsService().setDashboardExcludeCallsWithoutCategory(value);

  }

}



final dashboardExcludeCallsWithoutCategoryProvider =

    NotifierProvider.autoDispose<

      DashboardExcludeCallsWithoutCategoryNotifier,

      bool

    >(DashboardExcludeCallsWithoutCategoryNotifier.new);



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

      return CallsRepository(db).getDashboardStatistics(filter);

    });



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

  final rows = await DepartmentRepository(db).getActiveDepartments();

  return rows

      .map((r) => (r['name'] as String?)?.trim() ?? '')

      .where((s) => s.isNotEmpty)

      .toList();

});

