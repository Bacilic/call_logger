import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/settings_provider.dart';
import '../../provider/call_entry_provider.dart';
import '../../provider/notes_field_hint_provider.dart';

/// Μπάρα κατάστασης κλήσης: εκκρεμότητα (checkbox) και χρονόμετρο (MM:SS ή εικονίδιο) με Play/Pause και χειροκίνητη εισαγωγή.
class CallStatusBar extends ConsumerWidget {
  const CallStatusBar({super.key, this.showPendingToggle = true});

  final bool showPendingToggle;

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
    final retainPlayPauseAfterManualZero = ref.watch(
      callEntryProvider.select((s) => s.retainPlayPauseAfterManualZero),
    );
    final notesNonEmpty = ref.watch(
      callEntryProvider.select((s) => s.notes.trim().isNotEmpty),
    );
    final notifier = ref.read(callEntryProvider.notifier);
    final showTimerAsync = ref.watch(showActiveTimerProvider);
    final showPlayPause =
        durationSeconds > 0 || isTimerRunning || retainPlayPauseAfterManualZero;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPendingToggle)
          _PendingCheckboxRow(
            isPending: isPending,
            notesNonEmpty: notesNonEmpty,
            onTogglePending: () => notifier.togglePending(),
            onDisabledTap: () => ref
                .read(notesFieldHintTickProvider.notifier)
                .requestHintFlash(),
          ),
        if (showPendingToggle) const SizedBox(height: 0),
        showTimerAsync.when(
          data: (showActiveTimer) {
            Widget timerContent;
            if (showActiveTimer) {
              timerContent = Tooltip(
                message:
                    'Διπλό κλικ για προσαρμοσμένο χρόνο. Σταματήστε το χρονόμετρο',
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
                message:
                    'Διπλό κλικ για προσαρμοσμένο χρόνο. Σταματήστε το χρονόμετρο',
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
                    tooltip: isTimerRunning
                        ? 'Παύση χρονομέτρου'
                        : 'Συνέχιση χρονομέτρου',
                  ),
                ),
              ],
            );
          },
          loading: () => const SizedBox(
            width: 60,
            height: 32,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, s) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// Μέγιστη χειροκίνητη διάρκεια: μία βάρδια (8 ώρες).
  static const int _maxManualDurationSeconds = 8 * 60 * 60;

  static const String _invalidDurationMessage =
      'Η τιμή δεν είναι έγκυρη. Διορθώστε ή πατήστε: Ακύρωση.';

  static const String _exceedsShiftMessage =
      'Δεν μπορείτε να ορίσετε διάρκεια μεγαλύτερη από μία βάρδια (8 ώρες).';

  /// Επιστρέφει λεπτά ως [double] ή null αν η μορφή δεν επιτρέπει ασφαλή ανάλυση.
  static double? _parseMinutesInput(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s.contains(',') && s.contains('.')) return null;
    final commaCount = ','.allMatches(s).length;
    final dotCount = '.'.allMatches(s).length;
    if (commaCount > 1 || dotCount > 1) return null;
    final normalized = s.replaceAll(',', '.');
    final value = double.tryParse(normalized);
    if (value == null || !value.isFinite || value < 0) return null;
    return value;
  }

  static Future<void> _showManualDurationDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController();
    final notifier = ref.read(callEntryProvider.notifier);
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final errorStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            );
            return AlertDialog(
              title: const Text('Προσαρμογή χρόνου (λεπτά)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Λεπτά',
                        border: OutlineInputBorder(),
                        hintText: 'π.χ. 5 ή 1,5',
                      ),
                      autofocus: true,
                      onChanged: (_) {
                        setDialogState(() => errorText = null);
                      },
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(errorText!, style: errorStyle),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Ακύρωση'),
                ),
                FilledButton(
                  onPressed: () async {
                    final minutes = _parseMinutesInput(controller.text);
                    if (minutes == null) {
                      setDialogState(() => errorText = _invalidDurationMessage);
                      return;
                    }
                    final seconds = (minutes * 60).round();
                    if (seconds > _maxManualDurationSeconds) {
                      setDialogState(() => errorText = _exceedsShiftMessage);
                      return;
                    }
                    if (seconds == 0) {
                      final confirmed = await showDialog<bool>(
                        context: ctx,
                        builder: (confirmCtx) => AlertDialog(
                          content: const Text(
                            'Η διάρκεια κλήσης θα μηδενιστεί. Συνέχεια;',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(confirmCtx).pop(false),
                              child: const Text('Όχι'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(confirmCtx).pop(true),
                              child: const Text('Ναι'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                    }
                    if (ctx.mounted) {
                      Navigator.of(ctx).pop(seconds);
                    }
                  },
                  child: const Text('Αλλαγή'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (result != null && context.mounted) {
      notifier.setDurationManually(
        result,
        retainPlayPauseAfterManualZero: result == 0,
      );
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
                  : Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.38),
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
