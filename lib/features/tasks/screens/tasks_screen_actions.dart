part of 'tasks_screen.dart';

enum _ClosedEditMode { recreate, reopen, snooze }

Future<void> _createTasksForOrphans(
  BuildContext context,
  WidgetRef ref,
) async {
  final service = ref.read(taskServiceProvider);
  final created = await service.createTasksForOrphanCalls();
  if (!context.mounted) return;
  ref.invalidate(tasksProvider);
  ref.invalidate(totalTasksCountProvider);
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

void _showTaskSaveError(BuildContext context, TaskSaveException e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(e.message)),
  );
}

Future<void> _openNewTaskForm(
  BuildContext context,
  WidgetRef ref,
) async {
  final result = await showTaskFormDialog(context, task: null);
  if (!context.mounted || result == null) return;
  try {
    await ref
        .read(tasksProvider.notifier)
        .addTask(result.copyWith(origin: Task.originManualFab));
    if (!context.mounted) return;
    final saveMessage = buildSaveConfirmationMessage(
      entityType: 'task',
      entityLabel: result.title,
      oldMap: const {},
      newMap: result.toMap(),
      isNew: true,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saveMessage),
        duration: saveConfirmationSnackBarDuration(saveMessage),
      ),
    );
  } on TaskSaveException catch (e) {
    if (!context.mounted) return;
    _showTaskSaveError(context, e);
  }
}

Future<void> _openTaskSettings(
  BuildContext context,
  WidgetRef ref,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => const TaskSettingsDialog(),
  );
}

Future<void> _onEdit(
  BuildContext context,
  WidgetRef ref,
  Task task,
) async {
  _ClosedEditMode? closedMode;
  if (TaskStatusX.fromString(task.status) == TaskStatus.closed) {
    closedMode = await _pickClosedEditMode(context, task);
    if (!context.mounted || closedMode == null) return;
  }

  final result = await showTaskFormDialog(context, task: task);
  if (!context.mounted || result == null) return;

  try {
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
          final recreateMessage =
              'Δημιουργήθηκε νέα εκκρεμότητα «${result.title}»';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(recreateMessage),
              duration: saveConfirmationSnackBarDuration(recreateMessage),
            ),
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
    final saveMessage = result.id != null
        ? buildSaveConfirmationMessage(
            entityType: 'task',
            entityLabel: result.title,
            oldMap: mapForTaskSaveConfirmationDiff(task.toMap()),
            newMap: mapForTaskSaveConfirmationDiff(result.toMap()),
            isNew: false,
          )
        : buildSaveConfirmationMessage(
            entityType: 'task',
            entityLabel: result.title,
            oldMap: const {},
            newMap: result.toMap(),
            isNew: true,
          );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saveMessage),
        duration: saveConfirmationSnackBarDuration(saveMessage),
      ),
    );
  } on TaskSaveException catch (e) {
    if (!context.mounted) return;
    _showTaskSaveError(context, e);
  }
}

String _buildClosedInfoText(Task task) {
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
  final snoozeEntries = task.snoozeEntries;
  final lastSnoozeAt =
      snoozeEntries.isNotEmpty ? snoozeEntries.last.snoozedAt : null;
  String fromLastSnoozeText = '';
  if (lastSnoozeAt != null && completedAt != null) {
    fromLastSnoozeText = durationSince(lastSnoozeAt, completedAt);
  }
  final solution = (task.solutionNotes?.trim().isNotEmpty ?? false)
      ? task.solutionNotes!.trim()
      : 'Καθόλου λύση';
  final durationSegment = durationText.isNotEmpty
      ? fromLastSnoozeText.isNotEmpty
          ? ' ($durationText, από τελευταία αναβολή: $fromLastSnoozeText)'
          : ' ($durationText)'
      : fromLastSnoozeText.isNotEmpty
          ? ' (από τελευταία αναβολή: $fromLastSnoozeText)'
          : '';
  return 'Η εκκρεμότητα έχει ολοκληρωθεί στις $completedText$durationSegment.\n'
      'Λύση: $solution';
}

Future<_ClosedEditMode?> _pickClosedEditMode(
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

Future<void> _onSnooze(
  BuildContext context,
  WidgetRef ref,
  Task task,
) async {
  final service = ref.read(taskServiceProvider);
  final config =
      ref
          .read(taskSettingsConfigProvider)
          .maybeWhen(data: (c) => c, orElse: () => null) ??
      TaskSettingsConfig.defaultConfig();
  final maxRangeText = config.maxSnoozeDays == 1
      ? 'Μέγιστο εύρος: 1 ημέρα'
      : 'Μέγιστο εύρος: ${config.maxSnoozeDays} ημέρες';

  final result = await showDialog<({String choice, String? note})>(
    context: context,
    builder: (ctx) => _SnoozeChoiceDialog(
      config: config,
      maxRangeText: maxRangeText,
    ),
  );

  if (!context.mounted || result == null) return;

  final choice = result.choice;
  final snoozeNote = result.note;

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
        .addSnoozeEntry(newDue, note: snoozeNote);
    try {
      await ref.read(tasksProvider.notifier).updateTask(updatedTask);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Η εκκρεμότητα αναβλήθηκε για τις: ${DateFormat('dd/MM HH:mm').format(newDue)}',
          ),
        ),
      );
    } on TaskSaveException catch (e) {
      if (!context.mounted) return;
      _showTaskSaveError(context, e);
    }
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
  final newDue = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  final updatedTask = task
      .copyWith(
        dueDate: newDue.toIso8601String(),
        status: TaskStatus.snoozed.toDbValue,
      )
      .addSnoozeEntry(newDue, note: snoozeNote);
  try {
    await ref.read(tasksProvider.notifier).updateTask(updatedTask);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Η εκκρεμότητα αναβλήθηκε για τις: ${DateFormat('dd/MM HH:mm').format(newDue)}',
        ),
      ),
    );
  } on TaskSaveException catch (e) {
    if (!context.mounted) return;
    _showTaskSaveError(context, e);
  }
}

Future<void> _onDelete(
  BuildContext context,
  WidgetRef ref,
  Task task,
) async {
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

Future<void> _onComplete(
  BuildContext context,
  WidgetRef ref,
  Task task,
) async {
  final solutionNotes = await showTaskCloseDialog(
    context,
    initialSolutionNotes: task.solutionNotes,
    task: task,
  );
  if (!context.mounted || solutionNotes == null) return;
  if (task.id == null) return;
  await ref.read(tasksProvider.notifier).closeTask(task.id!, solutionNotes);
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Εκκρεμότητα ολοκληρώθηκε.')));
}

Future<bool> _onEditCaller(
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
  return saved;
}

Future<bool> _onEditDepartment(
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
  return saved;
}

Future<bool> _onEditEquipment(
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
    barrierDismissible: true,
    builder: (_) => EquipmentFormDialog(
      initialEquipment: row.$1,
      initialOwner: row.$2,
      notifier: notifier,
      ref: ref,
      onSaved: () => saved = true,
    ),
  );
  if (!context.mounted) return false;
  return saved;
}
