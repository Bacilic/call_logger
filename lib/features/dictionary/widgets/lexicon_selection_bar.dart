import 'package:flutter/material.dart';

import '../services/lexicon_ai_prompts.dart';

/// Η γραμμή πάνω από τη λίστα του Λεξικού: πόσες λέξεις έχουν επιλεγεί, και
/// ο «Έλεγχος με ΤΝ» για αυτές.
class LexiconSelectionBar extends StatelessWidget {
  const LexiconSelectionBar({
    super.key,
    required this.selectedCount,
    required this.matchingCount,
    required this.reviewing,
    required this.onSelectAllMatching,
    required this.onClear,
    required this.onReview,
    required this.onEditPrompt,
  });

  final int selectedCount;

  /// Πόσες λέξεις δείχνει το τρέχον φίλτρο, σε όλες τις σελίδες.
  final int matchingCount;
  final bool reviewing;
  final VoidCallback onSelectAllMatching;
  final VoidCallback onClear;
  final VoidCallback onReview;
  final VoidCallback onEditPrompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String status;
    if (selectedCount == 0) {
      status =
          'Καμία επιλεγμένη λέξη · κουτάκι για μία, Shift + κλικ για περιοχή, '
          'Ctrl + A για τη σελίδα';
    } else if (selectedCount > kLexiconAiReviewBatchSize) {
      status =
          'Επιλεγμένες: $selectedCount · ο έλεγχος στέλνει τις πρώτες '
          '$kLexiconAiReviewBatchSize';
    } else {
      status = 'Επιλεγμένες: $selectedCount';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            Icons.checklist,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: matchingCount == 0 ? null : onSelectAllMatching,
            child: Text('Όλες του φίλτρου ($matchingCount)'),
          ),
          TextButton(
            onPressed: selectedCount == 0 ? null : onClear,
            child: const Text('Καθαρισμός'),
          ),
          const SizedBox(width: 4),
          FilledButton.tonalIcon(
            onPressed: selectedCount == 0 || reviewing ? null : onReview,
            icon: reviewing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const Text('Έλεγχος με ΤΝ'),
          ),
          IconButton(
            tooltip: 'Προτροπή του «Ελέγχου με ΤΝ»',
            icon: const Icon(Icons.edit_note),
            onPressed: onEditPrompt,
          ),
        ],
      ),
    );
  }
}
