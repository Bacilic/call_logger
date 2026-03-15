// Προσωρινή χρήση DataTable – σε επόμενη φάση εξέτασε custom Table για sticky headers & row selection.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/equipment_column.dart';

const _minColumnWidth = 40.0;
const _maxColumnWidth = 600.0;
const _defaultDataColumnWidth = 120.0;
const _defaultCheckboxColumnWidth = 52.0;

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
  double _checkboxColumnWidth = _defaultCheckboxColumnWidth;
  final Map<String, double> _dataColumnWidths = {};

  double _getColumnWidth(int index) {
    if (index == 0) return _checkboxColumnWidth;
    final col = widget.visibleColumns[index - 1];
    return _dataColumnWidths[col.key] ?? _defaultDataColumnWidth;
  }

  void _setColumnWidth(int index, double width) {
    final w = width.clamp(_minColumnWidth, _maxColumnWidth);
    if (index == 0) {
      setState(() => _checkboxColumnWidth = w);
    } else {
      setState(() => _dataColumnWidths[widget.visibleColumns[index - 1].key] = w);
    }
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
    );
  }

  Color? get _focusHighlightColor =>
      Theme.of(context).colorScheme.surfaceContainerHighest;

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
    final sortedCol = widget.sortColumn;
    final asc = widget.sortAscending;
    final sortedIndex = sortedCol != null
        ? widget.visibleColumns.indexOf(sortedCol) + 1
        : -1;
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
                              horizontal: 16,
                              vertical: 12,
                            ),
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Expanded(
                                  child: DefaultTextStyle(
                                    style: headingTextStyle,
                                    child: columns[i].label,
                                  ),
                                ),
                                if (i == sortedIndex) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    asc ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                                    size: 20,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (i < columns.length - 1)
                      _TableResizeHandle(
                        onResize: (delta) {
                          _setColumnWidth(
                            i,
                            _getColumnWidth(i) + delta,
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
                  horizontal: 16,
                  vertical: 12,
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
    );

    final columns = <DataColumn>[
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
                  r.$1.id != null && widget.selectedIds.contains(r.$1.id)),
        ),
      ),
      ...widget.visibleColumns.map(
        (col) => DataColumn(
          label: Text(
            col.label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          onSort: col.sortValue != null
              ? (_, asc) => widget.onSetSort(col, asc)
              : null,
        ),
      ),
    ];

    final rows = <DataRow>[];
    for (var i = 0; i < _source.rowCount; i++) {
      final row = _source.getRow(i);
      if (row != null) rows.add(row);
    }

    final columnWidths = Map<int, TableColumnWidth>.fromIterables(
      List.generate(columns.length, (i) => i),
      List.generate(columns.length, (i) => FixedColumnWidth(_getColumnWidth(i))),
    );
    const columnSpacing = 24.0;
    const horizontalMargin = 16.0;
    final tableWidth = List.generate(columns.length, (i) => _getColumnWidth(i))
            .fold<double>(0, (a, b) => a + b) +
        (columns.length - 1) * columnSpacing +
        horizontalMargin * 2;

    final Widget tableContent;
    if (widget.continuousScroll) {
      final dataTableTheme = theme.dataTableTheme;
      final headingHeight = dataTableTheme.headingRowHeight ?? 56.0;
      final Color? headingColor =
          (dataTableTheme.headingRowColor ??
                  theme.colorScheme.surfaceContainerHighest)
              as Color?;
      final headingTextStyle =
          dataTableTheme.headingTextStyle ?? theme.textTheme.titleSmall!;
      tableContent = LayoutBuilder(
        builder: (context, constraints) {
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
                height: constraints.maxHeight,
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
                  ],
                ),
              ),
            ),
          );
        },
      );
    } else {
      tableContent = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SizedBox(
            width: tableWidth,
            child: PaginatedDataTable(
              showCheckboxColumn: false,
              columns: columns,
              source: _source,
              rowsPerPage: 15,
              showFirstLastButtons: true,
              columnSpacing: 24,
              horizontalMargin: 16,
            ),
          ),
        ),
      );
    }

    return Focus(
      focusNode: _tableFocusNode,
      onKeyEvent: _handleKey,
      child: MouseRegion(
        onEnter: (_) => _tableFocusNode.requestFocus(),
        child: tableContent,
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

  void update(
    List<EquipmentRow> items,
    Set<int> selectedIds,
    void Function(int id) onToggleSelection,
    void Function(EquipmentRow row, {String? focusedField}) onEditEquipment,
    int? focusedRowIndex,
    Color? focusHighlightColor,
    void Function(int index)? onRowTap,
    List<EquipmentColumn> visibleColumns,
  ) {
    _items = items;
    _selectedIds = selectedIds;
    _onToggleSelection = onToggleSelection;
    _onEditEquipment = onEditEquipment;
    _focusedRowIndex = focusedRowIndex;
    _focusHighlightColor = focusHighlightColor;
    _onRowTap = onRowTap;
    _visibleColumns = visibleColumns;
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

  @override
  DataRow? getRow(int index) {
    if (index < 0 || index >= _items.length) return null;
    final row = _items[index];
    final id = row.$1.id;
    final selected = id != null && _selectedIds.contains(id);
    final focused = index == _focusedRowIndex && _focusHighlightColor != null;
    return DataRow(
      selected: selected,
      onSelectChanged: id != null && _onToggleSelection != null
          ? (_) => _onToggleSelection!(id)
          : null,
      color: focused
          ? WidgetStateProperty.all(_focusHighlightColor)
          : null,
      cells: [
        DataCell(
          Checkbox(
            value: selected,
            onChanged: id != null && _onToggleSelection != null
                ? (_) => _onToggleSelection!(id)
                : null,
          ),
          onTap: () => _onRowTap?.call(index),
          onDoubleTap: () => _onDoubleTap(row, 'code'),
        ),
        ..._visibleColumns.map(
          (col) => DataCell(
            Text(
              col.displayValue(row),
              softWrap: true,
              overflow: TextOverflow.visible,
            ),
            onTap: () => _onRowTap?.call(index),
            onDoubleTap: () => _onDoubleTap(row, col.key),
          ),
        ),
      ],
    );
  }
}
