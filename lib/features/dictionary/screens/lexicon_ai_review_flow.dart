import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/dictionary_repository.dart';
import '../providers/lexicon_ai_review_provider.dart';
import '../providers/lexicon_selection_provider.dart';
import '../services/lexicon_ai_prompts.dart';
import '../services/lexicon_ai_review_service.dart';
import '../services/lexicon_review_plan.dart';
import '../services/lexicon_row_writer.dart';
import '../widgets/lexicon_review_dialog.dart';

/// Ο «Έλεγχος με ΤΝ» από άκρη σε άκρη: οι πρώτες επιλεγμένες λέξεις στην ΤΝ,
/// οι προτάσεις της στο παράθυρο ελέγχου, ό,τι εγκρίνει ο χρήστης στη βάση.
///
/// Στο «Άκυρο» η επιλογή μένει ως ήταν· μετά την «Εφαρμογή» οι λέξεις που
/// στάλθηκαν βγαίνουν από την επιλογή, ώστε ο επόμενος έλεγχος να πάρει τις
/// επόμενες. Το [onWaiting] δείχνει πότε περιμένουμε την ΤΝ.
Future<void> runLexiconAiReviewFlow({
  required BuildContext context,
  required WidgetRef ref,
  required LexiconRowWriter writer,
  required Future<void> Function() refreshList,
  required ValueChanged<bool> onWaiting,
}) async {
  final batch = ref
      .read(lexiconSelectionProvider)
      .firstBatch(kLexiconAiReviewBatchSize);
  if (batch.isEmpty) return;

  final messenger = ScaffoldMessenger.of(context);
  onWaiting(true);
  final LexiconAiReviewOutcome outcome;
  try {
    outcome = await ref.read(lexiconAiReviewRunnerProvider)([
      for (final row in batch) row['display_word'] as String? ?? '',
    ]);
  } finally {
    onWaiting(false);
  }

  final Map<int, LexiconAiVerdict> verdicts;
  switch (outcome) {
    case LexiconAiReviewed(verdicts: final answered):
      verdicts = answered;
    case LexiconAiReviewFailed(:final message):
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
  }

  final repository = DictionaryRepository(
    await DatabaseHelper.instance.database,
  );
  final items = await planLexiconReview(
    rows: batch,
    verdicts: verdicts,
    existingEntryId: (key) async =>
        (await repository.findFullDictionaryEntryByNormalizedWord(key))?['id']
            as int?,
  );
  if (!context.mounted) return;
  final chosen = await showLexiconReviewDialog(context, items);
  if (chosen == null) return;

  final applied = await applyLexiconReview(chosen, writer);
  ref.read(lexiconSelectionProvider.notifier).removeAll(batch);
  await refreshList();

  final failed = applied.failed.isEmpty
      ? ''
      : ' · δεν γράφτηκαν ${applied.failed.length}: '
            '${applied.failed.take(5).join(', ')}'
            '${applied.failed.length > 5 ? '…' : ''}';
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        'Διορθώθηκαν ${applied.fixed} · διαγράφηκαν ${applied.deleted} · '
        'εγκρίθηκαν ${applied.approved}$failed',
      ),
    ),
  );
}
