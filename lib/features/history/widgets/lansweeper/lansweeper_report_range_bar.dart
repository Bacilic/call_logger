import 'package:flutter/material.dart';

import '../../../../core/widgets/compact_tooltip.dart';
import '../../models/lansweeper_report_scope.dart';

/// Επιλογή χρονικού πλαισίου της αναφοράς, πάνω στην ίδια την αναφορά.
///
/// Χωρίς αυτήν το διάστημα οριζόταν μόνο από τα φίλτρα του Πίνακα Ελέγχου, σε
/// άλλη οθόνη — ο χρήστης έπρεπε να φύγει και να γυρίσει για να το αλλάξει.
class LansweeperReportRangeBar extends StatelessWidget {
  const LansweeperReportRangeBar({
    super.key,
    required this.scope,
    required this.onSelect,
  });

  final LansweeperReportScope scope;
  final ValueChanged<LansweeperReportRange> onSelect;

  static const _tooltips = {
    LansweeperReportRange.today: 'Οι κλήσεις της σημερινής ημέρας',
    LansweeperReportRange.yesterday: 'Οι κλήσεις της χθεσινής ημέρας',
    LansweeperReportRange.last7Days: 'Οι κλήσεις των τελευταίων επτά ημερών',
    LansweeperReportRange.allTime: 'Κάθε κλήση, χωρίς όριο ημερομηνίας',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Text(
            'Διάστημα',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        for (final range in LansweeperReportScope.presets)
          Tooltip(
            message: _tooltips[range] ?? '',
            child: ChoiceChip(
              label: Text(
                LansweeperReportScope.range(range).label ?? '',
                style: const TextStyle(fontSize: 12),
              ),
              selected: scope.range == range,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onSelect(range),
            ),
          ),
        if (scope.range == LansweeperReportRange.dashboardFilters)
          const CompactTooltip(
            message:
                'Ισχύουν τα φίλτρα των Στατιστικών Κλήσεων — ημερομηνίες, '
                'τμήμα, υπάλληλος και εξοπλισμός',
            child: ChoiceChip(
              label: Text('Φίλτρα Στατιστικών', style: TextStyle(fontSize: 12)),
              selected: true,
              visualDensity: VisualDensity.compact,
              onSelected: null,
            ),
          ),
      ],
    );
  }
}
