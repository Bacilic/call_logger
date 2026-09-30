import '../../../core/widgets/compact_tooltip.dart';
import '../../../core/widgets/dialog_snackbar_scope.dart';
import '../../../core/widgets/draggable_dialog_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import '../models/task_personal_settings.dart';
import '../models/task_settings_config.dart';
import '../providers/task_settings_config_provider.dart';
import '../ui/task_due_option_tooltips.dart';

/// Διάλογος ρυθμίσεων εκκρεμοτήτων, σε δύο φανερές ομάδες: **κοινές για
/// όλους** (`app_settings`) και **δικές μου** (προσωπικές του χρήστη).
///
/// Και οι δύο ομάδες ζουν σε πρόχειρο και γράφονται **μόνο** στο
/// «Αποθήκευση»· η «Ακύρωση» δεν αφήνει καμία αλλαγή πίσω της.
class TaskSettingsDialog extends ConsumerStatefulWidget {
  const TaskSettingsDialog({super.key});

  @override
  ConsumerState<TaskSettingsDialog> createState() => _TaskSettingsDialogState();
}

class _TaskSettingsDialogState extends ConsumerState<TaskSettingsDialog>
    with DialogSnackbarHost {
  final _formKey = GlobalKey<FormState>();
  final SettingsService _settings = SettingsService();
  late final TextEditingController _maxDaysController;
  TaskSettingsConfig? _draft;
  TaskSettingsConfig? _initial;
  TaskPersonalSettings? _personal;
  TaskPersonalSettings? _personalInitial;
  bool _loading = true;

  static const String _msgInvalidDaysFormat =
      'Μη έγκυρη τιμή· μόνο αριθμός από 1 έως 365';
  static const String _msgInvalidDaysRange =
      'Λάθος εύρος. Παρακαλώ εισάγετε από 1 έως 365';

  @override
  void initState() {
    super.initState();
    _maxDaysController = TextEditingController();
    _maxDaysController.addListener(_onMaxDaysTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final personal = await _loadPersonal();
      try {
        final c = await ref.read(taskSettingsConfigProvider.future);
        if (!mounted) return;
        setState(() {
          _draft = c;
          _initial = c;
          _personal = personal;
          _personalInitial = personal;
          _maxDaysController.text = c.maxSnoozeDays.toString();
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        final fallback = TaskSettingsConfig.defaultConfig();
        setState(() {
          _draft = fallback;
          _initial = fallback;
          _personal = personal;
          _personalInitial = personal;
          _maxDaysController.text = fallback.maxSnoozeDays.toString();
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _maxDaysController.dispose();
    super.dispose();
  }

  Future<TaskPersonalSettings> _loadPersonal() async {
    final ui = _settings.windowUi;
    return TaskPersonalSettings(
      notifyHandovers: await ui.getNotifyTaskHandovers(),
      showBadge: await ui.getShowTasksBadge(),
      printPreview: await ui.getTaskPrintPreview(),
    );
  }

  /// Γράφει μόνο τους προσωπικούς διακόπτες που άλλαξαν, και ενημερώνει όσα
  /// σημεία της εφαρμογής τους δείχνουν.
  Future<void> _savePersonal(
    TaskPersonalSettings from,
    TaskPersonalSettings to,
  ) async {
    final ui = _settings.windowUi;
    if (to.notifyHandovers != from.notifyHandovers) {
      await ui.setNotifyTaskHandovers(to.notifyHandovers);
      ref.invalidate(notifyTaskHandoversProvider);
    }
    if (to.showBadge != from.showBadge) {
      await ui.setShowTasksBadge(to.showBadge);
      ref.invalidate(showTasksBadgeProvider);
    }
    if (to.printPreview != from.printPreview) {
      await ui.setTaskPrintPreview(to.printPreview);
      ref.invalidate(taskPrintPreviewProvider);
    }
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _optionLabel(String option) {
    switch (option) {
      case TaskSettingsConfig.kOneHour:
        return '+1 ώρα';
      case TaskSettingsConfig.kDayEnd:
        return 'Μέσα στο ωράριο';
      case TaskSettingsConfig.kNextBusiness:
        return 'Επόμενη εργάσιμη';
      default:
        return option;
    }
  }

  int? _parseMaxDays(String value) => int.tryParse(value.trim());

  void _onMaxDaysTextChanged() {
    if (!mounted) return;
    setState(() {});
    _formKey.currentState?.validate();
  }

  String? _validateMaxDaysInput(String? value) {
    final t = value?.trim() ?? '';
    if (t.isEmpty) return _msgInvalidDaysFormat;
    final n = int.tryParse(t);
    if (n == null) return _msgInvalidDaysFormat;
    if (n < 1 || n > 365) return _msgInvalidDaysRange;
    return null;
  }

  List<String> _buildChanges() {
    final personal = _personal;
    final personalInitial = _personalInitial;
    return [
      ..._buildSharedChanges(),
      if (personal != null && personalInitial != null)
        ...personal.changesFrom(personalInitial),
    ];
  }

  /// Αλλαγές στις **κοινές** ρυθμίσεις — αυτές που βλέπουν όλοι.
  List<String> _buildSharedChanges() {
    final initial = _initial;
    final draft = _draft;
    if (initial == null || draft == null) return const [];

    final changes = <String>[];
    if (draft.dayEndTime != initial.dayEndTime) {
      changes.add(
        'Ώρα τελευταίας εκκρεμότητας: ${_formatTime(initial.dayEndTime)} -> ${_formatTime(draft.dayEndTime)}',
      );
    }
    if (draft.nextBusinessHour != initial.nextBusinessHour) {
      changes.add(
        'Ώρα έναρξης επόμενης εργάσιμης: ${_formatTime(initial.nextBusinessHour)} -> ${_formatTime(draft.nextBusinessHour)}',
      );
    }
    if (draft.skipWeekends != initial.skipWeekends) {
      changes.add(
        'Παράλειψη Σαββατοκύριακων: ${initial.skipWeekends ? 'Ναι' : 'Όχι'} -> ${draft.skipWeekends ? 'Ναι' : 'Όχι'}',
      );
    }
    if (draft.defaultSnoozeOption != initial.defaultSnoozeOption) {
      changes.add(
        'Προεπιλεγμένη αναβολή: ${_optionLabel(initial.defaultSnoozeOption)} -> ${_optionLabel(draft.defaultSnoozeOption)}',
      );
    }

    final rawDays = _maxDaysController.text;
    final parsedDays = _parseMaxDays(rawDays);
    final initialDays = initial.maxSnoozeDays;
    if (parsedDays == null || parsedDays < 1 || parsedDays > 365) {
      if (rawDays.trim() != initialDays.toString()) {
        changes.add(
          'Μέγιστο εύρος αναβολής (ημέρες): $initialDays -> ${rawDays.trim().isEmpty ? '(κενό)' : rawDays.trim()}',
        );
      }
    } else if (parsedDays != initialDays) {
      changes.add(
        'Μέγιστο εύρος αναβολής (ημέρες): $initialDays -> $parsedDays',
      );
    }

    if (draft.autoCloseQuickAdds != initial.autoCloseQuickAdds) {
      changes.add(
        'Αυτόματο κλείσιμο Γρήγορων Προσθηκών: ${initial.autoCloseQuickAdds ? 'Ναι' : 'Όχι'} -> ${draft.autoCloseQuickAdds ? 'Ναι' : 'Όχι'}',
      );
    }

    return changes;
  }

  bool get _hasChanges => _buildChanges().isNotEmpty;
  bool get _isDaysValid =>
      _validateMaxDaysInput(_maxDaysController.text) == null;

  Future<bool> _confirmDiscardIfNeeded() async {
    final changes = _buildChanges();
    if (changes.isEmpty) return true;

    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => DraggableDialogShell(
        title: const Text('Μη αποθηκευμένες αλλαγές'),
        builder: (titleHandle) => AlertDialog(
          title: titleHandle,
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Θα χαθούν οι ακόλουθες αλλαγές:'),
                  const SizedBox(height: 8),
                  for (final item in changes) Text('• $item'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Επιστροφή'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Απόρριψη αλλαγών'),
            ),
          ],
        ),
      ),
    );
    return discard == true;
  }

  Future<void> _pickTime(
    String title,
    TimeOfDay initial,
    ValueChanged<TimeOfDay> onDone,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: title,
    );
    if (picked != null) onDone(picked);
  }

  /// Επικεφαλίδα ομάδας: ποιον αφορούν οι ρυθμίσεις από κάτω.
  Widget _groupTitle(String title, String subtitle) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _onSave() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate() || _draft == null) return;
    final baseline = _initial;
    if (baseline == null) return;
    final days = int.tryParse(_maxDaysController.text.trim());
    if (days == null) return;
    final clamped = days.clamp(1, 365);
    final updated = _draft!.copyWith(maxSnoozeDays: clamped);
    setState(() => _draft = updated);
    _maxDaysController.text = clamped.toString();
    try {
      // Γράφεται μόνο ό,τι άλλαξε από τη στιγμή που άνοιξε ο διάλογος: ό,τι
      // άγγιξε στο μεταξύ ο συνάδελφος στα υπόλοιπα πεδία δεν επανέρχεται.
      if (_buildSharedChanges().isNotEmpty) {
        await ref
            .read(taskSettingsConfigProvider.notifier)
            .saveChanges(from: baseline, to: updated);
      }
      final personal = _personal;
      final personalInitial = _personalInitial;
      if (personal != null && personalInitial != null) {
        await _savePersonal(personalInitial, personal);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        showDialogSnackBar(
          SnackBar(
            content: Text(
              'Αποτυχία αποθήκευσης: ${humanizeUserFacingError(e)}',
            ),
          ),
        );
      }
    }
  }

  Widget _wrapDialog(Widget child) {
    return DialogSnackbarScope(
      messengerKey: dialogMessengerKey,
      child: Center(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _draft == null) {
      return _wrapDialog(
        const AlertDialog(
          title: Text('Ρυθμίσεις εκκρεμοτήτων'),
          content: SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }

    final d = _draft!;

    return _wrapDialog(
      PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final navigator = Navigator.of(context);
          final discard = await _confirmDiscardIfNeeded();
          if (discard && mounted) {
            navigator.pop();
          }
        },
        child: DraggableDialogShell(
          title: const Text('Ρυθμίσεις εκκρεμοτήτων'),
          builder: (titleHandle) => AlertDialog(
            title: titleHandle,
            content: SizedBox(
              // 440 για το περιεχόμενο + 16 για τη λωρίδα της μπάρας κύλισης.
              width: 456,
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  // Λωρίδα για τη μπάρα κύλισης: χωρίς αυτήν η μπάρα κάθεται
                  // πάνω στα εικονίδια και στους διακόπτες της δεξιάς άκρης.
                  padding: const EdgeInsets.only(right: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _groupTitle(
                        'Κοινές για όλους',
                        'Αλλάζουν για όλους τους συναδέλφους, σε κάθε υπολογιστή.',
                      ),
                      _sectionTitle('Ωράριο εκκρεμοτήτων'),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Ώρα τελευταίας εκκρεμότητας («μέσα στο ωράριο»)',
                            maxLines: 1,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        subtitle: Text(_formatTime(d.dayEndTime)),
                        trailing: const Icon(Icons.access_time),
                        onTap: () => _pickTime(
                          'Όριο τέλους ωραρίου',
                          d.dayEndTime,
                          (t) => setState(
                            () => _draft = d.copyWith(dayEndTime: t),
                          ),
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Ώρα έναρξης ωραρίου'),
                        subtitle: Text(_formatTime(d.nextBusinessHour)),
                        trailing: const Icon(Icons.wb_sunny_outlined),
                        onTap: () => _pickTime(
                          'Ώρα επόμενης εργάσιμης',
                          d.nextBusinessHour,
                          (t) => setState(
                            () => _draft = d.copyWith(nextBusinessHour: t),
                          ),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Παράλειψη Σαββατοκύριακων'),
                        value: d.skipWeekends,
                        onChanged: (v) => setState(
                          () => _draft = d.copyWith(skipWeekends: v),
                        ),
                      ),
                      _sectionTitle('Ολοκλήρωση εκκρεμοτήτας μέσα σε:'),
                      Text(
                        'Προεπιλεγμένη ώρα ολοκλήρωσης μίας νέας εκκρεμότητας',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            CompactTooltip(
                              message: TaskDueOptionTooltips.plusOneHour(),
                              child: ChoiceChip(
                                label: const Text('+1 ώρα'),
                                selected:
                                    d.defaultSnoozeOption ==
                                    TaskSettingsConfig.kOneHour,
                                onSelected: (_) => setState(
                                  () => _draft = d.copyWith(
                                    defaultSnoozeOption:
                                        TaskSettingsConfig.kOneHour,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            CompactTooltip(
                              message: TaskDueOptionTooltips.withinSchedule(
                                d.nextBusinessHour,
                                d.dayEndTime,
                              ),
                              child: ChoiceChip(
                                label: const Text('Μέσα στο ωράριο'),
                                selected:
                                    d.defaultSnoozeOption ==
                                    TaskSettingsConfig.kDayEnd,
                                onSelected: (_) => setState(
                                  () => _draft = d.copyWith(
                                    defaultSnoozeOption:
                                        TaskSettingsConfig.kDayEnd,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            CompactTooltip(
                              message: TaskDueOptionTooltips.nextBusiness(
                                d.nextBusinessHour,
                              ),
                              child: ChoiceChip(
                                label: const Text('Επόμενη εργάσιμη'),
                                selected:
                                    d.defaultSnoozeOption ==
                                    TaskSettingsConfig.kNextBusiness,
                                onSelected: (_) => setState(
                                  () => _draft = d.copyWith(
                                    defaultSnoozeOption:
                                        TaskSettingsConfig.kNextBusiness,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _maxDaysController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Μέγιστο εύρος αναβολής (ημέρες)',
                          border: const OutlineInputBorder(),
                          errorStyle: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          suffixIcon: _maxDaysController.text.isNotEmpty
                              ? Semantics(
                                  label: 'Καθαρισμός εύρους ημερών',
                                  child: IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: _maxDaysController.clear,
                                    tooltip: 'Καθαρισμός εύρους ημερών',
                                  ),
                                )
                              : null,
                        ),
                        validator: _validateMaxDaysInput,
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Αυτόματο κλείσιμο Γρήγορων Προσθηκών',
                        ),
                        value: _draft?.autoCloseQuickAdds ?? true,
                        onChanged: (v) => setState(
                          () =>
                              _draft = _draft?.copyWith(autoCloseQuickAdds: v),
                        ),
                      ),
                      const Divider(height: 32),
                      _groupTitle(
                        'Δικές μου',
                        'Μόνο για εσάς — δεν αλλάζουν τίποτα στους συναδέλφους.',
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Ειδοποίηση όταν κάποιος αγγίξει εκκρεμότητά μου',
                        ),
                        subtitle: const Text(
                          'Μήνυμα όταν μου ανατεθεί εκκρεμότητα, όταν μου '
                          'αφαιρεθεί, ή όταν κλείσει κάποιος άλλος μια δική '
                          'μου. Δεν εμφανίζεται ποτέ πάνω σε ενεργή κλήση.',
                        ),
                        value: _personal?.notifyHandovers ?? true,
                        onChanged: (value) => setState(
                          () => _personal = _personal?.copyWith(
                            notifyHandovers: value,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Εμφάνιση μετρητή στο μενού Εκκρεμοτήτων (Badge)',
                        ),
                        subtitle: const Text(
                          'Εμφανίζει στο πλαϊνό μενού το πλήθος ανοιχτών και αναβεβλημένων εκκρεμοτήτων.',
                        ),
                        value: _personal?.showBadge ?? true,
                        onChanged: (value) => setState(
                          () =>
                              _personal = _personal?.copyWith(showBadge: value),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Προεπισκόπηση πριν την εκτύπωση εκκρεμότητας',
                        ),
                        subtitle: const Text(
                          'Δείχνει το φύλλο όπως θα βγει στο χαρτί, με κουμπί '
                          'εκτύπωσης μέσα του. Κλειστό, η «Εκτύπωση…» πάει '
                          'κατευθείαν στο παράθυρο των Windows.',
                        ),
                        value: _personal?.printPreview ?? true,
                        onChanged: (value) => setState(
                          () => _personal = _personal?.copyWith(
                            printPreview: value,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final discard = await _confirmDiscardIfNeeded();
                  if (discard && mounted) navigator.pop();
                },
                child: const Text('Ακύρωση'),
              ),
              FilledButton(
                onPressed: (_hasChanges && _isDaysValid) ? _onSave : null,
                child: const Text('Αποθήκευση'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
