import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../core/widgets/spell_check_controller.dart';

/// Διάλογος κλεισίματος εκκρεμότητας με υποχρεωτικό πεδίο "Λύση / Σημειώσεις Κλεισίματος".
/// Επιστρέφει τα solutionNotes αν ο χρήστης επιβεβαιώσει, αλλιώς null.
Future<String?> showTaskCloseDialog(
  BuildContext context, {
  String? initialSolutionNotes,
}) {
  return showDialog<String?>(
    context: context,
    builder: (context) => _TaskCloseDialog(
      initialSolutionNotes: initialSolutionNotes,
    ),
  );
}

class _TaskCloseDialog extends ConsumerStatefulWidget {
  const _TaskCloseDialog({this.initialSolutionNotes});

  final String? initialSolutionNotes;

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
    return AlertDialog(
      title: const Text('Ολοκλήρωση εκκρεμότητας'),
      content: Form(
        key: _formKey,
        child: LexiconSpellTextFormField(
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
