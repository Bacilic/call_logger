import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/user_facing_error_messages.dart';
import '../../../core/widgets/dialog_snackbar_scope.dart';
import '../../../core/widgets/resizable_text_area.dart';
import '../../../core/widgets/spell_check_controller.dart';
import '../../history/providers/history_provider.dart';
import '../models/knowledge_article.dart';
import '../providers/knowledge_provider.dart';

/// Ανοίγει τη φόρμα άρθρου Βάσης Γνώσης· επιστρέφει το id αν αποθηκεύτηκε.
///
/// Την ίδια φόρμα βλέπει και η οθόνη Βάσης Γνώσης και το «Αποθήκευση ως γνώση»
/// της αναφοράς Lansweeper — στη δεύτερη περίπτωση προσυμπληρωμένη από κλήση.
Future<int?> showKnowledgeArticleDialog(
  BuildContext context, {
  KnowledgeArticle? article,
}) {
  return showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _KnowledgeArticleDialog(
      article: article ?? const KnowledgeArticle(),
    ),
  );
}

class _KnowledgeArticleDialog extends ConsumerStatefulWidget {
  const _KnowledgeArticleDialog({required this.article});

  final KnowledgeArticle article;

  @override
  ConsumerState<_KnowledgeArticleDialog> createState() =>
      _KnowledgeArticleDialogState();
}

class _KnowledgeArticleDialogState
    extends ConsumerState<_KnowledgeArticleDialog>
    with DialogSnackbarHost {
  late final SpellCheckController _titleController;
  late final SpellCheckController _symptomController;
  late final SpellCheckController _solutionController;
  late final TextEditingController _tagsController;
  int? _categoryId;
  bool _saving = false;

  bool get _isNew => widget.article.id == null;

  @override
  void initState() {
    super.initState();
    _titleController = SpellCheckController()..text = widget.article.title;
    _symptomController = SpellCheckController()..text = widget.article.symptom;
    _solutionController = SpellCheckController()
      ..text = widget.article.solution;
    _tagsController = TextEditingController(text: widget.article.tags);
    _categoryId = widget.article.categoryId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _symptomController.dispose();
    _solutionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final symptom = _symptomController.text.trim();
    final solution = _solutionController.text.trim();
    if (symptom.isEmpty || solution.isEmpty) {
      showDialogSnackBar(
        const SnackBar(
          content: Text(
            'Το σύμπτωμα και η λύση είναι υποχρεωτικά — χωρίς αυτά το άρθρο δεν '
            'βρίσκεται και δεν βοηθά.',
          ),
        ),
      );
      return;
    }

    final title = _titleController.text.trim();
    final updated = widget.article.copyWith(
      // Άτιτλο άρθρο δεν ξεχωρίζει σε λίστα· το σύμπτωμα είναι ο φυσικός τίτλος.
      title: title.isEmpty ? symptom : title,
      symptom: symptom,
      solution: solution,
      tags: _tagsController.text,
      categoryId: _categoryId,
      clearCategory: _categoryId == null,
    );

    setState(() => _saving = true);
    try {
      final id = await ref.read(knowledgeActionsProvider.notifier).save(updated);
      if (!mounted) return;
      Navigator.of(context).pop(id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isNew
                ? 'Το άρθρο προστέθηκε στη Βάση Γνώσης.'
                : 'Το άρθρο ενημερώθηκε.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showDialogSnackBar(
        SnackBar(
          content: Text('Αποτυχία αποθήκευσης: ${humanizeUserFacingError(e)}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(historyCategoryEntriesProvider);
    return DialogSnackbarScope(
      messengerKey: dialogMessengerKey,
      child: Center(
        child: AlertDialog(
          title: Text(_isNew ? 'Νέο άρθρο γνώσης' : 'Επεξεργασία άρθρου'),
          contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ResizableTextArea(
                    controller: _titleController,
                    minLines: 1,
                    autoGrowMaxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Τίτλος',
                      helperText:
                          'Πώς θα το αναγνωρίσετε σε λίστα. Κενό σημαίνει «όσο λέει το σύμπτωμα».',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ResizableTextArea(
                    controller: _symptomController,
                    minLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Σύμπτωμα — όπως το λέει ο χρήστης',
                      helperText:
                          'Τηλεγραφικά, με τα λόγια του καλούντα. Έτσι θα το βρει η εφαρμογή την επόμενη φορά.',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ResizableTextArea(
                    controller: _solutionController,
                    minLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Λύση',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _tagsController,
                    decoration: const InputDecoration(
                      labelText: 'Λέξεις-κλειδιά',
                      helperText:
                          'Χωρισμένες με κόμμα, π.χ. VNC, μαύρη οθόνη, απομακρυσμένη',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  categoriesAsync.when(
                    data: (entries) {
                      final options = <({int? id, String name})>[
                        (id: null, name: '— Χωρίς κατηγορία —'),
                        ...entries.map((e) => (id: e.id, name: e.name)),
                      ];
                      final selected = options.any((e) => e.id == _categoryId)
                          ? _categoryId
                          : null;
                      return DropdownButtonFormField<int?>(
                        initialValue: selected,
                        decoration: const InputDecoration(
                          labelText: 'Κατηγορία προβλήματος',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: options
                            .map(
                              (entry) => DropdownMenuItem<int?>(
                                value: entry.id,
                                child: Text(entry.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _categoryId = value),
                      );
                    },
                    loading: () => const SizedBox(
                      height: 44,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Ακύρωση'),
            ),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('Αποθήκευση'),
            ),
          ],
        ),
      ),
    );
  }
}
