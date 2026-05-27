import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task_analytics_filter.dart';
import '../models/task_analytics_summary.dart';
import 'task_analytics_date_provider.dart';
import 'task_service_provider.dart';

final taskAnalyticsFilterProvider = Provider.autoDispose<TaskAnalyticsFilter>((
  ref,
) {
  final asyncDates = ref.watch(taskAnalyticsDateProvider);
  return asyncDates.when(
    data: (dates) => TaskAnalyticsFilter(
      startDate: dates.startDate,
      endDate: dates.endDate,
    ),
    loading: () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      return TaskAnalyticsFilter(startDate: today, endDate: today);
    },
    error: (_, _) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      return TaskAnalyticsFilter(startDate: today, endDate: today);
    },
  );
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
