import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/task_save_exception.dart';
import '../../../core/errors/task_stale_exception.dart';
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
import '../../operators/avatars/operator_avatar_image.dart';
import '../../operators/utils/assignable_operators.dart';
import '../models/task.dart';
import '../models/task_settings_config.dart';
import '../providers/pending_task_delete_provider.dart';
import '../providers/task_service_provider.dart';
import '../providers/task_settings_config_provider.dart';
import '../providers/tasks_provider.dart';
import '../widgets/snooze_choice_dialog.dart';
import 'task_close_dialog.dart';
import 'task_conflict_dialog.dart';
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

/// Εκτελεί μια εγγραφή εκκρεμότητας με φρουρό διένεξης.
///
/// **Ένα σημείο για όλες τις ροές** (κλείσιμο, αναβολή, ανάθεση, επαναφορά,
/// επεξεργασία): αν ο φρουρός της βάσης βρει ότι κάποιος άλλος πρόλαβε, ο
/// χρήστης βλέπει τι άλλαξε και αποφασίζει. Χωρίς κοινό σημείο, κάθε νέα ροή θα
/// έπρεπε να θυμηθεί μόνη της τον διάλογο — και η πρώτη που θα τον ξεχνούσε θα
/// έσβηνε ξένη δουλειά σιωπηλά.
///
/// Επιστρέφει `true` μόνο όταν η εγγραφή τελικά πέρασε.
Future<bool> _writeTaskGuarded(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(bool force) write,
) async {
  try {
    await write(false);
    return true;
  } on TaskStaleException catch (conflict) {
    if (!context.mounted) return false;
    final choice = await showTaskConflictDialog(context, conflict);
    if (choice != TaskConflictChoice.overwrite) {
      // Και στο «Δες τη φρέσκια εικόνα» και στο κλείσιμο του διαλόγου: η λίστα
      // ξαναδιαβάζεται, ώστε ο χρήστης να κοιτάζει την αλήθεια πριν ξαναδοκιμάσει.
      await ref.read(tasksProvider.notifier).refresh();
      return false;
    }
    try {
      await write(true);
      return true;
    } on TaskSaveException catch (e) {
      if (!context.mounted) return false;
      _showTaskSaveError(context, e);
      return false;
    }
  }
}

/// Αποθήκευση εκκρεμότητας με φρουρό διένεξης.
///
/// Το [expected] είναι η εκκρεμότητα **όπως τη διάβασε η οθόνη**, πριν τις
/// αλλαγές του χρήστη. Είναι υποχρεωτικό και όχι προαιρετικό επίτηδες: χωρίς
/// αφετηρία ο φρουρός μπλοκάρει κάθε γραμμή που άγγιξε οποιοσδήποτε — και
/// τις δικές μου αλλαγές μαζί.
Future<bool> saveTaskGuarded(
  BuildContext context,
  WidgetRef ref,
  Task task, {
  required Task? expected,
}) {
  return _writeTaskGuarded(
    context,
    ref,
    (force) => ref
        .read(tasksProvider.notifier)
        .updateTask(task, expected: expected, force: force),
  );
}

/// Κλείσιμο εκκρεμότητας με φρουρό διένεξης.
Future<bool> closeTaskGuarded(
  BuildContext context,
  WidgetRef ref,
  Task task,
  String solutionNotes,
) {
  return _writeTaskGuarded(
    context,
    ref,
    (force) => ref
        .read(tasksProvider.notifier)
        .closeTask(task, solutionNotes, force: force),
  );
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

  // Τα ενεργά προφίλ, συν τον σημερινό υπεύθυνο ακόμη κι αν έχει
  // απενεργοποιηθεί: αλλιώς ο διάλογος δείχνει μόνο ενεργούς και «Χωρίς
  // ανάθεση», και η εκκρεμότητα μοιάζει αδέσποτη ενώ ανήκει κάπου.
  final operators = operatorsForAssignment(
    await ref.read(allOperatorsProvider.future),
    task.assignedOperatorId,
  );
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
    IconData? icon,
    String? avatarKey,
    bool isDisabledProfile = false,
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
          // Οι δύο γραμμές χωρίς πρόσωπο («Χωρίς ανάθεση») κρατούν εικονίδιο
          // ενέργειας· τα προφίλ δείχνουν το δικό τους. Και τα δύο πιάνουν το
          // ίδιο πλάτος, ώστε τα ονόματα να ευθυγραμμίζονται.
          SizedBox(
            width: 22,
            child: icon != null
                ? Icon(icon, size: 18, color: color)
                : OperatorAvatarImage(
                    avatarKey: avatarKey,
                    size: 22,
                    muted: isDisabledProfile || isCurrent,
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              // Πλάγια για το απενεργοποιημένο προφίλ — ίδιο σήμα με το
              // «(διαγραμμένο)» των οντοτήτων καταλόγου.
              style: TextStyle(
                color: color,
                fontStyle: isDisabledProfile ? FontStyle.italic : null,
              ),
            ),
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
            avatarKey: operator.avatarKey,
          ),
        for (final operator in others)
          option(
            id: operator.id,
            label: operatorChoiceLabel(operator),
            avatarKey: operator.avatarKey,
            isDisabledProfile: !operator.isActive,
          ),
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
        final reopened = await saveTaskGuarded(
          context,
          ref,
          result.copyWith(status: TaskStatus.open.toDbValue),
          expected: task,
        );
        if (!context.mounted || !reopened) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Η ολοκλήρωση αναιρέθηκε.')),
        );
        return;
      case ClosedTaskSaveMode.snoozeAgain:
        final due = result.dueDateTime ?? DateTime.now();
        final snoozedAgain = await saveTaskGuarded(
          context,
          ref,
          result
              .copyWith(status: TaskStatus.snoozed.toDbValue)
              .addSnoozeEntry(due, note: formResult.snoozeReason),
          expected: task,
        );
        if (!context.mounted || !snoozedAgain) return;
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
      final saved = await saveTaskGuarded(context, ref, result, expected: task);
      if (!saved) return;
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
    final reopened = await saveTaskGuarded(
      context,
      ref,
      task.copyWith(status: TaskStatus.open.toDbValue),
      expected: task,
    );
    if (!context.mounted || !reopened) return;
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
      final snoozed = await saveTaskGuarded(
        context,
        ref,
        updatedTask,
        expected: task,
      );
      if (!context.mounted || !snoozed) return;
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
    final snoozed = await saveTaskGuarded(
      context,
      ref,
      updatedTask,
      expected: task,
    );
    if (!context.mounted || !snoozed) return;
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
    final closed = await closeTaskGuarded(context, ref, task, solutionNotes);
    if (!context.mounted || !closed) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Εκκρεμότητα ολοκληρώθηκε.')));
  } on TaskSaveException catch (e) {
    if (!context.mounted) return;
    _showTaskSaveError(context, e);
  }
}

/// Μηνύματα όταν η συνδεδεμένη οντότητα δεν υπάρχει πια στον κατάλογο.
///
/// Ο εξοπλισμός το έλεγε ήδη, μέσα από τον κοινό εκκινητή της φόρμας του. Ο
/// υπάλληλος και το τμήμα γύριζαν σιωπηλά: το πάτημα δεν έκανε τίποτα και το
/// κουμπί έμοιαζε χαλασμένο.
const String kCatalogUserMissingMessage =
    'Ο υπάλληλος δεν βρέθηκε στον κατάλογο.';
const String kCatalogDepartmentMissingMessage =
    'Το τμήμα δεν βρέθηκε στον κατάλογο.';

void _showCatalogEntityMissing(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> editTaskCaller(
  BuildContext context,
  WidgetRef ref,
  Task task,
) async {
  final callerId = task.callerId;
  if (callerId == null) return false;
  final lookupBundle = await ref.read(lookupServiceProvider.future);
  if (!context.mounted) return false;
  final user = lookupBundle.service.findUserById(callerId);
  if (user == null) {
    _showCatalogEntityMissing(context, kCatalogUserMissingMessage);
    return false;
  }

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
  if (!context.mounted) return false;
  if (department == null) {
    _showCatalogEntityMissing(context, kCatalogDepartmentMissingMessage);
    return false;
  }

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
