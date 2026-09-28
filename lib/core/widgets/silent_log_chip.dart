import 'package:flutter/material.dart';

import '../services/crash_log_service.dart';
import 'compact_tooltip.dart';

/// Διακριτική ένδειξη ότι το ημερολόγιο της εφαρμογής έχει σιγήσει.
///
/// **Γιατί χρειάζεται ένδειξη και όχι μήνυμα.** Ο φάκελος `logs` δεν κρατά
/// μόνο σφάλματα: είναι ο πίνακας ανακοινώσεων των σταθμών. Όταν δεν απαντά,
/// τίποτα δεν σταματά — απλώς κανένα σφάλμα δεν καταγράφεται, κανείς δεν
/// βλέπει ότι δουλεύεις, και ο φρουρός της αναβάθμισης δεν μπορεί να δει τους
/// άλλους. Μια στιγμιαία ειδοποίηση θα χανόταν· η κατάσταση διαρκεί, άρα και
/// η ένδειξη.
///
/// Εμφανίζεται **μόνο όσο κρατά η σιωπή**: μόλις το ημερολόγιο μετακομίσει σε
/// φάκελο που απαντά, εξαφανίζεται μόνη της.
class SilentLogChip extends StatelessWidget {
  const SilentLogChip({super.key, required this.extended, this.serviceForTest});

  final bool extended;

  /// Παράκαμψη της υπηρεσίας (μόνο για τεστ).
  @visibleForTesting
  final CrashLogService? serviceForTest;

  @override
  Widget build(BuildContext context) {
    final service = serviceForTest ?? CrashLogService.instanceOrNull;
    if (service == null || service.isDiskAvailable) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final color = theme.colorScheme.tertiary;
    final reason = service.diskUnavailableReason;

    return CompactTooltip(
      message:
          'Ο φάκελος καταγραφής δεν απαντά, οπότε για αυτή τη συνεδρία:\n'
          '• τα σφάλματα δεν καταγράφονται πουθενά\n'
          '• οι συνάδελφοι δεν βλέπουν ότι δουλεύεις\n'
          '• ο έλεγχος «ποιος άλλος έχει τη βάση» δεν λειτουργεί'
          '${reason == null || reason.isEmpty ? '' : '\n\nΑιτία: $reason'}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_toggle_off_rounded, size: 18, color: color),
            if (extended) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Χωρίς καταγραφή',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
