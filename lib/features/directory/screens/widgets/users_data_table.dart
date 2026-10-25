// ΑΞΙΟΛΟΓΗΘΗΚΕ ΓΙΑ ΔΙΑΣΠΑΣΗ — ΜΕΝΕΙ ΩΣ ΕΧΕΙ (11/10/2026).
//
// Ρόλος: ένας — πώς φαίνεται και πώς χειρίζεται κανείς τον πίνακα των
// υπαλλήλων: σταθερή κεφαλίδα με ταξινόμηση και πλάτη στηλών, γραμμές με
// επιλογή/εστίαση/διπλό κλικ, πλήκτρα, σελίδες ή συνεχής κύλιση.
//
// Γιατί δεν διασπάστηκε: όλα απαντούν στο ίδιο ερώτημα, και μοιράζονται την
// ίδια κατάσταση (πλάτη στηλών, τρέχουσα σελίδα, εστίαση). Τους κωδικούς
// εξοπλισμού κάθε υπαλλήλου τους φέρνει έτοιμους άλλη υπηρεσία.
//
// Τι θα το άλλαζε: ερώτημα βάσης, κανόνας επιχείρησης ή υπολογισμός πάνω στα
// δεδομένα μέσα σε αυτό το αρχείο — τότε ξαναξετάζεται από την αρχή.
//
// Γνωστό, εκτός αρχείου: ο σκελετός του πίνακα υπάρχει σχεδόν πανομοιότυπος
// και στους πίνακες Τμημάτων, Κατηγοριών και Εξοπλισμού — και έχει ήδη
// αποκλίνει (η σελίδα που ακολουθεί την εστίαση υπάρχει μόνο στον
// Εξοπλισμό). Καταγεγραμμένο στο roadmap ως κοινή δουλειά των τεσσάρων.

import 'package:flutter/material.dart';

import '../../../calls/models/user_model.dart';
import '../../models/user_directory_column.dart';
import '../../services/user_equipment_codes.dart';
import '../../../../core/widgets/keyboard_row_navigation.dart';
import '../../../../core/widgets/row_navigation_logic.dart';
import 'catalog_select_all_checkbox.dart';
import 'catalog_table_chrome.dart';
import 'catalog_table_support.dart';

/// Πίνακας χρηστών με σελιδοποίηση, sortable headers, επιλογή γραμμής (αν η στήλη εμφανίζεται), διπλό κλικ = επεξεργασία.
/// Ένα κλικ = εστίαση γραμμής (η επιλογή αλλάζει από το κουτάκι της στήλης επιλογής), διπλό κλικ = άνοιγμα επεξεργασίας.
/// Πλήκτρα: ↑/↓ focus γραμμή, Enter = edit, Delete = confirm + deleteSelected.
class UsersDataTable extends StatefulWidget {
  const UsersDataTable({
    super.key,
    required this.users,
    required this.selectedIds,
    required this.sortColumn,
    required this.sortAscending,
    required this.visibleColumns,
    required this.onToggleSelection,
    required this.onSetSort,
    required this.onEditUser,
    this.focusedRowIndex,
    this.onSetFocusedRowIndex,
    this.onRequestDelete,
    this.onRequestBulkEdit,
    this.continuousScroll = true,
  });

  final List<UserModel> users;
  final Set<int> selectedIds;
  final String? sortColumn;
  final bool sortAscending;
  final List<UserDirectoryColumn> visibleColumns;
  final void Function(int id) onToggleSelection;
  final void Function(String? column, bool ascending) onSetSort;
  final void Function(UserModel user, {String? focusedField}) onEditUser;
  final int? focusedRowIndex;
  final void Function(int? index)? onSetFocusedRowIndex;
  final VoidCallback? onRequestDelete;

  /// Κλήση όταν Enter/Space με πολλαπλή επιλογή → ανοίγει μαζική επεξεργασία.
  final VoidCallback? onRequestBulkEdit;

  /// true = συνεχής κύλιση· false = σελίδες [_rowsPerPage] με ίδιο Table, resize, βελάκι sort.
  final bool continuousScroll;

  @override
  State<UsersDataTable> createState() => _UsersDataTableState();
}

const _minColumnWidth = 40.0;
const _maxColumnWidth = 600.0;
const _rowsPerPage = 15;

const _defaultWidthsByKey = <String, double>{
  'selection': 52.0,
  'id': 56.0,
  'last_name': 140.0,
  'first_name': 120.0,
  'nickname': 110.0,
  'phone': 120.0,
  'department': 140.0,
  'equipment': 140.0,
  'notes': 180.0,
};

class _UsersDataTableState extends State<UsersDataTable> {
  final _source = _UsersTableSource();
  final RowKeys _rowKeys = RowKeys();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final Map<String, double> _columnWidths = Map<String, double>.from(
    _defaultWidthsByKey,
  );

  /// Δείκτης πρώτης γραμμής τρέχουσας σελίδας (όταν [continuousScroll] == false).
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
      widget.visibleColumns.contains(UserDirectoryColumn.selection);

  double _widthForColumn(UserDirectoryColumn col) {
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
  int? _rowIdAt(int? index) => catalogRowIdAt(widget.users, index, (u) => u.id);

  @override
  void didUpdateWidget(UsersDataTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _source.update(
      widget.users,
      widget.selectedIds,
      widget.onToggleSelection,
      widget.onEditUser,
      widget.focusedRowIndex,
      _focusHighlightColor,
      _onRowTap,
      widget.visibleColumns,
      _selectionVisible,
    );
    if (!widget.continuousScroll) {
      final focus = widget.focusedRowIndex;
      if (focus != null &&
          focus != oldWidget.focusedRowIndex &&
          focus >= 0 &&
          focus < widget.users.length) {
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
    final n = widget.users.length;
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
      if (col == UserDirectoryColumn.selection) {
        list.add(
          DataColumn(
            label: CatalogSelectAllCheckbox(
              visibleIds: [
                for (final u in widget.users)
                  if (u.id != null) u.id!,
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

  Widget _wrapScrollableUsersTable({
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
      widget.users,
      widget.selectedIds,
      widget.onToggleSelection,
      widget.onEditUser,
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

        final Widget tableContent;
        if (widget.continuousScroll) {
          final rows = <DataRow>[];
          for (var i = 0; i < _source.rowCount; i++) {
            final row = _source.getRow(i);
            if (row != null) rows.add(row);
          }
          tableContent = _wrapScrollableUsersTable(
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
          final n = widget.users.length;
          final start = n == 0 ? 0 : _pagedFirstRowIndex;
          final pageRows = <DataRow>[];
          for (var i = start; i < n && i < start + _rowsPerPage; i++) {
            final row = _source.getRow(i);
            if (row != null) pageRows.add(row);
          }
          tableContent = _wrapScrollableUsersTable(
            context: context,
            theme: theme,
            columns: columns,
            rows: pageRows,
            maxHeight: constraints.maxHeight,
            columnWidths: columnWidths,
            tableWidth: tableWidth,
            firstRowIndex: start,
            bottomBar: CatalogPaginationBar(
              rowCount: widget.users.length,
              firstRowIndex: _pagedFirstRowIndex,
              pageSize: _rowsPerPage,
              onFirstRowIndexChanged: (start) =>
                  setState(() => _pagedFirstRowIndex = start),
            ),
          );
        }

        _rowKeys.retainFirst(widget.users.length);
        return KeyboardRowNavigation(
          rowCount: widget.users.length,
          focusedRowIndex: widget.focusedRowIndex,
          onFocusRow: (i) => widget.onSetFocusedRowIndex?.call(i),
          pageStep: widget.continuousScroll
              ? kDefaultRowPageStep
              : _rowsPerPage,
          onRevealRow: (i, {required movingDown}) =>
              _rowKeys.reveal(i, movingDown: movingDown),
          onOpen: (focused) => catalogOpenFromKeyboard<UserModel>(
            rows: widget.users,
            focusedIndex: focused,
            selectedCount: widget.selectedIds.length,
            onBulkEdit: widget.onRequestBulkEdit,
            onEdit: widget.onEditUser,
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

class _UsersTableSource extends DataTableSource {
  List<UserModel> _users = [];
  Set<int> _selectedIds = {};
  void Function(int id)? _onToggleSelection;
  void Function(UserModel user, {String? focusedField})? _onEditUser;
  int? _focusedRowIndex;
  Color? _focusHighlightColor;
  void Function(int index)? _onRowTap;
  List<UserDirectoryColumn> _visibleColumns = [];
  bool _selectionVisible = true;

  void update(
    List<UserModel> users,
    Set<int> selectedIds,
    void Function(int id) onToggleSelection,
    void Function(UserModel user, {String? focusedField}) onEditUser,
    int? focusedRowIndex,
    Color? focusHighlightColor,
    void Function(int index)? onRowTap,
    List<UserDirectoryColumn> visibleColumns,
    bool selectionVisible,
  ) {
    _users = users;
    _selectedIds = selectedIds;
    _onToggleSelection = onToggleSelection;
    _onEditUser = onEditUser;
    _focusedRowIndex = focusedRowIndex;
    _focusHighlightColor = focusHighlightColor;
    _onRowTap = onRowTap;
    _visibleColumns = visibleColumns;
    _selectionVisible = selectionVisible;
    notifyListeners();
  }

  @override
  int get rowCount => _users.length;

  @override
  bool get isRowCountApproximate => false;

  @override
  int get selectedRowCount => _selectedIds.length;

  void _onDoubleTap(UserModel user, UserDirectoryColumn col) =>
      _onEditUser?.call(user, focusedField: col.editFocusField);

  DataCell _cellForColumn(
    UserModel user,
    int? id,
    bool selected,
    int rowIndex,
    UserDirectoryColumn col,
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
          onDoubleTap: () => _onDoubleTap(user, col),
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
          onDoubleTap: () => _onDoubleTap(user, col),
        );
      case 'last_name':
        return DataCell(
          Text(
            user.lastName ?? '',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(user, col),
        );
      case 'first_name':
        return DataCell(
          Text(
            user.firstName ?? '',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(user, col),
        );
      case 'nickname':
        return DataCell(
          Text(
            user.nickname ?? '',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(user, col),
        );
      case 'phone':
        return DataCell(
          Text(
            user.phoneJoined,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(user, col),
        );
      case 'department':
        return DataCell(
          Text(
            user.departmentName ?? '–',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(user, col),
        );
      case 'equipment':
        return DataCell(
          Text(
            UserEquipmentCodes.textForUser(id),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(user, col),
        );
      case 'notes':
        return DataCell(
          Text(
            user.notes ?? '',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(user, col),
        );
      default:
        return DataCell(
          const SizedBox.shrink(),
          onTap: () => _onRowTap?.call(rowIndex),
          onDoubleTap: () => _onDoubleTap(user, col),
        );
    }
  }

  @override
  DataRow? getRow(int index) {
    if (index < 0 || index >= _users.length) return null;
    final user = _users[index];
    final id = user.id;
    final selected =
        _selectionVisible && id != null && _selectedIds.contains(id);
    final focused = index == _focusedRowIndex && _focusHighlightColor != null;
    final cells = <DataCell>[
      for (final col in _visibleColumns)
        _cellForColumn(user, id, selected, index, col),
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
