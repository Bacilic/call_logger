import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/draggable_dialog_shell.dart';
import '../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../core/widgets/spell_check_controller.dart';
import '../../calls/provider/smart_entity_selector_provider.dart';
import '../../calls/screens/widgets/smart_entity_selector_widget.dart';
import '../models/task.dart';
import '../models/task_settings_config.dart';
import '../providers/task_service_provider.dart';
import '../providers/task_settings_config_provider.dart';
import '../ui/task_due_option_tooltips.dart';
import '../ui/task_due_quick_chips.dart';

/// Ψευδο-κωδικός για το chip «Προεπιλογή ρυθμίσεων» — δεν αποθηκεύεται πουθενά,
/// χρησιμεύει μόνο για να ξεχωρίζει το chip μέσα στη σειρά.
const String _kSettingsDefaultOption = 'settings_default';

/// Επιστρέφει το Task που δημιουργήθηκε/τροποποιήθηκε ή null αν ακυρώθηκε.
Future<Task?> showTaskFormDialog(BuildContext context, {Task? task}) {
  return showDialog<Task?>(
    context: context,
    builder: (context) => _TaskFormDialog(task: task),
  );
}

class _TaskFormDialog extends ConsumerStatefulWidget {
  const _TaskFormDialog({this.task});

  final Task? task;

  @override
  ConsumerState<_TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends ConsumerState<_TaskFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final GlobalKey<SmartEntitySelectorWidgetState> _entitySelectorKey =
      GlobalKey<SmartEntitySelectorWidgetState>();

  /// Για ασφαλές `invalidate` στο `dispose` — το `ref` εκεί δεν επιτρέπεται.
  ProviderContainer? _providerContainer;
  late final SpellCheckController _titleController;
  late final SpellCheckController _descriptionController;
  late final List<SpellCheckController> _snoozeNoteControllers;
  late int _priority;
  late DateTime _dueDate;
  bool _userPickedDue = false;

  static const List<int> _priorityValues = [0, 1, 2];
  static const List<String> _priorityLabels = ['Κανονική', 'Υψηλή', 'Κρίσιμη'];

  @override
  void initState() {
    super.initState();
    if (widget.task != null) {
      Future.microtask(() {
        if (!mounted) return;
        ref.read(taskSmartEntityProvider.notifier).loadFromTask(widget.task!);
      });
    }
    final t = widget.task;
    _titleController = SpellCheckController()..text = t?.title ?? '';
    _descriptionController = SpellCheckController()
      ..text = t?.description ?? '';
    _snoozeNoteControllers = (t?.snoozeEntries ?? const [])
        .map((e) => SpellCheckController()..text = e.note ?? '')
        .toList();
    _priority = t?.priority ?? 0;
    _userPickedDue = t != null;
    _dueDate =
        t?.dueDateTime ??
        ref
            .read(taskServiceProvider)
            .calculateNextDueDate(
              TaskSettingsConfig.defaultConfig(),
              option: TaskSettingsConfig.kOptionDefault,
            );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.task != null || _userPickedDue) return;
      ref.read(taskSettingsConfigProvider.future).then((c) {
        if (!mounted || widget.task != null || _userPickedDue) return;
        setState(() {
          _dueDate = ref
              .read(taskServiceProvider)
              .calculateNextDueDate(
                c,
                option: TaskSettingsConfig.kOptionDefault,
              );
        });
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _providerContainer ??= ProviderScope.containerOf(context);
  }

  @override
  void dispose() {
    final container = _providerContainer;
    if (container != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        container.invalidate(taskSmartEntityProvider);
      });
    }
    _titleController.dispose();
    _descriptionController.dispose();
    for (final controller in _snoozeNoteControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  TaskSettingsConfig _readSnoozeConfig() =>
      ref
          .read(taskSettingsConfigProvider)
          .maybeWhen(data: (c) => c, orElse: () => null) ??
      TaskSettingsConfig.defaultConfig();

  Future<void> _pickDueDate() async {
    final cfg = _readSnoozeConfig();
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    final lastDate = firstDate.add(Duration(days: cfg.maxSnoozeDays));
    var initialDate = DateTime(_dueDate.year, _dueDate.month, _dueDate.day);
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
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueDate),
    );
    if (!mounted || time == null) return;
    setState(() {
      _userPickedDue = true;
      _dueDate = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  /// Στιγμή λήξης μιας γρήγορης επιλογής — ο ίδιος υπολογισμός που εφαρμόζεται
  /// όταν πατηθεί, ώστε το chip να μη δείχνει άλλη ώρα από την πραγματική.
  DateTime _quickDue(String option, DateTime from) => ref
      .read(taskServiceProvider)
      .calculateNextDueDate(
        _readSnoozeConfig(),
        option: option,
        fromDate: from,
      );

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final dueDateStr = _dueDate.toIso8601String();
    final entityState = ref.read(taskSmartEntityProvider);
    final phoneRaw = entityState.phoneText?.trim();
    final phoneText = phoneRaw == null || phoneRaw.isEmpty ? null : phoneRaw;
    String? trimOrNull(String s) {
      final t = s.trim();
      return t.isEmpty ? null : t;
    }

    final result =
        widget.task?.copyWith(
          title: title,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          dueDate: dueDateStr,
          priority: _priority,
          updatedAt: DateTime.now().toIso8601String(),
          callerId: entityState.selectedCaller?.id,
          userText: trimOrNull(entityState.callerDisplayText),
          phoneText: phoneText,
          departmentText: trimOrNull(entityState.departmentText),
          equipmentText: trimOrNull(entityState.equipmentText),
        ) ??
        Task(
          title: title,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          dueDate: dueDateStr,
          status: 'open',
          priority: _priority,
          callerId: entityState.selectedCaller?.id,
          userText: trimOrNull(entityState.callerDisplayText),
          phoneText: phoneText,
          departmentText: trimOrNull(entityState.departmentText),
          equipmentText: trimOrNull(entityState.equipmentText),
          origin: Task.originManualFab,
        );

    final Task submitted;
    if (widget.task != null &&
        widget.task!.snoozeEntries.isNotEmpty &&
        _snoozeNoteControllers.length == widget.task!.snoozeEntries.length) {
      submitted = result.withUpdatedSnoozeNotes(
        _snoozeNoteControllers.map((c) => c.text).toList(),
      );
    } else {
      submitted = result;
    }
    Navigator.of(context).pop(submitted);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(taskSettingsConfigProvider);
    final service = ref.read(taskServiceProvider);
    final cfg =
        ref
            .watch(taskSettingsConfigProvider)
            .maybeWhen(data: (c) => c, orElse: () => null) ??
        TaskSettingsConfig.defaultConfig();
    // Μία στιγμή αναφοράς ανά χτίσιμο: κάθε γρήγορη προθεσμία και η
    // προεπισκόπησή της προκύπτουν από το ίδιο «τώρα».
    final quickDueNow = DateTime.now();
    final suggestedDefault = service.calculateNextDueDate(
      cfg,
      option: TaskSettingsConfig.kOptionDefault,
      fromDate: quickDueNow,
    );

    final theme = Theme.of(context);
    final mq = MediaQuery.sizeOf(context);
    final dialogWidth = (mq.width - 48).clamp(400.0, 860.0);
    final hasEntityContent = ref.watch(
      taskSmartEntityProvider.select((s) => s.hasAnyContent),
    );

    return DraggableDialogShell(
      title: Text(
        widget.task == null ? 'Νέα εκκρεμότητα' : 'Επεξεργασία εκκρεμότητας',
      ),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: dialogWidth,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest,
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const gapsAndTrailing = 120.0;
                          final mw = constraints.maxWidth;
                          final available = (mw - gapsAndTrailing).clamp(
                            200.0,
                            double.infinity,
                          );
                          final w1 = (available * 0.18).clamp(0.0, 170.0);
                          final w2 = (available * 0.34).clamp(0.0, 300.0);
                          final wDept = (available * 0.24).clamp(0.0, 240.0);
                          final w3 = (available * 0.20).clamp(0.0, 185.0);
                          final minRowWidth =
                              w1 +
                              12 +
                              w2 +
                              12 +
                              wDept +
                              12 +
                              w3 +
                              gapsAndTrailing;
                          final selector = SmartEntitySelectorWidget(
                            key: _entitySelectorKey,
                            provider: taskSmartEntityProvider,
                            w1: w1,
                            w2: w2,
                            wDept: wDept,
                            w3: w3,
                            trailingRowChildren: [
                              const SizedBox(width: 4),
                              IgnorePointer(
                                ignoring: !hasEntityContent,
                                child: AnimatedOpacity(
                                  opacity: hasEntityContent ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 180),
                                  child: AnimatedScale(
                                    scale: hasEntityContent ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 180),
                                    child: IconButton(
                                      icon: Icon(
                                        Icons.clear,
                                        color: theme.colorScheme.error,
                                      ),
                                      tooltip: 'Καθαρισμός πεδίων καλούντα',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 40,
                                        minHeight: 40,
                                      ),
                                      onPressed: () => _entitySelectorKey
                                          .currentState
                                          ?.performClearAllFields(),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                          if (mw + 0.5 < minRowWidth) {
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: minRowWidth,
                                child: selector,
                              ),
                            );
                          }
                          return selector;
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LexiconSpellTextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Τίτλος',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Υποχρεωτικό πεδίο'
                        : null,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  LexiconSpellTextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Περιγραφή',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _priority.clamp(0, 2),
                    decoration: const InputDecoration(
                      labelText: 'Προτεραιότητα',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(
                      _priorityValues.length,
                      (i) => DropdownMenuItem(
                        value: _priorityValues[i],
                        child: Text(_priorityLabels[i]),
                      ),
                    ),
                    onChanged: (v) => setState(() => _priority = v ?? 0),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Γρήγορη προθεσμία',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  TaskDueQuickChips(
                    now: quickDueNow,
                    choices: [
                      TaskDueQuickChoice(
                        option: TaskSettingsConfig.kOneHour,
                        label: '+1 ώρα',
                        due: _quickDue(
                          TaskSettingsConfig.kOneHour,
                          quickDueNow,
                        ),
                        tooltip: TaskDueOptionTooltips.plusOneHour(),
                      ),
                      TaskDueQuickChoice(
                        option: TaskSettingsConfig.kDayEnd,
                        label: 'Μέσα στο ωράριο',
                        due: _quickDue(TaskSettingsConfig.kDayEnd, quickDueNow),
                        tooltip: TaskDueOptionTooltips.withinSchedule(
                          cfg.nextBusinessHour,
                          cfg.dayEndTime,
                        ),
                      ),
                      TaskDueQuickChoice(
                        option: TaskSettingsConfig.kNextBusiness,
                        label: 'Επόμενη εργάσιμη',
                        due: _quickDue(
                          TaskSettingsConfig.kNextBusiness,
                          quickDueNow,
                        ),
                        tooltip: TaskDueOptionTooltips.nextBusiness(
                          cfg.nextBusinessHour,
                        ),
                      ),
                      TaskDueQuickChoice(
                        option: _kSettingsDefaultOption,
                        label: 'Προεπιλογή ρυθμίσεων',
                        due: suggestedDefault,
                        tooltip:
                            'Η λήξη ορίζεται από την προεπιλεγμένη επιλογή των '
                            'ρυθμίσεων εκκρεμοτήτων.',
                      ),
                    ],
                    onSelected: (choice) => setState(() {
                      _userPickedDue = true;
                      _dueDate = choice.due;
                    }),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ημερομηνία / ώρα λήξης'),
                    subtitle: Text(
                      '${_dueDate.day}/${_dueDate.month}/${_dueDate.year} ${_dueDate.hour.toString().padLeft(2, '0')}:${_dueDate.minute.toString().padLeft(2, '0')}',
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: _pickDueDate,
                      child: const Text('Επιλογή'),
                    ),
                  ),
                  if (widget.task != null &&
                      widget.task!.snoozeEntries.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Αναβολές',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    for (
                      var i = 0;
                      i < widget.task!.snoozeEntries.length;
                      i++
                    ) ...[
                      Text(
                        'Αναβολή ${i + 1} — '
                        '${DateFormat('dd/MM HH:mm').format(widget.task!.snoozeEntries[i].snoozedAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LexiconSpellTextFormField(
                        key: ValueKey('snooze_note_$i'),
                        controller: _snoozeNoteControllers[i],
                        decoration: const InputDecoration(
                          labelText: 'Σημείωση αναβολής',
                          hintText: 'Σημείωση αναβολής',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        minLines: 1,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                      if (i < widget.task!.snoozeEntries.length - 1)
                        const SizedBox(height: 8),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: _submit,
            child: Text(widget.task == null ? 'Δημιουργία' : 'Αποθήκευση'),
          ),
        ],
      ),
    );
  }
}
