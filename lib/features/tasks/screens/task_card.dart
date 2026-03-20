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

class TaskCard extends StatefulWidget {
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

  static String _relativeCreatedAt(DateTime? createdAt) {
    if (createdAt == null) return '';
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'μόλις τώρα';
    if (diff.inHours < 1) return 'πριν ${diff.inMinutes} λεπτά';
    if (diff.inHours < 24) return 'πριν ${diff.inHours} ώρες';
    if (diff.inDays == 1) return 'χθες';
    if (diff.inDays < 7) return '${diff.inDays} μέρες πριν';
    return DateFormat('dd/MM/yyyy').format(createdAt);
  }

  static String _durationSince(DateTime from, DateTime to) {
    var diff = to.difference(from);
    if (diff.isNegative) diff = Duration.zero;

    var totalMinutes = diff.inMinutes;
    if (totalMinutes <= 0) totalMinutes = 1;

    final days = totalMinutes ~/ (24 * 60);
    final hours = (totalMinutes % (24 * 60)) ~/ 60;
    final minutes = totalMinutes % 60;

    if (days > 0) {
      if (hours > 0 && minutes > 0) return '$days μ. $hours ώρες και $minutes λεπτά';
      if (hours > 0) return '$days μ. και $hours ώρες';
      if (minutes > 0) return '$days μ. και $minutes λεπτά';
      return '$days μ.';
    }
    if (hours > 0 && minutes > 0) return '$hours ώρες και $minutes λεπτά';
    if (hours > 0) return '$hours ώρες';
    return '$minutes λεπτά';
  }

  static Color _statusChipColor(TaskStatus status, ColorScheme scheme) {
    return switch (status) {
      TaskStatus.open => scheme.surfaceContainerHighest,
      TaskStatus.snoozed => scheme.tertiaryContainer,
      TaskStatus.closed => scheme.surfaceContainerHighest,
    };
  }

  static String _buildStatusTooltip(Task task, TaskStatus status) {
    final createdAt = task.createdAtDateTime;
    final completedAt = task.updatedAtDateTime;
    final snoozeEntries = task.snoozeEntries;
    final lastSnoozeAt =
        snoozeEntries.isNotEmpty ? snoozeEntries.last.snoozedAt : null;

    switch (status) {
      case TaskStatus.open:
        final rel = _relativeCreatedAt(createdAt);
        return rel.isEmpty ? 'Ανοικτή εκκρεμότητα' : 'Δημιουργία: $rel';
      case TaskStatus.snoozed:
        if (snoozeEntries.isEmpty) return 'Αναβληθείσα εκκρεμότητα';
        final lines = <String>[
          'Αναβολές: ${snoozeEntries.length}',
        ];
        for (final entry in snoozeEntries.asMap().entries) {
          final i = entry.key + 1;
          lines.add(
            '$iη: ${DateFormat('dd/MM HH:mm').format(entry.value.snoozedAt)}',
          );
        }
        return lines.join('\n');
      case TaskStatus.closed:
        final total = (createdAt != null && completedAt != null)
            ? _durationSince(createdAt, completedAt)
            : '';
        final fromLast = (lastSnoozeAt != null && completedAt != null)
            ? _durationSince(lastSnoozeAt, completedAt)
            : '';
        if (total.isEmpty && fromLast.isEmpty) {
          return 'Ολοκληρωμένη εκκρεμότητα';
        }
        if (fromLast.isEmpty) return 'Συνολικός χρόνος: $total';
        return 'Συνολικός χρόνος: $total\nΑπό τελευταία αναβολή: $fromLast';
    }
  }

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  bool _showSolution = false;

  static bool _nonEmptyText(String? value) =>
      value != null && value.trim().isNotEmpty;

  bool _hasEntityMetadata() {
    final t = widget.task;
    return _nonEmptyText(t.userText) ||
        _nonEmptyText(t.phoneText) ||
        _nonEmptyText(t.departmentText) ||
        _nonEmptyText(t.equipmentText);
  }

  Widget _buildEntityMetadata(ThemeData theme) {
    final t = widget.task;
    final user = t.userText?.trim();
    final phone = t.phoneText?.trim();
    final dept = t.departmentText?.trim();
    final equip = t.equipmentText?.trim();

    final hasUser = user != null && user.isNotEmpty;
    final hasPhone = phone != null && phone.isNotEmpty;
    final hasDept = dept != null && dept.isNotEmpty;
    final hasEquip = equip != null && equip.isNotEmpty;

    if (!hasUser && !hasPhone && !hasDept && !hasEquip) {
      return const SizedBox.shrink();
    }

    final onVar = theme.colorScheme.onSurfaceVariant;
    final textStyle = theme.textTheme.bodySmall?.copyWith(color: onVar);

    Widget row(IconData icon, String text) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: onVar),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: textStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 12.0,
      runSpacing: 4.0,
      children: [
        if (hasUser) row(Icons.person_outline, user),
        if (hasPhone) row(Icons.phone_outlined, phone),
        if (hasDept) row(Icons.domain, dept),
        if (hasEquip) row(Icons.computer_outlined, equip),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;
    final cardColor = TaskCard._cardColor(task, theme.colorScheme);
    final status = TaskStatusX.fromString(task.status);
    final isSnoozed = status == TaskStatus.snoozed;
    final isClosed = status == TaskStatus.closed;
    final hasSolution =
        (task.solutionNotes?.trim().isNotEmpty ?? false) && isClosed;

    final dueFormatted = task.dueDateTime != null
        ? DateFormat('dd/MM HH:mm').format(task.dueDateTime!)
        : task.dueDate;
    final completedFormatted = task.updatedAtDateTime != null
        ? DateFormat('dd/MM - HH:mm').format(task.updatedAtDateTime!)
        : dueFormatted;
    final statusLabel = isSnoozed ? 'Αναβληθείσα' : status.displayLabelEl;
    final statusTooltip = TaskCard._buildStatusTooltip(task, status);

    return Card(
      elevation: 1,
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: statusTooltip,
                      child: Chip(
                        backgroundColor:
                            TaskCard._statusChipColor(status, theme.colorScheme),
                        label: Text(
                          statusLabel,
                          style: theme.textTheme.labelSmall,
                        ),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    if (hasSolution)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () {
                            setState(() => _showSolution = !_showSolution);
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_showSolution ? 'Απόκρυψη λύσης' : 'Λύση'),
                              const SizedBox(width: 2),
                              Icon(
                                _showSolution
                                    ? Icons.arrow_drop_up
                                    : Icons.arrow_drop_down,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (hasSolution) const SizedBox(height: 6),
                  ],
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (task.description != null && task.description!.isNotEmpty)
                  _TaskDescription(description: task.description!),
                if (task.description != null &&
                    task.description!.isNotEmpty &&
                    _hasEntityMetadata())
                  const SizedBox(height: 8),
                _buildEntityMetadata(theme),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      status == TaskStatus.closed ? completedFormatted : dueFormatted,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (task.priority != null && task.priority! > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          task.priority == 1 ? 'Υψηλή' : 'Κρίσιμη',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: task.priority == 1
                                ? Colors.orange.shade700
                                : theme.colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
                if (widget.onComplete != null && status != TaskStatus.closed)
                  IconButton(
                    icon: const Icon(Icons.check_circle_outline),
                    tooltip: 'Ολοκλήρωση',
                    onPressed: widget.onComplete,
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Ενέργειες',
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        widget.onEdit?.call();
                        break;
                      case 'snooze':
                        widget.onSnooze?.call();
                        break;
                      case 'delete':
                        widget.onDelete?.call();
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
          if (hasSolution && _showSolution)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(
                    height: 10,
                    thickness: 0.5,
                    color: Colors.black87,
                  ),
                  Text(
                    task.solutionNotes!.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
