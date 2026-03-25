import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/settings_provider.dart';
import '../../provider/call_entry_provider.dart';
import '../../provider/notes_field_hint_provider.dart';

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
    final isPending = ref.watch(callEntryProvider.select((s) => s.isPending));
    final durationSeconds = ref.watch(
      callEntryProvider.select((s) => s.durationSeconds),
    );
    final isTimerRunning = ref.watch(
      callEntryProvider.select((s) => s.isCallTimerRunning),
    );
    final notesNonEmpty = ref.watch(
      callEntryProvider.select((s) => s.notes.trim().isNotEmpty),
    );
    final notifier = ref.read(callEntryProvider.notifier);
    final showTimerAsync = ref.watch(showActiveTimerProvider);
    final showPlayPause = durationSeconds > 0 || isTimerRunning;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PendingCheckboxRow(
          isPending: isPending,
          notesNonEmpty: notesNonEmpty,
          onTogglePending: () => notifier.togglePending(),
          onDisabledTap: () => ref
              .read(notesFieldHintTickProvider.notifier)
              .requestHintFlash(),
        ),
        const SizedBox(height: 0),
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                timerContent,
                const SizedBox(width: 8),
                // Δεσμεύει χώρο ώστε να μη μετακινείται η διάταξη όταν εμφανίζεται το Play/Pause.
                Visibility(
                  visible: showPlayPause,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: IconButton(
                    icon: Icon(
                      isTimerRunning ? Icons.pause : Icons.play_arrow,
                      size: 24,
                    ),
                    onPressed: () {
                      final n = ref.read(callEntryProvider.notifier);
                      if (n.isTimerRunning) {
                        n.stopTimer();
                      } else {
                        n.startTimerOnce();
                      }
                    },
                    tooltip: isTimerRunning ? 'Παύση χρονομέτρου' : 'Συνέχιση χρονομέτρου',
                  ),
                ),
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

class _PendingCheckboxRow extends StatelessWidget {
  const _PendingCheckboxRow({
    required this.isPending,
    required this.notesNonEmpty,
    required this.onTogglePending,
    required this.onDisabledTap,
  });

  final bool isPending;
  final bool notesNonEmpty;
  final VoidCallback onTogglePending;
  final VoidCallback onDisabledTap;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Checkbox(
          value: isPending,
          onChanged: notesNonEmpty ? (_) => onTogglePending() : null,
          tristate: false,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            'Εκκρεμότητα',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: notesNonEmpty
                      ? null
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.38),
                ),
            softWrap: true,
          ),
        ),
      ],
    );
    if (notesNonEmpty) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onDisabledTap,
        child: row,
      ),
    );
  }
}
