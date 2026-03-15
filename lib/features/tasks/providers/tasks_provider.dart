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
}

/// Κλήσεις pending/open χωρίς αντίστοιχο task. Invalidate μετά δημιουργία tasks.
final orphanCallsProvider = FutureProvider<List<OrphanCall>>((ref) async {
  final service = ref.watch(taskServiceProvider);
  return service.getCallsWithoutTask();
});
