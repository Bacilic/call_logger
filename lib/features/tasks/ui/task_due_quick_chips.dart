import 'package:flutter/material.dart';

import '../../../core/utils/greek_weekday.dart';
import '../../../core/widgets/compact_tooltip.dart';

/// Προεπισκόπηση της στιγμής λήξης που δείχνει ένα chip γρήγορης επιλογής.
///
/// Ίδια ημέρα με το [now] → μόνο ώρα («19:43»)· μέσα στις επόμενες έξι ημέρες
/// → τρίγραμμο ημέρας και ώρα («ΠΕΜ 08:00»)· πιο πέρα ή στο παρελθόν →
/// ημερομηνία και ώρα («12/08 08:00»).
String formatTaskDuePreview(DateTime now, DateTime due) {
  final hm =
      '${due.hour.toString().padLeft(2, '0')}:'
      '${due.minute.toString().padLeft(2, '0')}';
  final today = DateTime(now.year, now.month, now.day);
  final dueDay = DateTime(due.year, due.month, due.day);
  final days = dueDay.difference(today).inDays;
  if (days == 0) return hm;
  if (days > 0 && days <= 6) return '${weekdayShortEl(due)} $hm';
  return '${due.day.toString().padLeft(2, '0')}/'
      '${due.month.toString().padLeft(2, '0')} $hm';
}

/// Μία γρήγορη επιλογή λήξης, μαζί με τη στιγμή που θα προκύψει αν επιλεγεί.
///
/// Το [due] είναι ήδη υπολογισμένο από τον καλούντα με τον ίδιο υπολογισμό που
/// θα εφαρμοστεί — έτσι το chip δεν μπορεί να δείχνει άλλη ώρα από την
/// πραγματική.
class TaskDueQuickChoice {
  const TaskDueQuickChoice({
    required this.option,
    required this.label,
    required this.due,
    required this.message,
  });

  /// Κωδικός επιλογής (`TaskSettingsConfig.kOneHour` κ.λπ.).
  final String option;

  /// Ετικέτα πάνω σειράς του chip.
  final String label;

  /// Η στιγμή λήξης που θα εφαρμοστεί — εμφανίζεται στην κάτω σειρά.
  final DateTime due;

  /// Κείμενο υπόδειξης· περνά από το κοινό πρότυπο [CompactTooltip].
  final String message;
}

/// Σειρά μικρών chips γρήγορης λήξης: ετικέτα πάνω, στιγμή λήξης από κάτω.
///
/// Οι υποδείξεις περνούν πάντα από το [CompactTooltip] ώστε να μην
/// απλώνονται σε όλο το πλάτος της οθόνης.
class TaskDueQuickChips extends StatelessWidget {
  const TaskDueQuickChips({
    super.key,
    required this.choices,
    required this.now,
    required this.onSelected,
    this.selectedOption,
  });

  final List<TaskDueQuickChoice> choices;

  /// Στιγμή αναφοράς για τη μορφοποίηση της προεπισκόπησης.
  final DateTime now;

  final ValueChanged<TaskDueQuickChoice> onSelected;

  /// Όταν δοθεί, το αντίστοιχο chip εμφανίζεται επιλεγμένο.
  final String? selectedOption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final choice in choices)
          CompactTooltip(
            message: choice.message,
            child: ChoiceChip(
              selected: choice.option == selectedOption,
              onSelected: (_) => onSelected(choice),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              label: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    choice.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    formatTaskDuePreview(now, choice.due),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
