import 'package:flutter/material.dart';

import '../models/task.dart';

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

class _TaskFormDialog extends StatefulWidget {
  const _TaskFormDialog({this.task});

  final Task? task;

  @override
  State<_TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends State<_TaskFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late int _priority;
  late DateTime _dueDate;

  static const List<int> _priorityValues = [0, 1, 2];
  static const List<String> _priorityLabels = ['Κανονική', 'Υψηλή', 'Κρίσιμη'];

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleController = TextEditingController(text: t?.title ?? '');
    _descriptionController = TextEditingController(text: t?.description ?? '');
    _priority = t?.priority ?? 0;
    _dueDate = t?.dueDateTime ?? DateTime.now().add(const Duration(hours: 1));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueDate),
    );
    if (!mounted || time == null) return;
    setState(() {
      _dueDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
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
