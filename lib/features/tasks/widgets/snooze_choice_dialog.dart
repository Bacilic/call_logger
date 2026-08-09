import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/widgets/compact_tooltip.dart';
import '../../../core/widgets/draggable_dialog_shell.dart';
import '../../../core/widgets/resizable_text_area.dart';
import '../../../core/widgets/spell_check_controller.dart';
import '../models/task_settings_config.dart';
import '../ui/task_due_option_tooltips.dart';
import '../ui/task_due_quick_chips.dart';

/// Αποτέλεσμα του διαλόγου αναβολής.
///
/// Το [due] είναι ακριβώς η στιγμή που εμφανίστηκε στο chip — εφαρμόζεται
/// αυτούσια, ώστε η αναβολή να μη διαφέρει από αυτό που είδε ο χρήστης. Για
/// την επιλογή [SnoozeChoiceDialog.customChoice] είναι `null`, γιατί ακολουθεί
/// επιλογέας ημερομηνίας.
typedef SnoozeChoiceResult = ({String choice, DateTime? due, String? note});

/// Διάλογος επιλογής αναβολής: λόγος, γρήγορες επιλογές με ορατή στιγμή λήξης,
/// προσαρμοσμένη ημερομηνία. Μετακινείται από τη λωρίδα του τίτλου.
///
/// Η επιλογή chip κλείνει τον διάλογο, γι' αυτό ο λόγος αναβολής βρίσκεται
/// **πάνω** από τα chips: όποιος διαβάζει με τη σειρά προλαβαίνει να τον γράψει.
class SnoozeChoiceDialog extends StatefulWidget {
  const SnoozeChoiceDialog({
    super.key,
    required this.config,
    required this.maxRangeText,
    required this.calculateDue,
    this.taskTitle,
    this.currentDue,
    this.initialNow,
  });

  /// Κωδικός για «Άλλη ημερομηνία…».
  static const String customChoice = 'custom';

  final TaskSettingsConfig config;

  /// Π.χ. «Μέγιστο εύρος: 365 ημέρες».
  final String maxRangeText;

  /// Υπολογισμός στιγμής λήξης — ο ίδιος που εφαρμόζει η αναβολή.
  final DateTime Function(String option, DateTime from) calculateDue;

  /// Τίτλος της εκκρεμότητας που αναβάλλεται (πλαίσιο για τον χρήστη).
  final String? taskTitle;

  /// Η λήξη που ισχύει τώρα, πριν την αναβολή.
  final DateTime? currentDue;

  /// Στιγμή αναφοράς των προεπισκοπήσεων. Κενή στην εφαρμογή — παίρνει την ώρα
  /// του συστήματος και ανανεώνεται όσο ο διάλογος μένει ανοιχτός.
  ///
  /// Οι δοκιμές τη δίνουν ρητά ώστε να ορίζουν **και τις δύο άκρες** του
  /// χρόνου: και τη στιγμή αναφοράς και τη στιγμή λήξης. Όταν δοθεί, το ρολόι
  /// **δεν** ξεκινά: τη στιγμή αναφοράς την κατέχει ο καλών, οπότε ο διάλογος
  /// δεν έχει δικαίωμα να την αλλάξει από κάτω του.
  final DateTime? initialNow;

  @override
  State<SnoozeChoiceDialog> createState() => _SnoozeChoiceDialogState();
}

class _SnoozeChoiceDialogState extends State<SnoozeChoiceDialog> {
  final _noteController = SpellCheckController();

  /// Στιγμή αναφοράς των προεπισκοπήσεων· ανανεώνεται ώστε οι ώρες στα chips
  /// να μη μπαγιατεύουν όσο ο διάλογος μένει ανοιχτός.
  late DateTime _now;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _now = widget.initialNow ?? DateTime.now();
    // Σταθερή στιγμή αναφοράς από τον καλούντα σημαίνει σταθερή: δεν μπορεί να
    // μπαγιατέψει, οπότε δεν χρειάζεται ρολόι που θα την ξαναέγραφε.
    if (widget.initialNow != null) return;
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _noteController.dispose();
    super.dispose();
  }

  String? get _trimmedNote {
    final trimmed = _noteController.text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _pop(String choice, DateTime? due) {
    Navigator.of(context).pop((choice: choice, due: due, note: _trimmedNote));
  }

  List<TaskDueQuickChoice> _buildChoices() {
    final config = widget.config;
    return [
      TaskDueQuickChoice(
        option: TaskSettingsConfig.kOneHour,
        label: '+1 ώρα',
        due: widget.calculateDue(TaskSettingsConfig.kOneHour, _now),
        message: TaskDueOptionTooltips.plusOneHour(),
      ),
      TaskDueQuickChoice(
        option: TaskSettingsConfig.kDayEnd,
        label: 'Μέσα στο ωράριο',
        due: widget.calculateDue(TaskSettingsConfig.kDayEnd, _now),
        message: TaskDueOptionTooltips.withinSchedule(
          config.nextBusinessHour,
          config.dayEndTime,
        ),
      ),
      TaskDueQuickChoice(
        option: TaskSettingsConfig.kNextBusiness,
        label: 'Επόμενη εργάσιμη',
        due: widget.calculateDue(TaskSettingsConfig.kNextBusiness, _now),
        message: TaskDueOptionTooltips.nextBusiness(config.nextBusinessHour),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableDialogShell(
      title: Row(
        children: [
          Icon(Icons.snooze, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          const Expanded(child: Text('Αναβολή')),
          Icon(
            Icons.open_with,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        // Το οριζόντιο περιθώριο περνά μέσα στο scrollable, ώστε η μπάρα
        // κύλησης να μένει στην άκρη του διαλόγου και όχι πάνω στα πεδία.
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
        content: SizedBox(
          width: 488,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildContextHeader(theme),
                ResizableTextArea(
                  controller: _noteController,
                  minLines: 2,
                  autoGrowMaxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Λόγος αναβολής (προαιρετικό)',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Νέα λήξη', style: theme.textTheme.titleSmall),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'ολοκληρώνει την αναβολή',
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TaskDueQuickChips(
                  choices: _buildChoices(),
                  now: _now,
                  onSelected: (choice) => _pop(choice.option, choice.due),
                ),
                const SizedBox(height: 6),
                _buildCustomDateButton(theme),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ακύρωση'),
          ),
        ],
      ),
    );
  }

  /// Ποια εκκρεμότητα αναβάλλεται και ποια λήξη ισχύει τώρα.
  Widget _buildContextHeader(ThemeData theme) {
    final title = widget.taskTitle;
    final current = widget.currentDue;
    if (title == null && current == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Text(
              title,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (current != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Τρέχουσα λήξη: ${formatTaskDuePreview(_now, current)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomDateButton(ThemeData theme) {
    return CompactTooltip(
      message:
          'Ανοίγει επιλογέα ημερομηνίας και ώρας, περιορισμένο στο μέγιστο '
          'εύρος αναβολής των ρυθμίσεων.',
      child: OutlinedButton(
        onPressed: () => _pop(SnoozeChoiceDialog.customChoice, null),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          visualDensity: VisualDensity.compact,
        ),
        child: Row(
          children: [
            const Icon(Icons.edit_calendar_outlined, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Άλλη ημερομηνία…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.maxRangeText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
