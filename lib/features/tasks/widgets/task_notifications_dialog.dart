import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/draggable_dialog_shell.dart';
import '../../operators/avatars/operator_avatar_image.dart';
import '../../operators/providers/operator_directory_providers.dart';
import '../models/task_notification.dart';

/// Πόσες ειδοποιήσεις δείχνει ο διάλογος πριν συνοψίσει τις υπόλοιπες.
///
/// Μετά από απουσία ημερών η λίστα μπορεί να είναι δεκάδες. Πέντε γραμμές
/// χωρούν χωρίς κύλιση και λένε ήδη «τι σε περιμένει»· το «Εντάξει» σβήνει
/// **όλες**, και η πλήρης εικόνα είναι ούτως ή άλλως η ίδια η οθόνη
/// Εκκρεμότητες.
const int kTaskNotificationsPreviewLimit = 5;

/// Τι απάντησε ο άνθρωπος στον διάλογο.
class TaskNotificationsDialogResult {
  const TaskNotificationsDialogResult({
    required this.silenceFuture,
    required this.openTasks,
  });

  /// Τίκαρε «να μην εμφανίζονται ξανά».
  final bool silenceFuture;

  /// Ζήτησε να πάει στις Εκκρεμότητες.
  final bool openTasks;
}

/// Ο ΕΝΑΣ διάλογος που μαζεύει ό,τι περιμένει τον άνθρωπο.
///
/// **Ποτέ ουρά διαλόγων.** Δέκα «Εντάξει» στη σειρά είναι τιμωρία — και όταν
/// κάποιος γυρίζει από άδεια, δέκα είναι το λίγο. Ό,τι έχει μαζευτεί μπαίνει
/// εδώ μέσα, με μία γραμμή σύνοψης όταν είναι περισσότερα από ένα.
///
/// Επιστρέφει `null` όταν ο διάλογος έκλεισε χωρίς απάντηση — τότε τίποτα δεν
/// σβήνεται και οι ειδοποιήσεις ξαναδοκιμάζουν αργότερα.
Future<TaskNotificationsDialogResult?> showTaskNotificationsDialog(
  BuildContext context, {
  required List<TaskNotification> notifications,
}) {
  return showDialog<TaskNotificationsDialogResult>(
    context: context,
    builder: (context) =>
        _TaskNotificationsDialog(notifications: notifications),
  );
}

class _TaskNotificationsDialog extends ConsumerStatefulWidget {
  const _TaskNotificationsDialog({required this.notifications});

  final List<TaskNotification> notifications;

  @override
  ConsumerState<_TaskNotificationsDialog> createState() =>
      _TaskNotificationsDialogState();
}

class _TaskNotificationsDialogState
    extends ConsumerState<_TaskNotificationsDialog> {
  bool _silence = false;

  List<TaskNotification> get _all => widget.notifications;

  bool get _isSingle => _all.length == 1;

  int get _hiddenCount =>
      (_all.length - kTaskNotificationsPreviewLimit).clamp(0, _all.length);

  /// Η σύνοψη μετρά **είδη**, όχι γραμμές: «3 ανατέθηκαν, 2 έκλεισαν» απαντά
  /// στο «τι με περιμένει», ενώ ένα σκέτο «5 ειδοποιήσεις» δεν απαντά τίποτα.
  String? get _summary {
    if (_isSingle) return null;
    final counts = <TaskNotificationKind, int>{};
    for (final item in _all) {
      counts[item.kind] = (counts[item.kind] ?? 0) + 1;
    }
    final parts = <String>[
      if (counts[TaskNotificationKind.assigned] case final n?)
        n == 1 ? '1 ανατέθηκε σε εσάς' : '$n ανατέθηκαν σε εσάς',
      if (counts[TaskNotificationKind.unassigned] case final n?)
        n == 1 ? '1 δεν είναι πια δική σας' : '$n δεν είναι πια δικές σας',
      if (counts[TaskNotificationKind.closed] case final n?)
        n == 1 ? '1 δική σας έκλεισε' : '$n δικές σας έκλεισαν',
    ];
    return parts.join(' · ');
  }

  String get _title {
    if (!_isSingle) return 'Όσο λείπατε';
    return switch (_all.single.kind) {
      TaskNotificationKind.assigned => 'Νέα εκκρεμότητα για εσάς',
      TaskNotificationKind.unassigned =>
        'Μια εκκρεμότητα δεν είναι πια δική σας',
      TaskNotificationKind.closed => 'Μια εκκρεμότητά σας έκλεισε',
    };
  }

  void _close({required bool openTasks}) {
    Navigator.of(context).pop(
      TaskNotificationsDialogResult(
        silenceFuture: _silence,
        openTasks: openTasks,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = ref.watch(operatorNamesProvider).value;
    final avatars =
        ref.watch(operatorAvatarsProvider).value ?? const <int, String?>{};
    final shown = _all.take(kTaskNotificationsPreviewLimit).toList();
    final summary = _summary;

    return DraggableDialogShell(
      title: Text(_title),
      builder: (titleHandle) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.notifications_none, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: titleHandle),
          ],
        ),
        // Πέντε γραμμές συν το κουτάκι δεν χωρούν σε χαμηλή οθόνη: χωρίς
        // κύλιση ο διάλογος ξεχειλίζει και κρύβει το ίδιο του το «Εντάξει».
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (summary != null) ...[
                  Text(
                    summary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                for (final item in shown) ...[
                  _NotificationTile(
                    notification: item,
                    actorName: item.actorOperatorId == null
                        ? null
                        : operatorDisplayNameFor(names, item.actorOperatorId!),
                    avatarKey: avatars[item.actorOperatorId],
                  ),
                  const SizedBox(height: 8),
                ],
                if (_hiddenCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 2),
                    child: Text(
                      'και $_hiddenCount ακόμη…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                // Το κουτάκι ΕΙΝΑΙ η ρύθμιση, όχι μια δεύτερη επιλογή δίπλα της:
                // όποιος το τικάρει εδώ το βρίσκει σβηστό και στις Ρυθμίσεις.
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  value: _silence,
                  onChanged: (value) =>
                      setState(() => _silence = value ?? false),
                  title: Text(
                    'Να μην εμφανίζονται ξανά αυτές οι ειδοποιήσεις',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _close(openTasks: true),
            child: Text(
              _isSingle ? 'Άνοιγμα εκκρεμότητας' : 'Άνοιγμα Εκκρεμοτήτων',
            ),
          ),
          FilledButton(
            onPressed: () => _close(openTasks: false),
            child: const Text('Εντάξει'),
          ),
        ],
      ),
    );
  }
}

/// Μία γραμμή: ποιος, τι, πότε — και ο τίτλος της εκκρεμότητας.
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.actorName,
    required this.avatarKey,
  });

  final TaskNotification notification;
  final String? actorName;
  final String? avatarKey;

  /// Το ρήμα σε ονομαστική παράθεση: τα ελληνικά ονόματα δεν κλίνονται από τον
  /// κώδικα, οπότε «Ανέθεσε: Βλάσης» και ποτέ «ανέθεσε ο Βλάση».
  String get _verb => switch (notification.kind) {
    TaskNotificationKind.assigned => 'Ανέθεσε',
    TaskNotificationKind.unassigned => 'Αφαίρεσε την ανάθεση',
    TaskNotificationKind.closed => 'Έκλεισε',
  };

  IconData get _icon => switch (notification.kind) {
    TaskNotificationKind.assigned => Icons.person_add_alt,
    TaskNotificationKind.unassigned => Icons.person_remove_alt_1_outlined,
    TaskNotificationKind.closed => Icons.check_circle_outline,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = notification.createdAt;
    final when = at == null ? '' : ' · ${DateFormat('dd/MM HH:mm').format(at)}';
    // Χωρίς αναγνωρισμένο δράστη μένει το γεγονός σκέτο: μια παύλα στη θέση
    // του ονόματος δεν προσθέτει τίποτα.
    final who = actorName == null ? _verb : '$_verb: $actorName';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: actorName != null
                ? OperatorAvatarImage(avatarKey: avatarKey, size: 18)
                : Icon(
                    _icon,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$who$when',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  notification.taskTitle,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
