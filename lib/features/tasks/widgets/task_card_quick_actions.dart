import 'package:flutter/material.dart';

import '../../../core/widgets/compact_tooltip.dart';
import '../models/task.dart';
import 'task_card_callbacks.dart';

/// Υποδείξεις για κουμπί που δείχνει σε οντότητα εκτός καταλόγου.
///
/// Γράφονται εδώ μία φορά ώστε το κείμενο που βλέπει ο χρήστης και το κείμενο
/// που φυλάνε τα τεστ να είναι το ίδιο.
const String kTaskActionCallerMissingHint =
    'Ο υπάλληλος δεν υπάρχει πια στον κατάλογο.';
const String kTaskActionDepartmentMissingHint =
    'Το τμήμα δεν υπάρχει πια στον κατάλογο.';
const String kTaskActionEquipmentMissingHint =
    'Ο εξοπλισμός δεν υπάρχει πια στον κατάλογο.';

/// Οι συντομεύσεις επεξεργασίας οντοτήτων μιας γρήγορης καταχώρησης.
///
/// Εμφανίζονται μόνο στις γρήγορες καταχωρήσεις: εκεί η εκκρεμότητα υπάρχει
/// ακριβώς για να διορθωθεί κάτι στον κατάλογο, οπότε η διαδρομή προς τη φόρμα
/// αξίζει να είναι ένα κλικ.
class TaskCardQuickActions extends StatelessWidget {
  const TaskCardQuickActions({
    required this.task,
    required this.callbacks,
    required this.onEntityEdited,
    super.key,
  });

  final Task task;
  final TaskCardCallbacks callbacks;

  /// Τι γίνεται μετά από επιτυχή αποθήκευση οντότητας — το αποφασίζει η κάρτα,
  /// γιατί εκεί ζουν οι ρυθμίσεις και ο διάλογος κλεισίματος.
  final Future<void> Function() onEntityEdited;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final actions = <Widget>[
      if (task.callerId != null && callbacks.onEditCaller != null)
        _button(
          icon: Icons.person_outline,
          label: 'Επεξεργασία Χρήστη',
          linkedDeleted: task.callerLinkedDeleted,
          missingHint: kTaskActionCallerMissingHint,
          onEdit: callbacks.onEditCaller!,
        ),
      if (task.departmentId != null && callbacks.onEditDepartment != null)
        _button(
          icon: Icons.domain_outlined,
          label: 'Επεξεργασία Τμήματος',
          linkedDeleted: task.departmentLinkedDeleted,
          missingHint: kTaskActionDepartmentMissingHint,
          onEdit: callbacks.onEditDepartment!,
        ),
      if (task.equipmentId != null && callbacks.onEditEquipment != null)
        _button(
          icon: Icons.computer_outlined,
          label: 'Επεξεργασία Εξοπλισμού',
          linkedDeleted: task.equipmentLinkedDeleted,
          missingHint: kTaskActionEquipmentMissingHint,
          onEdit: callbacks.onEditEquipment!,
        ),
    ];

    if (actions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(
            height: 10,
            thickness: 0.5,
            color: theme.colorScheme.outlineVariant,
          ),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }

  /// Ένα κουμπί γρήγορης επεξεργασίας συνδεδεμένης οντότητας.
  ///
  /// Το κουμπί μένει στη θέση του ακόμη κι όταν η οντότητα έχει διαγραφεί: η
  /// σύνδεση υπήρξε και η πληροφορία αξίζει να φαίνεται. Αυτό που αλλάζει είναι
  /// **πότε** το μαθαίνει ο χρήστης — εικονίδιο κομμένου δεσμού και υπόδειξη
  /// που εξηγεί, αντί για μήνυμα αποτυχίας μετά το πάτημα.
  Widget _button({
    required IconData icon,
    required String label,
    required bool linkedDeleted,
    required String missingHint,
    required Future<bool> Function() onEdit,
  }) {
    final button = OutlinedButton.icon(
      onPressed: () async {
        final result = await onEdit();
        if (!result) return;
        await onEntityEdited();
      },
      icon: Icon(linkedDeleted ? Icons.link_off : icon, size: 16),
      label: Text(label),
    );
    if (!linkedDeleted) return button;
    return CompactTooltip(message: missingHint, child: button);
  }
}
