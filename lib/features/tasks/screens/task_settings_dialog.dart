import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/settings_service.dart';
import '../models/task_settings_config.dart';
import '../providers/task_settings_config_provider.dart';
import '../ui/task_due_option_tooltips.dart';

/// Διάλογος γενικών ρυθμίσεων εκκρεμοτήτων (`app_settings`).
class TaskSettingsDialog extends ConsumerStatefulWidget {
  const TaskSettingsDialog({super.key});

  @override
  ConsumerState<TaskSettingsDialog> createState() => _TaskSettingsDialogState();
}

class _TaskSettingsDialogState extends ConsumerState<TaskSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  final SettingsService _settings = SettingsService();
  late final TextEditingController _maxDaysController;
  TaskSettingsConfig? _draft;
  TaskSettingsConfig? _initial;
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
      try {
        final c = await ref.read(taskSettingsConfigProvider.future);
        if (!mounted) return;
        setState(() {
          _draft = c;
          _initial = c;
          _maxDaysController.text = c.maxSnoozeDays.toString();
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        final fallback = TaskSettingsConfig.defaultConfig();
        setState(() {
          _draft = fallback;
          _initial = fallback;
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
      changes.add('Μέγιστο εύρος αναβολής (ημέρες): $initialDays -> $parsedDays');
    }

    if (draft.autoCloseQuickAdds != initial.autoCloseQuickAdds) {
      changes.add(
        'Αυτόματο κλείσιμο Γρήγορων Προσθηκών: ${initial.autoCloseQuickAdds ? 'Ναι' : 'Όχι'} -> ${draft.autoCloseQuickAdds ? 'Ναι' : 'Όχι'}',
      );
    }

    return changes;
  }

  bool get _hasChanges => _buildChanges().isNotEmpty;
  bool get _isDaysValid => _validateMaxDaysInput(_maxDaysController.text) == null;

  Future<bool> _confirmDiscardIfNeeded() async {
    final changes = _buildChanges();
    if (changes.isEmpty) return true;

    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Μη αποθηκευμένες αλλαγές'),
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

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Future<void> _onSave() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate() || _draft == null) return;
    final days = int.tryParse(_maxDaysController.text.trim());
    if (days == null) return;
    final clamped = days.clamp(1, 365);
    final updated = _draft!.copyWith(maxSnoozeDays: clamped);
    setState(() => _draft = updated);
    _maxDaysController.text = clamped.toString();
    try {
      await ref.read(taskSettingsConfigProvider.notifier).save(updated);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Αποτυχία αποθήκευσης: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _draft == null) {
      return const AlertDialog(
        title: Text('Ρυθμίσεις εκκρεμοτήτων'),
        content: SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final d = _draft!;

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final discard = await _confirmDiscardIfNeeded();
        if (discard && mounted) {
          navigator.pop();
        }
      },
      child: AlertDialog(
        title: const Text('Ρυθμίσεις εκκρεμοτήτων'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                      (t) => setState(() => _draft = d.copyWith(dayEndTime: t)),
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
                      (t) => setState(() => _draft = d.copyWith(nextBusinessHour: t)),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Παράλειψη Σαββατοκύριακων'),
                    value: d.skipWeekends,
                    onChanged: (v) =>
                        setState(() => _draft = d.copyWith(skipWeekends: v)),
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
                        Tooltip(
                          message: TaskDueOptionTooltips.plusOneHour(),
                          child: ChoiceChip(
                            label: const Text('+1 ώρα'),
                            selected:
                                d.defaultSnoozeOption == TaskSettingsConfig.kOneHour,
                            onSelected: (_) => setState(
                              () => _draft = d.copyWith(
                                defaultSnoozeOption: TaskSettingsConfig.kOneHour,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: TaskDueOptionTooltips.withinSchedule(
                            d.nextBusinessHour,
                            d.dayEndTime,
                          ),
                          child: ChoiceChip(
                            label: const Text('Μέσα στο ωράριο'),
                            selected:
                                d.defaultSnoozeOption == TaskSettingsConfig.kDayEnd,
                            onSelected: (_) => setState(
                              () => _draft = d.copyWith(
                                defaultSnoozeOption: TaskSettingsConfig.kDayEnd,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: TaskDueOptionTooltips.nextBusiness(
                            d.nextBusinessHour,
                          ),
                          child: ChoiceChip(
                            label: const Text('Επόμενη εργάσιμη'),
                            selected: d.defaultSnoozeOption ==
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
                    title: const Text('Αυτόματο κλείσιμο Γρήγορων Προσθηκών'),
                    value: _draft?.autoCloseQuickAdds ?? true,
                    onChanged: (v) => setState(
                      () => _draft = _draft?.copyWith(autoCloseQuickAdds: v),
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
                    value: ref.watch(showTasksBadgeProvider).value ?? true,
                    onChanged: (value) async {
                      await _settings.setShowTasksBadge(value);
                      if (!mounted) return;
                      ref.invalidate(showTasksBadgeProvider);
                      setState(() {});
                    },
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
    );
  }
}

