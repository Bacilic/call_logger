import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../calls/models/user_model.dart';

/// Πίνακας χρηστών με σελιδοποίηση, sortable headers, select-all και επιλογή γραμμής.
/// Single tap = toggle επιλογής, double tap = άνοιγμα modal επεξεργασίας.
/// Πλήκτρα: ↑/↓ focus γραμμή, Enter = edit, Delete = confirm + deleteSelected.
class UsersDataTable extends StatefulWidget {
  const UsersDataTable({
    super.key,
    required this.users,
    required this.selectedIds,
    required this.sortColumn,
    required this.sortAscending,
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
  final void Function(int id) onToggleSelection;
  final void Function(String? column, bool ascending) onSetSort;
  final void Function(UserModel user, {String? focusedField}) onEditUser;
  final int? focusedRowIndex;
  final void Function(int? index)? onSetFocusedRowIndex;
  final VoidCallback? onRequestDelete;
  /// Κλήση όταν Enter/Space με πολλαπλή επιλογή → ανοίγει μαζική επεξεργασία.
  final VoidCallback? onRequestBulkEdit;
  /// true = συνεχής κύλιση (DataTable + Scrollbar), false = PaginatedDataTable.
  final bool continuousScroll;

  @override
  State<UsersDataTable> createState() => _UsersDataTableState();
}

const _minColumnWidth = 40.0;
const _maxColumnWidth = 600.0;
const _defaultUserColumnWidths = [
  52.0,  // checkbox
  56.0,  // ID
  140.0, // Επώνυμο
  120.0, // Όνομα
  120.0, // Τηλέφωνο
  140.0, // Τμήμα
  120.0, // Τοποθεσία
  180.0, // Σημειώσεις
];

class _UsersDataTableState extends State<UsersDataTable> {
  final _source = _UsersTableSource();
  final FocusNode _tableFocusNode = FocusNode();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  late List<double> _columnWidths;

  @override
  void initState() {
    super.initState();
    _columnWidths = List<double>.from(_defaultUserColumnWidths);
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
    );
  }

  Color? get _focusHighlightColor =>
      Theme.of(context).colorScheme.surfaceContainerHighest;

  static const _sortColumnToIndex = {
    'id': 1,
    'last_name': 2,
    'first_name': 3,
    'phone': 4,
    'department': 5,
    'location': 6,
  };

  Widget _buildStickyHeader(
    BuildContext context,
    List<DataColumn> columns,
    double headingHeight,
    Color? headingColor,
    TextStyle headingTextStyle,
    Map<int, TableColumnWidth> columnWidths,
  ) {
    final sortedIndex = widget.sortColumn != null
        ? _sortColumnToIndex[widget.sortColumn] ?? -1
        : -1;
    final asc = widget.sortAscending;
    return Table(
      columnWidths: columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: headingColor ?? Theme.of(context).colorScheme.surfaceContainerHighest,
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
                          setState(() {
                            _columnWidths[i] = (_columnWidths[i] + delta)
                                .clamp(_minColumnWidth, _maxColumnWidth);
                          });
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
    int rowIndex,
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

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final users = widget.users;
    final len = users.length;
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
          widget.onEditUser(users[idx]);
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
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = <DataColumn>[
          DataColumn(
            label: _SelectAllCheckbox(
              selectedIds: widget.selectedIds,
              users: widget.users,
              onSelectAll: () {
                for (final u in widget.users) {
                  if (u.id != null && !widget.selectedIds.contains(u.id)) {
                    widget.onToggleSelection(u.id!);
                  }
                }
              },
              onDeselectAll: () {
                for (final id in widget.selectedIds.toList()) {
                  widget.onToggleSelection(id);
                }
              },
              allSelected: widget.users.isNotEmpty &&
                  widget.users.every((u) =>
                      u.id != null && widget.selectedIds.contains(u.id)),
            ),
          ),
          DataColumn(
            label: const Text('ID'),
            onSort: (_, asc) => widget.onSetSort('id', asc),
          ),
          DataColumn(
            label: const Text('Επώνυμο'),
            onSort: (_, asc) => widget.onSetSort('last_name', asc),
          ),
          DataColumn(
            label: const Text('Όνομα'),
            onSort: (_, asc) => widget.onSetSort('first_name', asc),
          ),
          DataColumn(
            label: const Text('Τηλέφωνο'),
            onSort: (_, asc) => widget.onSetSort('phone', asc),
          ),
          DataColumn(
            label: const Text('Τμήμα'),
            onSort: (_, asc) => widget.onSetSort('department', asc),
          ),
          DataColumn(
            label: const Text('Τοποθεσία'),
            onSort: (_, asc) => widget.onSetSort('location', asc),
          ),
          const DataColumn(label: Text('Σημειώσεις')),
        ];

        final Widget tableContent;
        if (widget.continuousScroll) {
          final rows = <DataRow>[];
          for (var i = 0; i < _source.rowCount; i++) {
            final row = _source.getRow(i);
            if (row != null) rows.add(row);
          }
          final theme = Theme.of(context);
          final dataTableTheme = theme.dataTableTheme;
          final headingHeight =
              dataTableTheme.headingRowHeight ?? 56.0;
          final Color? headingColor =
              (dataTableTheme.headingRowColor ?? theme.colorScheme.surfaceContainerHighest) as Color?;
          final columnWidths = Map<int, TableColumnWidth>.fromIterables(
            List.generate(_columnWidths.length, (i) => i),
            _columnWidths.map((w) => FixedColumnWidth(w)),
          );
          const columnSpacing = 24.0;
          const horizontalMargin = 16.0;
          final tableWidth = _columnWidths.fold<double>(0, (a, b) => a + b) +
              (_columnWidths.length - 1) * columnSpacing +
              horizontalMargin * 2;
          tableContent = Scrollbar(
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
                      dataTableTheme.headingTextStyle ?? theme.textTheme.titleSmall!,
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
                            for (var i = 0; i < rows.length; i++)
                              _dataRowToTableRow(context, rows[i], i),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        } else {
          final fallbackTableWidth = 700.0;
          tableContent = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SizedBox(
                width: fallbackTableWidth,
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

class _SelectAllCheckbox extends StatelessWidget {
  const _SelectAllCheckbox({
    required this.selectedIds,
    required this.users,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.allSelected,
  });

  final Set<int> selectedIds;
  final List<UserModel> users;
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

class _UsersTableSource extends DataTableSource {
  List<UserModel> _users = [];
  Set<int> _selectedIds = {};
  void Function(int id)? _onToggleSelection;
  void Function(UserModel user, {String? focusedField})? _onEditUser;
  int? _focusedRowIndex;
  Color? _focusHighlightColor;
  void Function(int index)? _onRowTap;

  void update(
    List<UserModel> users,
    Set<int> selectedIds,
    void Function(int id) onToggleSelection,
    void Function(UserModel user, {String? focusedField}) onEditUser,
    int? focusedRowIndex,
    Color? focusHighlightColor,
    void Function(int index)? onRowTap,
  ) {
    _users = users;
    _selectedIds = selectedIds;
    _onToggleSelection = onToggleSelection;
    _onEditUser = onEditUser;
    _focusedRowIndex = focusedRowIndex;
    _focusHighlightColor = focusHighlightColor;
    _onRowTap = onRowTap;
    notifyListeners();
  }

  @override
  int get rowCount => _users.length;

  @override
  bool get isRowCountApproximate => false;

  @override
  int get selectedRowCount => _selectedIds.length;

  void _onDoubleTap(UserModel user, String field) => _onEditUser?.call(user, focusedField: field);

  @override
  DataRow? getRow(int index) {
    if (index < 0 || index >= _users.length) return null;
    final user = _users[index];
    final id = user.id;
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
          onDoubleTap: () => _onDoubleTap(user, 'id'),
        ),
        DataCell(
          Text('${id ?? ''}'),
          onTap: () => _onRowTap?.call(index),
          onDoubleTap: () => _onDoubleTap(user, 'id'),
        ),
        DataCell(
          Text(
            user.lastName ?? '',
            softWrap: true,
            overflow: TextOverflow.visible,
          ),
          onTap: () => _onRowTap?.call(index),
          onDoubleTap: () => _onDoubleTap(user, 'lastName'),
        ),
        DataCell(
          Text(
            user.firstName ?? '',
            softWrap: true,
            overflow: TextOverflow.visible,
          ),
          onTap: () => _onRowTap?.call(index),
          onDoubleTap: () => _onDoubleTap(user, 'firstName'),
        ),
        DataCell(
          Text(
            user.phone ?? '',
            softWrap: true,
            overflow: TextOverflow.visible,
          ),
          onTap: () => _onRowTap?.call(index),
          onDoubleTap: () => _onDoubleTap(user, 'phone'),
        ),
        DataCell(
          Text(
            user.department ?? '',
            softWrap: true,
            overflow: TextOverflow.visible,
          ),
          onTap: () => _onRowTap?.call(index),
          onDoubleTap: () => _onDoubleTap(user, 'department'),
        ),
        DataCell(
          Text(
            user.location ?? '',
            softWrap: true,
            overflow: TextOverflow.visible,
          ),
          onTap: () => _onRowTap?.call(index),
          onDoubleTap: () => _onDoubleTap(user, 'location'),
        ),
        DataCell(
          Text(
            user.notes ?? '',
            softWrap: true,
            overflow: TextOverflow.visible,
          ),
          onTap: () => _onRowTap?.call(index),
          onDoubleTap: () => _onDoubleTap(user, 'notes'),
        ),
      ],
    );
  }
}
