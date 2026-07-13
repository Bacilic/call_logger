import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../core/widgets/spell_check_controller.dart';
import '../models/task.dart';
import '../utils/task_duration_format.dart';

/// Διάλογος κλεισίματος εκκρεμότητας με υποχρεωτικό πεδίο "Λύση / Σημειώσεις Κλεισίματος".
/// Επιστρέφει τα solutionNotes αν ο χρήστης επιβεβαιώσει, αλλιώς null.
Future<String?> showTaskCloseDialog(
  BuildContext context, {
  String? initialSolutionNotes,
  Task? task,
}) {
  return showDialog<String?>(
    context: context,
    builder: (context) => _TaskCloseDialog(
      initialSolutionNotes: initialSolutionNotes,
      task: task,
    ),
  );
}

List<String> buildTaskCloseTimingLines({
  required DateTime? createdAt,
  required List<TaskSnoozeEntry> snoozeEntries,
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();
  final lines = <String>[];
  if (createdAt != null) {
    final createdLabel = DateFormat('dd/MM/yyyy HH:mm').format(createdAt);
    final sinceCreation = durationSince(createdAt, effectiveNow);
    lines.add('Δημιουργήθηκε: $createdLabel — πριν από $sinceCreation');
  }
  if (snoozeEntries.isNotEmpty) {
    final lastSnooze = snoozeEntries.last.snoozedAt;
    final snoozeLabel = DateFormat('dd/MM HH:mm').format(lastSnooze);
    final sinceSnooze = durationSince(lastSnooze, effectiveNow);
    lines.add(
      'Τελευταία αναβολή: $snoozeLabel — πριν από $sinceSnooze '
      '(${snoozeEntries.length} αναβολές συνολικά)',
    );
  }
  return lines;
}

class _TaskCloseDialog extends ConsumerStatefulWidget {
  const _TaskCloseDialog({this.initialSolutionNotes, this.task});

  final String? initialSolutionNotes;
  final Task? task;

  @override
  ConsumerState<_TaskCloseDialog> createState() => _TaskCloseDialogState();
}

class _TaskCloseDialogState extends ConsumerState<_TaskCloseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final SpellCheckController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SpellCheckController()
      ..text = widget.initialSolutionNotes?.trim() ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    if (!_formKey.currentState!.validate()) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timingLines = buildTaskCloseTimingLines(
      createdAt: widget.task?.createdAtDateTime,
      snoozeEntries: widget.task?.snoozeEntries ?? const [],
    );

    return AlertDialog(
      title: const Text('Ολοκλήρωση εκκρεμότητας'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (timingLines.isNotEmpty) ...[
                Text(
                  timingLines.join('\n'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              LexiconSpellTextFormField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'Λύση / Σημειώσεις Κλεισίματος',
                  hintText: 'Περιγράψτε τη λύση ή σημειώσεις...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Το πεδίο είναι υποχρεωτικό για το κλείσιμο.';
                  }
                  return null;
                },
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: const Text('Κλείσιμο εκκρεμότητας'),
        ),
      ],
    );
  }
}
