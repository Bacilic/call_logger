import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../models/category_model.dart';
import '../../providers/category_directory_provider.dart';
import 'category_undo_snackbar.dart';

enum _EditSaveChoice { cancel, rename, newRow }

/// Διάλογος προσθήκης ή επεξεργασίας κατηγορίας.
class CategoryFormDialog extends StatefulWidget {
  const CategoryFormDialog({
    super.key,
    this.initialCategory,
    required this.notifier,
  });

  final CategoryModel? initialCategory;
  final CategoryDirectoryNotifier notifier;

  @override
  State<CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<CategoryFormDialog> {
  late final TextEditingController _controller;
  late final String _initialFieldText;

  void _onControllerChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    _initialFieldText = widget.initialCategory?.name ?? '';
    _controller = TextEditingController(text: _initialFieldText);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  /// Ενεργή αποθήκευση μόνο αν το πεδίο διαφέρει από το αρχικό και δεν είναι κενό (μετά το trim).
  bool get _saveEnabled =>
      _controller.text.trim().isNotEmpty &&
      _controller.text != _initialFieldText;

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _onSave() async {
    final t = _controller.text.trim();
    if (t.isEmpty) {
      _showError('Συμπληρώστε όνομα κατηγορίας.');
      return;
    }
    final init = widget.initialCategory;
    if (init == null) {
      try {
        final restored = await widget.notifier.addCategory(t);
        if (!mounted) return;
        if (restored) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(kCategoryRestoredFromDeletedUserMessage),
            ),
          );
        }
        Navigator.of(context).pop();
      } catch (e) {
        _showError('$e');
      }
      return;
    }
    final initId = init.id;
    if (initId == null) return;
    if (DatabaseHelper.normalizeCategoryNameForLookup(t) ==
        DatabaseHelper.normalizeCategoryNameForLookup(init.name)) {
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }
    final choice = await showDialog<_EditSaveChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Τρόπος αποθήκευσης'),
        content: const Text(
          'Το όνομα άλλαξε. Μετονομασία της τρέχουσας κατηγορίας (ενημέρωση κλήσεων με το ίδιο category_id) ή δημιουργία νέας εγγραφής;',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_EditSaveChoice.cancel),
            child: const Text('Ακύρωση'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_EditSaveChoice.newRow),
            child: const Text('Νέα κατηγορία'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_EditSaveChoice.rename),
            child: const Text('Μετονομασία'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == _EditSaveChoice.cancel) {
      return;
    }
    try {
      if (choice == _EditSaveChoice.rename) {
        await widget.notifier.renameCategory(initId, t);
      } else {
        final restored = await widget.notifier.addCategory(t);
        if (!mounted) return;
        if (restored) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(kCategoryRestoredFromDeletedUserMessage),
            ),
          );
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _showError('$e');
    }
  }

  Future<void> _onDelete() async {
    final init = widget.initialCategory;
    final id = init?.id;
    if (init == null || id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή κατηγορίας'),
        content: Text('Σήμανση ως διαγραμμένη την κατηγορία «${init.name}»;'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.notifier.deleteByIds([id]);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    if (messenger != null) {
      CategoryUndoSnackBar.show(
        messenger,
        message: 'Σημειώθηκε ως διαγραμμένη: ${init.name}',
        onUndo: () {
          widget.notifier.undoLastDelete();
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialCategory != null;
    return AlertDialog(
      title: Text(isEdit ? 'Επεξεργασία κατηγορίας' : 'Νέα κατηγορία'),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: _controller,
          decoration: const InputDecoration(
            labelText: 'Όνομα',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (_) {
            if (_saveEnabled) _onSave();
          },
        ),
      ),
      actions: [
        if (isEdit)
          TextButton(
            onPressed: _onDelete,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Διαγραφή'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: _saveEnabled ? _onSave : null,
          child: const Text('Αποθήκευση'),
        ),
      ],
    );
  }
}
