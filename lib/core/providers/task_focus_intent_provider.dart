import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Κατανάλωση από [TasksScreen]: scroll στη κάρτα με το συγκεκριμένο `task.id`.
class TaskFocusIntentNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void focus(int taskId) {
    state = taskId;
  }

  void clear() {
    state = null;
  }
}

final taskFocusIntentProvider =
    NotifierProvider<TaskFocusIntentNotifier, int?>(
  TaskFocusIntentNotifier.new,
);
