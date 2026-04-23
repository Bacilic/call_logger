import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../core/widgets/spell_check_controller.dart';
import '../../calls/provider/smart_entity_selector_provider.dart';
import '../../calls/screens/widgets/smart_entity_selector_widget.dart';
import '../models/task.dart';
import '../models/task_settings_config.dart';
import '../providers/task_service_provider.dart';
import '../providers/task_settings_config_provider.dart';
import '../ui/task_due_option_tooltips.dart';

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
    _providerContainer?.invalidate(taskSmartEntityProvider);
    _titleController.dispose();
    _descriptionController.dispose();
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

  void _applyQuickDue(String option) {
    final service = ref.read(taskServiceProvider);
    setState(() {
      _userPickedDue = true;
      _dueDate = service.calculateNextDueDate(
        _readSnoozeConfig(),
        option: option,
        fromDate: DateTime.now(),
      );
    });
  }

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
    Navigator.of(context).pop(result);
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
    final suggestedDefault = service.calculateNextDueDate(
      cfg,
      option: TaskSettingsConfig.kOptionDefault,
      fromDate: DateTime.now(),
    );

    final theme = Theme.of(context);
    final mq = MediaQuery.sizeOf(context);
    final dialogWidth = (mq.width - 48).clamp(400.0, 860.0);
    final hasEntityContent = ref.watch(
      taskSmartEntityProvider.select((s) => s.hasAnyContent),
    );

    return AlertDialog(
      title: Text(
        widget.task == null ? 'Νέα εκκρεμότητα' : 'Επεξεργασία εκκρεμότητας',
      ),
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
                const SizedBox(height: 6),
                Text(
                  'Προτεινόμενη από ρυθμίσεις: '
                  '${suggestedDefault.day}/${suggestedDefault.month}/${suggestedDefault.year} '
                  '${suggestedDefault.hour.toString().padLeft(2, '0')}:'
                  '${suggestedDefault.minute.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Tooltip(
                      message: TaskDueOptionTooltips.plusOneHour(),
                      child: FilledButton.tonal(
                        onPressed: () =>
                            _applyQuickDue(TaskSettingsConfig.kOneHour),
                        child: const Text('+1 ώρα'),
                      ),
                    ),
                    Tooltip(
                      message: TaskDueOptionTooltips.withinSchedule(
                        cfg.nextBusinessHour,
                        cfg.dayEndTime,
                      ),
                      child: FilledButton.tonal(
                        onPressed: () =>
                            _applyQuickDue(TaskSettingsConfig.kDayEnd),
                        child: const Text('Μέσα στο ωράριο'),
                      ),
                    ),
                    Tooltip(
                      message: TaskDueOptionTooltips.nextBusiness(
                        cfg.nextBusinessHour,
                      ),
                      child: FilledButton.tonal(
                        onPressed: () =>
                            _applyQuickDue(TaskSettingsConfig.kNextBusiness),
                        child: const Text('Επόμενη εργάσιμη'),
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () {
                        setState(() {
                          _userPickedDue = true;
                          _dueDate = suggestedDefault;
                        });
                      },
                      child: const Text('Προεπιλογή ρυθμίσεων'),
                    ),
                  ],
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
    );
  }
}
