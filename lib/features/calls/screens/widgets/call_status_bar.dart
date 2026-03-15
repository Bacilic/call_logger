import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/settings_provider.dart';
import '../../provider/call_entry_provider.dart';

/// Μπάρα κατάστασης κλήσης: εκκρεμότητα (checkbox) και χρονόμετρο (MM:SS ή εικονίδιο) με Play/Pause και χειροκίνητη εισαγωγή.
class CallStatusBar extends ConsumerWidget {
  const CallStatusBar({super.key});

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static Color _durationColor(int seconds) {
    if (seconds < 60) return Colors.green;
    if (seconds <= 300) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(callEntryProvider);
    final notifier = ref.read(callEntryProvider.notifier);
    final showTimerAsync = ref.watch(showActiveTimerProvider);
    final durationSeconds = entry.durationSeconds;
    final isTimerRunning = notifier.isTimerRunning;
    final notesNonEmpty = entry.notes.trim().isNotEmpty;
    final showPlayPause = durationSeconds > 0 || isTimerRunning;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: entry.isPending,
              onChanged: notesNonEmpty ? (_) => notifier.togglePending() : null,
              tristate: false,
            ),
            const SizedBox(width: 4),
            Text(
              'Εκκρεμότητα',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: notesNonEmpty
                    ? null
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        showTimerAsync.when(
          data: (showActiveTimer) {
            Widget timerContent;
            if (showActiveTimer) {
              timerContent = Tooltip(
                message: 'Διπλό κλικ για προσαρμοσμένο χρόνο. Σταματήστε το χρονόμετρο',
                child: GestureDetector(
                  onDoubleTap: () {
                    if (!isTimerRunning && durationSeconds > 0) {
                      _showManualDurationDialog(context, ref);
                    }
                  },
                  child: Text(
                    _formatDuration(durationSeconds),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _durationColor(durationSeconds),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              );
            } else {
              timerContent = Tooltip(
                message: 'Διπλό κλικ για προσαρμοσμένο χρόνο. Σταματήστε το χρονόμετρο',
                child: GestureDetector(
                  onDoubleTap: () {
                    if (!isTimerRunning && durationSeconds > 0) {
                      _showManualDurationDialog(context, ref);
                    }
                  },
                  child: Icon(
                    Icons.timer_outlined,
                    size: 28,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                timerContent,
                if (showPlayPause) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      isTimerRunning ? Icons.pause : Icons.play_arrow,
                      size: 24,
                    ),
                    onPressed: () {
                      if (isTimerRunning) {
                        notifier.stopTimer();
                      } else {
                        notifier.startTimerOnce();
                      }
                    },
                    tooltip: isTimerRunning ? 'Παύση χρονομέτρου' : 'Συνέχιση χρονομέτρου',
                  ),
                ],
              ],
            );
          },
          loading: () => const SizedBox(
            width: 60,
            height: 32,
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          error: (e, s) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  static Future<void> _showManualDurationDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final notifier = ref.read(callEntryProvider.notifier);
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Χρόνος χειροκίνητα (λεπτά)'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Λεπτά',
              border: OutlineInputBorder(),
              hintText: 'π.χ. 5',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Ακύρωση'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                final minutes = int.tryParse(text);
                if (minutes != null && minutes >= 0) {
                  Navigator.of(ctx).pop(minutes);
                }
              },
              child: const Text('Εντάξει'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result != null && context.mounted) {
      notifier.setDurationManually(result * 60);
    }
  }
}
