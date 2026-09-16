import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/main_nav_request_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/current_operator.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/widgets/main_nav_destination.dart';
import '../../calls/provider/call_entry_provider.dart';
import '../models/task_notification.dart';
import '../providers/task_notifications_provider.dart';
import 'task_notifications_dialog.dart';

/// Δείχνει τι περιμένει τον χειριστή, σε **όποια οθόνη κι αν βρίσκεται**.
///
/// Κάθεται στο κέλυφος και όχι στην οθόνη Εκκρεμότητες: η ανάθεση γίνεται στο
/// μηχάνημα του άλλου, και ο παραλήπτης μπορεί να δουλεύει οπουδήποτε.
///
/// **Δεν έχει δικό του χρονομετρητή.** Ο περιοδικός φρουρός της κοινόχρηστης
/// βάσης ξαναδιαβάζει τις ειδοποιήσεις μαζί με όλα τα υπόλοιπα· εδώ γίνεται
/// μόνο η απόφαση «τώρα ή αργότερα».
///
/// Τρεις λόγοι σιωπής, και κανένας δεν χάνει ειδοποίηση:
///
/// 1. **Ενεργή κλήση.** Ο χειριστής μιλά με άνθρωπο· ένας διάλογος μπροστά στη
///    φόρμα είναι το χειρότερο δυνατό timing. Η ειδοποίηση μένει γραμμένη και
///    εμφανίζεται μόλις η κλήση τελειώσει.
/// 2. **Η ρύθμιση είναι κλειστή.** Οι ειδοποιήσεις εξακολουθούν να γράφονται —
///    αν την ξανανοίξει, δεν βρίσκει άδειο παρελθόν.
/// 3. **Διάλογος ήδη ανοιχτός.** Ποτέ δεύτερος από πάνω στον πρώτο.
class TaskNotificationsListener extends ConsumerStatefulWidget {
  const TaskNotificationsListener({super.key});

  @override
  ConsumerState<TaskNotificationsListener> createState() =>
      _TaskNotificationsListenerState();
}

class _TaskNotificationsListenerState
    extends ConsumerState<TaskNotificationsListener> {
  bool _dialogOpen = false;

  Future<void> _maybeShow(List<TaskNotification> notifications) async {
    if (_dialogOpen || notifications.isEmpty) return;
    if (!mounted) return;

    _dialogOpen = true;
    try {
      final result = await showTaskNotificationsDialog(
        context,
        notifications: notifications,
      );
      if (result == null) return;

      // Σβήνει ΟΛΕΣ, και τις κρυμμένες πίσω από το «και Ν ακόμη»: το «Εντάξει»
      // σημαίνει «τα είδα». Πρώτα η διαγραφή και μετά η πλοήγηση — αλλιώς μια
      // αλλαγή οθόνης θα μπορούσε να αφήσει τη διαγραφή στη μέση.
      final operatorId = CurrentOperator.active?.id;
      if (operatorId != null) {
        await ref
            .read(taskNotificationsRepositoryProvider)
            .clearFor(operatorId);
        ref.invalidate(taskNotificationsProvider);
      }

      if (result.silenceFuture) {
        await SettingsService().windowUi.setNotifyTaskHandovers(false);
        ref.invalidate(notifyTaskHandoversProvider);
      }

      if (!result.openTasks || !mounted) return;
      // Με μία ειδοποίηση πάμε στην ίδια την κάρτα· με πολλές, στη λίστα —
      // η εστίαση σε μία από τις πέντε θα ήταν αυθαίρετη επιλογή.
      ref
          .read(mainNavRequestProvider.notifier)
          .request(
            MainNavRequest(
              destination: MainNavDestination.tasks,
              taskFocusEntityId: notifications.length == 1
                  ? notifications.single.taskId
                  : null,
            ),
          );
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Και τα τρία με `watch` και όχι `listen`: όταν η κλήση τελειώσει ή η
    // ρύθμιση ξανανοίξει, το build ξανατρέχει και η κρατημένη ειδοποίηση
    // εμφανίζεται — χωρίς να χρειάζεται νέα εγγραφή στη βάση για αφορμή.
    final onCall = ref.watch(callEntryHasActiveCallProvider);
    final enabled = ref.watch(notifyTaskHandoversProvider).value ?? true;
    final pending =
        ref.watch(taskNotificationsProvider).value ??
        const <TaskNotification>[];

    if (!onCall && enabled && pending.isNotEmpty && !_dialogOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_maybeShow(pending));
      });
    }

    return const SizedBox.shrink();
  }
}
