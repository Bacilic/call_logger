import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/diagnostics_export_options.dart';
import '../models/windows_events.dart';

enum _PeriodMode { lastDays, range }

enum _WindowsPeriod { same, own }

/// Ο οδηγός της εξαγωγής διαγνωστικών: περίοδος, υπολογιστές, περιεχόμενο.
///
/// Δηλώνει μόνο επιλογές — δεν διαβάζει και δεν γράφει τίποτα. Επιστρέφει τα
/// φίλτρα, ή `null` αν ο χρήστης ακύρωσε.
class DiagnosticsExportDialog extends StatefulWidget {
  const DiagnosticsExportDialog({
    super.key,
    required this.stations,
    required this.thisStation,
    required this.oldestDay,
    required this.today,
    this.initial,
  });

  /// Οι υπολογιστές που βρέθηκαν στα αρχεία.
  final List<String> stations;

  /// Ο υπολογιστής που κάνει την εξαγωγή — προεπιλεγμένος.
  final String thisStation;

  /// Η παλαιότερη ημέρα με αρχείο· `null` όταν δεν υπάρχει κανένα.
  final DateTime? oldestDay;

  final DateTime today;

  /// Προσυμπληρωμένα φίλτρα (π.χ. «αυτό το περιστατικό»).
  final DiagnosticsExportOptions? initial;

  static const int defaultDays = 7;

  static Future<DiagnosticsExportOptions?> show(
    BuildContext context, {
    required List<String> stations,
    required String thisStation,
    required DateTime? oldestDay,
    required DateTime today,
    DiagnosticsExportOptions? initial,
  }) {
    return showDialog<DiagnosticsExportOptions>(
      context: context,
      builder: (_) => DiagnosticsExportDialog(
        stations: stations,
        thisStation: thisStation,
        oldestDay: oldestDay,
        today: today,
        initial: initial,
      ),
    );
  }

  @override
  State<DiagnosticsExportDialog> createState() =>
      _DiagnosticsExportDialogState();
}

class _DiagnosticsExportDialogState extends State<DiagnosticsExportDialog> {
  late _PeriodMode _mode;
  late final TextEditingController _daysController;
  late DateTimeRange _range;
  late final Set<String> _stations;
  late final Set<DiagnosticsContent> _contents;
  bool _includeWindows = true;
  final Set<WindowsEventLevel> _windowsLevels = {
    ...WindowsEventLevel.selectable,
  };
  _WindowsPeriod _windowsPeriod = _WindowsPeriod.same;
  late final TextEditingController _windowsDaysController;
  String? _error;

  List<String> get _allStations {
    final names = {...widget.stations, widget.thisStation}
      ..removeWhere((name) => name.isEmpty);
    return names.toList()..sort();
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _daysController = TextEditingController(
      text: '${DiagnosticsExportDialog.defaultDays}',
    );
    _windowsDaysController = TextEditingController(
      text: '${WindowsEventsOptions.defaultOwnDays}',
    );
    if (initial != null) {
      _mode = _PeriodMode.range;
      _range = DateTimeRange(start: initial.from, end: initial.to);
      _stations = {...initial.stations};
      _contents = {...initial.contents};
      final windows = initial.windows;
      _includeWindows = windows != null;
      if (windows != null) {
        _windowsLevels
          ..clear()
          ..addAll(windows.levels);
      }
    } else {
      _mode = _PeriodMode.lastDays;
      final (from, to) = DiagnosticsExportOptions.lastDays(
        DiagnosticsExportDialog.defaultDays,
        widget.today,
      );
      _range = DateTimeRange(start: from, end: to);
      _stations = {widget.thisStation};
      _contents = {...DiagnosticsContent.values};
    }
  }

  @override
  void dispose() {
    _daysController.dispose();
    _windowsDaysController.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: widget.today,
      initialDateRange: _range,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _range = picked;
      _mode = _PeriodMode.range;
    });
  }

  void _submit() {
    final DateTime from;
    final DateTime to;
    if (_mode == _PeriodMode.lastDays) {
      final days = int.tryParse(_daysController.text.trim());
      if (days == null || days < 1) {
        setState(() => _error = 'Γράψτε πόσες ημέρες (τουλάχιστον 1).');
        return;
      }
      (from, to) = DiagnosticsExportOptions.lastDays(days, widget.today);
    } else {
      from = _range.start;
      to = _range.end;
    }
    if (_stations.isEmpty) {
      setState(() => _error = 'Διαλέξτε τουλάχιστον έναν υπολογιστή.');
      return;
    }
    if (_contents.isEmpty && !_includeWindows) {
      setState(() => _error = 'Διαλέξτε τουλάχιστον ένα είδος περιεχομένου.');
      return;
    }
    int? windowsDays;
    if (_includeWindows && _windowsPeriod == _WindowsPeriod.own) {
      windowsDays = int.tryParse(_windowsDaysController.text.trim());
      if (windowsDays == null || windowsDays < 1) {
        setState(
          () => _error =
              'Γράψτε για πόσες ημέρες θέλετε τα συμβάντα των '
              'Windows (τουλάχιστον 1).',
        );
        return;
      }
    }
    Navigator.of(context).pop(
      DiagnosticsExportOptions(
        from: from,
        to: to,
        stations: {..._stations},
        contents: {..._contents},
        windows: _includeWindows
            ? WindowsEventsOptions(
                levels: {..._windowsLevels},
                ownDays: windowsDays,
              )
            : null,
      ),
    );
  }

  String _day(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final hint = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final oldest = widget.oldestDay;

    return AlertDialog(
      title: const Text('Εξαγωγή διαγνωστικών'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Περίοδος', style: heading),
              RadioGroup<_PeriodMode>(
                groupValue: _mode,
                onChanged: (mode) {
                  if (mode == null) return;
                  setState(() {
                    _mode = mode;
                    _error = null;
                  });
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Radio<_PeriodMode>(value: _PeriodMode.lastDays),
                        const Text('Τελευταίες '),
                        SizedBox(
                          width: 56,
                          child: TextField(
                            controller: _daysController,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onTap: () =>
                                setState(() => _mode = _PeriodMode.lastDays),
                            onChanged: (_) => setState(() => _error = null),
                          ),
                        ),
                        const Text(' ημέρες'),
                      ],
                    ),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Radio<_PeriodMode>(value: _PeriodMode.range),
                        const Text('Από – έως: '),
                        TextButton(
                          onPressed: _pickRange,
                          child: Text(
                            '${_day(_range.start)} – ${_day(_range.end)}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                oldest == null
                    ? 'Δεν υπάρχουν ακόμη αρχεία καταγραφής.'
                    : 'Διαθέσιμα αρχεία από ${_day(oldest)}.',
                style: hint,
              ),
              const SizedBox(height: 16),
              Text('Υπολογιστές', style: heading),
              Wrap(
                spacing: 16,
                children: [
                  for (final station in _allStations)
                    _CheckLabel(
                      label: station == widget.thisStation
                          ? '$station (αυτός)'
                          : station,
                      value: _stations.contains(station),
                      onChanged: (on) => setState(() {
                        on ? _stations.add(station) : _stations.remove(station);
                        _error = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Περιεχόμενο της εφαρμογής', style: heading),
              Wrap(
                spacing: 16,
                children: [
                  for (final content in DiagnosticsContent.values)
                    _CheckLabel(
                      label: content.label,
                      value: _contents.contains(content),
                      onChanged: (on) => setState(() {
                        on ? _contents.add(content) : _contents.remove(content);
                        _error = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              _CheckLabel(
                label:
                    'Συμβάντα Windows αυτού του υπολογιστή '
                    '(${widget.thisStation})',
                value: _includeWindows,
                onChanged: (on) => setState(() {
                  _includeWindows = on;
                  _error = null;
                }),
              ),
              if (_includeWindows)
                Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 16,
                        children: [
                          for (final level in WindowsEventLevel.selectable)
                            _CheckLabel(
                              label: level.label,
                              value: _windowsLevels.contains(level),
                              onChanged: (on) => setState(() {
                                on
                                    ? _windowsLevels.add(level)
                                    : _windowsLevels.remove(level);
                              }),
                            ),
                        ],
                      ),
                      RadioGroup<_WindowsPeriod>(
                        groupValue: _windowsPeriod,
                        onChanged: (period) {
                          if (period == null) return;
                          setState(() {
                            _windowsPeriod = period;
                            _error = null;
                          });
                        },
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Radio<_WindowsPeriod>(
                              value: _WindowsPeriod.same,
                            ),
                            const Text('Ίδια περίοδος'),
                            const SizedBox(width: 16),
                            const Radio<_WindowsPeriod>(
                              value: _WindowsPeriod.own,
                            ),
                            const Text('Τελευταίες '),
                            SizedBox(
                              width: 56,
                              child: TextField(
                                controller: _windowsDaysController,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(3),
                                ],
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                onTap: () => setState(
                                  () => _windowsPeriod = _WindowsPeriod.own,
                                ),
                                onChanged: (_) => setState(() => _error = null),
                              ),
                            ),
                            const Text(' ημέρες'),
                          ],
                        ),
                      ),
                      Text(
                        'Τα συμβάντα της ίδιας της εφαρμογής, και τα '
                        'κλεισίματα και οι διακοπές ρεύματος του υπολογιστή, '
                        'μπαίνουν πάντα, σε κάθε επίπεδο.',
                        style: hint,
                      ),
                    ],
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Άκυρο'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Εξαγωγή…')),
      ],
    );
  }
}

class _CheckLabel extends StatelessWidget {
  const _CheckLabel({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(value: value, onChanged: (on) => onChanged(on ?? false)),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}
