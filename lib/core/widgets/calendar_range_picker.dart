import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../utils/date_parser_util.dart';

/// Custom desktop-style date/range picker με επεξεργάσιμο πεδίο και popup ημερολόγιο.
/// Η αρχή εβδομάδας είναι σταθερή στη Δευτέρα και δεν αλλάζει από τον χρήστη.
class CalendarRangePicker extends StatefulWidget {
  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;

  const CalendarRangePicker({
    super.key,
    this.value,
    required this.onChanged,
  });

  @override
  State<CalendarRangePicker> createState() => CalendarRangePickerState();
}

class CalendarRangePickerState extends State<CalendarRangePicker> {
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  static const int _firstDayOfWeek = DateTime.monday;

  final LayerLink _layerLink = LayerLink();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  OverlayEntry? _overlayEntry;
  DateTime _displayedMonth = DateTime.now();
  String? _errorText;
  String? _lastProcessedText;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  bool _isSelectingEnd = false;

  @override
  void initState() {
    super.initState();
    _displayedMonth = DateTime(
      widget.value?.start.year ?? DateTime.now().year,
      widget.value?.start.month ?? DateTime.now().month,
    );
    _syncControllerFromValue();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _handleSubmitted(_controller.text);
  }

  /// Επιβεβαίωση του τρέχοντος κειμένου (ίδια λογική με Enter).
  /// Με [force]: εφαρμόζει ακόμη κι αν το πεδίο δεν άλλαξε — χρήσιμο στον διάλογο
  /// όταν η προεπιλογή είναι ήδη η σωστή ημερομηνία.
  void applyCurrentInput({bool force = false}) {
    _handleSubmitted(_controller.text, force: force);
  }

  @override
  void didUpdateWidget(CalendarRangePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _syncControllerFromValue();
  }

  void _syncControllerFromValue() {
    if (widget.value == null) {
      _controller.text = '';
      _lastProcessedText = '';
      return;
    }
    final start = widget.value!.start;
    final end = widget.value!.end;
    if (start.year == end.year &&
        start.month == end.month &&
        start.day == end.day) {
      _controller.text = _dateFormat.format(start);
    } else {
      _controller.text =
          '${_dateFormat.format(start)} - ${_dateFormat.format(end)}';
    }
    _lastProcessedText = _controller.text;
  }

  void _syncControllerFromDraftRange() {
    final start = _rangeStart;
    final end = _rangeEnd ?? _rangeStart;
    if (start == null || end == null) return;

    final from = start.isBefore(end) ? start : end;
    final to = start.isBefore(end) ? end : start;
    if (from.year == to.year && from.month == to.month && from.day == to.day) {
      _controller.text = _dateFormat.format(from);
      return;
    }
    _controller.text = '${_dateFormat.format(from)} - ${_dateFormat.format(to)}';
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _removeOverlay();
    _controller.dispose();
    super.dispose();
  }

  void _handleSubmitted(String text, {bool force = false}) {
    final normalizedText = text.trim();
    final lastProcessedNormalized = _lastProcessedText?.trim();
    if (!force && normalizedText == lastProcessedNormalized) return;

    if (normalizedText.isEmpty) {
      setState(() {
        _errorText = null;
        _rangeStart = null;
        _rangeEnd = null;
        _isSelectingEnd = false;
      });
      _controller.clear();
      _lastProcessedText = '';
      widget.onChanged(null);
      return;
    }

    if (!force && text == _lastProcessedText) return;
    _lastProcessedText = text;
    final (range, errorMessage) = DateParserUtil.parseSmartInput(text);

    if (!mounted) return;
    if (errorMessage != null) {
      setState(() => _errorText = errorMessage);
      return;
    }

    if (range != null) {
      setState(() => _errorText = null);
      final start = range.start;
      final end = range.end;
      if (start.year == end.year &&
          start.month == end.month &&
          start.day == end.day) {
        _controller.text = _dateFormat.format(start);
      } else {
        _controller.text =
            '${_dateFormat.format(start)} - ${_dateFormat.format(end)}';
      }
      // Keep dedupe token in sync with normalized text to prevent a second
      // submit cycle (focus-loss after Enter) from re-triggering onChanged.
      _lastProcessedText = _controller.text;

      widget.onChanged(range);
    } else {
      setState(() => _errorText = null);
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;
    setState(() {
      _rangeStart = null;
      _rangeEnd = null;
      _isSelectingEnd = false;
    });

    final box = context.findRenderObject() as RenderBox?;
    final topLeft = box != null ? box.localToGlobal(Offset.zero) : Offset.zero;
    final screenWidth = MediaQuery.sizeOf(context).width;
    const overlayWidth = 350.0;
    final useRightAnchors =
        (topLeft.dx + overlayWidth) > screenWidth || topLeft.dx > screenWidth / 2;

    _overlayEntry = OverlayEntry(
      builder: (context) => _CalendarOverlay(
        layerLink: _layerLink,
        displayedMonth: _displayedMonth,
        firstDayOfWeek: _firstDayOfWeek,
        value: widget.value,
        rangeStart: _rangeStart,
        rangeEnd: _rangeEnd,
        useRightAnchors: useRightAnchors,
        overlayWidth: overlayWidth,
        onMonthChanged: (m) {
          if (!mounted) return;
          setState(() => _displayedMonth = m);
          _overlayEntry?.markNeedsBuild();
        },
        onDayTapped: (date) {
          if (!mounted) return;
          final d = DateTime(date.year, date.month, date.day);
          setState(() {
            if (_rangeStart == null || !_isSelectingEnd) {
              _rangeStart = d;
              _rangeEnd = d;
              _isSelectingEnd = true;
            } else {
              _rangeEnd = d;
              _isSelectingEnd = false;
            }
          });
          _syncControllerFromDraftRange();
          _overlayEntry?.markNeedsBuild();
        },
        onRangeEndChanged: (date) {
          if (!mounted) return;
          final d = DateTime(date.year, date.month, date.day);
          if (!_isSelectingEnd || _rangeStart == null) return;
          setState(() => _rangeEnd = d);
          _syncControllerFromDraftRange();
          _overlayEntry?.markNeedsBuild();
        },
        onApply: () {
          if (!mounted) return;
          final start = _rangeStart;
          final end = _rangeEnd ?? _rangeStart;
          if (start == null) return;

          final s = DateTime(start.year, start.month, start.day);
          final e = end != null ? DateTime(end.year, end.month, end.day) : s;
          final range = DateTimeRange(
            start: s.isBefore(e) ? s : e,
            end: s.isBefore(e) ? e : s,
          );

          widget.onChanged(range);
          _syncControllerFromValue();
          _lastProcessedText = _controller.text;
          setState(() {
            _errorText = null;
            _rangeStart = null;
            _rangeEnd = null;
            _isSelectingEnd = false;
          });
          _removeOverlay();
        },
        onDismiss: _removeOverlay,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 280,
            child: TextFormField(
              controller: _controller,
              focusNode: _focusNode,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Ημερομηνίες',
                hintText: 'ΗΗ/ΜΜ/ΕΕΕΕ - ΗΗ/ΜΜ/ΕΕΕΕ',
                border: const OutlineInputBorder(),
                errorBorder: OutlineInputBorder(
                  borderSide:
                      BorderSide(color: Theme.of(context).colorScheme.error),
                ),
                errorText: _errorText,
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) {
                    final hasText = value.text.trim().isNotEmpty;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Tooltip(
                          message: 'Οδηγός Εισαγωγής\n'
                              '• "7" -> Ημέρα τρέχοντος μηνός\n'
                              '• "1/2" -> Ημερομηνία τρέχοντος έτους\n'
                              '• "1/2\\26" -> Έτος 2026 (1, 2 ή 4 ψηφία)\n'
                              '• "1/1 έως 5/1" -> Εύρος (οποιοδήποτε γράμμα ανάμεσα)\n'
                              '• "+" -> Σημερινή ημερομηνία',
                          preferBelow: false,
                          child: Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        if (hasText) ...[
                          const SizedBox(width: 2),
                          IconButton(
                            tooltip: 'Καθαρισμός εύρους ημερομηνιών',
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              setState(() {
                                _errorText = null;
                                _rangeStart = null;
                                _rangeEnd = null;
                                _isSelectingEnd = false;
                              });
                              _controller.clear();
                              _lastProcessedText = '';
                            },
                          ),
                        ],
                        if (_errorText != null) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: _errorText!,
                            preferBelow: false,
                            child: Icon(
                              Icons.error_outline,
                              size: 18,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
              onFieldSubmitted: (_) => _handleSubmitted(_controller.text),
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'[0-9/\\\-\s\+a-zA-Zα-ωΑ-Ωά-ώΆ-Ώ]'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: _showOverlay,
            tooltip: 'Άνοιγμα ημερολογίου',
          ),
        ],
      ),
    );
  }
}

class _CalendarOverlay extends StatelessWidget {
  const _CalendarOverlay({
    required this.layerLink,
    required this.displayedMonth,
    required this.firstDayOfWeek,
    required this.value,
    this.rangeStart,
    this.rangeEnd,
    required this.useRightAnchors,
    required this.overlayWidth,
    required this.onMonthChanged,
    required this.onDayTapped,
    required this.onRangeEndChanged,
    required this.onApply,
    required this.onDismiss,
  });

  final LayerLink layerLink;
  final DateTime displayedMonth;
  final int firstDayOfWeek;
  final DateTimeRange? value;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final bool useRightAnchors;
  final double overlayWidth;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDayTapped;
  final ValueChanged<DateTime> onRangeEndChanged;
  final VoidCallback onApply;
  final VoidCallback onDismiss;

  static const List<String> _weekDayNames = [
    'Δευ',
    'Τρι',
    'Τετ',
    'Πεμ',
    'Παρ',
    'Σαβ',
    'Κυρ',
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDismiss,
        ),
        CompositedTransformFollower(
          link: layerLink,
          showWhenUnlinked: false,
          followerAnchor: useRightAnchors ? Alignment.topRight : Alignment.topLeft,
          targetAnchor: useRightAnchors ? Alignment.bottomRight : Alignment.bottomLeft,
          offset: const Offset(0, 8),
          child: TapRegion(
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 350),
                child: SizedBox(
                  width: overlayWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildMonthNavigation(context),
                        const SizedBox(height: 8),
                        _buildWeekdayHeader(context),
                        const SizedBox(height: 4),
                        _buildCalendarGrid(context),
                        const SizedBox(height: 8),
                        _buildBottomActions(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        textStyle: const TextStyle(fontSize: 12),
      ),
      onPressed: rangeStart != null ? onApply : null,
      icon: const Icon(Icons.check, size: 18),
      label: const Text('Εφαρμογή'),
    );
  }

  Widget _buildMonthNavigation(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy', 'el').format(displayedMonth);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () {
            final prev = DateTime(displayedMonth.year, displayedMonth.month - 1);
            onMonthChanged(prev);
          },
        ),
        Text(
          monthLabel,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        IconButton(
          icon: const Icon(Icons.arrow_forward_ios, size: 18),
          onPressed: () {
            final next = DateTime(displayedMonth.year, displayedMonth.month + 1);
            onMonthChanged(next);
          },
        ),
      ],
    );
  }

  Widget _buildWeekdayHeader(BuildContext context) {
    final dayOrder = List.generate(7, (i) => (firstDayOfWeek - 1 + i) % 7 + 1);
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: dayOrder
          .map(
            (d) => Expanded(
              child: Center(
                child: Text(
                  _weekDayNames[d - 1],
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildCalendarGrid(BuildContext context) {
    final year = displayedMonth.year;
    final month = displayedMonth.month;
    final firstOfMonth = DateTime(year, month, 1);
    final offset = (firstOfMonth.weekday - firstDayOfWeek + 7) % 7;
    final firstDisplayed = firstOfMonth.subtract(Duration(days: offset));
    final dates = List.generate(42, (i) => firstDisplayed.add(Duration(days: i)));

    final theme = Theme.of(context);
    final selectedStart = value != null
        ? DateTime(value!.start.year, value!.start.month, value!.start.day)
        : null;
    final selectedEnd = value != null
        ? DateTime(value!.end.year, value!.end.month, value!.end.day)
        : null;
    final rangeStartNorm = rangeStart != null
        ? DateTime(rangeStart!.year, rangeStart!.month, rangeStart!.day)
        : null;
    final rangeEndNorm =
        rangeEnd != null ? DateTime(rangeEnd!.year, rangeEnd!.month, rangeEnd!.day) : null;
    final rangeMin = (rangeStartNorm != null && rangeEndNorm != null)
        ? (rangeStartNorm.isBefore(rangeEndNorm) ? rangeStartNorm : rangeEndNorm)
        : rangeStartNorm;
    final rangeMax = (rangeStartNorm != null && rangeEndNorm != null)
        ? (rangeStartNorm.isBefore(rangeEndNorm) ? rangeEndNorm : rangeStartNorm)
        : rangeEndNorm ?? rangeStartNorm;
    final isPreviewingSelection = rangeMin != null;

    final gridContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(6, (row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: List.generate(7, (col) {
            final idx = row * 7 + col;
            final date = dates[idx];
            final isCurrentMonth = date.month == month && date.year == year;
            final isSelected = !isPreviewingSelection &&
                selectedStart != null &&
                selectedEnd != null &&
                !date.isBefore(selectedStart) &&
                !date.isAfter(selectedEnd);
            final isInPreviewRange = rangeMin != null &&
                rangeMax != null &&
                !date.isBefore(rangeMin) &&
                !date.isAfter(rangeMax);

            Color? cellColor;
            if (isSelected) {
              cellColor = theme.colorScheme.primaryContainer;
            } else if (isInPreviewRange) {
              cellColor = theme.colorScheme.primaryContainer.withValues(alpha: 0.6);
            }

            final textOpacity = isCurrentMonth ? 1.0 : 0.3;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.all(1),
                child: SizedBox(
                  height: 28,
                  child: InkWell(
                    onTap: () => onDayTapped(date),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cellColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${date.day}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight:
                              isSelected || isInPreviewRange ? FontWeight.bold : null,
                          color: (theme.textTheme.bodySmall?.color ??
                                  theme.colorScheme.onSurface)
                              .withValues(alpha: textOpacity),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      }),
    );

    const double cellHeight = 30; // 28 + 2 padding
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = constraints.maxWidth / 7;
        return GestureDetector(
          onPanStart: (d) {
            final col = (d.localPosition.dx / cellWidth).floor().clamp(0, 6);
            final row = (d.localPosition.dy / cellHeight).floor().clamp(0, 5);
            final idx = row * 7 + col;
            if (idx >= 0 && idx < 42) onDayTapped(dates[idx]);
          },
          onPanUpdate: (d) {
            final col = (d.localPosition.dx / cellWidth).floor().clamp(0, 6);
            final row = (d.localPosition.dy / cellHeight).floor().clamp(0, 5);
            final idx = row * 7 + col;
            if (idx >= 0 && idx < 42) onRangeEndChanged(dates[idx]);
          },
          child: gridContent,
        );
      },
    );
  }
}

/// Απόσταση από την κορυφή της ασφαλούς περιοχής (μετά το system UI) ώστε το παράθυρο
/// να πέφτει στο ύψος της σειράς φίλτρων (κουμπί ημερολογίου) κάτω από την [AppBar].
const double _kDateRangeDialogTopInset = kToolbarHeight + 20;

class CalendarRangePickerDialogResult {
  const CalendarRangePickerDialogResult.selected(this.range) : wasCleared = false;

  const CalendarRangePickerDialogResult.cleared()
      : range = null,
        wasCleared = true;

  final DateTimeRange? range;
  final bool wasCleared;
}

class _CalendarRangePickerDialogBody extends StatefulWidget {
  const _CalendarRangePickerDialogBody({this.initialValue});

  final DateTimeRange? initialValue;

  @override
  State<_CalendarRangePickerDialogBody> createState() =>
      _CalendarRangePickerDialogBodyState();
}

class _CalendarRangePickerDialogBodyState extends State<_CalendarRangePickerDialogBody> {
  final GlobalKey<CalendarRangePickerState> _pickerKey =
      GlobalKey<CalendarRangePickerState>();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(
        top: _kDateRangeDialogTopInset,
        left: 40,
        right: 40,
      ),
      title: const Text('Εύρος ημερομηνιών'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: CalendarRangePicker(
            key: _pickerKey,
            value: widget.initialValue,
            onChanged: (range) {
              if (range == null) {
                Navigator.of(context).pop(
                  const CalendarRangePickerDialogResult.cleared(),
                );
                return;
              }
              Navigator.of(context).pop(
                CalendarRangePickerDialogResult.selected(range),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: () =>
              _pickerKey.currentState?.applyCurrentInput(force: true),
          child: const Text('Εφαρμογή'),
        ),
      ],
    );
  }
}

/// Πλαίσιο.dialog για desktop:
/// - null: ακύρωση
/// - [CalendarRangePickerDialogResult.cleared]: ρητός καθαρισμός φίλτρου
/// - [CalendarRangePickerDialogResult.selected]: επιβεβαιωμένο εύρος
Future<CalendarRangePickerDialogResult?> showCalendarRangePickerDialog(
  BuildContext context, {
  DateTimeRange? initialValue,
}) {
  return showDialog<CalendarRangePickerDialogResult>(
    context: context,
    builder: (dialogContext) => _CalendarRangePickerDialogBody(
      initialValue: initialValue,
    ),
  );
}
