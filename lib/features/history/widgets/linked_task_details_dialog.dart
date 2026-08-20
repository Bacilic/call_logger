import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/draggable_dialog_shell.dart';
import '../../../core/widgets/linkable_selectable_text.dart';
import '../../tasks/models/task.dart';
import '../../tasks/providers/task_service_provider.dart';
import '../../tasks/screens/tasks_screen_actions.dart';

/// Η συνδεδεμένη εκκρεμότητα μιας κλήσης — πληροφορία πρώτα, ενέργειες μετά.
///
/// Αντικαθιστά τη διαδρομή «Άνοιγμα → ερώτηση επαναφοράς → φόρμα»: για να δει
/// κανείς τι είναι η εκκρεμότητα δεν χρειάζεται να δηλώσει πρώτα τι θα της
/// κάνει. Οι ενέργειες αλλάζουν με την κατάσταση, η κάρτα όχι.
///
/// Ο διάλογος **μένει ανοιχτός** μετά από κάθε ενέργεια και ξαναδιαβάζει την
/// εκκρεμότητα, ώστε να φαίνεται το αποτέλεσμα· κλείνει μόνο ο χρήστης.
Future<void> showLinkedTaskDetailsDialog(
  BuildContext context, {
  required Task task,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _LinkedTaskDetailsDialog(initialTask: task),
  );
}

class _LinkedTaskDetailsDialog extends ConsumerStatefulWidget {
  const _LinkedTaskDetailsDialog({required this.initialTask});

  final Task initialTask;

  @override
  ConsumerState<_LinkedTaskDetailsDialog> createState() =>
      _LinkedTaskDetailsDialogState();
}

class _LinkedTaskDetailsDialogState
    extends ConsumerState<_LinkedTaskDetailsDialog> {
  late Task _task;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _task = widget.initialTask;
  }

  TaskStatus get _status => TaskStatusX.fromString(_task.status);

  /// Ξαναδιαβάζει την εκκρεμότητα μετά από ενέργεια. Αν έχει διαγραφεί στο
  /// μεταξύ, ο διάλογος κλείνει — δεν έχει νόημα να δείχνει φάντασμα.
  Future<void> _reload() async {
    final id = _task.id;
    if (id == null) return;
    final row = await ref.read(taskServiceProvider).getTaskRowById(id);
    if (!mounted) return;
    if (row == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _task = Task.fromMap(row));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableDialogShell(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Συνδεδεμένη εκκρεμότητα'),
        ],
      ),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: _TaskDetailsCard(task: _task, status: _status),
          ),
        ),
        actions: _buildActions(),
      ),
    );
  }

  IconData get _statusIcon => switch (_status) {
    TaskStatus.open => Icons.pending_actions,
    TaskStatus.snoozed => Icons.snooze,
    TaskStatus.closed => Icons.check_circle_outline,
  };

  List<Widget> _buildActions() {
    final closed = _status == TaskStatus.closed;

    return [
      if (!closed)
        FilledButton.tonalIcon(
          onPressed: _busy
              ? null
              : () => _run(() => completeTask(context, ref, _task)),
          icon: const Icon(Icons.check_circle_outline, size: 20),
          label: const Text('Ολοκλήρωση'),
        ),
      if (closed)
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _run(() => reopenTask(context, ref, _task)),
          icon: const Icon(Icons.undo_rounded, size: 20),
          label: const Text('Αναίρεση ολοκλήρωσης'),
        ),
      if (!closed)
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _run(() => snoozeTask(context, ref, _task)),
          icon: const Icon(Icons.schedule_rounded, size: 20),
          label: Text(
            _status == TaskStatus.snoozed ? 'Αλλαγή αναβολής' : 'Αναβολή',
          ),
        ),
      OutlinedButton.icon(
        // Χωρίς την ερώτηση επαναφοράς: η αναίρεση έχει δικό της κουμπί.
        onPressed: _busy
            ? null
            : () => _run(() => editTask(context, ref, _task)),
        icon: const Icon(Icons.edit_outlined, size: 20),
        label: const Text('Επεξεργασία'),
      ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Κλείσιμο'),
      ),
    ];
  }
}

/// Η κάρτα της εκκρεμότητας μέσα στον διάλογο — ίδια στοιχεία με τον πίνακα
/// Εκκρεμοτήτων, με τη λύση ανοιχτή (εδώ η εκκρεμότητα είναι μία).
class _TaskDetailsCard extends StatelessWidget {
  const _TaskDetailsCard({required this.task, required this.status});

  final Task task;
  final TaskStatus status;

  static final DateFormat _fmt = DateFormat('dd/MM/yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = task.isQuickAdd
        ? task.cleanDescription
        : (task.description ?? '');
    final solution = task.solutionNotes?.trim() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardColor(theme),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  task.displayTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(status: status),
            ],
          ),
          if (description.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            LinkableSelectableText(
              text: description.trim(),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 12),
          _MetadataRow(task: task),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          ..._buildDates(theme),
          if (solution.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Text(
              'ΛΥΣΗ',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            LinkableSelectableText(
              text: solution,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  Color _cardColor(ThemeData theme) {
    final scheme = theme.colorScheme;
    return switch (status) {
      TaskStatus.open => scheme.primaryContainer.withValues(alpha: 0.25),
      TaskStatus.snoozed => scheme.tertiaryContainer.withValues(alpha: 0.3),
      TaskStatus.closed => scheme.surfaceContainerHighest.withValues(
        alpha: 0.6,
      ),
    };
  }

  List<Widget> _buildDates(ThemeData theme) {
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final created = task.createdAtDateTime;
    final lines = <Widget>[];

    if (created != null) {
      lines.add(Text('Δημιουργήθηκε: ${_fmt.format(created)}', style: style));
    }

    switch (status) {
      case TaskStatus.closed:
        final completed = task.completedAtDateTime;
        if (completed != null) {
          final elapsed = created != null
              ? ' (${_humanDuration(completed.difference(created))})'
              : '';
          lines.add(
            Text(
              'Ολοκληρώθηκε: ${_fmt.format(completed)}$elapsed',
              style: style,
            ),
          );
        }
      case TaskStatus.snoozed:
        final until = task.snoozeUntilDateTime ?? task.dueDateTime;
        if (until != null) {
          final times = task.snoozeHistory.length;
          final suffix = times > 1
              ? ' ($times'
                    'η φορά)'
              : '';
          lines.add(
            Text('Αναβλήθηκε ως: ${_fmt.format(until)}$suffix', style: style),
          );
        }
      case TaskStatus.open:
        final due = task.dueDateTime;
        if (due != null) {
          lines.add(Text('Λήγει: ${_fmt.format(due)}', style: style));
        }
    }

    return [
      for (var i = 0; i < lines.length; i++) ...[
        if (i > 0) const SizedBox(height: 4),
        lines[i],
      ],
    ];
  }

  static String _humanDuration(Duration diff) {
    final mins = diff.inMinutes < 1 ? 1 : diff.inMinutes;
    final days = mins ~/ (24 * 60);
    final hours = (mins % (24 * 60)) ~/ 60;
    final minutes = mins % 60;
    if (days > 0) return '$days μ. $hours ώρ. $minutes λ.';
    if (hours > 0) return '$hours ώρ. $minutes λ.';
    return '$minutes λ.';
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onVar = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.bodySmall?.copyWith(color: onVar);

    final entries = <(IconData, String)>[
      if ((task.userText?.trim().isNotEmpty ?? false))
        (Icons.person_outline, task.userText!.trim()),
      if ((task.phoneText?.trim().isNotEmpty ?? false))
        (Icons.phone_outlined, task.phoneText!.trim()),
      if ((task.departmentText?.trim().isNotEmpty ?? false))
        (Icons.domain_outlined, task.departmentText!.trim()),
      if ((task.equipmentText?.trim().isNotEmpty ?? false))
        (Icons.computer_outlined, task.equipmentText!.trim()),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        for (final (icon, text) in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: onVar),
              const SizedBox(width: 4),
              Text(text, style: style),
            ],
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (status) {
      TaskStatus.open => ('ανοιχτή', theme.colorScheme.primary),
      TaskStatus.snoozed => ('σε αναβολή', theme.colorScheme.tertiary),
      TaskStatus.closed => ('ολοκληρωμένη', theme.colorScheme.outline),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
