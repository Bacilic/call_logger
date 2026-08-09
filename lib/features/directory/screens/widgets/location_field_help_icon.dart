import 'package:flutter/material.dart';

import '../../../../core/widgets/compact_tooltip.dart';

/// Τι γράφεται — και τι **δεν** γράφεται — στο πεδίο «Τοποθεσία».
///
/// Το πεδίο μπαίνει σε πειρασμό να γίνει διεύθυνση: κτίριο, όροφος, τμήμα και
/// μετά η λεπτομέρεια. Τα τρία πρώτα τα ξέρει ήδη η βάση και μπαίνουν μόνα τους
/// στη στήλη, οπότε η επανάληψή τους μόνο θόρυβο προσθέτει.
const String kLocationFieldHelpMessage =
    'Εδώ συμπληρώνονται λεπτομέρειες για τη θέση του εξοπλισμού μέσα στο '
    'γραφείο — π.χ. «πίσω από την πόρτα», «κάτω από το παράθυρο».\n\n'
    'ΔΕΝ συμπληρώνονται Κτίριο, Όροφος και Τμήμα: προκύπτουν μόνα τους.';

/// Εικονίδιο επεξήγησης στο άκρο του πεδίου «Τοποθεσία».
class LocationFieldHelpIcon extends StatelessWidget {
  const LocationFieldHelpIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const CompactTooltip(
      message: kLocationFieldHelpMessage,
      child: Icon(Icons.info_outline, size: 18),
    );
  }
}
