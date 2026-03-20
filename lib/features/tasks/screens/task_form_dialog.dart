import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/spell_check.dart';
import '../models/task.dart';
import '../models/task_snooze_config.dart';
import '../providers/task_service_provider.dart';
import '../providers/task_snooze_config_provider.dart';

/// Επιστρέφει το Task που δημιουργήθηκε/τροποποιήθηκε ή null αν ακυρώθηκε.
Future<Task?> showTaskFormDialog(
  BuildContext context, {
  Task? task,
}) {
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
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late int _priority;
  late DateTime _dueDate;
  bool _userPickedDue = false;

  static const List<int> _priorityValues = [0, 1, 2];
  static const List<String> _priorityLabels = ['Κανονική', 'Υψηλή', 'Κρίσιμη'];

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleController = TextEditingController(text: t?.title ?? '');
    _descriptionController = TextEditingController(text: t?.description ?? '');
    _priority = t?.priority ?? 0;
    _userPickedDue = t != null;
    _dueDate = t?.dueDateTime ??
        ref.read(taskServiceProvider).calculateNextDueDate(
              TaskSnoozeConfig.defaultConfig(),
              option: TaskSnoozeConfig.kOptionDefault,
            );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.task != null || _userPickedDue) return;
      ref.read(taskSnoozeConfigProvider.future).then((c) {
        if (!mounted || widget.task != null || _userPickedDue) return;
        setState(() {
          _dueDate = ref.read(taskServiceProvider).calculateNextDueDate(
                c,
                option: TaskSnoozeConfig.kOptionDefault,
              );
        });
      });
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  TaskSnoozeConfig _readSnoozeConfig() =>
      ref.read(taskSnoozeConfigProvider).maybeWhen(
            data: (c) => c,
            orElse: () => null,
          ) ??
      TaskSnoozeConfig.defaultConfig();

  Future<void> _pickDueDate() async {
    final cfg = _readSnoozeConfig();
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    final lastDate = firstDate.add(Duration(days: cfg.maxSnoozeDays));
    var initialDate = DateTime(
      _dueDate.year,
      _dueDate.month,
      _dueDate.day,
    );
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
      _dueDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
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
    final result = widget.task?.copyWith(
          title: title,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          dueDate: dueDateStr,
          priority: _priority,
          updatedAt: DateTime.now().toIso8601String(),
        ) ??
        Task(
          title: title,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          dueDate: dueDateStr,
          status: 'open',
          priority: _priority,
        );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(taskSnoozeConfigProvider);
    final service = ref.read(taskServiceProvider);
    final cfg = ref.watch(taskSnoozeConfigProvider).maybeWhen(
          data: (c) => c,
          orElse: () => null,
        ) ??
        TaskSnoozeConfig.defaultConfig();
    final suggestedDefault = service.calculateNextDueDate(
      cfg,
      option: TaskSnoozeConfig.kOptionDefault,
      fromDate: DateTime.now(),
    );

    return AlertDialog(
      title: Text(widget.task == null ? 'Νέα εκκρεμότητα' : 'Επεξεργασία εκκρεμότητας'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Τίτλος',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Υποχρεωτικό πεδίο' : null,
                  textCapitalization: TextCapitalization.sentences,
                  spellCheckConfiguration: platformSpellCheckConfiguration,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Περιγραφή',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  spellCheckConfiguration: platformSpellCheckConfiguration,
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
                    FilledButton.tonal(
                      onPressed: () => _applyQuickDue(TaskSnoozeConfig.kOneHour),
                      child: const Text('+1 ώρα'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _applyQuickDue(TaskSnoozeConfig.kDayEnd),
                      child: const Text('Μέσα στην ημέρα'),
                    ),
                    FilledButton.tonal(
                      onPressed: () =>
                          _applyQuickDue(TaskSnoozeConfig.kNextBusiness),
                      child: const Text('Επόμενη εργάσιμη'),
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
