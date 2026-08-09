import 'package:flutter/material.dart';

import '../../../../core/widgets/intrinsic_width_opt_out.dart';

/// Η γραμμή «πλήρους θέσης» — 📍 Κτίριο › Όροφος › Τμήμα › Τοποθεσία.
///
/// Μόνο ανάγνωση: απαντά στο «πού θα το βρω;» συνθέτοντας ό,τι ξέρει η βάση
/// με ό,τι γράφεται εκείνη τη στιγμή στη φόρμα. Με κενό [text] δεν αποδίδει
/// τίποτα. Τυλιγμένη σε [IntrinsicWidthOptOut] ώστε ένα μακρύ μονοπάτι να
/// αναδιπλώνεται αντί να τεντώνει τον διάλογο.
class FullLocationLine extends StatelessWidget {
  const FullLocationLine({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return IntrinsicWidthOptOut(
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          '📍 $text',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
