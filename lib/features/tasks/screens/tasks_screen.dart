import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/task_focus_intent_provider.dart';
import '../../calls/provider/lookup_provider.dart';
import '../../directory/providers/department_directory_provider.dart';
import '../../directory/providers/directory_provider.dart';
import '../../directory/providers/equipment_directory_provider.dart';
import '../../directory/screens/widgets/department_form_dialog.dart';
import '../../directory/screens/widgets/equipment_form_dialog.dart';
import '../../directory/screens/widgets/user_form_dialog.dart';
import '../models/task.dart';
import '../models/task_settings_config.dart';
import '../providers/pending_task_delete_provider.dart';
import '../providers/task_service_provider.dart';
import '../providers/task_settings_config_provider.dart';
import '../providers/tasks_provider.dart';
import '../ui/task_due_option_tooltips.dart';
import 'task_card.dart';
import 'task_close_dialog.dart';
import 'task_filter_bar.dart';
import 'task_form_dialog.dart';
import 'task_settings_dialog.dart';

enum _ClosedEditMode {
  recreate,
  reopen,
  snooze,
}

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Εκκρεμότητες'),
        actions: [
          IconButton(
            icon: const Icon(Icons.schedule),
            tooltip: 'Ρυθμίσεις εκκρεμοτήτων',
            onPressed: () => _openTaskSettings(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openNewTaskForm(context, ref),
        child: const Icon(Icons.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TaskFilterBar(),
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OrphanCallsBanner(
                onCreateTasks: () => _createTasksForOrphans(context, ref),
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
                        // Προσθήκη bottom padding για να μην επικαλύπτεται η τελευταία κάρτα από το FAB
                        child: ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            8,
                            16,
                            88 + MediaQuery.of(context).viewPadding.bottom,
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
                                onEdit: () => _onEdit(context, ref, task),
                                onSnooze: () => _onSnooze(context, ref, task),
                                onDelete: () => _onDelete(context, ref, task),
                                onComplete: () =>
                                    _onComplete(context, ref, task),
                                onEditCaller: () =>
                                    _onEditCaller(context, ref, task),
                                onEditDepartment: () =>
                                    _onEditDepartment(context, ref, task),
                                onEditEquipment: () =>
                                    _onEditEquipment(context, ref, task),
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

  static Future<void> _openTaskSettings(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (context) => const TaskSettingsDialog(),
    );
  }

  static Future<void> _onEdit(BuildContext context, WidgetRef ref, Task task) async {
    _ClosedEditMode? closedMode;
    if (TaskStatusX.fromString(task.status) == TaskStatus.closed) {
      closedMode = await _pickClosedEditMode(context, task);
      if (!context.mounted || closedMode == null) return;
    }

    final result = await showTaskFormDialog(context, task: task);
    if (!context.mounted || result == null) return;

    if (closedMode != null) {
      final notifier = ref.read(tasksProvider.notifier);
      switch (closedMode) {
        case _ClosedEditMode.recreate:
          await notifier.addTask(
            result.copyWith(
              id: null,
              status: TaskStatus.open.toDbValue,
              solutionNotes: null,
              snoozeHistoryJson: null,
              createdAt: null,
              updatedAt: null,
            ),
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Δημιουργήθηκε νέα εκκρεμότητα.')),
          );
          return;
        case _ClosedEditMode.reopen:
          await notifier.updateTask(
            result.copyWith(
              status: TaskStatus.open.toDbValue,
              // Ρητό: στην αναίρεση ολοκλήρωσης η λύση παραμένει.
              solutionNotes: task.solutionNotes,
              createdAt: task.createdAt,
              snoozeHistoryJson: task.snoozeHistoryJson,
            ),
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Η ολοκλήρωση αναιρέθηκε.')),
          );
          return;
        case _ClosedEditMode.snooze:
          final due = result.dueDateTime ?? DateTime.now();
          await notifier.updateTask(
            result
                .copyWith(
                  status: TaskStatus.snoozed.toDbValue,
                  createdAt: task.createdAt,
                )
                .addSnoozeEntry(due),
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Η εκκρεμότητα αναβλήθηκε για τις: ${DateFormat('dd/MM HH:mm').format(due)}',
              ),
            ),
          );
          return;
      }
    }

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

  static String _buildClosedInfoText(Task task) {
    final completedAt = task.updatedAtDateTime;
    final createdAt = task.createdAtDateTime;
    final completedText = completedAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(completedAt)
        : 'άγνωστη ημερομηνία';
    String durationText = '';
    if (completedAt != null && createdAt != null) {
      final diff = completedAt.difference(createdAt);
      final mins = diff.inMinutes < 1 ? 1 : diff.inMinutes;
      final days = mins ~/ (24 * 60);
      final hours = (mins % (24 * 60)) ~/ 60;
      final minutes = mins % 60;
      if (days > 0) {
        durationText = '$days μ. $hours ώρ. $minutes λ.';
      } else if (hours > 0) {
        durationText = '$hours ώρ. $minutes λ.';
      } else {
        durationText = '$minutes λ.';
      }
    }
    final solution = (task.solutionNotes?.trim().isNotEmpty ?? false)
        ? task.solutionNotes!.trim()
        : 'Καθόλου λύση';
    return 'Η εκκρεμότητα έχει ολοκληρωθεί στις $completedText'
        '${durationText.isNotEmpty ? ' ($durationText)' : ''}.\n'
        'Λύση: $solution';
  }

  static Future<_ClosedEditMode?> _pickClosedEditMode(
    BuildContext context,
    Task task,
  ) async {
    var selected = _ClosedEditMode.reopen;
    return showDialog<_ClosedEditMode>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Επεξεργασία Εκκρεμότητας'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _buildClosedInfoText(task),
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  'Θέλετε να την επαναφέρετε ως:',
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<_ClosedEditMode>(
                  initialValue: selected,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: _ClosedEditMode.recreate,
                      child: Text('Εκ νέου'),
                    ),
                    DropdownMenuItem(
                      value: _ClosedEditMode.reopen,
                      child: Text('Αναίρεση ολοκλήρωσης'),
                    ),
                    DropdownMenuItem(
                      value: _ClosedEditMode.snooze,
                      child: Text('Αναβολή'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => selected = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Ακύρωση'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(selected),
              child: const Text('Συνέχεια'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _onSnooze(BuildContext context, WidgetRef ref, Task task) async {
    final service = ref.read(taskServiceProvider);
    final config = ref.read(taskSettingsConfigProvider).maybeWhen(
          data: (c) => c,
          orElse: () => null,
        ) ??
        TaskSettingsConfig.defaultConfig();
    final maxRangeText = config.maxSnoozeDays == 1
        ? 'Μέγιστο εύρος: 1 ημέρα'
        : 'Μέγιστο εύρος: ${config.maxSnoozeDays} ημέρες';

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Αναβολή'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Γρήγορη επιλογή',
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Tooltip(
                message: TaskDueOptionTooltips.plusOneHour(),
                child: FilledButton.tonal(
                  onPressed: () =>
                      Navigator.of(ctx).pop(TaskSettingsConfig.kOneHour),
                  child: const Text('+1 ώρα'),
                ),
              ),
              const SizedBox(height: 8),
              Tooltip(
                message: TaskDueOptionTooltips.withinSchedule(
                  config.nextBusinessHour,
                  config.dayEndTime,
                ),
                child: FilledButton.tonal(
                  onPressed: () =>
                      Navigator.of(ctx).pop(TaskSettingsConfig.kDayEnd),
                  child: const Text('Μέσα στο ωράριο'),
                ),
              ),
              const SizedBox(height: 8),
              Tooltip(
                message: TaskDueOptionTooltips.nextBusiness(
                  config.nextBusinessHour,
                ),
                child: FilledButton.tonal(
                  onPressed: () =>
                      Navigator.of(ctx).pop(TaskSettingsConfig.kNextBusiness),
                  child: const Text('Επόμενη εργάσιμη'),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      maxRangeText,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).colorScheme.onSurface,
                          ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => Navigator.of(ctx).pop('custom'),
                    icon: const Icon(Icons.edit_calendar_outlined, size: 20),
                    label: const Text('Άλλη ημερομηνία…'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Ο επιλογέας ημερομηνίας περιορίζεται στο παραπάνω εύρος.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Ακύρωση'),
          ),
        ],
      ),
    );

    if (!context.mounted || choice == null) return;

    if (choice != 'custom') {
      final newDue = service.calculateNextDueDate(
        config,
        option: choice,
        fromDate: DateTime.now(),
      );
      final updatedTask = task
          .copyWith(
            dueDate: newDue.toIso8601String(),
            status: TaskStatus.snoozed.toDbValue,
          )
          .addSnoozeEntry(newDue);
      await ref.read(tasksProvider.notifier).updateTask(
            updatedTask,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Η εκκρεμότητα αναβλήθηκε για τις: ${DateFormat('dd/MM HH:mm').format(newDue)}',
          ),
        ),
      );
      return;
    }

    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    final lastDate = firstDate.add(Duration(days: config.maxSnoozeDays));
    final raw = task.dueDateTime ?? now;
    final rawDay = DateTime(raw.year, raw.month, raw.day);
    var initialDate = rawDay;
    if (initialDate.isBefore(firstDate)) {
      initialDate = firstDate;
    } else if (initialDate.isAfter(lastDate)) {
      initialDate = lastDate;
    }

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (!context.mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(task.dueDateTime ?? DateTime.now()),
    );
    if (!context.mounted || time == null) return;
    final newDue = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final updatedTask = task
        .copyWith(
          dueDate: newDue.toIso8601String(),
          status: TaskStatus.snoozed.toDbValue,
        )
        .addSnoozeEntry(newDue);
    await ref.read(tasksProvider.notifier).updateTask(
          updatedTask,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Η εκκρεμότητα αναβλήθηκε για τις: ${DateFormat('dd/MM HH:mm').format(newDue)}',
        ),
      ),
    );
  }

  static Future<void> _onDelete(BuildContext context, WidgetRef ref, Task task) async {
    if (task.id == null) return;
    final created = task.createdAtDateTime;
    final createdLabel = created != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(created)
        : 'άγνωστη ημερομηνία';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή εκκρεμότητας'),
        content: Text(
          'Να διαγραφεί η εκκρεμότητα: ${task.title} από τη $createdLabel.\n\n'
          'Αυτή η πράξη δεν μπορεί να αναιρεθεί.',
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
    );
    if (confirm != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final tasksNotifier = ref.read(tasksProvider.notifier);
    final pendingDelete = ref.read(pendingTaskDeleteProvider.notifier);
    final taskId = task.id!;
    pendingDelete.begin(taskId);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(days: 1),
        content: _TaskDeleteCountdownSnackContent(
          taskTitle: task.title,
          onUndo: () {
            pendingDelete.clear();
            messenger.hideCurrentSnackBar();
          },
          onExpired: () async {
            messenger.hideCurrentSnackBar();
            try {
              await tasksNotifier.deleteTask(taskId);
              messenger.showSnackBar(
                const SnackBar(content: Text('Η εκκρεμότητα διαγράφηκε.')),
              );
            } finally {
              pendingDelete.clear();
            }
          },
          onAbortedExternally: pendingDelete.clear,
        ),
      ),
    );
  }

  static Future<void> _onComplete(BuildContext context, WidgetRef ref, Task task) async {
    final solutionNotes = await showTaskCloseDialog(
      context,
      initialSolutionNotes: task.solutionNotes,
    );
    if (!context.mounted || solutionNotes == null) return;
    if (task.id == null) return;
    await ref.read(tasksProvider.notifier).closeTask(task.id!, solutionNotes);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Εκκρεμότητα ολοκληρώθηκε.')),
    );
  }

  static Future<bool> _onEditCaller(
    BuildContext context,
    WidgetRef ref,
    Task task,
  ) async {
    final callerId = task.callerId;
    if (callerId == null) return false;
    final lookupBundle = await ref.read(lookupServiceProvider.future);
    final user = lookupBundle.service.findUserById(callerId);
    if (user == null) return false;

    final notifier = ref.read(directoryProvider.notifier);
    await notifier.loadUsers();
    if (!context.mounted) return false;
    var saved = false;
    await showDialog<bool>(
      context: context,
      builder: (_) => UserFormDialog(
        initialUser: user,
        notifier: notifier,
        onSaved: () => saved = true,
      ),
    );
    if (!context.mounted) return false;
    ref.invalidate(tasksProvider);
    return saved;
  }

  static Future<bool> _onEditDepartment(
    BuildContext context,
    WidgetRef ref,
    Task task,
  ) async {
    final departmentId = task.departmentId;
    if (departmentId == null) return false;

    final notifier = ref.read(departmentDirectoryProvider.notifier);
    await notifier.loadDepartments();
    final state = ref.read(departmentDirectoryProvider);
    final matchingDepartments = state.allDepartments
        .where((d) => d.id == departmentId)
        .toList();
    final department = matchingDepartments.isEmpty
        ? null
        : matchingDepartments.first;
    if (department == null || !context.mounted) return false;

    var saved = false;
    await showDialog<bool>(
      context: context,
      builder: (_) => DepartmentFormDialog(
        initialDepartment: department,
        notifier: notifier,
        onSaved: () => saved = true,
      ),
    );
    if (!context.mounted) return false;
    ref.invalidate(tasksProvider);
    return saved;
  }

  static Future<bool> _onEditEquipment(
    BuildContext context,
    WidgetRef ref,
    Task task,
  ) async {
    final equipmentId = task.equipmentId;
    if (equipmentId == null) return false;

    final notifier = ref.read(equipmentDirectoryProvider.notifier);
    await notifier.load();
    final equipmentState = ref.read(equipmentDirectoryProvider);
    final matchingRows = equipmentState.allItems
        .where((r) => r.$1.id == equipmentId)
        .toList();
    final row = matchingRows.isEmpty ? null : matchingRows.first;
    if (row == null || !context.mounted) return false;

    var saved = false;
    await showDialog<bool>(
      context: context,
      builder: (_) => EquipmentFormDialog(
        initialEquipment: row.$1,
        initialOwner: row.$2,
        notifier: notifier,
        ref: ref,
        onSaved: () => saved = true,
      ),
    );
    if (!context.mounted) return false;
    ref.invalidate(tasksProvider);
    return saved;
  }
}

/// Αντίστροφη μέτρηση πριν την οριστική διαγραφή· «Αναίρεση» κλείνει το SnackBar.
class _TaskDeleteCountdownSnackContent extends StatefulWidget {
  const _TaskDeleteCountdownSnackContent({
    required this.taskTitle,
    required this.onUndo,
    required this.onExpired,
    this.onAbortedExternally,
  });

  final String taskTitle;
  final VoidCallback onUndo;
  final Future<void> Function() onExpired;

  /// Όταν το SnackBar αφαιρεθεί χωρίς αναίρεση/λήξη (π.χ. αλλαγή οθόνης).
  final VoidCallback? onAbortedExternally;

  @override
  State<_TaskDeleteCountdownSnackContent> createState() =>
      _TaskDeleteCountdownSnackContentState();
}

class _TaskDeleteCountdownSnackContentState
    extends State<_TaskDeleteCountdownSnackContent> {
  static const int _initialSeconds = 5;
  int _remaining = _initialSeconds;
  Timer? _timer;
  bool _undone = false;
  bool _expireCallbackStarted = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _undone) return;
      if (_remaining <= 1) {
        _timer?.cancel();
        _timer = null;
        _expireCallbackStarted = true;
        widget.onExpired();
        return;
      }
      setState(() => _remaining--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!_undone && !_expireCallbackStarted) {
      widget.onAbortedExternally?.call();
    }
    super.dispose();
  }

  void _undo() {
    if (_undone) return;
    _undone = true;
    _timer?.cancel();
    widget.onUndo();
  }

  @override
  Widget build(BuildContext context) {
    const undoLinkBlue = Color(0xFF039BE5);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            'Η εκκρεμότητα: ${widget.taskTitle} θα διαγραφεί σε: $_remaining δευτ.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ) ??
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.35,
                ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: _undo,
          style: TextButton.styleFrom(
            foregroundColor: undoLinkBlue,
            padding: const EdgeInsets.only(left: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Αναίρεση'),
        ),
      ],
    );
  }
}

class _OrphanCallsBanner extends ConsumerWidget {
  const _OrphanCallsBanner({
    required this.onCreateTasks,
  });

  final VoidCallback onCreateTasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncOrphans = ref.watch(orphanCallsProvider);
    final count = asyncOrphans.when(
      data: (orphans) => orphans.length,
      loading: () => 0,
      error: (_, _) => 0,
    );
    if (count == 0) {
      return const SizedBox.shrink();
    }
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
