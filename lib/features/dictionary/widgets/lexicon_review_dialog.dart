import 'package:flutter/material.dart';

import '../services/lexicon_review_plan.dart';

/// Το παράθυρο ελέγχου των προτάσεων της ΤΝ. Επιστρέφει όσες λέξεις έμειναν
/// τσεκαρισμένες, ή `null` στο «Άκυρο» — τίποτα δεν γράφεται από εδώ.
Future<List<LexiconReviewItem>?> showLexiconReviewDialog(
  BuildContext context,
  List<LexiconReviewItem> items,
) {
  return showDialog<List<LexiconReviewItem>>(
    context: context,
    // Εκατοντάδες επιλογές δεν χάνονται από ένα κλικ έξω από το παράθυρο.
    barrierDismissible: false,
    builder: (_) => LexiconReviewDialog(items: items),
  );
}

class LexiconReviewDialog extends StatefulWidget {
  const LexiconReviewDialog({super.key, required this.items});

  final List<LexiconReviewItem> items;

  @override
  State<LexiconReviewDialog> createState() => _LexiconReviewDialogState();
}

class _LexiconReviewDialogState extends State<LexiconReviewDialog> {
  late final List<bool> _checked = [
    for (final item in widget.items) item.preselected,
  ];

  int get _checkedCount => _checked.where((c) => c).length;

  int _count(Set<LexiconReviewAction> actions) =>
      widget.items.where((i) => actions.contains(i.action)).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fixes = _count({LexiconReviewAction.fix});
    final deletions = _count({
      LexiconReviewAction.delete,
      LexiconReviewAction.deleteDuplicate,
    });
    final correct = _count({LexiconReviewAction.approve});
    final unanswered = _count({LexiconReviewAction.none});

    return AlertDialog(
      title: const Text('Έλεγχος λέξεων με ΤΝ'),
      content: SizedBox(
        width: 720,
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.items.length} λέξεις · $fixes διορθώσεις · '
              '$deletions διαγραφές · $correct σωστές'
              '${unanswered > 0 ? ' · $unanswered χωρίς απάντηση' : ''}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Τίποτα δεν αλλάζει πριν πατήσετε «Εφαρμογή». Οι σωστές που μένουν '
              'τσεκαρισμένες γίνονται «Χρήστης» και φεύγουν από την ουρά της '
              'Εισαγωγής. Όσες η ΤΝ δεν έκρινε με βεβαιότητα μένουν ατσεκάριστες.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: widget.items.length,
                itemBuilder: (context, i) => _ReviewRow(
                  item: widget.items[i],
                  checked: _checked[i],
                  onChanged: widget.items[i].applicable
                      ? (v) => setState(() => _checked[i] = v ?? false)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: _checkedCount == 0
              ? null
              : () => Navigator.of(context).pop([
                  for (var i = 0; i < widget.items.length; i++)
                    if (_checked[i]) widget.items[i],
                ]),
          child: Text('Εφαρμογή $_checkedCount επιλεγμένων'),
        ),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.item,
    required this.checked,
    required this.onChanged,
  });

  final LexiconReviewItem item;
  final bool checked;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final (proposal, proposalStyle) = switch (item.action) {
      LexiconReviewAction.fix => (
        item.suggestion,
        theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      LexiconReviewAction.deleteDuplicate => (
        '«${item.suggestion}» υπάρχει ήδη',
        muted,
      ),
      LexiconReviewAction.delete => ('δεν είναι λέξη', muted),
      LexiconReviewAction.approve => ('σωστή', muted),
      LexiconReviewAction.none => ('η ΤΝ δεν απάντησε', muted),
    };
    final actionLabel = switch (item.action) {
      LexiconReviewAction.fix => 'Διόρθωση',
      LexiconReviewAction.deleteDuplicate ||
      LexiconReviewAction.delete => 'Διαγραφή',
      LexiconReviewAction.approve => 'Σωστή',
      LexiconReviewAction.none => null,
    };

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Checkbox(value: checked, onChanged: onChanged),
          Expanded(
            flex: 3,
            child: Text(
              item.word,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              proposal,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: proposalStyle,
            ),
          ),
          SizedBox(
            width: 190,
            child: Wrap(
              spacing: 6,
              children: [
                if (actionLabel != null) _Tag(actionLabel),
                if (item.applicable && !item.sure)
                  const _Tag('αβέβαιη', warning: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.warning = false});

  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: warning ? scheme.tertiaryContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: warning
              ? scheme.onTertiaryContainer
              : scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
