import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task_snooze_config.dart';
import 'task_service_provider.dart';

/// Φόρτωση και ενημέρωση [TaskSnoozeConfig] μέσω [TaskService] (`app_settings`).
class TaskSnoozeConfigNotifier extends AsyncNotifier<TaskSnoozeConfig> {
  @override
  Future<TaskSnoozeConfig> build() async {
    final service = ref.read(taskServiceProvider);
    return service.getSnoozeConfig();
  }

  /// Αποθήκευση / ενημέρωση ρυθμίσεων στο `app_settings`.
  Future<void> updateConfig(TaskSnoozeConfig config) async {
    final service = ref.read(taskServiceProvider);
    await service.saveTaskSnoozeConfig(config);
    state = AsyncValue.data(config);
  }

  Future<void> save(TaskSnoozeConfig config) => updateConfig(config);
}

final taskSnoozeConfigProvider =
    AsyncNotifierProvider<TaskSnoozeConfigNotifier, TaskSnoozeConfig>(
  TaskSnoozeConfigNotifier.new,
);
