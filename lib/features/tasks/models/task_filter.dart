import 'task.dart';

/// Κριτήρια φιλτραρίσματος για λίστα εκκρεμοτήτων.
class TaskFilter {
  const TaskFilter({
    this.searchQuery = '',
    List<TaskStatus>? statuses,
    this.startDate,
    this.endDate,
  }) : statuses = statuses ?? const [TaskStatus.open, TaskStatus.snoozed];

  final String searchQuery;
  final List<TaskStatus> statuses;
  final DateTime? startDate;
  final DateTime? endDate;

  /// Προεπιλογή: κείμενο κενό, statuses open + snoozed, χωρίς ημερομηνίες.
  factory TaskFilter.initial() => TaskFilter(
        searchQuery: '',
        statuses: const [TaskStatus.open, TaskStatus.snoozed],
      );

  TaskFilter copyWith({
    String? searchQuery,
    List<TaskStatus>? statuses,
    DateTime? startDate,
    DateTime? endDate,
    bool clearDateRange = false,
  }) {
    return TaskFilter(
      searchQuery: searchQuery ?? this.searchQuery,
      statuses: statuses ?? this.statuses,
      startDate: clearDateRange ? null : (startDate ?? this.startDate),
      endDate: clearDateRange ? null : (endDate ?? this.endDate),
    );
  }
}
