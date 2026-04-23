import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task_analytics_filter.dart';
import '../models/task_analytics_summary.dart';
import 'task_service_provider.dart';
import 'tasks_provider.dart';

final taskAnalyticsFilterProvider = Provider.autoDispose<TaskAnalyticsFilter>((
  ref,
) {
  final filter = ref.watch(taskFilterProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final end = filter.endDate != null
      ? DateTime(
          filter.endDate!.year,
          filter.endDate!.month,
          filter.endDate!.day,
        )
      : today;
  final start = filter.startDate != null
      ? DateTime(
          filter.startDate!.year,
          filter.startDate!.month,
          filter.startDate!.day,
        )
      : end.subtract(const Duration(days: 29));
  return TaskAnalyticsFilter(startDate: start, endDate: end);
});

final taskAnalyticsProvider = FutureProvider.autoDispose<TaskAnalyticsSummary>((
  ref,
) async {
  final analyticsFilter = ref.watch(taskAnalyticsFilterProvider);
  final service = ref.read(taskServiceProvider);
  return service.getTaskAnalytics(
    DateTimeRange(
      start: analyticsFilter.startDate,
      end: analyticsFilter.endDate,
    ),
  );
});
