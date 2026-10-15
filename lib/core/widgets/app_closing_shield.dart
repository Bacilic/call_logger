import 'package:flutter/material.dart';

import '../services/app_close_controller.dart';
import 'shutdown_progress_screen.dart';

/// Το στρώμα πάνω από **όλη** την εφαρμογή — και πάνω από τους διαλόγους.
///
/// Από τη στιγμή που ξεκινά το κλείσιμο, κανένα κλικ και κανένα πλήκτρο δεν
/// φτάνει σε οθόνη ή διάλογο: ως 14/10/2026 ο διάλογος έμενε ορατός πάνω από
/// την οθόνη κλεισίματος, και ένα «Αποθήκευση» πατημένο εκείνη την ώρα
/// γραφόταν στη βάση μέσα στο κλείσιμο. Και το πληκτρολόγιο μετρά: ένα Enter
/// σε φόρμα είναι κι αυτό «Αποθήκευση».
///
/// Μπαίνει στο `builder` της εφαρμογής, **έξω** από τον πλοηγό όπου ζουν οι
/// διάλογοι. Η δομή μένει ίδια πριν και μετά το κλείσιμο, ώστε ο πλοηγός να
/// μη στηθεί ποτέ από την αρχή.
class AppClosingShield extends StatelessWidget {
  const AppClosingShield({
    super.key,
    required this.child,
    this.controllerForTest,
  });

  final Widget child;

  /// Παράκαμψη του ελεγκτή κλεισίματος (μόνο για τεστ).
  @visibleForTesting
  final AppCloseController? controllerForTest;

  @override
  Widget build(BuildContext context) {
    final controller = controllerForTest ?? appCloseController;
    return ValueListenableBuilder<AppClosingState>(
      valueListenable: controller.closingState,
      child: child,
      builder: (context, state, app) {
        final coordinator = state.coordinator;
        return Stack(
          fit: StackFit.expand,
          children: [
            ExcludeFocus(
              excluding: state.isClosing,
              child: AbsorbPointer(absorbing: state.isClosing, child: app),
            ),
            // Αόρατη ως το κατώφλι, αλλά ήδη στημένη: συλλέγει τα γεγονότα
            // των βημάτων από την αρχή.
            if (coordinator != null)
              Offstage(
                offstage: !state.progressRevealed,
                child: ShutdownProgressScreen(events: coordinator.events),
              ),
          ],
        );
      },
    );
  }
}
