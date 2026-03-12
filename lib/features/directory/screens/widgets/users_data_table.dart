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

class _UsersDataTableState extends State<UsersDataTable> {
  final _source = _UsersTableSource();
  final FocusNode _tableFocusNode = FocusNode();
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void dispose() {
    _verticalScrollController.dispose();
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
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final tableWidth = width > 700 ? width : 700.0;

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
          tableContent = Scrollbar(
            controller: _verticalScrollController,
            thumbVisibility: true,
            thickness: 12,
            radius: const Radius.circular(10),
            child: SingleChildScrollView(
              controller: _verticalScrollController,
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: DataTable(
                    showCheckboxColumn: false,
                    columns: columns,
                    rows: rows,
                    columnSpacing: 24,
                    horizontalMargin: 16,
                  ),
                ),
              ),
            ),
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
      },
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
          Text(user.lastName ?? ''),
          onTap: () => _onRowTap?.call(index),
          onDoubleTap: () => _onDoubleTap(user, 'lastName'),
        ),
        DataCell(
          Text(user.firstName ?? ''),
          onTap: () => _onRowTap?.call(index),
          onDoubleTap: () => _onDoubleTap(user, 'firstName'),
        ),
        DataCell(
          Text(user.phone ?? ''),
          onTap: () => _onRowTap?.call(index),
          onDoubleTap: () => _onDoubleTap(user, 'phone'),
        ),
        DataCell(
          Text(user.department ?? ''),
          onTap: () => _onRowTap?.call(index),
          onDoubleTap: () => _onDoubleTap(user, 'department'),
        ),
        DataCell(
          Text(user.location ?? ''),
          onTap: () => _onRowTap?.call(index),
          onDoubleTap: () => _onDoubleTap(user, 'location'),
        ),
        DataCell(
          Text(
            user.notes ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _onRowTap?.call(index),
          onDoubleTap: () => _onDoubleTap(user, 'notes'),
        ),
      ],
    );
  }
}
