import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/lansweeper_report_scope.dart';
import '../../providers/lansweeper_report_scope_provider.dart';
import '../lansweeper_report_dialog.dart';

/// Το εικονίδιο της Αναφοράς Lansweeper, όπου κι αν εμφανίζεται.
const String kLansweeperReportBadgeAsset = 'assets/lansweeper tickets.png';

/// Υπόδειξη της συντόμευσης προς την αναφορά, με τα πλήκτρα δηλωμένα.
const String kLansweeperReportShortcutTooltip =
    'Αναφορά Lansweeper — όσες κλήσεις μένουν να καταχωρηθούν (Ctrl+Shift+L)';

/// Η μοναδική πόρτα προς την Αναφορά Lansweeper.
///
/// Ο καλών **οφείλει** να δηλώσει τι θέλει να δει: χωρίς αυτό η αναφορά θα
/// έδειχνε ό,τι είχε μείνει από την προηγούμενη φορά, σε άλλη οθόνη και άλλη
/// μέρα. Το [scope] δέχεται και `null`, που σημαίνει ρητά «το διάστημα που
/// διάλεξε τελευταία ο χρήστης» — δήλωση κι αυτή, όχι παράλειψη.
///
/// Επιστρέφει `false` όταν η αναφορά είναι ήδη ανοιχτή, ώστε μια δεύτερη
/// συντόμευση να μη στοιβάζει διάλογο πάνω σε διάλογο.
Future<bool> openLansweeperReport(
  BuildContext context,
  WidgetRef ref, {
  required LansweeperReportScope? scope,
}) async {
  if (_isOpen) return false;
  _isOpen = true;
  try {
    final notifier = ref.read(lansweeperReportScopeProvider.notifier);
    if (scope == null) {
      // Πριν το άνοιγμα, ώστε ο διάλογος να γεννηθεί ήδη στο σωστό διάστημα
      // αντί να αναπηδήσει από το «Σήμερα» μπροστά στα μάτια του χρήστη.
      await notifier.restoreRememberedRange();
      if (!context.mounted) return false;
    } else {
      notifier.set(scope);
    }
    await showDialog<void>(
      context: context,
      // Σημερινή συμπεριφορά, δηλωμένη: το κλικ έξω δεν κλείνει.
      barrierDismissible: false,
      builder: (context) => const LansweeperReportDialog(),
    );
  } finally {
    _isOpen = false;
  }
  return true;
}

/// Φρουρός διπλού ανοίγματος: η αναφορά είναι modal και καθολική, οπότε η
/// σημαία ζει έξω από κάθε widget — η συντόμευση μπορεί να πατηθεί από οθόνη
/// που δεν ξέρει καν ότι η αναφορά είναι ήδη ανοιχτή.
bool _isOpen = false;
