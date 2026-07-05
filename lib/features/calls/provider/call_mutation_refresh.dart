import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../history/providers/dashboard_provider.dart';
import '../../history/providers/history_provider.dart';
import '../../tasks/providers/task_analytics_provider.dart';
import '../../tasks/providers/tasks_provider.dart';
import 'calls_dashboard_providers.dart';

/// Κοινή ακύρωση providers μετά από εισαγωγή/τροποποίηση κλήσης.
void refreshAfterCallMutation(
  Ref ref, {
  int? callerId,
  String? equipmentCode,
  bool invalidateHistory = true,
}) {
  if (!ref.mounted) return;
  if (invalidateHistory) {
    ref.invalidate(historyCallsProvider);
    ref.invalidate(historyCategoryDateCallCountProvider);
    ref.invalidate(totalCallsCountProvider);
    ref.invalidate(dashboardStatsProvider);
    ref.invalidate(dashboardCallsForReportProvider);
  }
  ref.invalidate(globalRecentCallsProvider);
  if (callerId != null) {
    ref.invalidate(recentCallsProvider(callerId));
  }
  final code = equipmentCode?.trim();
  if (code != null && code.isNotEmpty) {
    ref.invalidate(recentCallsByEquipmentProvider(code));
  }
}

/// Ακύρωση providers εργασιών μετά από δημιουργία/διαγραφή task.
void invalidateTaskListProviders(Ref ref) {
  if (!ref.mounted) return;
  ref.invalidate(tasksProvider);
  ref.invalidate(totalTasksCountProvider);
  ref.invalidate(orphanCallsProvider);
  ref.invalidate(taskAnalyticsProvider);
}
