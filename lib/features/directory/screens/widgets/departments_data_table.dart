import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/models/building_map_floor.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/utils/department_display_utils.dart';
import '../../models/department_directory_column.dart';
import '../../models/department_floor_display_extension.dart';
import '../../models/department_model.dart';

/// Πίνακας τμημάτων: sort, επιλογή, πληκτρολόγιο όπως οι χρήστες.
class DepartmentsDataTable extends StatefulWidget {
  const DepartmentsDataTable({
    super.key,
    required this.departments,
    required this.selectedIds,
    required this.sortColumn,
    required this.sortAscending,
    required this.visibleColumns,
    required this.onToggleSelection,
    required this.onSetSort,
    required this.onEditDepartment,
    this.focusedRowIndex,
    this.onSetFocusedRowIndex,
    this.onRequestDelete,
    this.onRequestBulkEdit,
    this.continuousScroll = true,
    this.floorsById = const {},
  });

  /// Ετικέτες από `building_map_floors` ανά id· για υπότιτλο στήλης κτιρίου/ορόφου.
  final Map<int, BuildingMapFloor> floorsById;
  final List<DepartmentModel> departments;
  final Set<int> selectedIds;
  final String? sortColumn;
  final bool sortAscending;
  final List<DepartmentDirectoryColumn> visibleColumns;
  final void Function(int id) onToggleSelection;
  final void Function(String? column, bool ascending) onSetSort;
  final void Function(DepartmentModel d, {String? focusedField}) onEditDepartment;
  final int? focusedRowIndex;
  final void Function(int? index)? onSetFocusedRowIndex;
  final VoidCallback? onRequestDelete;
  final VoidCallback? onRequestBulkEdit;
  final bool continuousScroll;

  @override
  State<DepartmentsDataTable> createState() => _DepartmentsDataTableState();
}

const _minColumnWidth = 40.0;
const _maxColumnWidth = 600.0;
const _rowsPerPage = 15;

const _defaultWidthsByKey = <String, double>{
  'selection': 52.0,
  'id': 56.0,
  'name': 180.0,
  'building': 120.0,
  'color': 56.0,
  'phones': 140.0,
  'equipment': 140.0,
  'notes': 180.0,
};

Color? _parseHexColor(String? s) {
  if (s == null) return null;
  var h = s.trim();
  if (h.isEmpty) return null;
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) {
    final v = int.tryParse(h, radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  return null;
}

class _DepartmentsDataTableState extends State<DepartmentsDataTable> {
  final _source = _DepartmentsTableSource();
  final FocusNode _tableFocusNode = FocusNode();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final Map<String, double> _columnWidths =
      Map<String, double>.from(_defaultWidthsByKey);
  int _pagedFirstRowIndex = 0;

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
      widget.visibleColumns.contains(DepartmentDirectoryColumn.selection);

  double _widthForColumn(DepartmentDirectoryColumn col) {
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
  void didUpdateWidget(DepartmentsDataTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    final theme = Theme.of(context);
    _source.update(
      widget.departments,
      widget.selectedIds,
      widget.onToggleSelection,
      widget.onEditDepartment,
      widget.focusedRowIndex,
      _focusHighlightColor,
      _onRowTap,
      widget.visibleColumns,
      _selectionVisible,
      widget.floorsById,
      theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    if (!widget.continuousScroll) {
      _clampPagedFirstRowIndex();
    }
  }

  void _clampPagedFirstRowIndex() {
    final n = widget.departments.length;
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
    final rows = widget.departments;
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
          widget.onEditDepartment(rows[idx]);
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
      if (col == DepartmentDirectoryColumn.selection) {
        list.add(
          DataColumn(
            label: _DepartmentSelectAllCheckbox(
              selectedIds: widget.selectedIds,
              departments: widget.departments,
              onSelectAll: () {
                for (final d in widget.departments) {
                  if (d.id != null && !widget.selectedIds.contains(d.id)) {
                    widget.onToggleSelection(d.id!);
                  }
                }
              },
              onDeselectAll: () {
                for (final id in widget.selectedIds.toList()) {
                  widget.onToggleSelection(id);
                }
              },
              allSelected: widget.departments.isNotEmpty &&
                  widget.departments.every((d) =>
                      d.id != null && widget.selectedIds.contains(d.id)),
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

  Widget _paginationBar(BuildContext context, ThemeData theme) {
    final n = widget.departments.length;
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

  @override
  Widget build(BuildContext context) {
    final themeForSource = Theme.of(context);
    _source.update(
      widget.departments,
      widget.selectedIds,
      widget.onToggleSelection,
      widget.onEditDepartment,
      widget.focusedRowIndex,
      _focusHighlightColor,
      _onRowTap,
      widget.visibleColumns,
      _selectionVisible,
      widget.floorsById,
      themeForSource.textTheme.bodySmall?.copyWith(
        color: themeForSource.colorScheme.onSurfaceVariant,
      ),
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

        final Widget tableContent;
        if (widget.continuousScroll) {
          final rows = <DataRow>[];
          for (var i = 0; i < _source.rowCount; i++) {
            final row = _source.getRow(i);
            if (row != null) rows.add(row);
          }
          tableContent = _wrapScrollableTable(
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
          final n = widget.departments.length;
          final start = n == 0 ? 0 : _pagedFirstRowIndex;
          final pageRows = <DataRow>[];
          for (var i = start; i < n && i < start + _rowsPerPage; i++) {
            final row = _source.getRow(i);
            if (row != null) pageRows.add(row);
          }
          tableContent = _wrapScrollableTable(
            context: context,
            theme: theme,
            columns: columns,
            rows: pageRows,
            maxHeight: constraints.maxHeight,
            columnWidths: columnWidths,
            tableWidth: tableWidth,
            bottomBar: _paginationBar(context, theme),
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

class _DepartmentSelectAllCheckbox extends StatelessWidget {
  const _DepartmentSelectAllCheckbox({
    required this.selectedIds,
    required this.departments,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.allSelected,
  });

  final Set<int> selectedIds;
  final List<DepartmentModel> departments;
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

class _DepartmentsTableSource extends DataTableSource {
  List<DepartmentModel> _departments = [];
  Set<int> _selectedIds = {};
  void Function(int id)? _onToggleSelection;
  void Function(DepartmentModel d, {String? focusedField})? _onEditDepartment;
  int? _focusedRowIndex;
  Color? _focusHighlightColor;
  void Function(int index)? _onRowTap;
  List<DepartmentDirectoryColumn> _visibleColumns = [];
  bool _selectionVisible = true;
  Map<int, BuildingMapFloor> _floorsById = {};
  TextStyle? _secondaryMetaStyle;

  String _phonesTextForDepartment(DepartmentModel d) {
    final id = d.id;
    if (id == null) return '';
    final phones = LookupService.instance.getPhonesByDepartment(id);
    return phones.join(', ');
  }

  String _equipmentTextForDepartment(DepartmentModel d) {
    final id = d.id;
    if (id == null) return '';
    final equipment = LookupService.instance.getAllEquipmentByDepartment(id);
    final labels = equipment
        .map((e) {
          final code = e.code?.trim();
          if (code != null && code.isNotEmpty) return code;
          return e.displayLabel.trim();
        })
        .where((v) => v.isNotEmpty)
        .toList();
    return labels.join(', ');
  }

  void update(
    List<DepartmentModel> departments,
    Set<int> selectedIds,
    void Function(int id) onToggleSelection,
    void Function(DepartmentModel d, {String? focusedField}) onEditDepartment,
    int? focusedRowIndex,
    Color? focusHighlightColor,
    void Function(int index)? onRowTap,
    List<DepartmentDirectoryColumn> visibleColumns,
    bool selectionVisible,
    Map<int, BuildingMapFloor> floorsById,
    TextStyle? secondaryMetaStyle,
  ) {
    _departments = departments;
    _selectedIds = selectedIds;
    _onToggleSelection = onToggleSelection;
    _onEditDepartment = onEditDepartment;
    _focusedRowIndex = focusedRowIndex;
    _focusHighlightColor = focusHighlightColor;
    _onRowTap = onRowTap;
    _visibleColumns = visibleColumns;
    _selectionVisible = selectionVisible;
    _floorsById = floorsById;
    _secondaryMetaStyle = secondaryMetaStyle;
    notifyListeners();
  }

  @override
  int get rowCount => _departments.length;

  @override
  bool get isRowCountApproximate => false;

  @override
  int get selectedRowCount => _selectedIds.length;

  void _onDoubleTap(DepartmentModel d, DepartmentDirectoryColumn col) =>
      _onEditDepartment?.call(d, focusedField: col.editFocusField);

  String _displayName(DepartmentModel d) {
    if (d.isDeleted) {
      return '${d.name}$kDepartmentDeletedDisplaySuffix';
    }
    return d.name;
  }

  DataCell _cellForColumn(
    DepartmentModel d,
    int? id,
    bool selected,
    int rowIndex,
    DepartmentDirectoryColumn col,
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
          onDoubleTap: () => _onDoubleTap(d, col),
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
          onDoubleTap: () => _onDoubleTap(d, col),
        );
      case 'name':
        return DataCell(
          Text(
            _displayName(d),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(d, col),
        );
      case 'building':
        final floorTxt = d.floorDisplayWithCatalog(_floorsById);
        return DataCell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                d.building ?? '',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
              if (floorTxt != null && floorTxt.isNotEmpty)
                Text(
                  floorTxt,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: _secondaryMetaStyle,
                ),
            ],
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(d, col),
        );
      case 'color':
        final parsed = _parseHexColor(d.color);
        return DataCell(
          Align(
            alignment: Alignment.centerLeft,
            child: parsed != null
                ? Tooltip(
                    message: d.color ?? '',
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: parsed,
                          border: Border.all(color: Colors.black26),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(d, col),
        );
      case 'notes':
        return DataCell(
          Text(
            d.notes ?? '',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(d, col),
        );
      case 'phones':
        return DataCell(
          Text(
            _phonesTextForDepartment(d),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(d, col),
        );
      case 'equipment':
        return DataCell(
          Text(
            _equipmentTextForDepartment(d),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(d, col),
        );
      default:
        return DataCell(
          const SizedBox.shrink(),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(d, col),
        );
    }
  }

  @override
  DataRow? getRow(int index) {
    if (index < 0 || index >= _departments.length) return null;
    final d = _departments[index];
    final id = d.id;
    final selected =
        _selectionVisible && id != null && _selectedIds.contains(id);
    final focused = index == _focusedRowIndex && _focusHighlightColor != null;
    final cells = <DataCell>[
      for (final col in _visibleColumns)
        _cellForColumn(d, id, selected, index, col),
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
