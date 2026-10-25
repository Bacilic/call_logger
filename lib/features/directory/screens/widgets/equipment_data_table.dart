// ΑΞΙΟΛΟΓΗΘΗΚΕ ΓΙΑ ΔΙΑΣΠΑΣΗ — ΜΕΝΕΙ ΩΣ ΕΧΕΙ (11/10/2026).
//
// Ρόλος: ένας — πώς φαίνεται και πώς χειρίζεται κανείς τον πίνακα του
// εξοπλισμού: σταθερή κεφαλίδα με ταξινόμηση και πλάτη στηλών, γραμμές με
// επιλογή/εστίαση/διπλό κλικ, πλήκτρα, σελίδες ή συνεχής κύλιση.
//
// Γιατί δεν διασπάστηκε: όλα απαντούν στο ίδιο ερώτημα, και μοιράζονται την
// ίδια κατάσταση (πλάτη στηλών, τρέχουσα σελίδα, εστίαση). Το περιεχόμενο των
// κελιών το αποφασίζει ήδη το μοντέλο των στηλών, σε άλλο αρχείο.
//
// Τι θα το άλλαζε: ερώτημα βάσης, κανόνας επιχείρησης ή υπολογισμός πάνω στα
// δεδομένα μέσα σε αυτό το αρχείο — τότε ξαναξετάζεται από την αρχή.
//
// Γνωστό, εκτός αρχείου: ο σκελετός του πίνακα (κεφαλίδα, γραμμές, λαβή
// πλάτους, πλήκτρα, σελίδες) υπάρχει πανομοιότυπος και στους πίνακες
// Υπαλλήλων, Τμημάτων και Κατηγοριών — καταγεγραμμένο στο roadmap ως κοινή
// δουλειά των τεσσάρων, όχι ως διάσπαση αυτού.

import 'package:flutter/material.dart';

import '../../../../core/services/default_remote_tool_display.dart';
import '../../models/equipment_column.dart';
import '../../../../core/widgets/keyboard_row_navigation.dart';
import '../../../../core/widgets/row_navigation_logic.dart';
import 'catalog_select_all_checkbox.dart';
import 'catalog_table_chrome.dart';
import 'catalog_table_support.dart';

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
  'remoteParams': 220.0,
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
    this.showBuildingInLocationColumn = true,
    this.focusedRowIndex,
    this.onSetFocusedRowIndex,
    this.onRequestDelete,
    this.onRequestBulkEdit,
    this.continuousScroll = true,
    this.defaultRemoteDisplay,
  });

  final List<EquipmentRow> items;
  final Set<int> selectedIds;
  final EquipmentColumn? sortColumn;
  final bool sortAscending;
  final List<EquipmentColumn> visibleColumns;
  final void Function(int id) onToggleSelection;
  final void Function(EquipmentColumn? column, bool ascending) onSetSort;
  final void Function(EquipmentRow row, {String? focusedField}) onEditEquipment;

  /// Συμβατό με [EquipmentDirectoryState.showBuildingInLocationColumn].
  final bool showBuildingInLocationColumn;
  final int? focusedRowIndex;
  final void Function(int? index)? onSetFocusedRowIndex;
  final VoidCallback? onRequestDelete;
  final VoidCallback? onRequestBulkEdit;
  final bool continuousScroll;

  /// Όταν δίνεται, επίλυση id → όνομα και στυλ για ανενεργά/διαγραμμένα εργαλεία.
  final DefaultRemoteToolDisplay Function(EquipmentRow row)?
  defaultRemoteDisplay;

  @override
  State<EquipmentDataTable> createState() => _EquipmentDataTableState();
}

class _EquipmentDataTableState extends State<EquipmentDataTable> {
  final _source = _EquipmentTableSource();
  final RowKeys _rowKeys = RowKeys();
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
    super.dispose();
  }

  void _onRowTap(int index) {
    widget.onSetFocusedRowIndex?.call(index);
  }

  /// Το id της γραμμής [index], ή `null` αν δεν υπάρχει (π.χ. η λίστα μίκρυνε).
  int? _rowIdAt(int? index) =>
      catalogRowIdAt(widget.items, index, (row) => row.$1.id);

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
      widget.showBuildingInLocationColumn,
      widget.defaultRemoteDisplay,
      Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontStyle: FontStyle.italic,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
    if (!widget.continuousScroll) {
      final focus = widget.focusedRowIndex;
      if (focus != null &&
          focus != oldWidget.focusedRowIndex &&
          focus >= 0 &&
          focus < widget.items.length) {
        _pagedFirstRowIndex = pageStartShowingRow(
          focusedRow: focus,
          pageSize: _rowsPerPage,
          currentStart: _pagedFirstRowIndex,
        );
      }
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
      _pagedFirstRowIndex = lastPageStart(count: n, pageSize: _rowsPerPage);
    }
  }

  Color? get _focusHighlightColor => catalogFocusedRowColor(context);

  /// Πλάγιο, αχνό κείμενο για placeholder «Χωρίς κάτοχο» (δεν είναι πραγματική εγγραφή).
  TextStyle _styleForEmptyOwnerCell(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium ?? const TextStyle();
    return base.copyWith(
      fontStyle: FontStyle.italic,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
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
    int firstRowIndex = 0,
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
              CatalogStickyHeader(
                columns: columns,
                headingHeight: headingHeight,
                headingColor: headingColor,
                headingTextStyle: headingTextStyle,
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

  List<DataColumn> _buildEquipmentDataColumns(ThemeData theme) {
    return [
      for (final col in widget.visibleColumns)
        if (col.key == 'selection')
          DataColumn(
            label: CatalogSelectAllCheckbox(
              visibleIds: [
                for (final row in widget.items)
                  if (row.$1.id != null) row.$1.id!,
              ],
              selectedIds: widget.selectedIds,
              onToggleSelection: widget.onToggleSelection,
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
      widget.showBuildingInLocationColumn,
      widget.defaultRemoteDisplay,
      theme.textTheme.bodyMedium?.copyWith(
        fontStyle: FontStyle.italic,
        color: theme.colorScheme.onSurfaceVariant,
      ),
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
    final tableWidth =
        List.generate(
          columns.length,
          (i) => _widthForColumn(widget.visibleColumns[i]),
        ).fold<double>(0, (a, b) => a + b) +
        (columns.length - 1) * columnSpacing +
        horizontalMargin * 2;

    _rowKeys.retainFirst(widget.items.length);
    return KeyboardRowNavigation(
      rowCount: widget.items.length,
      focusedRowIndex: widget.focusedRowIndex,
      onFocusRow: (i) => widget.onSetFocusedRowIndex?.call(i),
      pageStep: widget.continuousScroll ? kDefaultRowPageStep : _rowsPerPage,
      onRevealRow: (i, {required movingDown}) =>
          _rowKeys.reveal(i, movingDown: movingDown),
      onOpen: (focused) => catalogOpenFromKeyboard<EquipmentRow>(
        rows: widget.items,
        focusedIndex: focused,
        selectedCount: widget.selectedIds.length,
        onBulkEdit: widget.onRequestBulkEdit,
        onEdit: widget.onEditEquipment,
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
              firstRowIndex: start,
              bottomBar: CatalogPaginationBar(
                rowCount: widget.items.length,
                firstRowIndex: _pagedFirstRowIndex,
                pageSize: _rowsPerPage,
                onFirstRowIndexChanged: (start) =>
                    setState(() => _pagedFirstRowIndex = start),
              ),
            );
          }
          return tableContent;
        },
      ),
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
  bool _showBuildingInLocationColumn = true;
  DefaultRemoteToolDisplay Function(EquipmentRow row)? _defaultRemoteDisplay;
  TextStyle? _defaultRemoteMutedStyle;

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
    bool showBuildingInLocationColumn,
    DefaultRemoteToolDisplay Function(EquipmentRow row)? defaultRemoteDisplay,
    TextStyle? defaultRemoteMutedStyle,
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
    _showBuildingInLocationColumn = showBuildingInLocationColumn;
    _defaultRemoteDisplay = defaultRemoteDisplay;
    _defaultRemoteMutedStyle = defaultRemoteMutedStyle;
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
        if (col.key == EquipmentColumn.defaultRemote.key &&
            _defaultRemoteDisplay != null) {
          final d = _defaultRemoteDisplay!(row);
          return DataCell(
            Text(
              d.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: d.useMutedItalic ? _defaultRemoteMutedStyle : null,
            ),
            onTap: () => _onRowTap?.call(rowIndex),
            onDoubleTap: () => _onDoubleTap(row, col.key),
          );
        }
        final cellText = col.key == EquipmentColumn.location.key
            ? equipmentRowLocationFormattedLine(
                row,
                showBuilding: _showBuildingInLocationColumn,
              )
            : col.displayValue(row);
        final isEmptyOwnerPlaceholder =
            col.key == EquipmentColumn.owner.key &&
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
      onSelectChanged:
          _selectionVisible && id != null && _onToggleSelection != null
          ? (_) => _onToggleSelection!(id)
          : null,
      color: focused ? WidgetStateProperty.all(_focusHighlightColor) : null,
      cells: cells,
    );
  }
}
