class TaskAnalyticsOriginSlice {
  const TaskAnalyticsOriginSlice({
    required this.origin,
    required this.label,
    required this.count,
    required this.percent,
  });

  final String origin;
  final String label;
  final int count;
  final double percent;
}

class TaskAnalyticsBacklogPoint {
  const TaskAnalyticsBacklogPoint({
    required this.date,
    required this.createdCount,
    required this.closedCount,
    required this.delta,
    required this.runningDelta,
  });

  final DateTime date;
  final int createdCount;
  final int closedCount;
  final int delta;
  final int runningDelta;
}

class TaskAnalyticsSummary {
  const TaskAnalyticsSummary({
    required this.rangeStart,
    required this.rangeEnd,
    required this.activeNowCount,
    required this.activeCreatedInRangeCount,
    required this.createdInRangeCount,
    required this.closedInRangeCount,
    required this.cancelledInRangeCount,
    required this.overdueActiveCount,
    required this.overdueInRangeCount,
    required this.overdueRateActive,
    required this.overdueRateRange,
    required this.completionRateInRange,
    required this.cancellationRateInRange,
    required this.avgCompletionSeconds,
    required this.avgSnoozesPerTask,
    required this.originDistribution,
    required this.backlogGrowth,
    required this.sparklineActive,
    required this.sparklineClosed,
    required this.sparklineCancelled,
    required this.sparklineOverdue,
    required this.sparklineCompletionRate,
  });

  final DateTime rangeStart;
  final DateTime rangeEnd;
  final int activeNowCount;
  final int activeCreatedInRangeCount;
  final int createdInRangeCount;
  final int closedInRangeCount;
  final int cancelledInRangeCount;
  final int overdueActiveCount;
  final int overdueInRangeCount;
  final double overdueRateActive;
  final double overdueRateRange;
  final double completionRateInRange;
  final double cancellationRateInRange;
  final double avgCompletionSeconds;
  final double avgSnoozesPerTask;
  final List<TaskAnalyticsOriginSlice> originDistribution;
  final List<TaskAnalyticsBacklogPoint> backlogGrowth;
  final List<double> sparklineActive;
  final List<double> sparklineClosed;
  final List<double> sparklineCancelled;
  final List<double> sparklineOverdue;
  final List<double> sparklineCompletionRate;
}
