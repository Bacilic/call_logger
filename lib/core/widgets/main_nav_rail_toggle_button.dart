import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'main_nav_rail_metrics.dart';

/// Κουμπί σύμπτυξης / επέκτασης της πλευρικής μπάρας.
///
/// Κλειστή μπάρα: κάθεται στο κέντρο της ζώνης εικονιδίου, στην ίδια κατακόρυφη
/// γραμμή με τα εικονίδια των κουμπιών. Ανοιχτή μπάρα: στη δεξιά άκρη, όπως στις
/// γνωστές εφαρμογές με πλευρικό πάνελ.
///
/// Η μετακίνηση δένεται στο [NavigationRail.extendedAnimation], ώστε το κουμπί
/// να γλιστράει μαζί με το πλάτος της μπάρας αντί να πηδάει στην τελική θέση.
class MainNavRailToggleButton extends StatelessWidget {
  const MainNavRailToggleButton({
    super.key,
    required this.extended,
    required this.extendedWidth,
    required this.onToggle,
  });

  /// Αν η μπάρα δείχνει λεζάντες — καθορίζει φορά βέλους και επεξήγηση.
  final bool extended;

  /// Πλάτος της ανοιχτής μπάρας, ώστε η δεξιά άκρη να είναι η σωστή.
  final double extendedWidth;

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final animation = NavigationRail.extendedAnimation(context);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final progress = animation.value;
        return SizedBox(
          width: lerpDouble(
            kMainNavRailIconZoneWidth,
            extendedWidth,
            progress,
          ),
          child: Align(
            alignment: Alignment.lerp(
              Alignment.center,
              Alignment.centerRight,
              progress,
            )!,
            child: Padding(
              padding: EdgeInsets.only(
                right: kMainNavRailLabelTrailingPadding * progress,
              ),
              child: child,
            ),
          ),
        );
      },
      child: IconButton(
        key: const ValueKey('nav_rail_toggle'),
        icon: Icon(extended ? Icons.chevron_left : Icons.chevron_right),
        tooltip: extended ? 'Σύμπτυξη πλοήγησης' : 'Επέκταση πλοήγησης',
        onPressed: onToggle,
      ),
    );
  }
}
