import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task.dart';
import '../providers/task_service_provider.dart';
import '../providers/tasks_provider.dart';
import 'task_card.dart';
import 'task_close_dialog.dart';
import 'task_form_dialog.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTasks = ref.watch(tasksProvider);
    final asyncOrphans = ref.watch(orphanCallsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Εκκρεμότητες'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openNewTaskForm(context, ref),
        child: const Icon(Icons.add),
      ),
      body: asyncTasks.when(
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              asyncOrphans.when(
                data: (orphans) {
                  if (orphans.isEmpty) return const SizedBox.shrink();
                  return _OrphanCallsBanner(
                    count: orphans.length,
                    onCreateTasks: () => _createTasksForOrphans(context, ref),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
              Expanded(
                child: tasks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.task_alt_outlined,
                              size: 64,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Δεν υπάρχουν εκκρεμότητες αυτή τη στιγμή',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () =>
                            ref.read(tasksProvider.notifier).refresh(),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 16),
                          itemCount: tasks.length,
                          itemBuilder: (context, index) {
                            final task = tasks[index];
                            return TaskCard(
                              task: task,
                              onEdit: () => _onEdit(context, ref, task),
                              onSnooze: () => _onSnooze(context, ref, task),
                              onDelete: () => _onDelete(context, ref, task),
                              onComplete: () => _onComplete(context, ref, task),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _createTasksForOrphans(
      BuildContext context, WidgetRef ref) async {
    final service = ref.read(taskServiceProvider);
    final created = await service.createTasksForOrphanCalls();
    if (!context.mounted) return;
    ref.invalidate(tasksProvider);
    ref.invalidate(orphanCallsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          created > 0
              ? 'Δημιουργήθηκαν $created εκκρεμότητες.'
              : 'Δεν βρέθηκαν κλήσεις χωρίς εκκρεμότητα.',
        ),
      ),
    );
  }

  static Future<void> _openNewTaskForm(BuildContext context, WidgetRef ref) async {
    final result = await showTaskFormDialog(context, task: null);
    if (!context.mounted || result == null) return;
    await ref.read(tasksProvider.notifier).addTask(result);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Εκκρεμότητα δημιουργήθηκε.')),
    );
  }

  static Future<void> _onEdit(BuildContext context, WidgetRef ref, Task task) async {
    final result = await showTaskFormDialog(context, task: task);
    if (!context.mounted || result == null) return;
    if (result.id != null) {
      await ref.read(tasksProvider.notifier).updateTask(result);
    } else {
      await ref.read(tasksProvider.notifier).addTask(result);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Εκκρεμότητα ενημερώθηκε.')),
    );
  }

  static Future<void> _onSnooze(BuildContext context, WidgetRef ref, Task task) async {
    final date = await showDatePicker(
      context: context,
      initialDate: task.dueDateTime ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (!context.mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(task.dueDateTime ?? DateTime.now()),
    );
    if (!context.mounted || time == null) return;
    final newDue = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    await ref.read(tasksProvider.notifier).updateTask(
          task.copyWith(dueDate: newDue.toIso8601String()),
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ημερομηνία αναβλήθηκε.')),
    );
  }

  static Future<void> _onDelete(BuildContext context, WidgetRef ref, Task task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή εκκρεμότητας'),
        content: const Text('Να διαγραφεί αυτή η εκκρεμότητα;'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Όχι'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ναι'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    if (task.id == null) return;
    await ref.read(tasksProvider.notifier).deleteTask(task.id!);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Εκκρεμότητα διαγράφηκε.')),
    );
  }

  static Future<void> _onComplete(BuildContext context, WidgetRef ref, Task task) async {
    final solutionNotes = await showTaskCloseDialog(context);
    if (!context.mounted || solutionNotes == null) return;
    if (task.id == null) return;
    await ref.read(tasksProvider.notifier).closeTask(task.id!, solutionNotes);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Εκκρεμότητα ολοκληρώθηκε.')),
    );
  }
}

class _OrphanCallsBanner extends StatelessWidget {
  const _OrphanCallsBanner({
    required this.count,
    required this.onCreateTasks,
  });

  final int count;
  final VoidCallback onCreateTasks;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 20,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Υπάρχουν $count κλήσεις χωρίς εκκρεμότητα.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                ),
              ),
              FilledButton.tonal(
                onPressed: onCreateTasks,
                child: const Text('Δημιουργία εκκρεμοτήτων'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
