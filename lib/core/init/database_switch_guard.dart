import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/active_critical_operations_provider.dart';
import '../providers/main_nav_request_provider.dart';
import '../providers/pending_deferred_actions_provider.dart';
import '../widgets/main_nav_destination.dart';
import '../../features/calls/layout/call_form_clear.dart';
import '../../features/calls/provider/call_entry_provider.dart';
import '../../features/calls/provider/smart_entity_selector_provider.dart';
import '../../features/database/providers/backup_scheduler_provider.dart';

/// Είδος εμποδίου πριν την εναλλαγή αρχείου βάσης.
enum DatabaseSwitchBlockerKind {
  openCallForm,
  lansweeperSubmitRunning,
  backupJobRunning,
}

/// Περιγραφή εμποδίου εναλλαγής βάσης για τον διάλογο-φρουρό.
class DatabaseSwitchBlocker {
  const DatabaseSwitchBlocker({
    required this.kind,
    required this.title,
    required this.description,
    required this.interruptible,
  });

  final DatabaseSwitchBlockerKind kind;
  final String title;
  final String description;
  final bool interruptible;
}

/// Συλλέγει τα τρέχοντα εμπόδια εναλλαγής βάσης (χωρίς UI).
List<DatabaseSwitchBlocker> collectDatabaseSwitchBlockers(WidgetRef ref) {
  final blockers = <DatabaseSwitchBlocker>[];

  final smart = ref.read(callSmartEntityProvider);
  final entry = ref.read(callEntryProvider);
  final hasOpenCallForm =
      smart.hasAnyContent ||
      entry.isCallTimerRunning ||
      entry.durationSeconds > 0 ||
      entry.notes.trim().isNotEmpty ||
      entry.category.trim().isNotEmpty;
  if (hasOpenCallForm) {
    blockers.add(
      const DatabaseSwitchBlocker(
        kind: DatabaseSwitchBlockerKind.openCallForm,
        title: 'Ανοιχτή κλήση',
        description:
            'Υπάρχει ανοιχτή κλήση σε εξέλιξη (πεδία φόρμας, χρονόμετρο ή σημειώσεις).',
        interruptible: true,
      ),
    );
  }

  final activeOps = ref.read(activeCriticalOperationsProvider);
  if (activeOps.contains(CriticalOperation.lansweeperTicketSubmit)) {
    blockers.add(
      const DatabaseSwitchBlocker(
        kind: DatabaseSwitchBlockerKind.lansweeperSubmitRunning,
        title: 'Αποστολή Lansweeper',
        description:
            'Η αποστολή εισιτηρίου στο Lansweeper βρίσκεται σε εξέλιξη και δεν μπορεί να διακοπεί με ασφάλεια.',
        interruptible: false,
      ),
    );
  }

  if (ref.read(backupSchedulerProvider.notifier).isBackupJobRunning) {
    blockers.add(
      const DatabaseSwitchBlocker(
        kind: DatabaseSwitchBlockerKind.backupJobRunning,
        title: 'Αντίγραφο ασφαλείας',
        description:
            'Το αντίγραφο ασφαλείας βρίσκεται σε εξέλιξη και δεν μπορεί να διακοπεί με ασφάλεια.',
        interruptible: false,
      ),
    );
  }

  return blockers;
}

/// Οριστικοποιεί κατηγορία Γ και καθαρίζει snackbars αναίρεσης πριν την εναλλαγή.
///
/// Καλείται ΜΟΝΟ όταν η εναλλαγή πρόκειται να επιτραπεί (`true`).
Future<bool> _finalizeAllowedDatabaseSwitch(
  BuildContext context,
  WidgetRef ref,
) async {
  final labels = await ref
      .read(pendingDeferredActionsProvider.notifier)
      .settleAll();
  if (!context.mounted) return true;
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  if (labels.isNotEmpty) {
    messenger.showSnackBar(
      SnackBar(content: Text('Ολοκληρώθηκαν πρώτα: ${labels.join(', ')}')),
    );
  }
  return true;
}

/// Τρέχει μια ροή εναλλαγής βάσης πίσω από τον φρουρό, δηλώνοντάς την όσο διαρκεί.
///
/// Η δήλωση [CriticalOperation.databaseSwitch] κλείνει την ΑΝΤΙΣΤΡΟΦΗ φορά του
/// ελέγχου αντιγράφων: ο φρουρός μπλοκάρει την εναλλαγή όταν τρέχει αντίγραφο,
/// ενώ αυτό εδώ εμποδίζει τον περιοδικό `_tick` του χρονοδιακόπτη να ΞΕΚΙΝΗΣΕΙ
/// αντίγραφο πάνω σε βάση που αλλάζει εκείνη τη στιγμή.
///
/// Επιστρέφει `false` όταν ο φρουρός απέρριψε την εναλλαγή (η [action] δεν τρέχει).
Future<bool> runGuardedDatabaseSwitch(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action,
) async {
  if (!await ensureDatabaseSwitchAllowed(context, ref)) return false;
  final ops = ref.read(activeCriticalOperationsProvider.notifier);
  ops.begin(CriticalOperation.databaseSwitch);
  try {
    await action();
    return true;
  } finally {
    ops.end(CriticalOperation.databaseSwitch);
  }
}

/// Επιστρέφει `true` αν επιτρέπεται να προχωρήσει η εναλλαγή βάσης.
Future<bool> ensureDatabaseSwitchAllowed(
  BuildContext context,
  WidgetRef ref,
) async {
  final blockers = collectDatabaseSwitchBlockers(ref);
  if (blockers.isEmpty) {
    return _finalizeAllowedDatabaseSwitch(context, ref);
  }

  final nonInterruptible = blockers
      .where((b) => !b.interruptible)
      .toList(growable: false);
  if (nonInterruptible.isNotEmpty) {
    if (!context.mounted) return false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final names = nonInterruptible.map((b) => b.title).join(', ');
        return AlertDialog(
          title: const Text('Δεν είναι εφικτή η αλλαγή βάσης'),
          content: Text(
            '$names.\n\n'
            'Η ενέργεια βρίσκεται σε εξέλιξη και δεν μπορεί να διακοπεί με ασφάλεια. '
            'Περιμένετε να ολοκληρωθεί και δοκιμάστε ξανά.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Εντάξει, θα περιμένω'),
            ),
          ],
        );
      },
    );
    return false;
  }

  if (!context.mounted) return false;
  final choice = await showDialog<_OpenCallFormGuardChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Δεν είναι εφικτή η αλλαγή βάσης'),
      content: const Text(
        'Δεν είναι εφικτή η αλλαγή βάσης διότι υπάρχει ανοιχτή κλήση σε εξέλιξη',
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(_OpenCallFormGuardChoice.cancel),
          child: const Text('Άκυρο'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(_OpenCallFormGuardChoice.discardCall),
          child: const Text('Διακοπή κλήσης'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(ctx).pop(_OpenCallFormGuardChoice.goToCall),
          child: const Text('Μετάβαση στην κλήση'),
        ),
      ],
    ),
  );

  switch (choice) {
    case _OpenCallFormGuardChoice.discardCall:
      // Πλήρης εκκαθάριση (4 βήματα + ξέπλυμα αλυσίδας): η φόρμα καθαρίζεται ενώ
      // η οθόνη κλήσεων ΔΕΝ είναι προσαρτημένη, οπότε τα σκέτα clearAll/reset θα
      // άφηναν κολλημένες επιβεβαιώσεις/μάνταλο και «dirty» providers.
      clearCallFormCompletely(ref);
      if (!context.mounted) {
        await ref.read(pendingDeferredActionsProvider.notifier).settleAll();
        return true;
      }
      return _finalizeAllowedDatabaseSwitch(context, ref);
    case _OpenCallFormGuardChoice.goToCall:
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
    case _OpenCallFormGuardChoice.cancel:
    case null:
      return false;
  }
}

enum _OpenCallFormGuardChoice { cancel, discardCall, goToCall }
