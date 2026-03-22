// Προσωρινή χρήση DataTable – σε επόμενη φάση εξέτασε custom Table για sticky headers & row selection.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/equipment_column.dart';

const _minColumnWidth = 40.0;
const _maxColumnWidth = 600.0;
const _defaultDataFallbackWidth = 120.0;
const _rowsPerPage = 15;

const _defaultWidthsByKey = <String, double>{
  'selection': 52.0,
  'id': 56.0,
  'code': 120.0,
  'type': 120.0,
  'owner': 140.0,
  'location': 120.0,
  'phone': 120.0,
  'notes': 180.0,
  'customIp': 140.0,
  'anydeskId': 120.0,
  'defaultRemote': 160.0,
};

/// Πίνακας εξοπλισμού: mirror του UsersDataTable – checkbox, δυναμικές στήλες, sort, πλήκτρα, focus.
class EquipmentDataTable extends StatefulWidget {
  const EquipmentDataTable({
    super.key,
    required this.items,
    required this.selectedIds,
    required this.sortColumn,
    required this.sortAscending,
    required this.visibleColumns,
    required this.onToggleSelection,
    required this.onSetSort,
    required this.onEditEquipment,
    this.focusedRowIndex,
    this.onSetFocusedRowIndex,
    this.onRequestDelete,
    this.onRequestBulkEdit,
    this.continuousScroll = true,
  });

  final List<EquipmentRow> items;
  final Set<int> selectedIds;
  final EquipmentColumn? sortColumn;
  final bool sortAscending;
  final List<EquipmentColumn> visibleColumns;
  final void Function(int id) onToggleSelection;
  final void Function(EquipmentColumn? column, bool ascending) onSetSort;
  final void Function(EquipmentRow row, {String? focusedField}) onEditEquipment;
  final int? focusedRowIndex;
  final void Function(int? index)? onSetFocusedRowIndex;
  final VoidCallback? onRequestDelete;
  final VoidCallback? onRequestBulkEdit;
  final bool continuousScroll;

  @override
  State<EquipmentDataTable> createState() => _EquipmentDataTableState();
}

class _EquipmentDataTableState extends State<EquipmentDataTable> {
  final _source = _EquipmentTableSource();
  final FocusNode _tableFocusNode = FocusNode();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final Map<String, double> _dataColumnWidths = {};
  int _pagedFirstRowIndex = 0;

  bool get _selectionVisible =>
      widget.visibleColumns.contains(EquipmentColumn.selection);

  double _widthForColumn(EquipmentColumn col) {
    return _dataColumnWidths[col.key] ??
        _defaultWidthsByKey[col.key] ??
        _defaultDataFallbackWidth;
  }

  void _setColumnWidth(int visibleIndex, double width) {
    final col = widget.visibleColumns[visibleIndex];
    final w = width.clamp(_minColumnWidth, _maxColumnWidth);
    setState(() => _dataColumnWidths[col.key] = w);
  }

  int _sortedVisibleColumnIndex() {
    final sc = widget.sortColumn;
    if (sc == null) return -1;
    for (var i = 0; i < widget.visibleColumns.length; i++) {
      if (widget.visibleColumns[i].key == sc.key) return i;
    }
    return -1;
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _tableFocusNode.dispose();
    super.dispose();
  }

  void _onRowTap(int index) {
    widget.onSetFocusedRowIndex?.call(index);
  }

  @override
  void didUpdateWidget(EquipmentDataTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _source.update(
      widget.items,
      widget.selectedIds,
      widget.onToggleSelection,
      widget.onEditEquipment,
      widget.focusedRowIndex,
      _focusHighlightColor,
      _onRowTap,
      widget.visibleColumns,
      _selectionVisible,
      _styleForEmptyOwnerCell(context),
    );
    if (!widget.continuousScroll) {
      _clampPagedFirstRowIndex();
    }
  }

  void _clampPagedFirstRowIndex() {
    final n = widget.items.length;
    if (n == 0) {
      _pagedFirstRowIndex = 0;
      return;
    }
    if (_pagedFirstRowIndex >= n) {
      _pagedFirstRowIndex = ((n - 1) ~/ _rowsPerPage) * _rowsPerPage;
    }
  }

  Color? get _focusHighlightColor =>
      Theme.of(context).colorScheme.surfaceContainerHighest;

  /// Πλάγιο, αχνό κείμενο για placeholder «Χωρίς κάτοχο» (δεν είναι πραγματική εγγραφή).
  TextStyle _styleForEmptyOwnerCell(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium ?? const TextStyle();
    return base.copyWith(
      fontStyle: FontStyle.italic,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final items = widget.items;
    final len = items.length;
    if (len == 0) return KeyEventResult.ignored;
    final onSetFocus = widget.onSetFocusedRowIndex;
    final current = widget.focusedRowIndex;

    if (key == LogicalKeyboardKey.arrowDown) {
      if (onSetFocus != null) {
        final next = current == null ? 0 : (current + 1).clamp(0, len - 1);
        onSetFocus(next);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (onSetFocus != null) {
        final next = current == null ? len - 1 : (current - 1).clamp(0, len - 1);
        onSetFocus(next);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      if (widget.selectedIds.length > 1 && widget.onRequestBulkEdit != null) {
        widget.onRequestBulkEdit!();
      } else {
        final idx = current ?? 0;
        if (idx >= 0 && idx < len) {
          widget.onEditEquipment(items[idx]);
        }
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      if (widget.selectedIds.isNotEmpty) {
        widget.onRequestDelete?.call();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildStickyHeader(
    BuildContext context,
    List<DataColumn> columns,
    double headingHeight,
    Color? headingColor,
    TextStyle headingTextStyle,
    Map<int, TableColumnWidth> columnWidths,
  ) {
    final sortedIndex = _sortedVisibleColumnIndex();
    final asc = widget.sortAscending;
    return Table(
      columnWidths: columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: headingColor ??
                Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          children: [
            for (var i = 0; i < columns.length; i++)
              TableCell(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: columns[i].onSort != null
                              ? () => columns[i].onSort!(
                                  0,
                                  i == sortedIndex ? !asc : true,
                                )
                              : null,
                          child: Container(
                            height: headingHeight,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Expanded(
                                  child: DefaultTextStyle(
                                    style: headingTextStyle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    child: columns[i].label,
                                  ),
                                ),
                                if (i == sortedIndex) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    asc ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    _TableResizeHandle(
                      onResize: (delta) {
                        _setColumnWidth(
                          i,
                          _widthForColumn(widget.visibleColumns[i]) + delta,
                        );
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  TableRow _dataRowToTableRow(
    BuildContext context,
    DataRow dataRow,
  ) {
    final theme = Theme.of(context);
    final dataTableTheme = theme.dataTableTheme;
    final rowColor = dataRow.selected
        ? (dataTableTheme.dataRowColor?.resolve({WidgetState.selected}) ??
            theme.colorScheme.primaryContainer.withValues(alpha: 0.3))
        : dataTableTheme.dataRowColor?.resolve({WidgetState.selected});
    return TableRow(
      decoration: BoxDecoration(color: rowColor),
      children: [
        for (final cell in dataRow.cells)
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: InkWell(
              onTap: cell.onTap,
              onDoubleTap: cell.onDoubleTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: cell.child,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _wrapEquipmentScrollableTable({
    required BuildContext context,
    required ThemeData theme,
    required List<DataColumn> columns,
    required List<DataRow> rows,
    required double maxHeight,
    required Map<int, TableColumnWidth> columnWidths,
    required double tableWidth,
    Widget? bottomBar,
  }) {
    final dataTableTheme = theme.dataTableTheme;
    final headingHeight = dataTableTheme.headingRowHeight ?? 56.0;
    final Color? headingColor =
        (dataTableTheme.headingRowColor ??
                theme.colorScheme.surfaceContainerHighest)
            as Color?;
    final headingTextStyle =
        dataTableTheme.headingTextStyle ?? theme.textTheme.titleSmall!;
    return Scrollbar(
      controller: _verticalScrollController,
      thumbVisibility: true,
      thickness: 12,
      radius: const Radius.circular(10),
      child: SingleChildScrollView(
        controller: _horizontalScrollController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          height: maxHeight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStickyHeader(
                context,
                columns,
                headingHeight,
                headingColor,
                headingTextStyle,
                columnWidths,
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _verticalScrollController,
                  child: Table(
                    columnWidths: columnWidths,
                    defaultVerticalAlignment:
                        TableCellVerticalAlignment.middle,
                    children: [
                      for (final row in rows)
                        _dataRowToTableRow(context, row),
                    ],
                  ),
                ),
              ),
              ?bottomBar,
            ],
          ),
        ),
      ),
    );
  }

  Widget _equipmentPaginationBar(BuildContext context, ThemeData theme) {
    final n = widget.items.length;
    if (n == 0) {
      return Material(
        color: theme.colorScheme.surfaceContainerLowest,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Center(
            child: Text(
              '0 από 0',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }
    final start = _pagedFirstRowIndex;
    final end = (start + _rowsPerPage).clamp(0, n);
    final lastPageStart = ((n - 1) ~/ _rowsPerPage) * _rowsPerPage;

    void goFirst() => setState(() => _pagedFirstRowIndex = 0);
    void goPrev() => setState(
          () => _pagedFirstRowIndex =
              (start - _rowsPerPage).clamp(0, lastPageStart),
        );
    void goNext() => setState(() {
          final next = start + _rowsPerPage;
          if (next < n) _pagedFirstRowIndex = next;
        });
    void goLast() => setState(() => _pagedFirstRowIndex = lastPageStart);

    return Theme(
      data: theme.copyWith(
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: const Size(32, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.all(4),
            visualDensity: VisualDensity.compact,
            iconSize: 20,
          ),
        ),
      ),
      child: Material(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Πρώτη σελίδα',
                icon: const Icon(Icons.first_page),
                onPressed: start > 0 ? goFirst : null,
              ),
              IconButton(
                tooltip: 'Προηγούμενη',
                icon: const Icon(Icons.chevron_left),
                onPressed: start > 0 ? goPrev : null,
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '${start + 1}–$end από $n',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Επόμενη',
                icon: const Icon(Icons.chevron_right),
                onPressed: end < n ? goNext : null,
              ),
              IconButton(
                tooltip: 'Τελευταία σελίδα',
                icon: const Icon(Icons.last_page),
                onPressed: end < n ? goLast : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<DataColumn> _buildEquipmentDataColumns(ThemeData theme) {
    return [
      for (final col in widget.visibleColumns)
        if (col.key == 'selection')
          DataColumn(
            label: _SelectAllCheckbox(
              selectedIds: widget.selectedIds,
              items: widget.items,
              onSelectAll: () {
                for (final row in widget.items) {
                  if (row.$1.id != null &&
                      !widget.selectedIds.contains(row.$1.id)) {
                    widget.onToggleSelection(row.$1.id!);
                  }
                }
              },
              onDeselectAll: () {
                for (final id in widget.selectedIds.toList()) {
                  widget.onToggleSelection(id);
                }
              },
              allSelected: widget.items.isNotEmpty &&
                  widget.items.every((r) =>
                      r.$1.id != null &&
                      widget.selectedIds.contains(r.$1.id)),
            ),
          )
        else
          DataColumn(
            label: Text(
              col.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            onSort: col.sortValue != null
                ? (_, asc) => widget.onSetSort(col, asc)
                : null,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _source.update(
      widget.items,
      widget.selectedIds,
      widget.onToggleSelection,
      widget.onEditEquipment,
      widget.focusedRowIndex,
      _focusHighlightColor,
      _onRowTap,
      widget.visibleColumns,
      _selectionVisible,
      _styleForEmptyOwnerCell(context),
    );

    final columns = _buildEquipmentDataColumns(theme);

    final columnWidths = Map<int, TableColumnWidth>.fromIterables(
      List.generate(columns.length, (i) => i),
      List.generate(
        columns.length,
        (i) => FixedColumnWidth(_widthForColumn(widget.visibleColumns[i])),
      ),
    );
    const columnSpacing = 24.0;
    const horizontalMargin = 16.0;
    final tableWidth = List.generate(
            columns.length,
            (i) => _widthForColumn(widget.visibleColumns[i]))
        .fold<double>(0, (a, b) => a + b) +
        (columns.length - 1) * columnSpacing +
        horizontalMargin * 2;

    return Focus(
      focusNode: _tableFocusNode,
      onKeyEvent: _handleKey,
      child: MouseRegion(
        onEnter: (_) => _tableFocusNode.requestFocus(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final Widget tableContent;
            if (widget.continuousScroll) {
              final rows = <DataRow>[];
              for (var i = 0; i < _source.rowCount; i++) {
                final row = _source.getRow(i);
                if (row != null) rows.add(row);
              }
              tableContent = _wrapEquipmentScrollableTable(
                context: context,
                theme: theme,
                columns: columns,
                rows: rows,
                maxHeight: constraints.maxHeight,
                columnWidths: columnWidths,
                tableWidth: tableWidth,
              );
            } else {
              _clampPagedFirstRowIndex();
              final n = widget.items.length;
              final start = n == 0 ? 0 : _pagedFirstRowIndex;
              final pageRows = <DataRow>[];
              for (var i = start; i < n && i < start + _rowsPerPage; i++) {
                final row = _source.getRow(i);
                if (row != null) pageRows.add(row);
              }
              tableContent = _wrapEquipmentScrollableTable(
                context: context,
                theme: theme,
                columns: columns,
                rows: pageRows,
                maxHeight: constraints.maxHeight,
                columnWidths: columnWidths,
                tableWidth: tableWidth,
                bottomBar: _equipmentPaginationBar(context, theme),
              );
            }
            return tableContent;
          },
        ),
      ),
    );
  }
}

class _TableResizeHandle extends StatefulWidget {
  const _TableResizeHandle({required this.onResize});

  final void Function(double delta) onResize;

  @override
  State<_TableResizeHandle> createState() => _TableResizeHandleState();
}

class _TableResizeHandleState extends State<_TableResizeHandle> {
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

class _SelectAllCheckbox extends StatelessWidget {
  const _SelectAllCheckbox({
    required this.selectedIds,
    required this.items,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.allSelected,
  });

  final Set<int> selectedIds;
  final List<EquipmentRow> items;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;
  final bool allSelected;

  @override
  Widget build(BuildContext context) {
    return Checkbox(
      value: allSelected,
      tristate: true,
      onChanged: (_) {
        if (allSelected) {
          onDeselectAll();
        } else {
          onSelectAll();
        }
      },
    );
  }
}

class _EquipmentTableSource extends DataTableSource {
  List<EquipmentRow> _items = [];
  Set<int> _selectedIds = {};
  void Function(int id)? _onToggleSelection;
  void Function(EquipmentRow row, {String? focusedField})? _onEditEquipment;
  int? _focusedRowIndex;
  Color? _focusHighlightColor;
  void Function(int index)? _onRowTap;
  List<EquipmentColumn> _visibleColumns = [];
  bool _selectionVisible = true;
  TextStyle? _emptyOwnerTextStyle;

  void update(
    List<EquipmentRow> items,
    Set<int> selectedIds,
    void Function(int id) onToggleSelection,
    void Function(EquipmentRow row, {String? focusedField}) onEditEquipment,
    int? focusedRowIndex,
    Color? focusHighlightColor,
    void Function(int index)? onRowTap,
    List<EquipmentColumn> visibleColumns,
    bool selectionVisible,
    TextStyle emptyOwnerTextStyle,
  ) {
    _items = items;
    _selectedIds = selectedIds;
    _onToggleSelection = onToggleSelection;
    _onEditEquipment = onEditEquipment;
    _focusedRowIndex = focusedRowIndex;
    _focusHighlightColor = focusHighlightColor;
    _onRowTap = onRowTap;
    _visibleColumns = visibleColumns;
    _selectionVisible = selectionVisible;
    _emptyOwnerTextStyle = emptyOwnerTextStyle;
    notifyListeners();
  }

  @override
  int get rowCount => _items.length;

  @override
  bool get isRowCountApproximate => false;

  @override
  int get selectedRowCount => _selectedIds.length;

  void _onDoubleTap(EquipmentRow row, String fieldKey) =>
      _onEditEquipment?.call(row, focusedField: fieldKey);

  DataCell _cellForColumn(
    EquipmentRow row,
    int? id,
    bool selected,
    int rowIndex,
    EquipmentColumn col,
  ) {
    switch (col.key) {
      case 'selection':
        return DataCell(
          Checkbox(
            value: selected,
            onChanged: id != null && _onToggleSelection != null
                ? (_) => _onToggleSelection!(id)
                : null,
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(row, 'code'),
        );
      case 'id':
        return DataCell(
          Text(
            id != null ? '$id' : '–',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(row, 'id'),
        );
      default:
        final cellText = col.displayValue(row);
        final isEmptyOwnerPlaceholder = col.key == EquipmentColumn.owner.key &&
            cellText == EquipmentColumn.emptyOwnerDisplayLabel;
        return DataCell(
          Text(
            cellText,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: isEmptyOwnerPlaceholder ? _emptyOwnerTextStyle : null,
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(row, col.key),
        );
    }
  }

  @override
  DataRow? getRow(int index) {
    if (index < 0 || index >= _items.length) return null;
    final row = _items[index];
    final id = row.$1.id;
    final selected =
        _selectionVisible && id != null && _selectedIds.contains(id);
    final focused = index == _focusedRowIndex && _focusHighlightColor != null;
    final cells = <DataCell>[
      for (final col in _visibleColumns)
        _cellForColumn(row, id, selected, index, col),
    ];
    return DataRow(
      selected: selected,
      onSelectChanged: _selectionVisible && id != null && _onToggleSelection != null
          ? (_) => _onToggleSelection!(id)
          : null,
      color: focused
          ? WidgetStateProperty.all(_focusHighlightColor)
          : null,
      cells: cells,
    );
  }
}
