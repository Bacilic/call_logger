import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/task_service_provider.dart';
import '../providers/tasks_provider.dart';
import 'task_card.dart';

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
                          itemBuilder: (context, index) =>
                              TaskCard(task: tasks[index]),
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
