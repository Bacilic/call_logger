import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/lansweeper_submit_progress.dart';
import '../../providers/lansweeper_submit_progress_provider.dart';

/// Το ζωντανό χρονόμετρο της αποστολής, σε ένα widget που ξαναχτίζεται **μόνο
/// του**.
///
/// Ο λόγος είναι πρακτικός: η αναφορά κουβαλά ολόκληρη τη λίστα των κλήσεων,
/// και ένα ξαναχτίσιμο είκοσι φορές το δευτερόλεπτο θα ξανασχεδίαζε κι εκείνη.
/// Εδώ κινείται μόνο ο αριθμός.
///
/// Ο χρόνος **δεν μετριέται εδώ** — διαβάζεται από το ρολόι της πορείας. Το
/// χρονόμετρο απλώς λέει στην οθόνη «κοίτα ξανά».
class LansweeperSubmitElapsed extends ConsumerStatefulWidget {
  const LansweeperSubmitElapsed({required this.builder, super.key});

  final Widget Function(BuildContext context, int elapsedMilliseconds) builder;

  @override
  ConsumerState<LansweeperSubmitElapsed> createState() =>
      _LansweeperSubmitElapsedState();
}

class _LansweeperSubmitElapsedState
    extends ConsumerState<LansweeperSubmitElapsed> {
  Timer? _ticker;

  void _syncTicker({required bool running}) {
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = ref.watch(
      lansweeperSubmitProgressProvider.select((p) => p.isRunning),
    );
    _syncTicker(running: running);
    final elapsed = ref
        .read(lansweeperSubmitProgressProvider.notifier)
        .elapsedMilliseconds;
    return widget.builder(context, elapsed);
  }
}

/// Ο χρόνος ως κείμενο σταθερού πλάτους.
///
/// Σταθερό πλάτος και ψηφία ίδιου βήματος (tabular) επειδή ο αριθμός αλλάζει
/// είκοσι φορές το δευτερόλεπτο: χωρίς αυτά, το κουμπί δίπλα του θα χοροπηδούσε
/// σε κάθε χιλιοστό.
class LansweeperElapsedText extends StatelessWidget {
  const LansweeperElapsedText({
    required this.milliseconds,
    this.color,
    this.style,
    super.key,
  });

  final int milliseconds;
  final Color? color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium;
    return SizedBox(
      width: 82,
      child: Text(
        formatLansweeperElapsed(milliseconds),
        textAlign: TextAlign.right,
        maxLines: 1,
        style: base?.copyWith(
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Η μία γραμμή που λέει τι κάνει η αποστολή τώρα — ή τι έκανε μόλις.
///
/// Είναι μόνιμη, δεν εμφανίζεται και εξαφανίζεται: η θέση της είναι δεσμευμένη
/// ώστε τα κουμπιά από κάτω να μη μετακινούνται τη στιγμή που ο χρήστης πάει
/// να τα πατήσει.
class LansweeperSubmitStatusBar extends ConsumerWidget {
  const LansweeperSubmitStatusBar({this.selectedCallId, super.key});

  /// Ποια κλήση βλέπει αυτή τη στιγμή ο χρήστης.
  ///
  /// Το αποτέλεσμα μιας αποστολής **δεν** εμφανίζεται πάνω σε άλλη κλήση: θα
  /// έδειχνε καταχωρημένη μια κλήση που δεν στάλθηκε ποτέ. Η αποστολή που
  /// τρέχει τώρα φαίνεται πάντα — εκεί η πληροφορία «κάτι δουλεύει» μετράει
  /// περισσότερο από το ποιανού είναι.
  final int? selectedCallId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracked = ref.watch(lansweeperSubmitProgressProvider);
    final progress = tracked.isRunning || tracked.concernsCall(selectedCallId)
        ? tracked
        : LansweeperSubmitProgress.idle;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (
      Color accent,
      IconData? icon,
      String text,
    ) = switch (progress.outcome) {
      LansweeperSubmitOutcome.idle => (
        theme.textTheme.bodySmall?.color ?? scheme.outline,
        Icons.cloud_queue_rounded,
        'Έτοιμη για αποστολή',
      ),
      LansweeperSubmitOutcome.running => (
        scheme.primary,
        null,
        _runningText(progress),
      ),
      LansweeperSubmitOutcome.success => (
        Colors.green.shade700,
        Icons.check_circle_outline_rounded,
        progress.summary ?? 'Καταχωρήθηκε',
      ),
      LansweeperSubmitOutcome.failure => (
        scheme.error,
        Icons.error_outline_rounded,
        progress.summary ?? 'Η αποστολή απέτυχε',
      ),
    };

    final showElapsed = !progress.isIdle;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          if (icon != null)
            Icon(icon, size: 18, color: accent)
          else
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: accent),
            ),
          ),
          if (showElapsed) ...[
            const SizedBox(width: 8),
            LansweeperSubmitElapsed(
              builder: (context, elapsed) => LansweeperElapsedText(
                milliseconds: elapsed,
                color: accent,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _runningText(LansweeperSubmitProgress progress) {
    final step = progress.currentStep;
    final label = step?.label ?? 'Αποστολή';
    if (progress.totalSteps <= 1 || progress.currentStepNumber == 0) {
      return '$label…';
    }
    return '$label… · βήμα ${progress.currentStepNumber} από '
        '${progress.totalSteps}';
  }
}

/// Η αναλυτική πορεία: ποια βήματα τελείωσαν, πόσο κράτησαν, πού είμαστε τώρα.
///
/// Ζει στον χώρο που κρατούσε το ιστορικό των αιτημάτων — εκεί που υπήρχε
/// άφθονο ύψος και σχεδόν ποτέ περιεχόμενο. Όταν δεν έχει τρέξει καμία
/// αποστολή, δεν εμφανίζεται καθόλου.
class LansweeperSubmitStepsPanel extends ConsumerWidget {
  const LansweeperSubmitStepsPanel({this.selectedCallId, super.key});

  /// Ίδιος κανόνας με τη ζώνη κατάστασης: η πορεία μιας αποστολής δεν
  /// κρέμεται πάνω από άλλη κλήση.
  final int? selectedCallId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(lansweeperSubmitProgressProvider);
    if (progress.isIdle || progress.steps.isEmpty) {
      return const SizedBox.shrink();
    }
    if (!progress.isRunning && !progress.concernsCall(selectedCallId)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);

    return Card(
      child: ExpansionTile(
        key: const ValueKey('lansweeper_submit_steps_panel'),
        // Ανοιχτή όσο τρέχει, κλειστή μόλις τελειώσει: η λεπτομέρεια χρειάζεται
        // όσο περιμένεις, όχι αφού μάθεις το αποτέλεσμα.
        initiallyExpanded: progress.isRunning,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        dense: true,
        title: Text('Πορεία αποστολής', style: theme.textTheme.titleSmall),
        subtitle: progress.totalMilliseconds == null
            ? null
            : Text(
                'Συνολικά '
                '${formatLansweeperElapsed(progress.totalMilliseconds!)}',
                style: theme.textTheme.bodySmall,
              ),
        children: [
          for (final step in progress.steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  _stepIcon(context, step.status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      step.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: step.status == LansweeperSubmitStepStatus.pending
                            ? theme.disabledColor
                            : null,
                      ),
                    ),
                  ),
                  if (step.elapsedMilliseconds != null)
                    Text(
                      formatLansweeperElapsed(step.elapsedMilliseconds!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _stepIcon(BuildContext context, LansweeperSubmitStepStatus status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      LansweeperSubmitStepStatus.done => Icon(
        Icons.check_rounded,
        size: 16,
        color: Colors.green.shade700,
      ),
      LansweeperSubmitStepStatus.failed => Icon(
        Icons.close_rounded,
        size: 16,
        color: scheme.error,
      ),
      LansweeperSubmitStepStatus.running => SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
      ),
      LansweeperSubmitStepStatus.pending => Icon(
        Icons.circle_outlined,
        size: 16,
        color: Theme.of(context).disabledColor,
      ),
    };
  }
}
