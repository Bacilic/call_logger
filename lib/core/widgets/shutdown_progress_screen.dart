import 'dart:async';
// ignore: unnecessary_import
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../services/shutdown_coordinator.dart';

/// Πλήρους οθόνης πρόοδος κλεισίματος — χωρίς κουμπιά.
class ShutdownProgressScreen extends StatefulWidget {
  const ShutdownProgressScreen({
    super.key,
    required this.events,
    this.stepLabels = ShutdownCoordinator.stepLabels,
    this.now,
  });

  final Stream<ShutdownStepEvent> events;
  final List<String> stepLabels;
  final DateTime Function()? now;

  @override
  State<ShutdownProgressScreen> createState() => _ShutdownProgressScreenState();
}

class _ShutdownProgressScreenState extends State<ShutdownProgressScreen> {
  late final List<_StepUiState> _steps;
  StreamSubscription<ShutdownStepEvent>? _subscription;
  Timer? _ticker;
  int? _runningIndex;
  DateTime? _runningStartedAt;

  @override
  void initState() {
    super.initState();
    _steps = [
      for (final label in widget.stepLabels) _StepUiState(label: label),
    ];
    _subscription = widget.events.listen(_onEvent);
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_runningIndex != null && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  void _onEvent(ShutdownStepEvent event) {
    if (!mounted) return;
    if (event.stepIndex < 0 || event.stepIndex >= _steps.length) return;

    setState(() {
      final step = _steps[event.stepIndex];
      if (event.phase == ShutdownStepPhase.started) {
        step.status = _StepStatus.running;
        _runningIndex = event.stepIndex;
        _runningStartedAt = (widget.now ?? DateTime.now)();
        step.elapsedMs = 0;
      } else if (event.phase == ShutdownStepPhase.completed) {
        step.status = _StepStatus.completed;
        step.elapsedMs = event.durationMs ?? step.elapsedMs;
        if (_runningIndex == event.stepIndex) {
          _runningIndex = null;
          _runningStartedAt = null;
        }
      } else if (event.phase == ShutdownStepPhase.failed) {
        step.status = _StepStatus.failed;
        step.elapsedMs = event.durationMs ?? step.elapsedMs;
        if (_runningIndex == event.stepIndex) {
          _runningIndex = null;
          _runningStartedAt = null;
        }
      } else if (event.phase == ShutdownStepPhase.interrupted) {
        step.status = _StepStatus.interrupted;
        if (_runningIndex == event.stepIndex) {
          _runningIndex = null;
          _runningStartedAt = null;
        }
      }
    });
  }

  int _liveElapsedMs(int index) {
    final step = _steps[index];
    if (step.status != _StepStatus.running ||
        _runningIndex != index ||
        _runningStartedAt == null) {
      return step.elapsedMs ?? 0;
    }
    final now = (widget.now ?? DateTime.now)();
    return now.difference(_runningStartedAt!).inMilliseconds.clamp(0, 1 << 30);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Κλείσιμο εφαρμογής',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ολοκληρώνονται τα βήματα τερματισμού…',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: _steps.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final step = _steps[index];
                    final elapsedMs = _liveElapsedMs(index);
                    return _ShutdownStepTile(
                      label: step.label,
                      status: step.status,
                      elapsedMs: elapsedMs,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _StepStatus { pending, running, completed, failed, interrupted }

class _StepUiState {
  _StepUiState({required this.label});

  final String label;
  _StepStatus status = _StepStatus.pending;
  int? elapsedMs;
}

class _ShutdownStepTile extends StatelessWidget {
  const _ShutdownStepTile({
    required this.label,
    required this.status,
    required this.elapsedMs,
  });

  final String label;
  final _StepStatus status;
  final int elapsedMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, trailing) = switch (status) {
      _StepStatus.pending => (
          Icons.circle_outlined,
          theme.colorScheme.outline,
          null,
        ),
      _StepStatus.running => (
          Icons.hourglass_top,
          theme.colorScheme.primary,
          Text(
            _formatElapsed(elapsedMs),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      _StepStatus.completed => (
          Icons.check_circle,
          theme.colorScheme.primary,
          elapsedMs > 0
              ? Text(
                  _formatElapsed(elapsedMs),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : null,
        ),
      _StepStatus.failed || _StepStatus.interrupted => (
          Icons.cancel,
          theme.colorScheme.error,
          Text(
            'διακόπηκε',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: status == _StepStatus.running
              ? FontWeight.w600
              : FontWeight.w400,
        ),
      ),
      trailing: trailing,
    );
  }

  static String _formatElapsed(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final frac = ((ms % 1000) / 100).floor();
    if (minutes > 0) {
      return '$minutes:${seconds.toString().padLeft(2, '0')}.${frac}s';
    }
    return '$seconds.${frac}s';
  }
}

/// Προγραμματίζει εμφάνιση οθόνης προόδου μόνο αν το κλείσιμο αργεί.
///
/// Επιστρέφει το [Timer]· ακυρώστε το όταν το κλείσιμο ολοκληρωθεί νωρίτερα.
Timer scheduleShutdownProgressReveal({
  Duration delay = ShutdownCoordinator.progressRevealDelay,
  required void Function() onReveal,
  required bool Function() isShutdownStillRunning,
}) {
  return Timer(delay, () {
    if (isShutdownStillRunning()) {
      onReveal();
    }
  });
}
