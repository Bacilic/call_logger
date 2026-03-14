import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../../calls/models/equipment_model.dart';
import '../../calls/provider/lookup_provider.dart';
import '../../calls/models/user_model.dart';
import '../models/equipment_column.dart';

/// Κατάσταση καρτέλας εξοπλισμού: mirror του DirectoryState (allItems, filteredItems, search, sort, selection, undo).
class EquipmentDirectoryState {
  const EquipmentDirectoryState({
    this.allItems = const [],
    this.filteredItems = const [],
    this.visibleColumns = const [],
    this.allColumns = const [],
    this.searchQuery = '',
    this.sortColumn,
    this.sortAscending = true,
    this.selectedIds = const {},
    this.lastDeleted,
    this.lastBulkUpdated,
    this.focusedRowIndex,
  });

  final List<EquipmentRow> allItems;
  final List<EquipmentRow> filteredItems;
  final List<EquipmentColumn> visibleColumns;
  final List<EquipmentColumn> allColumns;
  final String searchQuery;
  final EquipmentColumn? sortColumn;
  final bool sortAscending;
  final Set<int> selectedIds;
  final List<EquipmentRow>? lastDeleted;
  final List<EquipmentRow>? lastBulkUpdated;
  final int? focusedRowIndex;

  EquipmentDirectoryState copyWith({
    List<EquipmentRow>? allItems,
    List<EquipmentRow>? filteredItems,
    List<EquipmentColumn>? visibleColumns,
    List<EquipmentColumn>? allColumns,
    String? searchQuery,
    EquipmentColumn? sortColumn,
    bool? sortAscending,
    Set<int>? selectedIds,
    List<EquipmentRow>? lastDeleted,
    List<EquipmentRow>? lastBulkUpdated,
    int? focusedRowIndex,
  }) {
    return EquipmentDirectoryState(
      allItems: allItems ?? this.allItems,
      filteredItems: filteredItems ?? this.filteredItems,
      visibleColumns: visibleColumns ?? this.visibleColumns,
      allColumns: allColumns ?? this.allColumns,
      searchQuery: searchQuery ?? this.searchQuery,
      sortColumn: sortColumn ?? this.sortColumn,
      sortAscending: sortAscending ?? this.sortAscending,
      selectedIds: selectedIds ?? this.selectedIds,
      lastDeleted: lastDeleted ?? this.lastDeleted,
      lastBulkUpdated: lastBulkUpdated ?? this.lastBulkUpdated,
      focusedRowIndex: focusedRowIndex ?? this.focusedRowIndex,
    );
  }
}

/// Notifier: φόρτωση, φιλτράρισμα, ταξινόμηση, επιλογή, CRUD, undo, μαζική επεξεργασία.
class EquipmentDirectoryNotifier extends Notifier<EquipmentDirectoryState> {
  void _invalidateLookupCache() {
    ref.invalidate(lookupServiceProvider);
  }

  @override
  EquipmentDirectoryState build() {
    final initial = EquipmentDirectoryState(
      visibleColumns: List<EquipmentColumn>.from(EquipmentColumn.defaults),
      allColumns: List<EquipmentColumn>.from(EquipmentColumn.all),
    );
    Future.microtask(() async {
      await load();
    });
    return initial;
  }

  Future<List<Map<String, dynamic>>> getEquipmentRows() {
    return DatabaseHelper.instance.getAllEquipment();
  }

  Future<List<Map<String, dynamic>>> getUserRows() {
    return DatabaseHelper.instance.getAllUsers();
  }

  Future<void> load() async {
    final equipmentRows = await getEquipmentRows();
    final userRows = await getUserRows();

    final usersMap = <int, UserModel>{};
    for (final map in userRows) {
      final u = UserModel.fromMap(map);
      if (u.id != null) usersMap[u.id!] = u;
    }

    final List<EquipmentRow> items = [];
    for (final eq in equipmentRows) {
      final equipment = EquipmentModel.fromMap(eq);
      final owner =
          equipment.userId != null ? usersMap[equipment.userId] : null;
      items.add((equipment, owner));
    }

    state = state.copyWith(allItems: items);
    filterAndSort();
  }

  void filterAndSort() {
    final q = SearchTextNormalizer.normalizeForSearch(state.searchQuery);
    var list = state.allItems;
    final visibleCols = state.visibleColumns;

    if (q.isNotEmpty) {
      list = list.where((row) {
        for (final col in visibleCols) {
          final text = col.displayValue(row);
          if (SearchTextNormalizer.normalizeForSearch(text).contains(q)) {
            return true;
          }
        }
        return false;
      }).toList();
    }

    final col = state.sortColumn;
    final asc = state.sortAscending;
    if (col != null && col.sortValue != null) {
      list = List<EquipmentRow>.from(list);
      list.sort((a, b) {
        final va = col.sortValue!(a);
        final vb = col.sortValue!(b);
        final cmp = _compareComparable(va, vb);
        return asc ? cmp : -cmp;
      });
    }

    final len = list.length;
    final idx = state.focusedRowIndex;
    final clamped =
        idx != null && idx >= len ? (len > 0 ? len - 1 : null) : idx;

    state = state.copyWith(
      filteredItems: list,
      focusedRowIndex: clamped,
    );
  }

  static int _compareComparable(Comparable? a, Comparable? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    if (a is String && b is String) return a.compareTo(b);
    if (a is num && b is num) return a.compareTo(b);
    return a.compareTo(b);
  }

  void setFocusedRowIndex(int? index) {
    final len = state.filteredItems.length;
    final clamped =
        index == null || len == 0 ? null : index.clamp(0, len - 1);
    state = state.copyWith(focusedRowIndex: clamped);
  }

  void setSearchQuery(String q) {
    state = state.copyWith(searchQuery: q);
    filterAndSort();
  }

  void setSort(EquipmentColumn? column, bool ascending) {
    state = state.copyWith(sortColumn: column, sortAscending: ascending);
    filterAndSort();
  }

  void toggleSelection(int id) {
    final next = Set<int>.from(state.selectedIds);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    state = state.copyWith(selectedIds: next);
  }

  void clearSelection() {
    state = state.copyWith(selectedIds: {});
  }

  void updateVisibleColumns(List<EquipmentColumn> newList) {
    state = state.copyWith(
        visibleColumns: List<EquipmentColumn>.from(newList));
  }

  void reorderColumn(int oldIndex, int newIndex) {
    final list = List<EquipmentColumn>.from(state.visibleColumns);
    if (oldIndex < newIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = state.copyWith(visibleColumns: list);
  }

  void toggleColumn(EquipmentColumn col) {
    final list = List<EquipmentColumn>.from(state.visibleColumns);
    if (list.contains(col)) {
      list.remove(col);
    } else {
      list.add(col);
    }
    if (list.isEmpty) {
      state = state.copyWith(
        visibleColumns: List<EquipmentColumn>.from(EquipmentColumn.defaults),
      );
      return;
    }
    state = state.copyWith(visibleColumns: list);
  }

  bool hasDuplicateCode(String code, {int? excludeId}) {
    final c = code.trim();
    if (c.isEmpty) return false;
    for (final row in state.allItems) {
      if (excludeId != null && row.$1.id == excludeId) continue;
      if ((row.$1.code ?? '').trim() == c) return true;
    }
    return false;
  }

  Future<void> addEquipment(EquipmentModel eq) async {
    await DatabaseHelper.instance.insertEquipmentFromMap(eq.toMap());
    await load();
    _invalidateLookupCache();
  }

  Future<void> updateEquipment(EquipmentModel eq) async {
    if (eq.id == null) return;
    await DatabaseHelper.instance.updateEquipment(eq.id!, eq.toMap());
    await load();
    _invalidateLookupCache();
  }

  Future<void> deleteSelected() async {
    if (state.selectedIds.isEmpty) return;
    final toDelete = state.allItems
        .where((row) =>
            row.$1.id != null && state.selectedIds.contains(row.$1.id))
        .toList();
    await DatabaseHelper.instance.deleteEquipments(state.selectedIds.toList());
    state = state.copyWith(
      selectedIds: {},
      lastDeleted: toDelete,
    );
    await load();
    _invalidateLookupCache();
  }

  Future<void> undoLastDelete() async {
    final list = state.lastDeleted;
    if (list == null || list.isEmpty) return;
    for (final row in list) {
      final map = row.$1.toMap();
      map.remove('id');
      await DatabaseHelper.instance.insertEquipmentFromMap(map);
    }
    state = state.copyWith(lastDeleted: null);
    await load();
    _invalidateLookupCache();
  }

  Future<void> bulkUpdate(
      List<int> ids, Map<String, dynamic> changes) async {
    if (ids.isEmpty || changes.isEmpty) return;
    final toUpdate = state.allItems
        .where((row) =>
            row.$1.id != null && ids.contains(row.$1.id))
        .toList();
    if (toUpdate.isEmpty) return;
    await DatabaseHelper.instance.bulkUpdateEquipments(ids, changes);
    state = state.copyWith(lastBulkUpdated: toUpdate);
    await load();
    _invalidateLookupCache();
  }

  Future<void> undoLastBulkUpdate() async {
    final list = state.lastBulkUpdated;
    if (list == null || list.isEmpty) return;
    for (final row in list) {
      if (row.$1.id != null) {
        await DatabaseHelper.instance.updateEquipment(
            row.$1.id!, row.$1.toMap());
      }
    }
    state = state.copyWith(lastBulkUpdated: null);
    await load();
    _invalidateLookupCache();
  }
}

final equipmentDirectoryProvider =
    NotifierProvider.autoDispose<EquipmentDirectoryNotifier,
        EquipmentDirectoryState>(EquipmentDirectoryNotifier.new);
