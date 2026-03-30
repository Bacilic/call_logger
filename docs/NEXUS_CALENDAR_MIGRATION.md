# Nexus Calendar Picker - Οδηγός Μεταφοράς σε Άλλη Εφαρμογή

Αυτός ο οδηγός περιγράφει πώς να μεταφέρεις το custom ημερολόγιο (`NexusCalendarPicker`) σε άλλη εφαρμογή Flutter και να αντικαταστήσεις το full-screen picker (`showDateRangePicker`), με τους εξής σταθερούς κανόνες:

- Αρχή εβδομάδας: **Δευτέρα** (Monday, `DateTime.monday`)
- Η αρχή εβδομάδας **δεν αλλάζει** από τον χρήστη
- **Δεν υπάρχουν** προκαθορισμένα εύρη (preset ranges): τρέχουσα/προηγούμενη/επόμενη εβδομάδα

---

## 1) Τι να προσθέσεις στο νέο project

### Εξάρτηση (dependency)

Στο `pubspec.yaml` βεβαιώσου ότι υπάρχει η βιβλιοθήκη:

```yaml
dependencies:
  flutter:
    sdk: flutter
  intl: ^0.20.2
```

### Αρχεία

Δημιούργησε τα παρακάτω αρχεία:

- `lib/utils/date_parser_util.dart`
- `lib/widgets/nexus_calendar_picker.dart`

με τον κώδικα που ακολουθεί.

---

## 2) Κώδικας αρχείου `lib/utils/date_parser_util.dart`

```dart
import 'package:flutter/material.dart';

/// Αποτέλεσμα από parseSmartInput: είτε εύρος είτε μήνυμα σφάλματος.
typedef DateParseResult = (DateTimeRange? range, String? errorMessage);

/// Έξυπνος parser ημερομηνιών: μία ημέρα ή εύρος με expansion (d/m/y) και validation.
class DateParserUtil {
  DateParserUtil._();

  static const _rangeSeparatorRegex = r'[^0-9/\\\-]+';
  static const _datePartSeparatorRegex = r'[/\\\-]+';

  /// Αναλύει input σε ημερομηνία ή εύρος. Κενό input -> (null, null).
  /// Algorithm: + -> σήμερα; split σε clusters με [^0-9/\\\-]+; πάρε 2 clusters max;
  /// ανά cluster split με /,\,-; expansion 1/2/3 parts; validation; swap αν start > end.
  static DateParseResult parseSmartInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return (null, null);

    // a. Ειδική περίπτωση "+"
    if (trimmed == '+') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      return (DateTimeRange(start: today, end: today), null);
    }

    // b. Clusters: split by anything that is NOT digit, /, \, -
    final clusters = trimmed
        .split(RegExp(_rangeSeparatorRegex))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // c. Πρώτα 2 clusters
    if (clusters.isEmpty) return (null, null);
    final cluster1 = clusters[0];
    final cluster2 = clusters.length > 1 ? clusters[1] : null;

    final now = DateTime.now();
    final currentYear = now.year;
    final currentMonth = now.month;

    // d.–e. Parse first cluster
    final first = _parseCluster(cluster1, currentYear, currentMonth);
    if (first.$1 == null) {
      return (null, first.$2 ?? 'Δεν υπάρχει αυτή η μέρα');
    }
    final DateTime start = first.$1!;

    if (cluster2 == null) {
      return (DateTimeRange(start: start, end: start), null);
    }

    final second = _parseCluster(cluster2, currentYear, currentMonth);
    if (second.$1 == null) {
      return (null, second.$2 ?? 'Δεν υπάρχει αυτή η μέρα');
    }
    final DateTime end = second.$1!;

    // g. Swap logic
    final actualStart = start.isAfter(end) ? end : start;
    final actualEnd = start.isAfter(end) ? start : end;
    return (DateTimeRange(start: actualStart, end: actualEnd), null);
  }

  /// Επιστρέφει (DateTime?, errorMessage?).
  /// 3 ψηφία έτους -> "Μη έγκυρο έτος".
  /// Άκυρη ημέρα -> "Δεν υπάρχει αυτή η μέρα".
  static (DateTime?, String?) _parseCluster(
    String cluster,
    int currentYear,
    int currentMonth,
  ) {
    final parts = cluster
        .split(RegExp(_datePartSeparatorRegex))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (parts.isEmpty) return (null, null);

    int day;
    int month;
    int year;

    if (parts.length == 1) {
      final d = int.tryParse(parts[0]);
      if (d == null) return (null, 'Δεν υπάρχει αυτή η μέρα');
      day = d;
      month = currentMonth;
      year = currentYear;
    } else if (parts.length == 2) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (d == null || m == null) return (null, 'Δεν υπάρχει αυτή η μέρα');
      day = d;
      month = m;
      year = currentYear;
    } else if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final yearStr = parts[2];
      if (d == null || m == null) return (null, 'Δεν υπάρχει αυτή η μέρα');

      final yearLen = yearStr.length;
      if (yearLen == 3) return (null, 'Μη έγκυρο έτος');

      final y = int.tryParse(yearStr);
      if (y == null) return (null, 'Δεν υπάρχει αυτή η μέρα');

      if (yearLen == 1) {
        year = 2020 + y; // 6 -> 2026
      } else if (yearLen == 2) {
        year = 2000 + y; // 26 -> 2026
      } else if (yearLen == 4) {
        year = y;
      } else {
        return (null, 'Μη έγκυρο έτος');
      }

      day = d;
      month = m;
    } else {
      return (null, 'Δεν υπάρχει αυτή η μέρα');
    }

    // f. Validation: DateTime και έλεγχος ότι δεν διορθώθηκε
    try {
      final res = DateTime(year, month, day);
      if (res.day != day || res.month != month) {
        return (null, 'Δεν υπάρχει αυτή η μέρα');
      }
      return (res, null);
    } catch (_) {
      return (null, 'Δεν υπάρχει αυτή η μέρα');
    }
  }
}
```

---

## 3) Κώδικας αρχείου `lib/widgets/nexus_calendar_picker.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../utils/date_parser_util.dart';

/// Custom desktop-style date/range picker με επεξεργάσιμο πεδίο και popup ημερολόγιο.
/// Η αρχή εβδομάδας είναι σταθερή στη Δευτέρα και δεν αλλάζει από τον χρήστη.
class NexusCalendarPicker extends StatefulWidget {
  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;

  const NexusCalendarPicker({
    super.key,
    this.value,
    required this.onChanged,
  });

  @override
  State<NexusCalendarPicker> createState() => _NexusCalendarPickerState();
}

class _NexusCalendarPickerState extends State<NexusCalendarPicker> {
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

  @override
  void didUpdateWidget(NexusCalendarPicker oldWidget) {
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

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _removeOverlay();
    _controller.dispose();
    super.dispose();
  }

  void _handleSubmitted(String text) {
    if (text == _lastProcessedText) return;
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
            if (_rangeStart == null) {
              _rangeStart = d;
              _rangeEnd = d;
            } else {
              _rangeEnd = d;
            }
          });
          _overlayEntry?.markNeedsBuild();
        },
        onRangeEndChanged: (date) {
          if (!mounted) return;
          final d = DateTime(date.year, date.month, date.day);
          setState(() => _rangeEnd = d);
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
            width: 230,
            child: TextFormField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                labelText: 'Ημερομηνίες',
                hintText: 'ΗΗ/ΜΜ/ΕΕΕΕ - ΗΗ/ΜΜ/ΕΕΕΕ',
                border: const OutlineInputBorder(),
                errorBorder: OutlineInputBorder(
                  borderSide:
                      BorderSide(color: Theme.of(context).colorScheme.error),
                ),
                errorText: _errorText,
                suffixIcon: Row(
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

    final gridContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(6, (row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: List.generate(7, (col) {
            final idx = row * 7 + col;
            final date = dates[idx];
            final isCurrentMonth = date.month == month && date.year == year;
            final isSelected = selectedStart != null &&
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
                padding: const EdgeInsets.all(2),
                child: AspectRatio(
                  aspectRatio: 1,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cellSize = w / 7;
        return GestureDetector(
          onPanStart: (d) {
            final col = (d.localPosition.dx / cellSize).floor().clamp(0, 6);
            final row = (d.localPosition.dy / cellSize).floor().clamp(0, 5);
            final idx = row * 7 + col;
            if (idx >= 0 && idx < 42) onDayTapped(dates[idx]);
          },
          onPanUpdate: (d) {
            final col = (d.localPosition.dx / cellSize).floor().clamp(0, 6);
            final row = (d.localPosition.dy / cellSize).floor().clamp(0, 5);
            final idx = row * 7 + col;
            if (idx >= 0 && idx < 42) onRangeEndChanged(dates[idx]);
          },
          child: gridContent,
        );
      },
    );
  }
}
```

---

## 4) Prompt που μπορείς να δώσεις στον Cursor στην άλλη εφαρμογή

```text
Ενσωμάτωσε το custom date/range picker με βάση τα παρακάτω αρχεία:
- lib/widgets/nexus_calendar_picker.dart
- lib/utils/date_parser_util.dart

Αντικατάστησε κάθε χρήση του showDateRangePicker με το NexusCalendarPicker.

Απαιτήσεις:
1) Η αρχή εβδομάδας να είναι σταθερή στη Δευτέρα (DateTime.monday) και να ΜΗΝ είναι παραμετροποιήσιμη από τον χρήστη.
2) Να μην υπάρχουν καθόλου preset ranges (τρέχουσα εβδομάδα / προηγούμενη / επόμενη), ούτε στη λογική ούτε στο UI.
3) Να μην υπάρχει εξάρτηση από app-specific services (π.χ. SettingsService).
4) Να διατηρηθούν:
   - text input parsing μέσω DateParserUtil
   - popup overlay ημερολογίου
   - επιλογή range με click/drag
   - Apply button για επιβεβαίωση επιλογής
5) Αν λείπει το intl, πρόσθεσέ το στο pubspec.yaml.
6) Στο τέλος τρέξε ανάλυση και διόρθωσε imports/types αν χρειάζονται.

Δώσε μου τελική αναφορά με:
- λίστα αρχείων που άλλαξαν
- σύντομη περιγραφή ανά αρχείο
- πού ακριβώς αντικαταστάθηκε το showDateRangePicker.
```

---

## 5) Παράδειγμα χρήσης σε StatefulWidget

```dart
DateTimeRange? selectedRange;

@override
Widget build(BuildContext context) {
  return NexusCalendarPicker(
    value: selectedRange,
    onChanged: (range) {
      setState(() {
        selectedRange = range;
      });
    },
  );
}
```

---

## 6) Acceptance criteria (κριτήρια αποδοχής)

- Δεν υπάρχει χρήση `showDateRangePicker` στο codebase.
- Το ημερολόγιο εμφανίζει εβδομάδα με αρχή **Δευτέρα**.
- Δεν υπάρχει UI/λογική για `current/prev/next week`.
- Το widget υποστηρίζει single day και range.
- Δεν υπάρχουν εξαρτήσεις από `SettingsService`.

