import 'package:flutter/material.dart';

/// Μία γραμμή της κάρτας σύγκρισης των διαλόγων «Μήπως εννοείτε;».
class SuggestionComparisonRow {
  const SuggestionComparisonRow({
    required this.label,
    required this.icon,
    required this.name,
    required this.highlight,
    this.suffix,
    this.onTap,
    this.emphasized = false,
  });

  /// Ετικέτα αριστερά («Πληκτρολογήσατε», «Υπάρχει ήδη», ή κενή).
  final String label;

  final IconData icon;

  /// Το όνομα της γραμμής (πληκτρολογημένο ή υπάρχον).
  final String name;

  /// Το κοινό τμήμα που μαρκάρεται μέσα στο όνομα (θέση + μήκος)·
  /// μήκος 0 = κανένα μαρκάρισμα. Βλ. `TextSimilarity.matchedSpan`.
  final ({int start, int length}) highlight;

  /// Δευτερεύον κείμενο δίπλα στο όνομα (π.χ. «(Πληροφορική)»)· null = τίποτα.
  final String? suffix;

  /// Πατήσιμη γραμμή (επιλογή υπάρχουσας εγγραφής)· δείχνει και chevron.
  final VoidCallback? onTap;

  /// Διακριτό φόντο υπάρχουσας εγγραφής (το πληκτρολογημένο μένει λευκό).
  final bool emphasized;
}

/// Κάρτα σύγκρισης «Πληκτρολογήσατε / Υπάρχει ήδη» των διαλόγων «Μήπως
/// εννοείτε;» (υπάλληλοι, τμήματα).
///
/// Επιβάλλει το κοινό μοτίβο από ένα σημείο: ετικέτες, εικονίδια οντοτήτων και
/// μαρκαρισμένο το κοινό μέρος των ονομάτων ώστε να φαίνεται γιατί ταίριαξαν.
class SuggestionComparisonCard extends StatelessWidget {
  const SuggestionComparisonCard({super.key, required this.rows});

  final List<SuggestionComparisonRow> rows;

  /// Όνομα με μαρκαρισμένο το κοινό τμήμα ([SuggestionComparisonRow.highlight]).
  Widget _highlightedName(BuildContext context, SuggestionComparisonRow row) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodyLarge;
    final start = row.highlight.start.clamp(0, row.name.length);
    final end = (start + row.highlight.length).clamp(start, row.name.length);
    if (start == end) return Text(row.name, style: style);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          if (start > 0) TextSpan(text: row.name.substring(0, start)),
          TextSpan(
            text: row.name.substring(start, end),
            style: TextStyle(
              backgroundColor: scheme.primaryContainer,
              color: scheme.onPrimaryContainer,
            ),
          ),
          if (end < row.name.length) TextSpan(text: row.name.substring(end)),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, SuggestionComparisonRow row) {
    final theme = Theme.of(context);
    final suffix = row.suffix;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              row.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Icon(row.icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                _highlightedName(context, row),
                if (suffix != null && suffix.isNotEmpty)
                  Text(
                    suffix,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (row.onTap != null)
            Icon(Icons.chevron_right, color: theme.colorScheme.primary),
        ],
      ),
    );

    final decorated = Container(
      decoration: row.emphasized
          ? BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            )
          : null,
      child: row.onTap == null
          ? content
          : InkWell(onTap: row.onTap, child: content),
    );
    return decorated;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final row in rows) _buildRow(context, row)],
      ),
    );
  }
}
