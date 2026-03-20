import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task_snooze_config.dart';
import '../providers/task_snooze_config_provider.dart';

/// Διάλογος ρυθμίσεων αναβολών και εργάσιμων ωρών (`app_settings`).
class TaskSnoozeSettingsDialog extends ConsumerStatefulWidget {
  const TaskSnoozeSettingsDialog({super.key});

  @override
  ConsumerState<TaskSnoozeSettingsDialog> createState() =>
      _TaskSnoozeSettingsDialogState();
}

class _TaskSnoozeSettingsDialogState
    extends ConsumerState<TaskSnoozeSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _maxDaysController;
  TaskSnoozeConfig? _draft;
  TaskSnoozeConfig? _initial;
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
        final c = await ref.read(taskSnoozeConfigProvider.future);
        if (!mounted) return;
        setState(() {
          _draft = c;
          _initial = c;
          _maxDaysController.text = c.maxSnoozeDays.toString();
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        final fallback = TaskSnoozeConfig.defaultConfig();
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
      case TaskSnoozeConfig.kOneHour:
        return '+1 ώρα';
      case TaskSnoozeConfig.kDayEnd:
        return 'Μέσα στην ημέρα';
      case TaskSnoozeConfig.kNextBusiness:
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

  /// Επικύρωση πεδίου «μέγιστο εύρος ημερών» (κενό, μη αριθμός, εκτός 1–365).
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
      await ref.read(taskSnoozeConfigProvider.notifier).save(updated);
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
      return AlertDialog(
        title: const Text('Ρυθμίσεις αναβολών & εργάσιμων ωρών'),
        content: const SizedBox(
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
        title: const Text('Ρυθμίσεις αναβολών & εργάσιμων ωρών'),
        content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle('Εργάσιμες ώρες'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ώρα τελευταίας εκκρεμότητας («μέσα στην ημέρα»)'),
                  subtitle: Text(_formatTime(d.dayEndTime)),
                  trailing: const Icon(Icons.access_time),
                  onTap: () => _pickTime(
                    'Όριο μέσα στην ημέρα',
                    d.dayEndTime,
                    (t) => setState(() => _draft = d.copyWith(dayEndTime: t)),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ώρα έναρξης επόμενης εργάσιμης'),
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
                  onChanged: (v) =>
                      setState(() => _draft = d.copyWith(skipWeekends: v)),
                ),
                _sectionTitle('Νέα εκκρεμότητα'),
                Text(
                  'Προεπιλεγμένη αναβολή (νέα εκκρεμότητα)',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('+1 ώρα'),
                      selected:
                          d.defaultSnoozeOption == TaskSnoozeConfig.kOneHour,
                      onSelected: (_) => setState(
                        () => _draft = d.copyWith(
                          defaultSnoozeOption: TaskSnoozeConfig.kOneHour,
                        ),
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('Μέσα στην ημέρα'),
                      selected:
                          d.defaultSnoozeOption == TaskSnoozeConfig.kDayEnd,
                      onSelected: (_) => setState(
                        () => _draft = d.copyWith(
                          defaultSnoozeOption: TaskSnoozeConfig.kDayEnd,
                        ),
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('Επόμενη εργάσιμη'),
                      selected: d.defaultSnoozeOption ==
                          TaskSnoozeConfig.kNextBusiness,
                      onSelected: (_) => setState(
                        () => _draft = d.copyWith(
                          defaultSnoozeOption: TaskSnoozeConfig.kNextBusiness,
                        ),
                      ),
                    ),
                  ],
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
                              onPressed: () {
                                _maxDaysController.clear();
                              },
                              tooltip: 'Καθαρισμός εύρους ημερών',
                            ),
                          )
                        : null,
                  ),
                  validator: _validateMaxDaysInput,
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
