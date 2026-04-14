import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/non_user_phone_entry.dart';

/// Πίνακας τηλεφώνων χωρίς σύνδεση χρήστη· διπλό κλικ / Enter → επεξεργασία τμήματος.
/// Στήλες με αυτόματο πλάτος (ευρύτερο κείμενο) και χειροκίνητη αλλαγή πλάτους.
class NonUserPhonesDataTable extends StatefulWidget {
  const NonUserPhonesDataTable({
    super.key,
    required this.entries,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSetSort,
    required this.onOpenDepartment,
    this.focusedRowIndex,
    this.onSetFocusedRowIndex,
    this.continuousScroll = true,
  });

  final List<NonUserPhoneEntry> entries;
  final String? sortColumn;
  final bool sortAscending;
  final void Function(String? column, bool ascending) onSetSort;
  final void Function(NonUserPhoneEntry entry) onOpenDepartment;
  final int? focusedRowIndex;
  final void Function(int? index)? onSetFocusedRowIndex;
  final bool continuousScroll;

  @override
  State<NonUserPhonesDataTable> createState() => _NonUserPhonesDataTableState();
}

class _NonUserPhonesDataTableState extends State<NonUserPhonesDataTable> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _verticalScrollController = ScrollController();

  static const _headingHeight = 40.0;
  static const _minCol = 72.0;
  static const _maxCol = 900.0;
  static const _cellHPadding = 12.0;
  static const _handleWidth = 12.0;
  static const _rightSafePadding = 16.0;

  /// Βάση για πρώτο drag μετά το αυτόματο πλάτος.
  double _lastAutoPhone = 160;
  double _lastAutoDept = 200;

  bool _phoneUserSized = false;
  bool _deptUserSized = false;
  double _phoneColWidth = 160;
  double _deptColWidth = 200;

  @override
  void dispose() {
    _focusNode.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  Color? get _focusHighlight =>
      Theme.of(context).colorScheme.surfaceContainerHighest;

  double _textWidth(String text, TextStyle style) {
    if (text.isEmpty) return 0;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
    tp.layout();
    return tp.width;
  }

  /// Ευρύτερη γραμμή για πεδία που ενδέχεται να σπάσουν σε 2 γραμμές στην εμφάνιση.
  double _widestLineWidth(String text, TextStyle style) {
    if (text.isEmpty) return 0;
    var maxW = 0.0;
    for (final line in text.split('\n')) {
      final t = line.trimRight();
      if (t.isEmpty) continue;
      maxW = math.max(maxW, _textWidth(t, style));
    }
    return maxW;
  }

  /// Πλάτος στήλης = περιεχόμενο + οριζόντιο padding κελιού + λαβή αλλαγής μεγέθους.
  ({double phone, double dept}) _measureAutoWidths(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.titleSmall ?? const TextStyle();
    final bodyPhone = theme.textTheme.bodyLarge ?? const TextStyle();
    final bodyDept = theme.textTheme.bodyMedium ?? const TextStyle();

    final sortPhone = widget.sortColumn == 'phone';
    final sortDept = widget.sortColumn == 'department';
    const sortIconReserve = 22.0;

    var maxPhone = _textWidth('Τηλέφωνο', headerStyle) +
        (sortPhone ? sortIconReserve : 0);
    for (final e in widget.entries) {
      maxPhone = math.max(maxPhone, _textWidth(e.number, bodyPhone));
    }

    var maxDept = _textWidth('Τμήμα', headerStyle) +
        (sortDept ? sortIconReserve : 0);
    for (final e in widget.entries) {
      maxDept = math.max(
        maxDept,
        _widestLineWidth(e.departmentLabel, bodyDept),
      );
    }

    final pad = _cellHPadding * 2 + _handleWidth;
    final phone = math.min(
      _maxCol,
      math.max(_minCol, maxPhone + pad),
    );
    final dept = math.min(
      _maxCol,
      math.max(_minCol, maxDept + pad),
    );
    return (phone: phone, dept: dept);
  }

  void _resizePhone(double delta) {
    setState(() {
      final base = _phoneUserSized ? _phoneColWidth : _lastAutoPhone;
      _phoneColWidth = (base + delta).clamp(_minCol, _maxCol);
      _phoneUserSized = true;
    });
  }

  void _resizeDept(double delta) {
    setState(() {
      final base = _deptUserSized ? _deptColWidth : _lastAutoDept;
      _deptColWidth = (base + delta).clamp(_minCol, _maxCol);
      _deptUserSized = true;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final list = widget.entries;
    final len = list.length;
    if (len == 0) return KeyEventResult.ignored;
    final onSetFocus = widget.onSetFocusedRowIndex;

    if (key == LogicalKeyboardKey.arrowDown) {
      if (onSetFocus != null) {
        final cur = widget.focusedRowIndex;
        final next = cur == null ? 0 : (cur + 1).clamp(0, len - 1);
        onSetFocus(next);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (onSetFocus != null) {
        final cur = widget.focusedRowIndex;
        final next = cur == null ? len - 1 : (cur - 1).clamp(0, len - 1);
        onSetFocus(next);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      final idx = widget.focusedRowIndex ?? 0;
      if (idx >= 0 && idx < len) {
        widget.onOpenDepartment(list[idx]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onSort(String column) {
    final sc = widget.sortColumn;
    final asc = widget.sortAscending;
    if (sc == column) {
      widget.onSetSort(column, !asc);
    } else {
      widget.onSetSort(column, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedCol = widget.sortColumn;
    final asc = widget.sortAscending;

    final auto = _measureAutoWidths(context);
    _lastAutoPhone = auto.phone;
    _lastAutoDept = auto.dept;
    final wPhone = _phoneUserSized ? _phoneColWidth : auto.phone;
    final wDept = _deptUserSized ? _deptColWidth : auto.dept;

    Widget headerCell(String label, String sortKey) {
      final isSorted = sortedCol == sortKey;
      return InkWell(
        onTap: () => _onSort(sortKey),
        child: Container(
          height: _headingHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSorted)
                Icon(
                  asc ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 18,
                ),
            ],
          ),
        ),
      );
    }

    final columnWidths = <int, TableColumnWidth>{
      0: FixedColumnWidth(wPhone),
      1: FixedColumnWidth(wDept),
    };

    final table = Table(
      columnWidths: columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            TableCell(
              child: Row(
                children: [
                  Expanded(child: headerCell('Τηλέφωνο', 'phone')),
                  _NonUserTableResizeHandle(onResize: _resizePhone),
                ],
              ),
            ),
            TableCell(
              child: Row(
                children: [
                  Expanded(child: headerCell('Τμήμα', 'department')),
                  _NonUserTableResizeHandle(onResize: _resizeDept),
                ],
              ),
            ),
          ],
        ),
        for (var i = 0; i < widget.entries.length; i++)
          _dataRow(context, i, widget.entries[i]),
      ],
    );

    final totalTableWidth = wPhone + wDept;

    return LayoutBuilder(
      builder: (context, constraints) {
        final needHorizontalScroll = totalTableWidth > constraints.maxWidth;
        final fittedTable = SizedBox(width: totalTableWidth, child: table);
        Widget core = needHorizontalScroll
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: fittedTable,
              )
            : Align(
                alignment: Alignment.topLeft,
                child: fittedTable,
              );

        return Focus(
          focusNode: _focusNode,
          onKeyEvent: _onKey,
          child: GestureDetector(
            onTap: () => _focusNode.requestFocus(),
            child: Scrollbar(
              controller: _verticalScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _verticalScrollController,
                primary: false,
                child: Padding(
                  padding: const EdgeInsets.only(right: _rightSafePadding),
                  child: core,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  TableRow _dataRow(BuildContext context, int index, NonUserPhoneEntry e) {
    final theme = Theme.of(context);
    final focused = widget.focusedRowIndex == index;
    final bg = focused ? _focusHighlight : null;
    return TableRow(
      decoration: BoxDecoration(color: bg),
      children: [
        _cell(
          context,
          Text(e.number, style: theme.textTheme.bodyLarge),
          onTap: () => widget.onSetFocusedRowIndex?.call(index),
          onDoubleTap: () => widget.onOpenDepartment(e),
        ),
        _cell(
          context,
          Text(
            e.departmentLabel,
            style: theme.textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => widget.onSetFocusedRowIndex?.call(index),
          onDoubleTap: () => widget.onOpenDepartment(e),
        ),
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    Widget child, {
    VoidCallback? onTap,
    VoidCallback? onDoubleTap,
  }) {
    return TableCell(
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _NonUserTableResizeHandle extends StatefulWidget {
  const _NonUserTableResizeHandle({required this.onResize});

  final void Function(double delta) onResize;

  @override
  State<_NonUserTableResizeHandle> createState() =>
      _NonUserTableResizeHandleState();
}

class _NonUserTableResizeHandleState extends State<_NonUserTableResizeHandle> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showActive = _isHovered || _isDragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _isDragging = true),
        onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
        onHorizontalDragCancel: () => setState(() => _isDragging = false),
        onHorizontalDragUpdate: (details) => widget.onResize(details.delta.dx),
        child: SizedBox(
          width: 12,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 2,
              height: showActive ? 26 : 18,
              decoration: BoxDecoration(
                color: showActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
