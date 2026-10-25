import 'package:flutter/material.dart';

import '../../models/category_directory_column.dart';
import '../../models/category_model.dart';
import '../../../../core/widgets/keyboard_row_navigation.dart';
import '../../../../core/widgets/row_navigation_logic.dart';
import 'catalog_select_all_checkbox.dart';
import 'catalog_table_chrome.dart';
import 'catalog_table_support.dart';

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
  final RowKeys _rowKeys = RowKeys();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final Map<String, double> _columnWidths = Map<String, double>.from(
    _defaultWidthsByKey,
  );

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
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

  /// Το id της γραμμής [index], ή `null` αν δεν υπάρχει (π.χ. η λίστα μίκρυνε).
  int? _rowIdAt(int? index) =>
      catalogRowIdAt(widget.categories, index, (c) => c.id);

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

  Color? get _focusHighlightColor => catalogFocusedRowColor(context);

  int _sortedVisibleColumnIndex() {
    final sc = widget.sortColumn;
    if (sc == null) return -1;
    for (var i = 0; i < widget.visibleColumns.length; i++) {
      if (widget.visibleColumns[i].sortKey == sc) return i;
    }
    return -1;
  }

  List<DataColumn> _buildDataColumns(ThemeData theme) {
    final cols = widget.visibleColumns;
    final list = <DataColumn>[];
    for (final col in cols) {
      if (col == CategoryDirectoryColumn.selection) {
        list.add(
          DataColumn(
            label: CatalogSelectAllCheckbox(
              visibleIds: [
                for (final c in widget.categories)
                  if (c.id != null) c.id!,
              ],
              selectedIds: widget.selectedIds,
              onToggleSelection: widget.onToggleSelection,
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
    int firstRowIndex = 0,
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
              CatalogStickyHeader(
                columns: columns,
                headingHeight: headingHeight,
                headingColor: headingColor,
                headingTextStyle:
                    dataTableTheme.headingTextStyle ??
                    theme.textTheme.titleSmall!,
                columnWidths: columnWidths,
                sortedIndex: _sortedVisibleColumnIndex(),
                sortAscending: widget.sortAscending,
                onResizeColumn: (i, delta) => _setColumnWidth(
                  i,
                  _widthForColumn(widget.visibleColumns[i]) + delta,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _verticalScrollController,
                  child: Table(
                    columnWidths: columnWidths,
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      for (var i = 0; i < rows.length; i++)
                        catalogTableRow(
                          context,
                          rows[i],
                          rowKey: _rowKeys.keyFor(firstRowIndex + i),
                        ),
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
        final widthSum = visible.fold<double>(
          0,
          (a, c) => a + _widthForColumn(c),
        );
        final tableWidth =
            widthSum +
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

        _rowKeys.retainFirst(widget.categories.length);
        return KeyboardRowNavigation(
          rowCount: widget.categories.length,
          focusedRowIndex: widget.focusedRowIndex,
          onFocusRow: (i) => widget.onSetFocusedRowIndex?.call(i),
          pageStep: kDefaultRowPageStep,
          onRevealRow: (i, {required movingDown}) =>
              _rowKeys.reveal(i, movingDown: movingDown),
          onOpen: (focused) => catalogOpenFromKeyboard<CategoryModel>(
            rows: widget.categories,
            focusedIndex: focused,
            selectedCount: widget.selectedIds.length,
            onBulkEdit: widget.onRequestBulkEdit,
            onEdit: widget.onEditCategory,
          ),
          onToggleRow: (i) {
            final id = _rowIdAt(i);
            if (id != null) widget.onToggleSelection(id);
          },
          onDelete: (focused) => catalogDeleteFromKeyboard(
            selectedIds: widget.selectedIds,
            focusedId: _rowIdAt(focused),
            onToggleSelection: widget.onToggleSelection,
            onRequestDelete: widget.onRequestDelete,
          ),
          child: tableContent,
        );
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
      onSelectChanged:
          _selectionVisible && id != null && _onToggleSelection != null
          ? (_) => _onToggleSelection!(id)
          : null,
      color: focused ? WidgetStateProperty.all(_focusHighlightColor) : null,
      cells: cells,
    );
  }
}
