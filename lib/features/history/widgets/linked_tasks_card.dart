import 'package:flutter/material.dart';

import '../../tasks/models/task.dart';

/// Οι εκκρεμότητες που γέννησε η κλήση, μέσα στην επεξεργασία της.
///
/// Αντίστοιχο του [LansweeperEditWarning] για την άλλη «ουρά» μιας κλήσης:
/// εκεί το αίτημα Lansweeper, εδώ η εκκρεμότητα. Χωρίς αυτό, η σύνδεση
/// φαινόταν μόνο τη στιγμή της διαγραφής.
class LinkedTasksCard extends StatelessWidget {
  const LinkedTasksCard({
    required this.tasks,
    required this.onOpen,
    super.key,
  });

  final List<Task> tasks;
  final ValueChanged<Task> onOpen;

  String get _headline => tasks.length == 1
      ? 'Η κλήση έχει συνδεδεμένη εκκρεμότητα'
      : 'Η κλήση έχει ${tasks.length} συνδεδεμένες εκκρεμότητες';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.task_alt, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_headline, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final task in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _TaskStatusChip(status: task.status),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => onOpen(task),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Άνοιγμα'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskStatusChip extends StatelessWidget {
  const _TaskStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taskStatus = TaskStatusX.fromString(status);
    final (label, color) = switch (taskStatus) {
      TaskStatus.open => ('Ανοιχτή', theme.colorScheme.primary),
      TaskStatus.snoozed => ('Σε αναβολή', theme.colorScheme.tertiary),
      TaskStatus.closed => ('Κλειστή', theme.colorScheme.outline),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
