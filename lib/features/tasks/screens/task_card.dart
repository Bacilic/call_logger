import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/task_save_exception.dart';
import '../../../core/widgets/compact_tooltip.dart';
import '../../../core/widgets/draggable_dialog_shell.dart';
import '../../operators/providers/operator_directory_providers.dart';
import '../models/task.dart';
import '../models/task_settings_config.dart';
import '../providers/pending_task_delete_provider.dart';
import '../providers/task_settings_config_provider.dart';
import '../providers/tasks_provider.dart';
import '../utils/task_completion_summary.dart';
import '../widgets/task_card_actions.dart';
import '../widgets/task_card_callbacks.dart';
import '../widgets/task_card_quick_actions.dart';
import '../widgets/task_card_solution_zone.dart';
import '../widgets/task_card_summary.dart';
import 'tasks_screen_actions.dart';

// Οι υποδείξεις για διαγραμμένες οντότητες ζουν πλέον δίπλα στα κουμπιά που
// τις δείχνουν· μένουν προσβάσιμες από εδώ για όποιον εισάγει την κάρτα.
export '../widgets/task_card_quick_actions.dart'
    show
        kTaskActionCallerMissingHint,
        kTaskActionDepartmentMissingHint,
        kTaskActionEquipmentMissingHint;

/// Μία εκκρεμότητα στη λίστα — τρεις ζώνες που συντίθενται εδώ.
///
/// Η κάρτα δεν ζωγραφίζει η ίδια τίποτα: ενώνει τη σύνοψη (τι είναι),
/// τα σήματα και τις ενέργειες (σε τι κατάσταση είναι, τι της κάνεις), τη
/// ζώνη λύσης και τις συντομεύσεις καταλόγου. Ό,τι κρατά **κατάσταση** ή
/// αγγίζει τη βάση μένει εδώ· τα κομμάτια είναι καθαρές απεικονίσεις.
class TaskCard extends ConsumerStatefulWidget {
  const TaskCard({
    super.key,
    required this.task,
    this.onEdit,
    this.onAssign,
    this.onSnooze,
    this.onDelete,
    this.onComplete,
    this.onEditCaller,
    this.onEditDepartment,
    this.onEditEquipment,
  });

  final Task task;
  final VoidCallback? onEdit;

  /// Άνοιγμα του διαλόγου γρήγορης ανάθεσης — δίνεται από την οθόνη.
  final VoidCallback? onAssign;
  final VoidCallback? onSnooze;
  final VoidCallback? onDelete;
  final VoidCallback? onComplete;
  final Future<bool> Function()? onEditCaller;
  final Future<bool> Function()? onEditDepartment;
  final Future<bool> Function()? onEditEquipment;

  /// Οι ενέργειες σε ένα αντικείμενο, για τα κομμάτια της κάρτας.
  ///
  /// Το ίδιο το [TaskCard] κρατά τις παραμέτρους ξεχωριστά — έτσι το καλεί
  /// όλη η εφαρμογή — και τις μαζεύει μόνο όταν τις παραδίδει παρακάτω.
  TaskCardCallbacks get _callbacks => TaskCardCallbacks(
    onEdit: onEdit,
    onAssign: onAssign,
    onSnooze: onSnooze,
    onDelete: onDelete,
    onComplete: onComplete,
    onEditCaller: onEditCaller,
    onEditDepartment: onEditDepartment,
    onEditEquipment: onEditEquipment,
  );

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
  ConsumerState<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends ConsumerState<TaskCard> {
  bool _showSolution = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;
    final status = TaskStatusX.fromString(task.status);
    final isClosed = status == TaskStatus.closed;

    // Η λύση δείχνεται και σε ξανα-ανοιγμένη εκκρεμότητα: περιγράφει τι είχε
    // δοκιμαστεί και δεν παύει να ισχύει επειδή το θέμα ξανάνοιξε.
    final completion = TaskCompletionSummary.of(task);
    final hasSolution = completion.solution != null;

    final operatorNames = ref.watch(operatorNamesProvider).value;
    final operatorAvatars =
        ref.watch(operatorAvatarsProvider).value ?? const <int, String?>{};
    final disabledOperatorIds =
        ref.watch(disabledOperatorIdsProvider).value ?? const <int>{};
    final assignedId = task.assignedOperatorId;
    final creatorId = task.createdByOperatorId;

    final pendingDeleteTaskId = ref.watch(pendingTaskDeleteProvider);
    final isPendingDeleteSelf =
        pendingDeleteTaskId != null &&
        task.id != null &&
        pendingDeleteTaskId == task.id;

    Widget card = Card(
      elevation: 1,
      color: TaskCard._cardColor(task, theme.colorScheme),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: TaskCardSummary(task: task)),
                const SizedBox(width: 12),
                TaskCardActions(
                  task: task,
                  callbacks: widget._callbacks,
                  status: status,
                  assigneeName: assignedId == null
                      ? null
                      : operatorDisplayNameFor(operatorNames, assignedId),
                  creatorName: creatorId == null
                      ? null
                      : operatorDisplayNameFor(operatorNames, creatorId),
                  operatorAvatars: operatorAvatars,
                  disabledOperatorIds: disabledOperatorIds,
                  deleteMenuEnabled: pendingDeleteTaskId == null,
                  hasSolution: hasSolution,
                  showSolution: _showSolution,
                  onToggleSolution: () =>
                      setState(() => _showSolution = !_showSolution),
                ),
              ],
            ),
          ),
          if (hasSolution && _showSolution)
            TaskCardSolutionZone(completion: completion, isClosed: isClosed),
          if (task.isQuickAdd)
            TaskCardQuickActions(
              task: task,
              callbacks: widget._callbacks,
              onEntityEdited: _handleEntityEdited,
            ),
        ],
      ),
    );

    if (isPendingDeleteSelf) {
      card = CompactTooltip(
        message:
            'Εκκρεμεί η διαγραφή· πατήστε «Αναίρεση» στο μήνυμα κάτω για επαναφορά',
        child: AbsorbPointer(
          absorbing: true,
          child: Opacity(opacity: 0.5, child: card),
        ),
      );
    }

    return card;
  }

  /// Μετά από επιτυχή επεξεργασία οντότητας μέσα από τη γρήγορη καταχώρηση.
  Future<void> _handleEntityEdited() async {
    if (!mounted) return;
    await _handleQuickAddPostSave();
    if (!mounted) return;
    await deferTasksProviderInvalidate(ref);
  }

  Future<void> _handleQuickAddPostSave() async {
    final task = widget.task;
    if (!task.isQuickAdd || task.id == null || !mounted) return;

    final settings = ref
        .read(taskSettingsConfigProvider)
        .maybeWhen(
          data: (c) => c,
          orElse: () => TaskSettingsConfig.defaultConfig(),
        );
    if (settings.autoCloseQuickAdds) {
      await _closeQuickAddTask(task);
      return;
    }

    final shouldClose = await showDialog<bool>(
      context: context,
      builder: (ctx) => DraggableDialogShell(
        title: const Text('Επιτυχής Αποθήκευση'),
        builder: (titleHandle) => AlertDialog(
          title: titleHandle,
          content: const Text(
            'Η εγγραφή ενημερώθηκε. Θέλετε να κλείσει η εκκρεμότητα;',
          ),
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
      ),
    );
    if (!mounted || shouldClose != true) return;
    await _closeQuickAddTask(task);
  }

  Future<void> _closeQuickAddTask(Task task) async {
    final id = task.id;
    if (id == null) return;
    final notes = task.solutionNotes?.trim().isNotEmpty == true
        ? task.solutionNotes!.trim()
        : 'Κλείσιμο μετά από επιτυχή επεξεργασία οντότητας';
    try {
      final closed = await saveTaskGuarded(
        context,
        ref,
        task.copyWith(
          status: TaskStatus.closed.toDbValue,
          solutionNotes: notes,
        ),
        expected: task,
      );
      if (!mounted || !closed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Εκκρεμότητα ολοκληρώθηκε.')),
      );
    } on TaskSaveException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
