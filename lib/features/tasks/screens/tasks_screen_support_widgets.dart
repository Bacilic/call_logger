part of 'tasks_screen.dart';

/// Αντίστροφη μέτρηση πριν την οριστική διαγραφή· «Αναίρεση» κλείνει το SnackBar.
class _TaskDeleteCountdownSnackContent extends StatefulWidget {
  const _TaskDeleteCountdownSnackContent({
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
  State<_TaskDeleteCountdownSnackContent> createState() =>
      _TaskDeleteCountdownSnackContentState();
}

class _TaskDeleteCountdownSnackContentState
    extends State<_TaskDeleteCountdownSnackContent> {
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

class _OrphanCallsBanner extends ConsumerWidget {
  const _OrphanCallsBanner({required this.onCreateTasks});

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

class _SnoozeChoiceDialog extends StatefulWidget {
  const _SnoozeChoiceDialog({
    required this.config,
    required this.maxRangeText,
  });

  final TaskSettingsConfig config;
  final String maxRangeText;

  @override
  State<_SnoozeChoiceDialog> createState() => _SnoozeChoiceDialogState();
}

class _SnoozeChoiceDialogState extends State<_SnoozeChoiceDialog> {
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String? get _trimmedNote {
    final trimmed = _noteController.text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _pop(String choice) {
    Navigator.of(context).pop((choice: choice, note: _trimmedNote));
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final maxRangeText = widget.maxRangeText;

    return AlertDialog(
      title: const Text('Αναβολή'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Γρήγορη επιλογή',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Tooltip(
              message: TaskDueOptionTooltips.plusOneHour(),
              child: FilledButton.tonal(
                onPressed: () => _pop(TaskSettingsConfig.kOneHour),
                child: const Text('+1 ώρα'),
              ),
            ),
            const SizedBox(height: 8),
            Tooltip(
              message: TaskDueOptionTooltips.withinSchedule(
                config.nextBusinessHour,
                config.dayEndTime,
              ),
              child: FilledButton.tonal(
                onPressed: () => _pop(TaskSettingsConfig.kDayEnd),
                child: const Text('Μέσα στο ωράριο'),
              ),
            ),
            const SizedBox(height: 8),
            Tooltip(
              message: TaskDueOptionTooltips.nextBusiness(
                config.nextBusinessHour,
              ),
              child: FilledButton.tonal(
                onPressed: () => _pop(TaskSettingsConfig.kNextBusiness),
                child: const Text('Επόμενη εργάσιμη'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    maxRangeText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _pop('custom'),
                  icon: const Icon(Icons.edit_calendar_outlined, size: 20),
                  label: const Text('Άλλη ημερομηνία…'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Ο επιλογέας ημερομηνίας περιορίζεται στο παραπάνω εύρος.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Λόγος αναβολής (προαιρετικό)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
      ],
    );
  }
}
