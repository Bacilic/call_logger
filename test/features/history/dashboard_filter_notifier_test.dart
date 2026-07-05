// Χαρακτηρισμός μη τετριμμένης λογικής DashboardFilterNotifier.
//
//   flutter test test/features/history/dashboard_filter_notifier_test.dart

import 'package:call_logger/features/history/models/dashboard_date_preset.dart';
import 'package:call_logger/features/history/models/dashboard_filter_model.dart';
import 'package:call_logger/features/history/providers/dashboard_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

ProviderContainer _testContainer() {
  return ProviderContainer(
    overrides: callLoggerTestProviderOverrides(),
  );
}

Future<DashboardFilterNotifier> _readyNotifier(
  ProviderContainer container,
) async {
  container.listen(dashboardFilterProvider, (_, _) {});
  final notifier = container.read(dashboardFilterProvider.notifier);
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return notifier;
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('DashboardFilterNotifier — characterization', () {
    test('setCustomDateRange θέτει preset custom με dayOnly όρια', () async {
      final container = _testContainer();
      addTearDown(container.dispose);

      final notifier = await _readyNotifier(container);
      final fromRaw = DateTime(2024, 6, 15, 14, 30, 45);
      final toRaw = DateTime(2024, 6, 20, 8, 15, 0);

      await notifier.setCustomDateRange(fromRaw, toRaw);

      expect(notifier.activeDatePreset, DashboardDatePreset.custom);
      final filter = container.read(dashboardFilterProvider);
      expect(filter.dateFrom, DashboardFilterModel.dayOnly(fromRaw));
      expect(filter.dateTo, DashboardFilterModel.dayOnly(toRaw));
    });

    test('clearDateRange επαναφέρει σε preset all', () async {
      final container = _testContainer();
      addTearDown(container.dispose);

      final notifier = await _readyNotifier(container);
      await notifier.setCustomDateRange(
        DateTime(2024, 1, 1),
        DateTime(2024, 1, 31),
      );

      await notifier.clearDateRange();

      expect(notifier.activeDatePreset, DashboardDatePreset.all);
      final filter = container.read(dashboardFilterProvider);
      expect(filter.dateFrom, isNull);
      expect(filter.dateTo, isNull);
    });

    test('update() ανιχνεύει preset μέσω DashboardDatePreset.detect', () async {
      final container = _testContainer();
      addTearDown(container.dispose);

      final notifier = await _readyNotifier(container);
      await notifier.clearDateRange();
      expect(notifier.activeDatePreset, DashboardDatePreset.all);

      final today = DashboardFilterModel.dayOnly(DateTime.now());
      notifier.update((f) => f.copyWith(dateFrom: today, dateTo: today));
      expect(notifier.activeDatePreset, DashboardDatePreset.today);

      final end = DashboardFilterModel.dayOnly(DateTime.now());
      final start = end.subtract(const Duration(days: 6));
      notifier.update((f) => f.copyWith(dateFrom: start, dateTo: end));
      expect(notifier.activeDatePreset, DashboardDatePreset.last7);
    });

    test(
      'clearAllFilters καθαρίζει τα υπόλοιπα φίλτρα αλλά διατηρεί preset ημερομηνίας',
      () async {
        final container = _testContainer();
        addTearDown(container.dispose);

        final notifier = await _readyNotifier(container);
        final customFrom = DateTime(2024, 3, 10);
        final customTo = DateTime(2024, 3, 25);
        await notifier.setCustomDateRange(customFrom, customTo);

        notifier.update(
          (f) => f.copyWith(
            keyword: 'αναζήτηση',
            department: 'Τμήμα Δοκιμών',
            userName: 'Χρήστης',
            equipmentCode: 'PC-1',
          ),
        );

        notifier.clearAllFilters();

        expect(notifier.activeDatePreset, DashboardDatePreset.custom);
        final filter = container.read(dashboardFilterProvider);
        expect(filter.keyword, isEmpty);
        expect(filter.department, isNull);
        expect(filter.userName, isNull);
        expect(filter.equipmentCode, isNull);
        expect(filter.dateFrom, DashboardFilterModel.dayOnly(customFrom));
        expect(filter.dateTo, DashboardFilterModel.dayOnly(customTo));
      },
    );
  });
}
