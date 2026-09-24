import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/current_operator.dart';
import '../../../core/services/settings_service.dart';
import '../../calls/provider/call_entry_provider.dart';
import '../models/task_notification.dart';
import '../providers/task_notifications_provider.dart';
import '../services/task_notification_navigation.dart';
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

  /// Ειδοποιήσεις που δείχτηκαν ήδη και **δεν** σβήστηκαν.
  ///
  /// Χωρίς αυτό ο διάλογος δεν έφευγε ποτέ από την οθόνη: μόλις έκλεινε, το
  /// `build` ξανάβλεπε την ίδια μη άδεια λίστα και τον ξανάνοιγε. Συνέβαινε σε
  /// δύο δρόμους — με Escape ή κλικ έξω (όπου σκόπιμα δεν σβήνεται τίποτα),
  /// και όταν η διαγραφή δεν γινόταν γιατί δεν υπήρχε αναγνωρισμένος χρήστης.
  ///
  /// **Μνήμη συνεδρίας, όχι απόφαση.** Δεν γράφεται πουθενά: στην επόμενη
  /// εκκίνηση οι ειδοποιήσεις ξαναεμφανίζονται κανονικά, γιατί το «δεν
  /// απάντησα τώρα» δεν σημαίνει «μην με ξαναρωτήσεις ποτέ» — αυτό το λέει
  /// μόνο το κουτάκι στον διάλογο.
  final Set<int> _shownWithoutAnswer = <int>{};

  Future<void> _maybeShow(List<TaskNotification> notifications) async {
    if (_dialogOpen || notifications.isEmpty) return;
    if (!mounted) return;

    _dialogOpen = true;
    try {
      final result = await showTaskNotificationsDialog(
        context,
        notifications: notifications,
      );
      if (result == null) {
        // Έκλεισε χωρίς απάντηση: τίποτα δεν σβήνεται, αλλά ούτε ξαναρωτά
        // αμέσως. Η επόμενη εκκίνηση θα τις ξαναδείξει.
        _shownWithoutAnswer.addAll(notifications.map((n) => n.id));
        return;
      }

      // Σβήνει ΟΛΕΣ, και τις κρυμμένες πίσω από το «και Ν ακόμη»: το «Εντάξει»
      // σημαίνει «τα είδα». Πρώτα η διαγραφή και μετά η πλοήγηση — αλλιώς μια
      // αλλαγή οθόνης θα μπορούσε να αφήσει τη διαγραφή στη μέση.
      final operatorId = CurrentOperator.active?.id;
      if (operatorId != null) {
        await ref
            .read(taskNotificationsRepositoryProvider)
            .clearFor(operatorId);
        ref.invalidate(taskNotificationsProvider);
      } else {
        // Χωρίς αναγνωρισμένο χρήστη δεν υπάρχει ουρά να αδειάσει — αλλά ο
        // άνθρωπος απάντησε, και ο διάλογος δεν επιτρέπεται να ξαναπεταχτεί.
        _shownWithoutAnswer.addAll(notifications.map((n) => n.id));
      }

      if (result.silenceFuture) {
        await SettingsService().windowUi.setNotifyTaskHandovers(false);
        ref.invalidate(notifyTaskHandoversProvider);
      }

      if (!result.openTasks || !mounted) return;
      await openTaskFromNotifications(context, ref, notifications);
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

    // Ό,τι δείχτηκε και δεν απαντήθηκε δεν ξαναρωτά σε αυτή τη συνεδρία.
    final unanswered = pending
        .where((n) => !_shownWithoutAnswer.contains(n.id))
        .toList();

    if (!onCall && enabled && unanswered.isNotEmpty && !_dialogOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_maybeShow(unanswered));
      });
    }

    return const SizedBox.shrink();
  }
}
