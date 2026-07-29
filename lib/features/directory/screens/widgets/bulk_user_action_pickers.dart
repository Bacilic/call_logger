import 'package:flutter/material.dart';

import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/spell_check_controller.dart';

/// Κοινά βήματα των μαζικών ενεργειών (υπαλλήλων και εξοπλισμού): επιλογή
/// ενέργειας, επιβεβαίωση, ενημέρωση, ελεύθερο κείμενο και σημειώσεις.
///
/// Όλα μετακινούμενα και με το ίδιο λεξιλόγιο, ώστε οι δύο κατάλογοι να
/// συμπεριφέρονται πανομοιότυπα.

/// Επιλογή μίας από πολλές ενέργειες. Κάθε επιλογή: (ετικέτα, επεξήγηση, τιμή).
Future<T?> showBulkOptionDialog<T>(
  BuildContext context, {
  required String title,
  String? message,
  required List<(String, String?, T)> options,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => DraggableDialogShell(
      title: Text(title),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 470,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (message != null) ...[
                  Text(message),
                  const SizedBox(height: 12),
                ],
                for (final (label, subtitle, value) in options)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(label),
                      subtitle: subtitle == null ? null : Text(subtitle),
                      onTap: () => Navigator.of(ctx).pop(value),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Ακύρωση'),
          ),
        ],
      ),
    ),
  );
}

/// Σύνοψη «τι θα συμβεί σε ποιους» πριν από κάθε εκτέλεση.
Future<bool> showBulkConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Εφαρμογή',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => DraggableDialogShell(
      title: Text(title),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: Text(message)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

/// Ειλικρινές μήνυμα όταν η ενέργεια δεν έχει τίποτα να κάνει.
Future<void> showBulkInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(child: Text(message)),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Εντάξει'),
        ),
      ],
    ),
  );
}

/// Ελεύθερο κείμενο μίας γραμμής (π.χ. Τοποθεσία). Κενό δεν επιστρέφεται ποτέ.
Future<String?> showBulkTextInputDialog(
  BuildContext context, {
  required String title,
  required String label,
  String? helper,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) =>
        _BulkTextInputDialog(title: title, label: label, helper: helper),
  );
}

/// Σημειώσεις: τρόπος (προσθήκη/αντικατάσταση) + κείμενο με ορθογραφικό έλεγχο.
///
/// Επιστρέφει `(append, text)` — `append: true` σημαίνει προσθήκη σε νέα γραμμή.
Future<(bool, String)?> showBulkNotesDialog(
  BuildContext context, {
  required String title,
}) {
  return showDialog<(bool, String)>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _BulkNotesDialog(title: title),
  );
}

class _BulkTextInputDialog extends StatefulWidget {
  const _BulkTextInputDialog({
    required this.title,
    required this.label,
    this.helper,
  });

  final String title;
  final String label;
  final String? helper;

  @override
  State<_BulkTextInputDialog> createState() => _BulkTextInputDialogState();
}

class _BulkTextInputDialogState extends State<_BulkTextInputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canApply => _controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableDialogShell(
      title: Text(widget.title),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: widget.label,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (widget.helper != null && !_canApply)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    widget.helper!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: _canApply
                ? () => Navigator.of(context).pop(_controller.text.trim())
                : null,
            child: const Text('Συνέχεια'),
          ),
        ],
      ),
    );
  }
}

class _BulkNotesDialog extends StatefulWidget {
  const _BulkNotesDialog({required this.title});

  final String title;

  @override
  State<_BulkNotesDialog> createState() => _BulkNotesDialogState();
}

class _BulkNotesDialogState extends State<_BulkNotesDialog> {
  final _controller = SpellCheckController();
  final _focusNode = FocusNode();
  bool _append = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool get _canApply => _controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableDialogShell(
      title: Text(widget.title),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RadioGroup<bool>(
                groupValue: _append,
                onChanged: (v) => setState(() => _append = v ?? true),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<bool>(
                      value: true,
                      title: Text('Προσθήκη στις υπάρχουσες'),
                      subtitle: Text('Νέα γραμμή κάτω από ό,τι ήδη υπάρχει.'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<bool>(
                      value: false,
                      title: Text('Αντικατάσταση σημειώσεων'),
                      subtitle: Text(
                        'Οι παλιές σημειώσεις χάνονται '
                        '(με δυνατότητα αναίρεσης).',
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              LexiconSpellTextFormField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Κείμενο σημείωσης',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (!_canApply)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Το κενό κείμενο δεν αποθηκεύεται — για διαγραφή '
                    'σημειώσεων χρησιμοποιήστε τον «Καθαρισμό πεδίου».',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: _canApply
                ? () => Navigator.of(
                    context,
                  ).pop((_append, _controller.text.trim()))
                : null,
            child: const Text('Συνέχεια'),
          ),
        ],
      ),
    );
  }
}
