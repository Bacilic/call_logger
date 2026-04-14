import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';
import '../models/task_filter.dart';
import '../services/task_service.dart';
import 'task_service_provider.dart';

class TaskFilterNotifier extends Notifier<TaskFilter> {
  @override
  TaskFilter build() => TaskFilter.initial();

  void update(TaskFilter Function(TaskFilter) fn) {
    state = fn(state);
  }
}

final taskFilterProvider =
    NotifierProvider<TaskFilterNotifier, TaskFilter>(TaskFilterNotifier.new);

/// Μετρητές ανά κατάσταση (ίδια φίλτρα αναζήτησης/ημερομηνίας, χωρίς status chips).
/// Παρακολουθεί [tasksProvider] ώστε να ενημερώνεται μετά από αλλαγές λίστας.
final taskStatusCountsProvider =
    FutureProvider<Map<TaskStatus, int>>((ref) async {
  final filter = ref.watch(taskFilterProvider);
  ref.watch(tasksProvider);
  final service = ref.read(taskServiceProvider);
  return service.getTaskCounts(filter);
});

final tasksProvider =
    AsyncNotifierProvider<TasksNotifier, List<Task>>(TasksNotifier.new);

/// Πλήθος open+snoozed για badge στο κύριο μενού. Ανανεώνεται όταν αλλάζει η λίστα tasks.
final globalPendingTasksCountProvider = FutureProvider<int>((ref) async {
  ref.watch(tasksProvider);
  return ref.read(taskServiceProvider).getGlobalPendingTasksCount();
});

class TasksNotifier extends AsyncNotifier<List<Task>> {
  @override
  Future<List<Task>> build() async {
    final service = ref.read(taskServiceProvider);
    final filter = ref.watch(taskFilterProvider);
    return service.getFilteredTasks(filter);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    final service = ref.read(taskServiceProvider);
    final filter = ref.read(taskFilterProvider);
    state = await AsyncValue.guard(() => service.getFilteredTasks(filter));
  }

  Future<void> addTask(Task task) async {
    final service = ref.read(taskServiceProvider);
    await service.createTask(task);
    await refresh();
  }

  Future<void> updateTask(Task task) async {
    final service = ref.read(taskServiceProvider);
    await service.updateTask(task);
    await refresh();
  }

  Future<void> deleteTask(int id) async {
    final service = ref.read(taskServiceProvider);
    await service.deleteTask(id);
    await refresh();
    ref.invalidate(orphanCallsProvider);
  }

  Future<void> closeTask(int id, String solutionNotes) async {
    final service = ref.read(taskServiceProvider);
    await service.closeTask(id, solutionNotes);
    await refresh();
  }
}

/// Κλήσεις pending/open χωρίς αντίστοιχο task. Invalidate μετά δημιουργία tasks.
final orphanCallsProvider = FutureProvider<List<OrphanCall>>((ref) async {
  final service = ref.watch(taskServiceProvider);
  return service.getCallsWithoutTask();
});
