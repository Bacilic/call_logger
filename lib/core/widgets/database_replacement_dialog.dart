import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_replacement_notice.dart';
import '../init/database_switch_completion.dart';

/// Ανακοινώνει ότι το αρχείο βάσης αντικαταστάθηκε απ' έξω και ξαναδιαβάζει
/// ό,τι υπάρχει τώρα.
///
/// Η αποσύνδεση έχει **ήδη γίνει** από τον φρουρό — εδώ δεν σώζεται τίποτα,
/// μόνο ανακοινώνεται και ανανεώνεται η οθόνη. Ο διάλογος είναι σκόπιμα
/// αναπόδραστος: όσο είναι ανοιχτός, ο χρήστης δεν μπορεί να γράψει πάνω σε
/// δεδομένα που δεν ξέρει από ποια βάση προέρχονται. Δεν χρειάζεται χωριστός
/// μηχανισμός «παγώματος εγγραφών» — ο ίδιος ο διάλογος είναι το πάγωμα.
Future<void> showDatabaseReplacementDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String? databasePath,
  Future<void> Function()? onReconnected,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        Icons.swap_horizontal_circle_outlined,
        color: Theme.of(ctx).colorScheme.error,
      ),
      title: const Text('Η βάση άλλαξε από έξω'),
      content: SingleChildScrollView(
        child: Text(
          databaseReplacementMessage(databasePath),
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Επαναφόρτωση'),
        ),
      ],
    ),
  );

  ref.read(databaseReplacementNoticeProvider.notifier).clear();

  if (!context.mounted) return;
  await completeDatabaseSwitch(
    ref: ref,
    path: databasePath ?? '',
    showSuccessNotice: false,
    hooks: DatabaseSwitchCompletionHooks(onLifecycleChanged: onReconnected),
  );

  // Καινούριος φρουρός για την καινούρια σύνδεση. Ο προηγούμενος έχει «κάψει»
  // τη μία του βολή και από εδώ και πέρα θα απαντούσε «το χειρίζομαι εγώ» σε
  // κάθε σφάλμα βάσης — οπότε μια πραγματικά φθαρμένη βάση θα έσβηνε σιωπηλά
  // αντί να φτάσει στον χρήστη. Μετά το ξανάνοιγμα υπάρχει και νέα αφετηρία
  // ταυτότητας, άρα ο νέος φρουρός ξεκινά με σωστή εικόνα.
  ref.invalidate(databaseReplacementWatchdogProvider);
}
