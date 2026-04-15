import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/calls_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_repository.dart';
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
