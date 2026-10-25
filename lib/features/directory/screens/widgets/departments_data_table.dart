// ΑΞΙΟΛΟΓΗΘΗΚΕ ΓΙΑ ΔΙΑΣΠΑΣΗ — ΜΕΝΕΙ ΩΣ ΕΧΕΙ (11/10/2026).
//
// Ρόλος: ένας — πώς φαίνεται και πώς χειρίζεται κανείς τον πίνακα των
// τμημάτων: σταθερή κεφαλίδα με ταξινόμηση και πλάτη στηλών, γραμμές με
// επιλογή/εστίαση/διπλό κλικ, πλήκτρα, σελίδες ή συνεχής κύλιση, και τα κελιά
// του τμήματος (κτίριο/όροφος, χρώμα, τηλέφωνα, εξοπλισμός).
//
// Γιατί δεν διασπάστηκε: όλα απαντούν στο ίδιο ερώτημα, και μοιράζονται την
// ίδια κατάσταση (πλάτη στηλών, τρέχουσα σελίδα, εστίαση). Τηλέφωνα και
// εξοπλισμός διαβάζονται από τον κατάλογο στη μνήμη, όχι από τη βάση.
//
// Τι θα το άλλαζε: ερώτημα βάσης, κανόνας επιχείρησης ή υπολογισμός πάνω στα
// δεδομένα μέσα σε αυτό το αρχείο — τότε ξαναξετάζεται από την αρχή.
//
// Γνωστό: η μετατροπή χρώματος και ο κανόνας «κωδικός εξοπλισμού, αλλιώς
// ετικέτα» είναι αντίγραφα κανόνων που ζουν ήδη αλλού· ο σκελετός του πίνακα
// είναι κοινός με Υπαλλήλους/Κατηγορίες/Εξοπλισμό και έχει ήδη αποκλίνει.
// Καταγεγραμμένα στο roadmap.

import 'package:flutter/material.dart';

import '../../../../core/models/building_map_floor.dart';
import '../../../../core/services/lookup_service.dart';
import '../../models/department_directory_column.dart';
import '../../models/department_floor_display_extension.dart';
import '../../models/department_model.dart';
import '../../../../core/widgets/keyboard_row_navigation.dart';
import '../../../../core/widgets/row_navigation_logic.dart';
import '../../services/user_equipment_codes.dart';
import 'catalog_select_all_checkbox.dart';
import 'catalog_table_chrome.dart';
import 'catalog_table_support.dart';
import 'department_color_palette.dart';

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
  final void Function(DepartmentModel d, {String? focusedField})
  onEditDepartment;
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

class _DepartmentsDataTableState extends State<DepartmentsDataTable> {
  final _source = _DepartmentsTableSource();
  final RowKeys _rowKeys = RowKeys();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final Map<String, double> _columnWidths = Map<String, double>.from(
    _defaultWidthsByKey,
  );
  int _pagedFirstRowIndex = 0;

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

  /// Το id της γραμμής [index], ή `null` αν δεν υπάρχει (π.χ. η λίστα μίκρυνε).
  int? _rowIdAt(int? index) =>
      catalogRowIdAt(widget.departments, index, (d) => d.id);

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
      final focus = widget.focusedRowIndex;
      if (focus != null &&
          focus != oldWidget.focusedRowIndex &&
          focus >= 0 &&
          focus < widget.departments.length) {
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
    final n = widget.departments.length;
    if (n == 0) {
      _pagedFirstRowIndex = 0;
      return;
    }
    if (_pagedFirstRowIndex >= n) {
      _pagedFirstRowIndex = lastPageStart(count: n, pageSize: _rowsPerPage);
    }
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
      if (col == DepartmentDirectoryColumn.selection) {
        list.add(
          DataColumn(
            label: CatalogSelectAllCheckbox(
              visibleIds: [
                for (final d in widget.departments)
                  if (d.id != null) d.id!,
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
        final widthSum = visible.fold<double>(
          0,
          (a, c) => a + _widthForColumn(c),
        );
        final tableWidth =
            widthSum +
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
            firstRowIndex: start,
            bottomBar: CatalogPaginationBar(
              rowCount: widget.departments.length,
              firstRowIndex: _pagedFirstRowIndex,
              pageSize: _rowsPerPage,
              onFirstRowIndexChanged: (start) =>
                  setState(() => _pagedFirstRowIndex = start),
            ),
          );
        }

        _rowKeys.retainFirst(widget.departments.length);
        return KeyboardRowNavigation(
          rowCount: widget.departments.length,
          focusedRowIndex: widget.focusedRowIndex,
          onFocusRow: (i) => widget.onSetFocusedRowIndex?.call(i),
          pageStep: widget.continuousScroll
              ? kDefaultRowPageStep
              : _rowsPerPage,
          onRevealRow: (i, {required movingDown}) =>
              _rowKeys.reveal(i, movingDown: movingDown),
          onOpen: (focused) => catalogOpenFromKeyboard<DepartmentModel>(
            rows: widget.departments,
            focusedIndex: focused,
            selectedCount: widget.selectedIds.length,
            onBulkEdit: widget.onRequestBulkEdit,
            onEdit: widget.onEditDepartment,
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
    return UserEquipmentCodes.joinCodes(equipment);
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
            d.name,
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
        final parsed = tryParseDepartmentHex(d.color);
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
      onSelectChanged:
          _selectionVisible && id != null && _onToggleSelection != null
          ? (_) => _onToggleSelection!(id)
          : null,
      color: focused ? WidgetStateProperty.all(_focusHighlightColor) : null,
      cells: cells,
    );
  }
}
