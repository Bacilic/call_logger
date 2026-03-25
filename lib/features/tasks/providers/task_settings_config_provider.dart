import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task_settings_config.dart';
import 'task_service_provider.dart';

/// Φόρτωση και ενημέρωση [TaskSettingsConfig] μέσω `TaskService` (`app_settings`).
class TaskSettingsConfigNotifier extends AsyncNotifier<TaskSettingsConfig> {
  @override
  Future<TaskSettingsConfig> build() async {
    final service = ref.read(taskServiceProvider);
    return service.getTaskSettingsConfig();
  }

  /// Αποθήκευση / ενημέρωση ρυθμίσεων στο `app_settings`.
  Future<void> updateConfig(TaskSettingsConfig config) async {
    final service = ref.read(taskServiceProvider);
    await service.saveTaskSettingsConfig(config);
    state = AsyncValue.data(config);
  }

  Future<void> save(TaskSettingsConfig config) => updateConfig(config);
}

final taskSettingsConfigProvider =
    AsyncNotifierProvider<TaskSettingsConfigNotifier, TaskSettingsConfig>(
  TaskSettingsConfigNotifier.new,
);

