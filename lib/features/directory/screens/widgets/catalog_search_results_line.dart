import 'package:flutter/material.dart';

import '../../services/catalog_search_evaluation.dart';

/// Γραμμή αποτελεσμάτων κάτω από την αναζήτηση του Καταλόγου.
///
/// «Βρέθηκαν 2 αποτελέσματα · σε κρυφά πεδία — Τμήμα (1)»
///
/// Λέει πάντα πόσα βρέθηκαν, και —όταν κάποιο εύρημα ταιριάζει μόνο σε πεδίο
/// που δεν φαίνεται ως στήλη— ποιο πεδίο είναι αυτό. Χωρίς ενεργή αναζήτηση
/// δεν καταλαμβάνει καθόλου χώρο.
class CatalogSearchResultsLine extends StatelessWidget {
  const CatalogSearchResultsLine({super.key, required this.summary});

  final CatalogSearchSummary summary;

  @override
  Widget build(BuildContext context) {
    final text = catalogSearchResultsLineText(summary);
    if (text.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          key: const Key('catalog_search_results_line'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: summary.hasHiddenMatches
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
