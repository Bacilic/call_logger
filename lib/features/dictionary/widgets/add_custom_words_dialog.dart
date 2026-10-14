import 'package:flutter/material.dart';

import '../../../core/services/master_dictionary_service.dart';

/// Ο διάλογος «Νέες λέξεις στο λεξικό»: πολλές λέξεις μαζί, με κενά ή κόμμα,
/// σε μία κατηγορία. Επιστρέφει `true` όταν γράφτηκαν· ένα σφάλμα μένει μέσα
/// στον διάλογο, ώστε ο χρήστης να διορθώσει χωρίς να ξαναπληκτρολογήσει.
class AddCustomWordsDialog extends StatefulWidget {
  const AddCustomWordsDialog({
    super.key,
    required this.categories,
    required this.master,
    required this.addCustomWordErrorMessage,
  });

  final List<String> categories;
  final MasterDictionaryService master;
  final String Function(Object e) addCustomWordErrorMessage;

  @override
  State<AddCustomWordsDialog> createState() => _AddCustomWordsDialogState();
}

class _AddCustomWordsDialogState extends State<AddCustomWordsDialog> {
  late final TextEditingController _wordCtrl;
  late String _selectedCategory;
  String? _dialogError;

  @override
  void initState() {
    super.initState();
    _wordCtrl = TextEditingController();
    _selectedCategory = widget.categories.first;
  }

  @override
  void dispose() {
    _wordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _wordCtrl.text.trim().isNotEmpty;
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Νέες λέξεις στο λεξικό'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_dialogError != null) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(
                        alpha: 0.35,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        _dialogError!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _wordCtrl,
                autofocus: true,
                minLines: 4,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Λέξεις',
                  hintText: 'Χωρισμός με κενά ή κόμμα (ή επικόλληση λίστας)',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Κατηγορία',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    borderRadius: BorderRadius.circular(12),
                    value: widget.categories.contains(_selectedCategory)
                        ? _selectedCategory
                        : widget.categories.first,
                    isExpanded: true,
                    items: widget.categories
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c,
                            child: Text(
                              c,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _selectedCategory = v);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: canSubmit
              ? () async {
                  setState(() => _dialogError = null);
                  try {
                    await widget.master.addCustomWords(
                      input: _wordCtrl.text,
                      category: _selectedCategory,
                    );
                    if (!context.mounted) return;
                    Navigator.of(context).pop(true);
                  } catch (e) {
                    setState(
                      () => _dialogError = widget.addCustomWordErrorMessage(e),
                    );
                  }
                }
              : null,
          child: const Text('Προσθήκη'),
        ),
      ],
    );
  }
}
