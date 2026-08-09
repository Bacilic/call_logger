import 'package:flutter/material.dart';

import '../models/knowledge_article.dart';

/// Τι να γίνει όταν υπάρχει ήδη άρθρο για το ίδιο πρόβλημα.
enum KnowledgeDuplicateChoice {
  /// Ενημέρωση του υπάρχοντος — η νέα λύση αντικαθιστά την παλιά.
  update,

  /// Νέο άρθρο παρά την ομοιότητα (π.χ. άλλη αιτία, ίδιο σύμπτωμα).
  createNew,

  cancel,
}

/// Ρωτά πριν γεννηθεί δεύτερο άρθρο για κάτι ήδη καταγεγραμμένο.
///
/// Είναι η μοναδική άμυνα απέναντι στον τρόπο που πεθαίνουν οι βάσεις γνώσης:
/// όχι επειδή λείπει περιεχόμενο, αλλά επειδή το ίδιο πράγμα γράφεται πέντε
/// φορές με πέντε διατυπώσεις και κανείς δεν ξέρει ποια ισχύει.
Future<KnowledgeDuplicateChoice?> showKnowledgeDuplicateDialog(
  BuildContext context, {
  required KnowledgeArticle existing,
}) {
  return showDialog<KnowledgeDuplicateChoice>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: const Text('Υπάρχει ήδη παρόμοιο άρθρο'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Η Βάση Γνώσης έχει ήδη κάτι που μοιάζει με αυτό το περιστατικό:',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      existing.symptom,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(existing.solution, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Αν πρόκειται για το ίδιο πρόβλημα, η ενημέρωση κρατά τη βάση '
                'μικρή και αξιόπιστη. Αν είναι άλλη αιτία με ίδια συμπτώματα, '
                'φτιάξτε δεύτερο άρθρο.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(KnowledgeDuplicateChoice.cancel),
            child: const Text('Ακύρωση'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(KnowledgeDuplicateChoice.createNew),
            child: const Text('Νέο άρθρο'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(KnowledgeDuplicateChoice.update),
            child: const Text('Ενημέρωση υπάρχοντος'),
          ),
        ],
      );
    },
  );
}
