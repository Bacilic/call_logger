import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/main_nav_request_provider.dart';
import '../../../../core/widgets/main_nav_destination.dart';
import '../../../calls/layout/call_form_clear.dart';

enum _OpenCallGuardChoice { cancel, discardCall, goToCall }

/// Ο διάλογος που στέκεται ανάμεσα σε μια ενέργεια του Καταλόγου και την
/// ανοιχτή κλήση που την αφορά.
///
/// **Ένα σημείο για κάθε οντότητα.** Ήταν γραμμένος δύο φορές — μία για τον
/// εξοπλισμό και μία για τους υπαλλήλους — με μόνη διαφορά μία λέξη στο
/// μήνυμα. Η τρίτη αντιγραφή (τμήματα) θα ήταν η στιγμή που οι τρεις θα
/// άρχιζαν να αποκλίνουν: άλλες επιλογές, άλλη συμπεριφορά στο «Άκυρο».
///
/// Η πολιτική που επιβάλλει: **δεν απαγορεύει, ρωτά**. Ο χειριστής αποφασίζει
/// αν θα εγκαταλείψει την κλήση, αν θα γυρίσει σε αυτήν, ή αν θα ακυρώσει την
/// ενέργεια του Καταλόγου.
///
/// Επιστρέφει `true` όταν η ενέργεια επιτρέπεται να προχωρήσει.
Future<bool> ensureOpenCallAllowsCatalogAction(
  BuildContext context,
  WidgetRef ref, {
  required bool openCallInvolvesTarget,
  required String targetPhrase,
}) async {
  if (!openCallInvolvesTarget) return true;

  final choice = await showDialog<_OpenCallGuardChoice>(
    context: context,
    // Η ερώτηση δεν κλείνει με κλικ απ' έξω: μια κλήση σε εξέλιξη αξίζει ρητή
    // απάντηση, όχι σιωπηλή απόρριψη.
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Ανοιχτή κλήση'),
      content: Text(
        'Η ανοιχτή κλήση αφορά $targetPhrase. '
        'Ολοκληρώστε ή διακόψτε πρώτα την κλήση.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(_OpenCallGuardChoice.cancel),
          child: const Text('Άκυρο'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(_OpenCallGuardChoice.discardCall),
          child: const Text('Διακοπή κλήσης'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(_OpenCallGuardChoice.goToCall),
          child: const Text('Μετάβαση στην κλήση'),
        ),
      ],
    ),
  );

  switch (choice) {
    case _OpenCallGuardChoice.discardCall:
      clearCallFormCompletely(ref);
      return true;
    case _OpenCallGuardChoice.goToCall:
      if (context.mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
      }
      ref
          .read(mainNavRequestProvider.notifier)
          .request(const MainNavRequest(destination: MainNavDestination.calls));
      return false;
    case _OpenCallGuardChoice.cancel:
    case null:
      return false;
  }
}
