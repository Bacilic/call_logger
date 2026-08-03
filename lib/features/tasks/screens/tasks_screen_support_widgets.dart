import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

