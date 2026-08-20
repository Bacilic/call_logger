import 'package:flutter/material.dart';

import '../../../core/models/operator.dart';
import '../../../core/services/current_operator.dart';
import 'change_operator_dialog.dart';

/// Ποιος είναι συνδεδεμένος τώρα — μόνιμη ένδειξη στο κάτω μέρος της μπάρας
/// πλοήγησης, πάνω από την έκδοση. Κλικ → διάλογος «Αλλαγή χρήστη».
///
/// Παρακολουθεί την ταυτότητα ζωντανά: όταν ο συνάδελφος αλλάξει χρήστη, το
/// όνομα ενημερώνεται αμέσως, χωρίς επανεκκίνηση και χωρίς ξαναχτίσιμο του
/// κελύφους από έξω.
class ActiveOperatorChip extends StatelessWidget {
  const ActiveOperatorChip({
    super.key,
    required this.extended,
    this.openDialog = showChangeOperatorDialog,
  });

  /// Όταν false, μόνο εικονίδιο για στενό NavigationRail — το όνομα πάει
  /// στην επεξήγηση.
  final bool extended;

  /// Άνοιγμα του διαλόγου αλλαγής — αντικαθίσταται στα τεστ, ώστε το chip να
  /// ελέγχεται χωρίς πραγματική βάση.
  final Future<void> Function(BuildContext context) openDialog;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<Operator?>(
      valueListenable: CurrentOperator.listenable,
      builder: (context, operator, _) {
        final name = operator?.displayName.trim() ?? '';
        final hasOperator = name.isNotEmpty;
        final label = hasOperator ? name : 'Χωρίς χρήστη';
        final icon = hasOperator
            ? Icons.person_outline
            : Icons.person_off_outlined;
        final color = hasOperator ? scheme.onSurfaceVariant : scheme.error;

        return Tooltip(
          message: 'Αλλαγή χρήστη — τώρα: $label',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => openDialog(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                child: extended
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 18, color: color),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              label,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: color),
                            ),
                          ),
                        ],
                      )
                    : Icon(icon, size: 18, color: color),
              ),
            ),
          ),
        );
      },
    );
  }
}
