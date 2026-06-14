import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/spell_check_controller.dart';

class LansweeperSyncForm extends ConsumerWidget {
  const LansweeperSyncForm({
    required this.titleController,
    required this.notesController,
    this.onSuggest,
    this.isSuggesting = false,
    this.suggestModelLabel,
    this.suggestElapsedLabel,
    this.suggestDisabledTooltip,
    super.key,
  });

  final SpellCheckController titleController;
  final SpellCheckController notesController;
  final VoidCallback? onSuggest;
  final bool isSuggesting;
  final String? suggestModelLabel;
  final String? suggestElapsedLabel;
  final String? suggestDisabledTooltip;

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

    final suggestRow = Row(
      mainAxisSize: MainAxisSize.min,
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
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Φόρμα καταχώρησης Lansweeper',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            suggestRow,
            const SizedBox(height: 10),
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
                labelText: 'Σημειώσεις (περιγραφή ticket)',
                hintText:
                    'Καλών και εξοπλισμό συμπληρώνετε χειροκίνητα στο Lansweeper.',
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
