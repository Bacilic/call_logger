import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/category_directory_column.dart';
import '../../models/category_model.dart';

/// Πίνακας κατηγοριών: sort, επιλογή, κύλιση (χωρίς σελιδοποίηση).
class CategoriesDataTable extends StatefulWidget {
  const CategoriesDataTable({
    super.key,
    required this.categories,
    required this.selectedIds,
    required this.sortColumn,
    required this.sortAscending,
    required this.visibleColumns,
    required this.onToggleSelection,
    required this.onSetSort,
    required this.onEditCategory,
    this.focusedRowIndex,
    this.onSetFocusedRowIndex,
    this.onRequestDelete,
    this.onRequestBulkEdit,
  });

  final List<CategoryModel> categories;
  final Set<int> selectedIds;
  final String? sortColumn;
  final bool sortAscending;
  final List<CategoryDirectoryColumn> visibleColumns;
  final void Function(int id) onToggleSelection;
  final void Function(String? column, bool ascending) onSetSort;
  final void Function(CategoryModel c, {String? focusedField}) onEditCategory;
  final int? focusedRowIndex;
  final void Function(int? index)? onSetFocusedRowIndex;
  final VoidCallback? onRequestDelete;
  final VoidCallback? onRequestBulkEdit;

  @override
  State<CategoriesDataTable> createState() => _CategoriesDataTableState();
}

const _minColumnWidth = 40.0;
const _maxColumnWidth = 600.0;
const _defaultWidthsByKey = <String, double>{
  'selection': 52.0,
  'id': 56.0,
  'name': 220.0,
};

class _CategoriesDataTableState extends State<CategoriesDataTable> {
  final _source = _CategoriesTableSource();
  final FocusNode _tableFocusNode = FocusNode();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final Map<String, double> _columnWidths =
      Map<String, double>.from(_defaultWidthsByKey);

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

  bool get _selectionVisible =>
      widget.visibleColumns.contains(CategoryDirectoryColumn.selection);

  double _widthForColumn(CategoryDirectoryColumn col) {
    return _columnWidths[col.key] ??
        _defaultWidthsByKey[col.key] ??
        _defaultDataFallbackWidth;
  }

  static const _defaultDataFallbackWidth = 120.0;

  void _setColumnWidth(int visibleIndex, double width) {
    final col = widget.visibleColumns[visibleIndex];
    final w = width.clamp(_minColumnWidth, _maxColumnWidth);
    setState(() => _columnWidths[col.key] = w);
  }

  @override
  void didUpdateWidget(CategoriesDataTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _source.update(
      widget.categories,
      widget.selectedIds,
      widget.onToggleSelection,
      widget.onEditCategory,
      widget.focusedRowIndex,
      _focusHighlightColor,
      _onRowTap,
      widget.visibleColumns,
      _selectionVisible,
    );
  }

  Color? get _focusHighlightColor =>
      Theme.of(context).colorScheme.surfaceContainerHighest;

  int _sortedVisibleColumnIndex() {
    final sc = widget.sortColumn;
    if (sc == null) return -1;
    for (var i = 0; i < widget.visibleColumns.length; i++) {
      if (widget.visibleColumns[i].sortKey == sc) return i;
    }
    return -1;
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
                                    asc
                                        ? Icons.arrow_drop_up
                                        : Icons.arrow_drop_down,
                                    size: 18,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
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

  TableRow _dataRowToTableRow(BuildContext context, DataRow dataRow) {
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

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final rows = widget.categories;
    final len = rows.length;
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
        final next =
            current == null ? len - 1 : (current - 1).clamp(0, len - 1);
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
          widget.onEditCategory(rows[idx]);
        }
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (widget.selectedIds.isNotEmpty) {
        widget.onRequestDelete?.call();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  List<DataColumn> _buildDataColumns(ThemeData theme) {
    final cols = widget.visibleColumns;
    final list = <DataColumn>[];
    for (final col in cols) {
      if (col == CategoryDirectoryColumn.selection) {
        list.add(
          DataColumn(
            label: _CategorySelectAllCheckbox(
              selectedIds: widget.selectedIds,
              categories: widget.categories,
              onSelectAll: () {
                for (final c in widget.categories) {
                  if (c.id != null && !widget.selectedIds.contains(c.id)) {
                    widget.onToggleSelection(c.id!);
                  }
                }
              },
              onDeselectAll: () {
                for (final id in widget.selectedIds.toList()) {
                  widget.onToggleSelection(id);
                }
              },
              allSelected: widget.categories.isNotEmpty &&
                  widget.categories.every((c) =>
                      c.id != null && widget.selectedIds.contains(c.id)),
            ),
          ),
        );
      } else {
        list.add(
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
            onSort: col.sortKey != null
                ? (_, asc) => widget.onSetSort(col.sortKey!, asc)
                : null,
          ),
        );
      }
    }
    return list;
  }

  Widget _wrapScrollableTable({
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
                dataTableTheme.headingTextStyle ??
                    theme.textTheme.titleSmall!,
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

  @override
  Widget build(BuildContext context) {
    _source.update(
      widget.categories,
      widget.selectedIds,
      widget.onToggleSelection,
      widget.onEditCategory,
      widget.focusedRowIndex,
      _focusHighlightColor,
      _onRowTap,
      widget.visibleColumns,
      _selectionVisible,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final columns = _buildDataColumns(theme);

        final visible = widget.visibleColumns;
        final columnWidths = Map<int, TableColumnWidth>.fromIterables(
          List.generate(visible.length, (i) => i),
          visible.map((c) => FixedColumnWidth(_widthForColumn(c))).toList(),
        );
        const columnSpacing = 24.0;
        const horizontalMargin = 16.0;
        final widthSum =
            visible.fold<double>(0, (a, c) => a + _widthForColumn(c));
        final tableWidth = widthSum +
            (visible.length - 1) * columnSpacing +
            horizontalMargin * 2;

        final rows = <DataRow>[];
        for (var i = 0; i < _source.rowCount; i++) {
          final row = _source.getRow(i);
          if (row != null) rows.add(row);
        }
        final tableContent = _wrapScrollableTable(
          context: context,
          theme: theme,
          columns: columns,
          rows: rows,
          maxHeight: constraints.maxHeight,
          columnWidths: columnWidths,
          tableWidth: tableWidth,
        );

        return Focus(
          focusNode: _tableFocusNode,
          onKeyEvent: _handleKey,
          child: MouseRegion(
            onEnter: (_) => _tableFocusNode.requestFocus(),
            child: tableContent,
          ),
        );
      },
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

class _CategorySelectAllCheckbox extends StatelessWidget {
  const _CategorySelectAllCheckbox({
    required this.selectedIds,
    required this.categories,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.allSelected,
  });

  final Set<int> selectedIds;
  final List<CategoryModel> categories;
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

class _CategoriesTableSource extends DataTableSource {
  List<CategoryModel> _categories = [];
  Set<int> _selectedIds = {};
  void Function(int id)? _onToggleSelection;
  void Function(CategoryModel c, {String? focusedField})? _onEditCategory;
  int? _focusedRowIndex;
  Color? _focusHighlightColor;
  void Function(int index)? _onRowTap;
  List<CategoryDirectoryColumn> _visibleColumns = [];
  bool _selectionVisible = true;

  void update(
    List<CategoryModel> categories,
    Set<int> selectedIds,
    void Function(int id) onToggleSelection,
    void Function(CategoryModel c, {String? focusedField}) onEditCategory,
    int? focusedRowIndex,
    Color? focusHighlightColor,
    void Function(int index)? onRowTap,
    List<CategoryDirectoryColumn> visibleColumns,
    bool selectionVisible,
  ) {
    _categories = categories;
    _selectedIds = selectedIds;
    _onToggleSelection = onToggleSelection;
    _onEditCategory = onEditCategory;
    _focusedRowIndex = focusedRowIndex;
    _focusHighlightColor = focusHighlightColor;
    _onRowTap = onRowTap;
    _visibleColumns = visibleColumns;
    _selectionVisible = selectionVisible;
    notifyListeners();
  }

  @override
  int get rowCount => _categories.length;

  @override
  bool get isRowCountApproximate => false;

  @override
  int get selectedRowCount => _selectedIds.length;

  void _onDoubleTap(CategoryModel c, CategoryDirectoryColumn col) =>
      _onEditCategory?.call(c, focusedField: col.editFocusField);

  DataCell _cellForColumn(
    CategoryModel c,
    int? id,
    bool selected,
    int rowIndex,
    CategoryDirectoryColumn col,
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
          onDoubleTap: () => _onDoubleTap(c, col),
        );
      case 'id':
        return DataCell(
          Text(
            '${id ?? ''}',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(c, col),
        );
      case 'name':
        return DataCell(
          Text(
            c.name,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(c, col),
        );
      default:
        return DataCell(
          const SizedBox.shrink(),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(c, col),
        );
    }
  }

  @override
  DataRow? getRow(int index) {
    if (index < 0 || index >= _categories.length) return null;
    final c = _categories[index];
    final id = c.id;
    final selected =
        _selectionVisible && id != null && _selectedIds.contains(id);
    final focused = index == _focusedRowIndex && _focusHighlightColor != null;
    final cells = <DataCell>[
      for (final col in _visibleColumns)
        _cellForColumn(c, id, selected, index, col),
    ];
    return DataRow(
      selected: selected,
      onSelectChanged: _selectionVisible && id != null && _onToggleSelection != null
          ? (_) => _onToggleSelection!(id)
          : null,
      color: focused ? WidgetStateProperty.all(_focusHighlightColor) : null,
      cells: cells,
    );
  }
}
