// Προσωρινή χρήση DataTable – σε επόμενη φάση εξέτασε custom Table για sticky headers & row selection.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/equipment_column.dart';

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

    final tableWidth = 700.0 + widget.visibleColumns.length * 120.0;
    final Widget tableContent;
    if (widget.continuousScroll) {
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _onRowTap?.call(index),
            onDoubleTap: () => _onDoubleTap(row, col.key),
          ),
        ),
      ],
    );
  }
}
