import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/task_save_exception.dart';
import '../../../core/services/save_confirmation_summary.dart';
import '../../../core/widgets/draggable_dialog_shell.dart';
import '../../calls/provider/lookup_provider.dart';
import '../../directory/providers/department_directory_provider.dart';
import '../../directory/providers/directory_provider.dart';
import '../../directory/screens/widgets/department_form_dialog.dart';
import '../../directory/screens/widgets/user_form_dialog.dart';
import '../../directory/services/equipment_form_launcher.dart';
import '../../../core/services/current_operator.dart';
import '../../operators/providers/operator_directory_providers.dart';
import '../models/task.dart';
import '../models/task_settings_config.dart';
import '../providers/pending_task_delete_provider.dart';
import '../providers/task_service_provider.dart';
import '../providers/task_settings_config_provider.dart';
import '../providers/tasks_provider.dart';
import '../widgets/snooze_choice_dialog.dart';
import 'task_close_dialog.dart';
import 'task_form_dialog.dart';
import 'task_settings_dialog.dart';
import 'tasks_screen_support_widgets.dart';

Future<void> createTasksForOrphans(BuildContext context, WidgetRef ref) async {
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
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(e.message)));
}

Future<void> openNewTaskForm(BuildContext context, WidgetRef ref) async {
  final formResult = await showTaskFormDialog(context, task: null);
  if (!context.mounted || formResult == null) return;
  final result = formResult.task;
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

Future<void> openTaskSettings(BuildContext context, WidgetRef ref) async {
  await showDialog<void>(
    context: context,
    // Σημερινή συμπεριφορά, δηλωμένη: το κλικ έξω δεν κλείνει.
    barrierDismissible: false,
    builder: (context) => const TaskSettingsDialog(),
  );
}

/// Καθαρή αντιγραφή για το «Εκ νέου»: μόνο τα στοιχεία της υπόθεσης.
///
/// Χτίζεται ρητά αντί για copyWith, γιατί το copyWith με null ΚΡΑΤΑ την
/// παλιά τιμή — η «καθαρή» εκκρεμότητα γεννιόταν κουβαλώντας τη λύση, το
/// ιστορικό αναβολών και τη σφραγίδα ολοκλήρωσης της παλιάς.
Task recreatedTaskFrom(Task edited) {
  return Task(
    title: edited.title,
    description: edited.description,
    dueDate: edited.dueDate,
    status: TaskStatus.open.toDbValue,
    priority: edited.priority,
    callId: edited.callId,
    callerId: edited.callerId,
    equipmentId: edited.equipmentId,
    departmentId: edited.departmentId,
    phoneId: edited.phoneId,
    phoneText: edited.phoneText,
    userText: edited.userText,
    equipmentText: edited.equipmentText,
    departmentText: edited.departmentText,
    origin: edited.origin,
  );
}

/// Επεξεργασία εκκρεμότητας.
///
/// Σε ολοκληρωμένη, η απόφαση «τι απογίνεται» επιλέγεται ΜΕΣΑ στη φόρμα και
/// επιστρέφει μαζί με το αποτέλεσμα — δεν υπάρχει προηγούμενο βήμα που η φόρμα
/// δεν θυμάται, ούτε δεύτερο παράθυρο μετά το κουμπί. Τίποτα δεν γράφεται στη
/// βάση πριν πατηθεί η αποθήκευση.
/// Γρήγορη ανάθεση από το μενού της κάρτας — διάλογος επιλογής υπευθύνου.
///
/// «Σε εμένα» πρώτο (η συχνότερη κίνηση: «το παίρνω εγώ»), τα υπόλοιπα ενεργά
/// προφίλ αλφαβητικά, και «Χωρίς ανάθεση» τελευταίο για να ελευθερωθεί — η
/// εκκρεμότητα επιστρέφει τότε σε όποιον την άνοιξε. Η τρέχουσα επιλογή
/// σημαίνεται και δεν ξαναγράφεται.
Future<void> assignTaskFlow(
  BuildContext context,
  WidgetRef ref,
  Task task,
) async {
  final taskId = task.id;
  if (taskId == null) return;

  final operators = await ref.read(activeOperatorsProvider.future);
  if (!context.mounted) return;

  final activeId = CurrentOperator.active?.id;
  final me = [
    for (final operator in operators)
      if (operator.id == activeId) operator,
  ];
  final others = [
    for (final operator in operators)
      if (operator.id != activeId) operator,
  ];

  // Ο τρέχων υπεύθυνος μένει στη λίστα με το ✓, αλλά δεν ξαναδιαλέγεται:
  // η επιλογή που δεν αλλάζει τίποτα δεν προσφέρεται, και η λίστα κρατά
  // σταθερή σύνθεση — το μάτι ξέρει πού είναι ο καθένας χωρίς να ξαναψάχνει
  // επειδή κάποιος εξαφανίστηκε.
  Widget option({
    required int? id,
    required String label,
    IconData icon = Icons.person_outline,
  }) {
    final isCurrent = task.assignedOperatorId == id;
    final theme = Theme.of(context);
    final color = isCurrent ? theme.disabledColor : null;
    return SimpleDialogOption(
      onPressed: isCurrent
          ? null
          : () => Navigator.of(context).pop((assignee: id)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: TextStyle(color: color)),
          ),
          if (isCurrent) Icon(Icons.check, size: 18, color: color),
        ],
      ),
    );
  }

  final choice = await showDialog<({int? assignee})>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('Ανάθεση: ${task.title}', overflow: TextOverflow.ellipsis),
      children: [
        for (final operator in me)
          option(
            id: operator.id,
            label: 'Σε εμένα (${operator.displayName})',
            icon: Icons.person_pin_outlined,
          ),
        for (final operator in others)
          option(id: operator.id, label: operator.displayName),
        const Divider(height: 8),
        option(
          id: null,
          label: 'Χωρίς ανάθεση',
          icon: Icons.person_off_outlined,
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice.assignee == task.assignedOperatorId) return;

  try {
    await ref.read(taskServiceProvider).assignTask(taskId, choice.assignee);
    await ref.read(tasksProvider.notifier).refresh();
  } on Exception {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Η ανάθεση δεν αποθηκεύτηκε. Δοκιμάστε ξανά.'),
      ),
    );
  }
}

Future<void> editTask(BuildContext context, WidgetRef ref, Task task) async {
  final formResult = await showTaskFormDialog(context, task: task);
  if (!context.mounted || formResult == null) return;
  final result = formResult.task;

  try {
    final notifier = ref.read(tasksProvider.notifier);
    switch (formResult.closedMode) {
      case ClosedTaskSaveMode.recreate:
        await notifier.addTask(recreatedTaskFrom(result));
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
      case ClosedTaskSaveMode.reopen:
        // Η λύση και το ιστορικό ταξιδεύουν μέσα στο αποτέλεσμα της φόρμας·
        // μόνο η κατάσταση αλλάζει. Η σφραγίδα ολοκλήρωσης μένει στη βάση.
        await notifier.updateTask(
          result.copyWith(status: TaskStatus.open.toDbValue),
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Η ολοκλήρωση αναιρέθηκε.')),
        );
        return;
      case ClosedTaskSaveMode.snoozeAgain:
        final due = result.dueDateTime ?? DateTime.now();
        await notifier.updateTask(
          result
              .copyWith(status: TaskStatus.snoozed.toDbValue)
              .addSnoozeEntry(due, note: formResult.snoozeReason),
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Η εκκρεμότητα αναβλήθηκε για τις: '
              '${DateFormat('dd/MM HH:mm').format(due)}',
            ),
          ),
        );
        return;
      case ClosedTaskSaveMode.stayClosed:
      case null:
        // Κανονική αποθήκευση — η κατάσταση δεν αλλάζει.
        break;
    }

    if (result.id != null) {
      await notifier.updateTask(result);
    } else {
      await notifier.addTask(result);
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

/// Αναίρεση ολοκλήρωσης — η εκκρεμότητα ξαναγίνεται ανοιχτή.
///
/// Η λύση **παραμένει** καταγεγραμμένη: περιγράφει τι δοκιμάστηκε και δεν
/// παύει να ισχύει επειδή το θέμα ξανάνοιξε.
Future<void> reopenTask(BuildContext context, WidgetRef ref, Task task) async {
  try {
    await ref
        .read(tasksProvider.notifier)
        .updateTask(task.copyWith(status: TaskStatus.open.toDbValue));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Η ολοκλήρωση αναιρέθηκε.')));
  } on TaskSaveException catch (e) {
    if (!context.mounted) return;
    _showTaskSaveError(context, e);
  }
}

/// Γρήγορη αναβολή από το μενού της κάρτας ή από το Ιστορικό Κλήσεων.
///
/// Η αναβολή μέσα από τη φόρμα επεξεργασίας ΔΕΝ περνά από εδώ: εκεί η νέα
/// λήξη και ο λόγος ορίζονται στην ίδια οθόνη με τα υπόλοιπα πεδία.
Future<void> snoozeTask(BuildContext context, WidgetRef ref, Task task) async {
  final service = ref.read(taskServiceProvider);
  final config =
      ref
          .read(taskSettingsConfigProvider)
          .maybeWhen(data: (c) => c, orElse: () => null) ??
      TaskSettingsConfig.defaultConfig();
  final maxRangeText = config.maxSnoozeDays == 1
      ? 'έως 1 ημέρα'
      : 'έως ${config.maxSnoozeDays} ημέρες';

  final result = await showDialog<SnoozeChoiceResult>(
    context: context,
    builder: (ctx) => SnoozeChoiceDialog(
      config: config,
      maxRangeText: maxRangeText,
      taskTitle: task.title,
      currentDue: task.dueDateTime,
      calculateDue: (option, from) =>
          service.calculateNextDueDate(config, option: option, fromDate: from),
    ),
  );

  if (!context.mounted || result == null) return;

  final choice = result.choice;
  final snoozeNote = result.note;

  if (choice != SnoozeChoiceDialog.customChoice) {
    // Η στιγμή που έδειξε το chip είναι αυτή που εφαρμόζεται — χωρίς νέο
    // υπολογισμό που θα διέφερε από όσα είδε ο χρήστης.
    final newDue =
        result.due ??
        service.calculateNextDueDate(
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

Future<void> deleteTaskWithCountdown(
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
    builder: (ctx) => DraggableDialogShell(
      title: const Text('Διαγραφή εκκρεμότητας'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
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
      content: TaskDeleteCountdownSnackContent(
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

Future<void> completeTask(
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
  try {
    await ref.read(tasksProvider.notifier).closeTask(task.id!, solutionNotes);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Εκκρεμότητα ολοκληρώθηκε.')));
  } on TaskSaveException catch (e) {
    if (!context.mounted) return;
    _showTaskSaveError(context, e);
  }
}

Future<bool> editTaskCaller(
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

Future<bool> editTaskDepartment(
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

Future<bool> editTaskEquipment(
  BuildContext context,
  WidgetRef ref,
  Task task,
) async {
  final equipmentId = task.equipmentId;
  if (equipmentId == null) return false;
  return EquipmentFormLauncher.openById(context, ref, equipmentId);
}
