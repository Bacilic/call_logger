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

  /// Αποθηκεύει **μόνο ό,τι άλλαξε** ανάμεσα στην αφετηρία [from] και το [to].
  ///
  /// Το [from] είναι οι ρυθμίσεις **όπως τις φόρτωσε ο διάλογος**. Χωρίς αυτό,
  /// η αποθήκευση θα έγραφε ολόκληρο το δέμα από την εικόνα της οθόνης και θα
  /// έσβηνε την επιλογή που μόλις άλλαξε ο άλλος διαχειριστής.
  ///
  /// Η κατάσταση ενημερώνεται με ό,τι όντως αποθηκεύτηκε — εκεί φαίνονται και
  /// οι αλλαγές του συναδέλφου.
  Future<void> saveChanges({
    required TaskSettingsConfig from,
    required TaskSettingsConfig to,
  }) async {
    final service = ref.read(taskServiceProvider);
    final saved = await service.updateTaskSettingsConfig(
      (current) =>
          TaskSettingsConfig.applyChanges(from: from, to: to, onto: current),
    );
    state = AsyncValue.data(saved);
  }
}

final taskSettingsConfigProvider =
    AsyncNotifierProvider<TaskSettingsConfigNotifier, TaskSettingsConfig>(
      TaskSettingsConfigNotifier.new,
    );
