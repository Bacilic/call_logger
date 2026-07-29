import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/task_focus_intent_provider.dart';
import '../providers/task_settings_config_provider.dart';
import '../providers/tasks_provider.dart';
import 'task_card.dart';
import 'task_filter_bar.dart';
import 'tasks_screen_actions.dart';
import 'tasks_screen_support_widgets.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  final Map<int, GlobalKey> _taskScrollKeys = {};

  GlobalKey _keyForTaskId(int id) =>
      _taskScrollKeys.putIfAbsent(id, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    ref.listen<int?>(taskFocusIntentProvider, (previous, next) {
      if (next == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = _taskScrollKeys[next]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            alignment: 0.15,
          );
        }
        ref.read(taskFocusIntentProvider.notifier).clear();
      });
    });

    final asyncTasks = ref.watch(tasksProvider);
    ref.watch(taskSettingsConfigProvider);
    final totalTasksAsync = ref.watch(totalTasksCountProvider);
    // Διατήρηση τελευταίας γνωστής τιμής κατά το reload — αποφυγή απενεργοποίησης φίλτρων.
    final filtersEnabled = (totalTasksAsync.value ?? 0) > 0;
    final canCreateTask = !asyncTasks.hasError;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Εκκρεμότητες'),
        actions: [
          IconButton(
            icon: const Icon(Icons.schedule),
            tooltip: 'Ρυθμίσεις εκκρεμοτήτων',
            onPressed: () => openTaskSettings(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: canCreateTask ? () => openNewTaskForm(context, ref) : null,
        child: const Icon(Icons.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TaskFilterBar(filtersEnabled: filtersEnabled),
          Expanded(
            child: asyncTasks.when(
              loading: () => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Φόρτωση εκκρεμοτήτων...'),
                  ],
                ),
              ),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        err.toString(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () =>
                            ref.read(tasksProvider.notifier).refresh(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Επανάληψη'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (tasks) {
                final totalTaskCount = totalTasksAsync.value ?? 0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OrphanCallsBanner(
                      onCreateTasks: () => createTasksForOrphans(context, ref),
                    ),
                    Expanded(
                      child: tasks.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    totalTaskCount == 0
                                        ? Icons.task_alt_outlined
                                        : Icons.search_off_outlined,
                                    size: 64,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    totalTaskCount == 0
                                        ? 'Δεν υπάρχουν εκκρεμότητες αυτή τη στιγμή'
                                        : 'Δεν βρέθηκαν εκκρεμότητες με τα επιλεγμένα κριτήρια',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () =>
                                  ref.read(tasksProvider.notifier).refresh(),
                              // Προσθήκη bottom padding για να μην επικαλύπτεται η τελευταία κάρτα από το FAB
                              child: ListView.builder(
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  88 +
                                      MediaQuery.of(context).viewPadding.bottom,
                                ),
                                itemCount: tasks.length,
                                itemBuilder: (context, index) {
                                  final task = tasks[index];
                                  final Key scrollKey = task.id != null
                                      ? _keyForTaskId(task.id!)
                                      : ValueKey<int>(index);
                                  return KeyedSubtree(
                                    key: scrollKey,
                                    child: TaskCard(
                                      task: task,
                                      onEdit: () =>
                                          editTask(context, ref, task),
                                      onSnooze: () =>
                                          snoozeTask(context, ref, task),
                                      onDelete: () => deleteTaskWithCountdown(
                                        context,
                                        ref,
                                        task,
                                      ),
                                      onComplete: () =>
                                          completeTask(context, ref, task),
                                      onEditCaller: () =>
                                          editTaskCaller(context, ref, task),
                                      onEditDepartment: () =>
                                          editTaskDepartment(
                                            context,
                                            ref,
                                            task,
                                          ),
                                      onEditEquipment: () =>
                                          editTaskEquipment(context, ref, task),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
