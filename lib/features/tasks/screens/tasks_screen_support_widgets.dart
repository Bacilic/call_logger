import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/owner_filter.dart';
import '../providers/task_owner_filter_provider.dart';
import '../providers/tasks_provider.dart';

/// Αντίστροφη μέτρηση πριν την οριστική διαγραφή· «Αναίρεση» κλείνει το SnackBar.
class TaskDeleteCountdownSnackContent extends StatefulWidget {
  const TaskDeleteCountdownSnackContent({
    super.key,
    required this.taskTitle,
    required this.onUndo,
    required this.onExpired,
    this.onAbortedExternally,
  });

  final String taskTitle;
  final VoidCallback onUndo;
  final Future<void> Function() onExpired;

  /// Όταν το SnackBar αφαιρεθεί χωρίς αναίρεση/λήξη (π.χ. αλλαγή οθόνης).
  final VoidCallback? onAbortedExternally;

  @override
  State<TaskDeleteCountdownSnackContent> createState() =>
      _TaskDeleteCountdownSnackContentState();
}

class _TaskDeleteCountdownSnackContentState
    extends State<TaskDeleteCountdownSnackContent> {
  static const int _initialSeconds = 5;
  int _remaining = _initialSeconds;
  Timer? _timer;
  bool _undone = false;
  bool _expireCallbackStarted = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _undone) return;
      if (_remaining <= 1) {
        _timer?.cancel();
        _timer = null;
        _expireCallbackStarted = true;
        widget.onExpired();
        return;
      }
      setState(() => _remaining--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!_undone && !_expireCallbackStarted) {
      widget.onAbortedExternally?.call();
    }
    super.dispose();
  }

  void _undo() {
    if (_undone) return;
    _undone = true;
    _timer?.cancel();
    widget.onUndo();
  }

  @override
  Widget build(BuildContext context) {
    const undoLinkBlue = Color(0xFF039BE5);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            'Η εκκρεμότητα: ${widget.taskTitle} θα διαγραφεί σε: $_remaining δευτ.',
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ) ??
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.35,
                ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: _undo,
          style: TextButton.styleFrom(
            foregroundColor: undoLinkBlue,
            padding: const EdgeInsets.only(left: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Αναίρεση'),
        ),
      ],
    );
  }
}

/// Λωρίδα «κλήσεις χωρίς εκκρεμότητα» με κουμπί μαζικής δημιουργίας.
class OrphanCallsBanner extends ConsumerWidget {
  const OrphanCallsBanner({super.key, required this.onCreateTasks});

  final VoidCallback onCreateTasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncOrphans = ref.watch(orphanCallsProvider);
    final count = asyncOrphans.when(
      data: (orphans) => orphans.length,
      loading: () => 0,
      error: (_, _) => 0,
    );
    if (count == 0) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.6),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 20,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Υπάρχουν $count κλήσεις χωρίς εκκρεμότητα.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              FilledButton.tonal(
                onPressed: onCreateTasks,
                child: const Text('Δημιουργία εκκρεμοτήτων'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Η άδεια οθόνη των Εκκρεμοτήτων, με τα λόγια που ταιριάζουν στην αιτία.
///
/// Τρεις διαφορετικές καταστάσεις μοιάζουν ίδιες όταν η λίστα είναι άδεια:
/// δεν υπάρχει τίποτα, δεν ταιριάζει τίποτα, ή **υπάρχουν αλλά τις κρύβει το
/// φίλτρο χρήστη**. Η τρίτη είναι η επικίνδυνη: ο μετρητής της πλοήγησης
/// εξακολουθεί να λέει «1» και ο χρήστης βλέπει άδεια οθόνη — αντιφατικό
/// μήνυμα που μοιάζει με σφάλμα της εφαρμογής.
///
/// Ο μετρητής **δεν** ακολουθεί το φίλτρο, σκόπιμα: είναι ειδοποίηση και όχι
/// μετρητής λίστας, και ένα φίλτρο προβολής δεν επιτρέπεται να κρύψει δουλειά
/// που υπάρχει. Η αντίφαση λύνεται εδώ, εξηγώντας — όχι εκεί, σωπαίνοντας.
class TasksEmptyState extends ConsumerWidget {
  const TasksEmptyState({super.key, required this.totalTaskCount});

  /// Πόσες εκκρεμότητες υπάρχουν συνολικά, χωρίς κανένα φίλτρο.
  final int totalTaskCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hidden = ref.watch(tasksHiddenByOwnerFilterProvider).value ?? 0;
    final owner =
        ref.watch(taskOwnerFilterProvider).value ?? OwnerFilter.everyone;

    if (totalTaskCount == 0) {
      return _message(
        theme,
        icon: Icons.task_alt_outlined,
        title: 'Δεν υπάρχουν εκκρεμότητες αυτή τη στιγμή',
      );
    }

    if (hidden == 0 || owner.isEveryone) {
      return _message(
        theme,
        icon: Icons.search_off_outlined,
        title: 'Δεν βρέθηκαν εκκρεμότητες με τα επιλεγμένα κριτήρια',
      );
    }

    var ownerLabel = '';
    for (final option
        in ref.watch(taskOwnerOptionsProvider).value ?? const []) {
      if (option.value == owner) {
        ownerLabel = option.label;
        break;
      }
    }

    return _message(
      theme,
      icon: Icons.person_search_outlined,
      title: ownerLabel.isEmpty
          ? 'Καμία εκκρεμότητα για την επιλογή σας'
          : 'Καμία εκκρεμότητα για «$ownerLabel»',
      subtitle: hidden == 1
          ? 'Υπάρχει 1 ακόμη με άλλον χρήστη.'
          : 'Υπάρχουν $hidden ακόμη με άλλον χρήστη.',
      action: FilledButton.tonalIcon(
        onPressed: () => ref
            .read(taskOwnerFilterProvider.notifier)
            .select(OwnerFilter.everyone),
        icon: const Icon(Icons.groups_outlined),
        label: const Text('Δείξε όλες'),
      ),
    );
  }

  Widget _message(
    ThemeData theme, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.bodyLarge),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 20), action],
        ],
      ),
    );
  }
}
