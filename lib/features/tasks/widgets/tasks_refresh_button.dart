import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/compact_tooltip.dart';
import '../providers/tasks_provider.dart';
import '../services/tasks_freshness_label.dart';

/// Χειροκίνητη ανανέωση των εκκρεμοτήτων, με την ηλικία των στοιχείων.
///
/// Υπάρχει ακόμη κι όταν ο αυτόματος φρουρός δουλεύει, για δύο λόγους: ο
/// φρουρός στηρίζεται σε μετρητή του SQLite που **δεν έχει δοκιμαστεί πάνω από
/// δικτυακό φάκελο**, και ο χρήστης πρέπει να μπορεί να ρωτήσει «τώρα» χωρίς να
/// περιμένει κύκλο.
class TasksRefreshButton extends ConsumerStatefulWidget {
  const TasksRefreshButton({super.key});

  @override
  ConsumerState<TasksRefreshButton> createState() => _TasksRefreshButtonState();
}

class _TasksRefreshButtonState extends ConsumerState<TasksRefreshButton> {
  bool _busy = false;

  /// Ξαναδιαβάζει τη λίστα. Το ίδιο ρολόι που σφραγίζει τη φρεσκάδα ζει μέσα
  /// στον notifier — εδώ δεν υπολογίζεται τίποτα, μόνο ζητείται.
  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(tasksProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastRead = ref.watch(tasksFreshnessProvider);
    final freshness = tasksFreshnessLabel(lastRead: lastRead);

    return CompactTooltip(
      waitDuration: const Duration(milliseconds: 400),
      showDuration: const Duration(seconds: 4),
      message:
          'Ανανέωση από τη βάση\n'
          '$freshness\n\n'
          'Σε κοινόχρηστη βάση οι αλλαγές των συναδέλφων έρχονται μόνες τους· '
          'πατήστε εδώ αν θέλετε να ρωτήσετε τώρα.',
      child: IconButton(
        onPressed: _busy ? null : () => unawaited(_refresh()),
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh, size: 20),
      ),
    );
  }
}
