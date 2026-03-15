import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';

/// Περιγραφή εκκρεμότητας: δυναμικό ύψος έως 5 γραμμές, πάνω από 5 → κυλιώμενο πλαίσιο.
class _TaskDescription extends StatelessWidget {
  const _TaskDescription({required this.description});

  static const int _maxLines = 5;

  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    return LayoutBuilder(
      builder: (context, constraints) {
        final textDirection = Directionality.of(context);
        final painter = TextPainter(
          text: TextSpan(text: description, style: style),
          maxLines: null,
          textDirection: textDirection,
        );
        painter.layout(maxWidth: constraints.maxWidth);
        final lineHeight = painter.preferredLineHeight;
        final lineCount = (painter.height / lineHeight).ceil();
        if (lineCount <= _maxLines) {
          return Text(description, style: style);
        }
        return SizedBox(
          height: lineHeight * _maxLines,
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Text(description, style: style),
          ),
        );
      },
    );
  }
}

class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    this.onEdit,
    this.onSnooze,
    this.onDelete,
    this.onComplete,
  });

  final Task task;
  final VoidCallback? onEdit;
  final VoidCallback? onSnooze;
  final VoidCallback? onDelete;
  final VoidCallback? onComplete;

  /// Χρωματική κωδικοποίηση: κόκκινο (καθυστέρηση), πορτοκαλί (υψηλή προτεραιότητα), πράσινο (&lt; 1 ώρα).
  static Color? _cardColor(Task task, ColorScheme scheme) {
    if (task.isOverdue) {
      return scheme.errorContainer.withValues(alpha: 0.45);
    }
    if (task.priority != null && task.priority! > 0) {
      return scheme.tertiaryContainer.withValues(alpha: 0.5);
    }
    final due = task.dueDateTime;
    if (due != null) {
      final diff = due.difference(DateTime.now());
      if (diff.isNegative == false && diff.inMinutes < 60) {
        return scheme.primaryContainer.withValues(alpha: 0.4);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = _cardColor(task, theme.colorScheme);

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
            ? _TaskDescription(description: task.description!)
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
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
            if (onComplete != null)
              IconButton(
                icon: const Icon(Icons.check_circle_outline),
                tooltip: 'Ολοκλήρωση',
                onPressed: onComplete,
              ),
            PopupMenuButton<String>(
              tooltip: 'Ενέργειες',
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEdit?.call();
                    break;
                  case 'snooze':
                    onSnooze?.call();
                    break;
                  case 'delete':
                    onDelete?.call();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Επεξεργασία')),
                const PopupMenuItem(value: 'snooze', child: Text('Αναβολή')),
                const PopupMenuItem(value: 'delete', child: Text('Διαγραφή')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
