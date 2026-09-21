import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/compact_tooltip.dart';
import '../../history/models/lansweeper_sync_state.dart';
import '../../history/widgets/lansweeper/lansweeper_state_badge.dart';
import '../models/task.dart';
import '../utils/task_duration_format.dart';
import 'task_card_callbacks.dart';
import 'task_due_date_label.dart';
import 'task_person_chip.dart';

/// Η δεξιά στήλη της κάρτας: σε τι κατάσταση είναι η εκκρεμότητα και τι
/// μπορείς να της κάνεις.
///
/// Οι ενέργειες έρχονται ως ένα [TaskCardCallbacks] αντί για οκτώ ξεχωριστές
/// κλειστούρες: τα κουμπιά της κάρτας είναι ένα σύνολο και ταξιδεύουν μαζί.
class TaskCardActions extends StatelessWidget {
  const TaskCardActions({
    required this.task,
    required this.callbacks,
    required this.status,
    this.ticketViewUrlTemplate,
    required this.assigneeName,
    required this.creatorName,
    required this.closerName,
    required this.operatorAvatars,
    required this.disabledOperatorIds,
    required this.deleteMenuEnabled,
    required this.hasSolution,
    required this.showSolution,
    required this.onToggleSolution,
    super.key,
  });

  final Task task;
  final TaskCardCallbacks callbacks;
  final TaskStatus status;

  /// Το πρότυπο URL προβολής αιτήματος, από τις ρυθμίσεις Lansweeper.
  ///
  /// Χωρίς αυτό ο σύνδεσμος δίπλα στο σήμα δεν εμφανίζεται — ο αριθμός μένει
  /// ορατός, αλλά δεν υπόσχεται άνοιγμα που δεν μπορεί να γίνει.
  final String? ticketViewUrlTemplate;

  /// Το όνομα του υπευθύνου, ή `null` όταν δεν υπάρχει ανάθεση.
  final String? assigneeName;

  /// Το όνομα του δημιουργού, ή `null` όταν δεν είναι καταγεγραμμένος.
  final String? creatorName;

  /// Το όνομα όποιου ολοκλήρωσε την εκκρεμότητα, ή `null` όσο είναι ανοιχτή
  /// και για όσες έκλεισαν πριν αρχίσει να καταγράφεται.
  final String? closerName;

  /// Ποιο εικονίδιο φοράει ποιο προφίλ — ολόκληρος ο χάρτης, όχι τρία κλειδιά.
  ///
  /// Ο χάρτης κοστίζει το ίδιο με τρεις αναζητήσεις και δεν θα χρειαστεί νέα
  /// παράμετρος αν κάποτε η κάρτα δείξει τέταρτο πρόσωπο.
  final Map<int, String?> operatorAvatars;

  /// Ποια προφίλ έχουν απενεργοποιηθεί — τα σήματά τους γράφονται πλάγια.
  final Set<int> disabledOperatorIds;

  final bool deleteMenuEnabled;
  final bool hasSolution;
  final bool showSolution;
  final VoidCallback onToggleSolution;

  bool get _isClosed => status == TaskStatus.closed;

  String get _lansweeperState =>
      LansweeperSyncState.normalize(task.lansweeperState);

  bool get _hasTicket => (task.lansweeperMainTicketId ?? '').trim().isNotEmpty;

  /// Φαίνεται το σήμα Lansweeper;
  ///
  /// **Μόνο όταν λέει κάτι.** Η εκκρεμότητα δεν είναι ουρά που πρέπει να
  /// αδειάσει: ένα «Ακαταχώρητη» σε κάθε κάρτα θα ήταν θόρυβος που κρύβει τις
  /// λίγες που όντως έχουν αίτημα.
  bool get _showLansweeperBadge =>
      _hasTicket || _lansweeperState == LansweeperSyncState.failed;

  /// Ο δημιουργός δείχνεται μόνο όταν είναι ΑΛΛΟΣ από τον υπεύθυνο: όταν
  /// ταυτίζονται, το ίδιο όνομα δύο φορές δεν προσθέτει πληροφορία. Χωρίς
  /// ανάθεση ο δημιουργός ΕΙΝΑΙ η ευθύνη — ίδια φόρμουλα με το φίλτρο χρήστη,
  /// ώστε η κάρτα να εξηγεί γιατί εμφανίστηκε στο φίλτρο κάποιου.
  bool get _showCreator =>
      creatorName != null &&
      task.createdByOperatorId != task.assignedOperatorId;

  /// Ποιος χρωστούσε την εκκρεμότητα: ο υπεύθυνος, ή ο δημιουργός όταν δεν
  /// υπάρχει ανάθεση. Ίδια φόρμουλα με το φίλτρο χρήστη.
  int? get _responsibleId =>
      task.assignedOperatorId ?? task.createdByOperatorId;

  /// Ο κλείσας δείχνεται μόνο όταν είναι ΑΛΛΟΣ από αυτόν που τη χρωστούσε —
  /// αυτό ακριβώς είναι η πληροφορία που έλειπε από την κάρτα.
  ///
  /// Και μόνο σε ολοκληρωμένη: η σφραγίδα επιβιώνει της αναίρεσης, όπως η ώρα
  /// ολοκλήρωσης, αλλά ένα «Έκλεισε: …» πάνω σε ξανα-ανοιγμένη εκκρεμότητα θα
  /// διαβαζόταν σαν ψέμα. Επανεμφανίζεται μόλις ξανακλείσει.
  bool get _showCloser =>
      _isClosed &&
      closerName != null &&
      task.closedByOperatorId != _responsibleId;

  static String _relativeCreatedAt(DateTime? createdAt) {
    if (createdAt == null) return '';
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'μόλις τώρα';
    if (diff.inHours < 1) return 'πριν ${diff.inMinutes} λεπτά';
    if (diff.inHours < 24) return 'πριν ${diff.inHours} ώρες';
    if (diff.inDays == 1) return 'χθες';
    if (diff.inDays < 7) return '${diff.inDays} μέρες πριν';
    return DateFormat('dd/MM/yyyy').format(createdAt);
  }

  static Color _statusChipColor(TaskStatus status, ColorScheme scheme) {
    return switch (status) {
      TaskStatus.open => scheme.surfaceContainerHighest,
      TaskStatus.snoozed => scheme.tertiaryContainer,
      TaskStatus.closed => scheme.surfaceContainerHighest,
    };
  }

  String _statusTooltip() {
    final createdAt = task.createdAtDateTime;
    final completedAt = task.completedAtDateTime;
    final snoozeEntries = task.snoozeEntries;
    final lastSnoozeAt = snoozeEntries.isNotEmpty
        ? snoozeEntries.last.snoozedAt
        : null;

    switch (status) {
      case TaskStatus.open:
        final rel = _relativeCreatedAt(createdAt);
        // Το όνομα μπαίνει σε δική του γραμμή, σε ονομαστική: τα ελληνικά
        // ονόματα δεν κλίνονται από τον κώδικα, και ένα «από Βασίλης» θα
        // ήταν χειρότερο από τη σκέτη παράθεση.
        final by = creatorName == null ? '' : '\nΆνοιξε: $creatorName';
        if (rel.isEmpty) {
          return by.isEmpty ? 'Ανοικτή εκκρεμότητα' : 'Ανοικτή εκκρεμότητα$by';
        }
        return 'Δημιουργία: $rel$by';
      case TaskStatus.snoozed:
        if (snoozeEntries.isEmpty) return 'Αναβληθείσα εκκρεμότητα';
        final lines = <String>['Αναβολές: ${snoozeEntries.length}'];
        for (final entry in snoozeEntries.asMap().entries) {
          final i = entry.key + 1;
          final line =
              '$iη: ${DateFormat('dd/MM HH:mm').format(entry.value.snoozedAt)}';
          final note = entry.value.note?.trim();
          if (note != null && note.isNotEmpty) {
            lines.add('$line — λόγος: $note');
          } else {
            lines.add(line);
          }
        }
        return lines.join('\n');
      case TaskStatus.closed:
        final total = (createdAt != null && completedAt != null)
            ? durationSince(createdAt, completedAt)
            : '';
        final fromLast = (lastSnoozeAt != null && completedAt != null)
            ? durationSince(lastSnoozeAt, completedAt)
            : '';
        if (total.isEmpty && fromLast.isEmpty) {
          return 'Ολοκληρωμένη εκκρεμότητα';
        }
        if (fromLast.isEmpty) return 'Συνολικός χρόνος: $total';
        return 'Συνολικός χρόνος: $total\nΑπό τελευταία αναβολή: $fromLast';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPriorityBadge(theme),
            // Ό,τι δείχνει κατάσταση, την αλλάζει κιόλας: το chip του
            // υπευθύνου ανοίγει τον ίδιο επιλογέα με το μενού. Απλό κλικ —
            // είναι κουμπί, όχι κείμενο (η ημερομηνία δίπλα θέλει διπλό
            // επειδή είναι ετικέτα).
            if (assigneeName != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TaskPersonChip.assignee(
                  name: assigneeName!,
                  onAssign: callbacks.onAssign,
                  avatarKey: operatorAvatars[task.assignedOperatorId],
                  isDisabledProfile: disabledOperatorIds.contains(
                    task.assignedOperatorId,
                  ),
                ),
              ),
            _buildStatusChip(theme),
            const SizedBox(width: 10),
            TaskDueDateLabel(
              date: _isClosed ? task.completedAtDateTime : task.dueDateTime,
              pattern: _isClosed ? 'dd/MM - HH:mm' : 'dd/MM HH:mm',
              fallbackText: task.dueDate,
              showRemaining: !_isClosed,
              onSnooze: _isClosed ? null : callbacks.onSnooze,
            ),
            const SizedBox(width: 4),
            if (callbacks.onComplete != null && !_isClosed)
              IconButton(
                icon: const Icon(Icons.check_circle_outline),
                tooltip: 'Ολοκλήρωση',
                visualDensity: VisualDensity.compact,
                onPressed: callbacks.onComplete,
              ),
            _buildMenu(),
          ],
        ),
        // Δεύτερη σειρά, όχι δίπλα στα υπόλοιπα σήματα: η πάνω σειρά είναι ήδη
        // γεμάτη με ενέργειες, και τα δύο αυτά πρόσωπα δεν είναι ενέργειες —
        // είναι ιστορικό. Αναδιπλώνονται αντί να στριμώχνονται, γιατί όταν
        // φαίνονται και τα δύο μαζί δεν χωρούν πάντα σε μία γραμμή.
        // Δεύτερη σειρά: ό,τι είναι ΠΛΗΡΟΦΟΡΙΑ και όχι ενέργεια — ποιος την
        // άνοιξε, ποιος την έκλεισε, από πού ήρθε, πού κατέληξε.
        if (_showCreator ||
            _showCloser ||
            task.callId != null ||
            _showLansweeperBadge)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                if (_showCreator)
                  TaskPersonChip.creator(
                    name: creatorName!,
                    avatarKey: operatorAvatars[task.createdByOperatorId],
                    isDisabledProfile: disabledOperatorIds.contains(
                      task.createdByOperatorId,
                    ),
                  ),
                if (_showCloser)
                  TaskPersonChip.closer(
                    name: closerName!,
                    avatarKey: operatorAvatars[task.closedByOperatorId],
                    isDisabledProfile: disabledOperatorIds.contains(
                      task.closedByOperatorId,
                    ),
                  ),
                if (task.callId != null) _buildCallLinkChip(theme),
                if (_showLansweeperBadge)
                  LansweeperStateBadge(
                    state: _lansweeperState,
                    ticketId: task.lansweeperMainTicketId,
                    ticketViewUrlTemplate: ticketViewUrlTemplate,
                    inline: true,
                  ),
              ],
            ),
          ),
        if (hasSolution) _buildSolutionToggle(),
      ],
    );
  }

  /// «Από κλήση #344» — από πού γεννήθηκε η εκκρεμότητα.
  ///
  /// Δεν είναι κουμπί: ο δεσμός εξηγεί την προέλευση, δεν υπόσχεται πλοήγηση
  /// που δεν υπάρχει. Το ξέρει η φόρμα αποστολής και ο έλεγχος διπλού
  /// αιτήματος· ως τώρα ήταν το μόνο σημείο που δεν το έλεγε στον άνθρωπο.
  Widget _buildCallLinkChip(ThemeData theme) {
    final color = theme.colorScheme.onSurfaceVariant;
    // Ό,τι ξέρουμε, το λέμε. Ο αριθμός αιτήματος της κλήσης έρχεται μαζί με
    // την εκκρεμότητα, οπότε η υπόδειξη δεν έχει λόγο να υποθέτει «αν εκείνη
    // έχει αίτημα…» — ξέρει αν έχει, και ποιο.
    final callTicket = (task.linkedCallTicketId ?? '').trim();
    return CompactTooltip(
      message:
          'Η εκκρεμότητα γεννήθηκε από την κλήση #${task.callId}.\n'
          '${callTicket.isEmpty ? 'Η κλήση δεν έχει καταχωρηθεί ακόμα ως αίτημα στο Lansweeper.' : 'Η κλήση έχει καταχωρηθεί στο Lansweeper ως αίτημα '
                    '#$callTicket — η αποστολή θα σας ρωτήσει αν θέλετε νέο '
                    'ξεχωριστό αίτημα ή σημείωση σε εκείνο.'}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phone_in_talk_outlined, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              'από κλήση #${task.callId}',
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }

  /// Σήμα προτεραιότητας δίπλα στην κατάσταση: είναι ιδιότητα της εκκρεμότητας
  /// και όχι χρόνος, γι' αυτό δεν κάθεται κάτω από την ημερομηνία — εκεί
  /// έσπρωχνε την ημερομηνία εκτός ευθυγράμμισης με τα υπόλοιπα.
  Widget _buildPriorityBadge(ThemeData theme) {
    final priority = task.priority ?? 0;
    if (priority <= 0) return const SizedBox.shrink();

    final isCritical = priority > 1;
    final color = isCritical ? theme.colorScheme.error : Colors.orange.shade700;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          isCritical ? 'Κρίσιμη' : 'Υψηλή',
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme) {
    final label = status == TaskStatus.snoozed
        ? 'Αναβληθείσα'
        : status.displayLabelEl;

    return Tooltip(
      message: _statusTooltip(),
      // Πάνω από το chip: από κάτω σκέπαζε το κουμπί «Λύση».
      preferBelow: false,
      child: Chip(
        backgroundColor: _statusChipColor(status, theme.colorScheme),
        label: Text(label, style: theme.textTheme.labelSmall),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Ενέργειες',
      onSelected: (value) {
        switch (value) {
          case 'edit':
            callbacks.onEdit?.call();
            break;
          case 'assign':
            callbacks.onAssign?.call();
            break;
          case 'snooze':
            callbacks.onSnooze?.call();
            break;
          case 'lansweeper':
            callbacks.onSubmitToLansweeper?.call();
            break;
          case 'print':
            callbacks.onPrint?.call();
            break;
          case 'pdf':
            callbacks.onSaveAsPdf?.call();
            break;
          case 'delete':
            callbacks.onDelete?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Επεξεργασία')),
        // Ανάθεση και σε ολοκληρωμένη: το «ποιος το έλυσε/το χρεώνεται»
        // διορθώνεται και εκ των υστέρων.
        if (callbacks.onAssign != null)
          const PopupMenuItem(value: 'assign', child: Text('Ανάθεση')),
        // Σε ολοκληρωμένη, η αναβολή ζει μέσα στον διάλογο επεξεργασίας:
        // χρειάζεται πρώτα απόφαση για το αν η εκκρεμότητα ξανανοίγει, και με
        // ποια μορφή.
        if (!_isClosed)
          const PopupMenuItem(value: 'snooze', child: Text('Αναβολή')),
        // Και σε ολοκληρωμένη: η δουλειά μπορεί να έγινε, αλλά το helpdesk να
        // θέλει ακόμη το ίχνος της. Το κείμενο αλλάζει μόλις υπάρχει αίτημα,
        // ώστε να μη μοιάζει ότι θα ανοίξει δεύτερο.
        if (callbacks.onSubmitToLansweeper != null)
          PopupMenuItem<String>(
            value: 'lansweeper',
            child: Text(
              _hasTicket
                  ? 'Αίτημα Lansweeper #${task.lansweeperMainTicketId!.trim()}…'
                  : 'Αίτημα στο Lansweeper…',
            ),
          ),
        // Το φύλλο τυπώνεται σε όποια κατάσταση κι αν είναι η εκκρεμότητα:
        // μια ολοκληρωμένη τυπώνεται εξίσου, με τη λύση και τις αναβολές της.
        if (callbacks.onPrint != null)
          const PopupMenuItem(value: 'print', child: Text('Εκτύπωση…')),
        if (callbacks.onSaveAsPdf != null)
          const PopupMenuItem(value: 'pdf', child: Text('Αποθήκευση ως PDF…')),
        PopupMenuItem<String>(
          value: 'delete',
          enabled: deleteMenuEnabled,
          child: const Text('Διαγραφή'),
        ),
      ],
    );
  }

  Widget _buildSolutionToggle() {
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: onToggleSolution,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            showSolution
                ? 'Απόκρυψη λύσης'
                : (_isClosed ? 'Λύση' : 'Προηγούμενη λύση'),
          ),
          const SizedBox(width: 2),
          Icon(
            showSolution ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            size: 18,
          ),
        ],
      ),
    );
  }
}
