import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/spell_check_controller.dart';

class LansweeperSyncForm extends ConsumerWidget {
  const LansweeperSyncForm({
    required this.titleController,
    required this.notesController,
    required this.solutionController,
    this.onSuggest,
    this.onPreviewPrompt,
    this.onEditPromptTemplate,
    this.isSuggesting = false,
    this.suggestModelLabel,
    this.suggestElapsedLabel,
    this.suggestDisabledTooltip,
    this.previewDisabledTooltip,
    super.key,
  });

  final SpellCheckController titleController;
  final SpellCheckController notesController;
  final SpellCheckController solutionController;
  final VoidCallback? onSuggest;
  final VoidCallback? onPreviewPrompt;
  final VoidCallback? onEditPromptTemplate;
  final bool isSuggesting;
  final String? suggestModelLabel;
  final String? suggestElapsedLabel;
  final String? suggestDisabledTooltip;
  final String? previewDisabledTooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestButton = FilledButton.tonalIcon(
      onPressed: isSuggesting ? null : onSuggest,
      icon: isSuggesting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('✨', style: TextStyle(fontSize: 16)),
      label: Text(
        isSuggesting
            ? (suggestModelLabel ?? 'Πρόταση…')
            : 'Πρόταση ΤΝ',
      ),
    );

    final previewButton = OutlinedButton.icon(
      onPressed: isSuggesting ? null : onPreviewPrompt,
      icon: const Icon(Icons.article_outlined, size: 18),
      label: const Text('Προεπισκόπηση προτροπής'),
    );

    final promptEditorButton = onEditPromptTemplate == null
        ? null
        : IconButton(
            tooltip: 'Επεξεργασία προτύπου προτροπής',
            onPressed: isSuggesting ? null : onEditPromptTemplate,
            icon: Image.asset(
              'assets/prompt_editor.png',
              width: 20,
              height: 20,
            ),
          );

    final suggestRow = Row(
      children: [
        if (suggestDisabledTooltip != null && onSuggest == null)
          Tooltip(message: suggestDisabledTooltip!, child: suggestButton)
        else
          suggestButton,
        if (isSuggesting && suggestElapsedLabel != null) ...[
          const SizedBox(width: 10),
          Text(
            '${suggestElapsedLabel!} δλ',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ],
        const Spacer(),
        if (promptEditorButton != null) ...[
          promptEditorButton,
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: previewDisabledTooltip != null && onPreviewPrompt == null
                  ? Tooltip(
                      message: previewDisabledTooltip!,
                      child: previewButton,
                    )
                  : previewButton,
            ),
          ),
        ),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            suggestRow,
            const SizedBox(height: 8),
            Text(
              'Φόρμα καταχώρησης Lansweeper',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            LexiconSpellTextFormField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Τίτλος',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            LexiconSpellTextFormField(
              controller: notesController,
              minLines: 2,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: 'Σημειώσεις - Πρόβλημα (περιγραφή ticket)',
                hintText:
                    'Καλών και εξοπλισμό συμπληρώνετε χειροκίνητα στο Lansweeper.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            LexiconSpellTextFormField(
              controller: solutionController,
              minLines: 2,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: 'Λύση',
                hintText: 'Ενσωματώνεται στην περιγραφή ticket κατά την αποστολή.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
