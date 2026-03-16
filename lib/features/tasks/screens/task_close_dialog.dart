import 'package:flutter/material.dart';

import '../../../core/utils/spell_check.dart';

/// Δialόγιο κλεισίματος εκκρεμότητας με υποχρεωτικό πεδίο "Λύση / Σημειώσεις Κλεισίματος".
/// Επιστρέφει τα solutionNotes αν ο χρήστης επιβεβαιώσει, αλλιώς null.
Future<String?> showTaskCloseDialog(BuildContext context) {
  return showDialog<String?>(
    context: context,
    builder: (context) => const _TaskCloseDialog(),
  );
}

class _TaskCloseDialog extends StatefulWidget {
  const _TaskCloseDialog();

  @override
  State<_TaskCloseDialog> createState() => _TaskCloseDialogState();
}

class _TaskCloseDialogState extends State<_TaskCloseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

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
        child: TextFormField(
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
          spellCheckConfiguration: platformSpellCheckConfiguration,
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
