import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task.dart';
import '../services/task_service.dart';
import 'task_service_provider.dart';

final tasksProvider =
    AsyncNotifierProvider<TasksNotifier, List<Task>>(TasksNotifier.new);

class TasksNotifier extends AsyncNotifier<List<Task>> {
  @override
  Future<List<Task>> build() async {
    final service = ref.read(taskServiceProvider);
    return service.getOpenTasks();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    final service = ref.read(taskServiceProvider);
    state = await AsyncValue.guard(() => service.getOpenTasks());
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
