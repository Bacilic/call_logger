import 'task.dart';

/// Κριτήριο ταξινόμησης λίστας εκκρεμοτήτων (αντιστοιχεί σε στήλη SQLite).
enum TaskSortOption {
  createdAt,
  dueAt,
  priority,
  department,
  user,
  equipment,
}

/// Κριτήρια φιλτραρίσματος για λίστα εκκρεμοτήτων.
class TaskFilter {
  const TaskFilter({
    this.searchQuery = '',
    List<TaskStatus>? statuses,
    this.startDate,
    this.endDate,
    this.sortBy = TaskSortOption.createdAt,
    this.sortAscending = false,
  }) : statuses = statuses ?? const [TaskStatus.open, TaskStatus.snoozed];

  final String searchQuery;
  final List<TaskStatus> statuses;
  final DateTime? startDate;
  final DateTime? endDate;
  final TaskSortOption sortBy;
  final bool sortAscending;

  /// True όταν δεν είναι επιλεγμένο κανένα status chip.
  bool get allFiltersOff => statuses.isEmpty;

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
    TaskSortOption? sortBy,
    bool? sortAscending,
    bool clearDateRange = false,
  }) {
    return TaskFilter(
      searchQuery: searchQuery ?? this.searchQuery,
      statuses: statuses ?? this.statuses,
      startDate: clearDateRange ? null : (startDate ?? this.startDate),
      endDate: clearDateRange ? null : (endDate ?? this.endDate),
      sortBy: sortBy ?? this.sortBy,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }
}
