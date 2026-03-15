import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';

class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color? cardColor;
    if (task.isOverdue) {
      cardColor = theme.colorScheme.errorContainer.withValues(alpha: 0.4);
    } else if (task.isSnoozed) {
      cardColor = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    }

    final dueFormatted = task.dueDateTime != null
        ? DateFormat('dd/MM HH:mm').format(task.dueDateTime!)
        : task.dueDate;

    return Card(
      elevation: 1,
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Chip(
          label: Text(
            task.status,
            style: theme.textTheme.labelSmall,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        title: Text(
          task.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: task.description != null && task.description!.isNotEmpty
            ? Text(
                task.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              dueFormatted,
              style: theme.textTheme.bodySmall,
            ),
            if (task.priority != null && task.priority! > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'P${task.priority}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
