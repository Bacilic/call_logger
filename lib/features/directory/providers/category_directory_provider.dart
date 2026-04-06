import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../../history/providers/history_provider.dart';
import '../models/category_directory_column.dart';
import '../models/category_model.dart';

const _catalogCategoriesVisibleColumnsKey =
    'catalog_categories_visible_columns';

class _PatchKeep {
  const _PatchKeep();
}

const _kPatchKeep = _PatchKeep();

typedef _CategoryColumnLayout = ({
  List<CategoryDirectoryColumn> order,
  Set<String> visible,
});

/// Κατάσταση καταλόγου κατηγοριών.
class CategoryDirectoryState {
  CategoryDirectoryState({
    this.allCategories = const [],
    this.filteredCategories = const [],
    this.searchQuery = '',
    this.sortColumn,
    this.sortAscending = true,
    this.selectedIds = const {},
    this.lastDeleted,
    this.focusedRowIndex,
    List<CategoryDirectoryColumn>? columnOrder,
    Set<String>? visibleColumnKeys,
  })  : columnOrder = CategoryDirectoryColumn.pinSelectionFirst(
          List<CategoryDirectoryColumn>.from(
            columnOrder ?? CategoryDirectoryColumn.all,
          ),
        ),
        visibleColumnKeys = visibleColumnKeys != null &&
                visibleColumnKeys.isNotEmpty
            ? Set<String>.from(visibleColumnKeys)
            : {
                CategoryDirectoryColumn.selection.key,
                CategoryDirectoryColumn.name.key,
              };

  final List<CategoryModel> allCategories;
  final List<CategoryModel> filteredCategories;
  final String searchQuery;
  final String? sortColumn;
  final bool sortAscending;
  final Set<int> selectedIds;
  final List<CategoryModel>? lastDeleted;
  final int? focusedRowIndex;
  final List<CategoryDirectoryColumn> columnOrder;
  final Set<String> visibleColumnKeys;

  List<CategoryDirectoryColumn> get orderedVisibleColumns {
    return [
      for (final c in columnOrder)
        if (visibleColumnKeys.contains(c.key)) c
    ];
  }
}

class CategoryDirectoryNotifier extends Notifier<CategoryDirectoryState> {
  bool _columnLayoutHydrated = false;

  @override
  CategoryDirectoryState build() => CategoryDirectoryState();

  void _invalidateCategoryLists() {
    ref.invalidate(historyCategoriesProvider);
    ref.invalidate(historyCategoryEntriesProvider);
  }

  _CategoryColumnLayout? _parseColumnLayoutFromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final o = decoded['order'];
        final v = decoded['visible'];
        final rawOrder = <CategoryDirectoryColumn>[];
        if (o is List) {
          for (final e in o) {
            if (e is! String) continue;
            final c = CategoryDirectoryColumn.fromKey(e);
            if (c != null) rawOrder.add(c);
          }
        }
        final seenKeys = <String>{};
        final order = <CategoryDirectoryColumn>[];
        for (final c in rawOrder) {
          if (seenKeys.add(c.key)) order.add(c);
        }
        for (final c in CategoryDirectoryColumn.all) {
          if (!seenKeys.contains(c.key)) order.add(c);
        }
        Set<String> visible;
        if (v is List && v.isNotEmpty) {
          visible = {};
          for (final e in v) {
            if (e is String && CategoryDirectoryColumn.fromKey(e) != null) {
              visible.add(e);
            }
          }
          if (visible.isEmpty) {
            visible = {
              CategoryDirectoryColumn.selection.key,
              CategoryDirectoryColumn.name.key,
            };
          }
        } else {
          visible = {
            CategoryDirectoryColumn.selection.key,
            CategoryDirectoryColumn.name.key,
          };
        }
        return (
          order: CategoryDirectoryColumn.pinSelectionFirst(order),
          visible: visible,
        );
      }
    } catch (_) {}
    return null;
  }

  Future<_CategoryColumnLayout?> _readColumnLayoutFromSettings() async {
    final raw = await DatabaseHelper.instance
        .getSetting(_catalogCategoriesVisibleColumnsKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return _parseColumnLayoutFromJson(raw);
  }

  Future<void> _persistCategoryColumnLayout(CategoryDirectoryState s) async {
    final order = s.columnOrder;
    final vis = s.visibleColumnKeys;
    final payload = jsonEncode({
      'order': order.map((c) => c.key).toList(),
      'visible': [
        for (final c in order)
          if (vis.contains(c.key)) c.key
      ],
    });
    await DatabaseHelper.instance.setSetting(
      _catalogCategoriesVisibleColumnsKey,
      payload,
    );
  }

  Future<void> loadCategories() async {
    _CategoryColumnLayout? parsed;
    if (!_columnLayoutHydrated) {
      parsed = await _readColumnLayoutFromSettings();
      _columnLayoutHydrated = true;
    }
    final rows = await DatabaseHelper.instance.getActiveCategoryRows();
    if (!ref.mounted) return;
    final list = rows.map(CategoryModel.fromMap).toList();
    state = CategoryDirectoryState(
      allCategories: list,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: state.selectedIds,
      lastDeleted: state.lastDeleted,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: parsed != null
          ? List<CategoryDirectoryColumn>.from(parsed.order)
          : List<CategoryDirectoryColumn>.from(state.columnOrder),
      visibleColumnKeys: parsed != null
          ? Set<String>.from(parsed.visible)
          : Set<String>.from(state.visibleColumnKeys),
    );
    filterAndSort();
  }

  void filterAndSort() {
    final q =
        SearchTextNormalizer.normalizeForSearch(state.searchQuery);
    var list = state.allCategories;
    if (q.isNotEmpty) {
      list = list
          .where(
            (c) => SearchTextNormalizer.containsAllTokens(c.name, state.searchQuery),
          )
          .toList();
    }
    final col = state.sortColumn;
    final asc = state.sortAscending;
    if (col != null && col.isNotEmpty) {
      list = List<CategoryModel>.from(list);
      list.sort((a, b) {
        int cmp;
        switch (col) {
          case 'id':
            cmp = (a.id ?? 0).compareTo(b.id ?? 0);
            break;
          case 'name':
            cmp = a.name.compareTo(b.name);
            break;
          default:
            cmp = 0;
        }
        return asc ? cmp : -cmp;
      });
    }
    final len = list.length;
    final idx = state.focusedRowIndex;
    final clamped = idx != null && idx >= len ? (len > 0 ? len - 1 : null) : idx;
    state = CategoryDirectoryState(
      allCategories: state.allCategories,
      filteredCategories: list,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: state.selectedIds,
      lastDeleted: state.lastDeleted,
      focusedRowIndex: clamped,
      columnOrder: state.columnOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
  }

  void _patch({
    List<CategoryModel>? allCategories,
    List<CategoryModel>? filteredCategories,
    String? searchQuery,
    String? sortColumn,
    bool? sortAscending,
    Set<int>? selectedIds,
    Object? lastDeleted = _kPatchKeep,
    int? focusedRow,
    bool keepFocusedRow = true,
    List<CategoryDirectoryColumn>? columnOrder,
    Set<String>? visibleColumnKeys,
  }) {
    state = CategoryDirectoryState(
      allCategories: allCategories ?? state.allCategories,
      filteredCategories: filteredCategories ?? state.filteredCategories,
      searchQuery: searchQuery ?? state.searchQuery,
      sortColumn: sortColumn ?? state.sortColumn,
      sortAscending: sortAscending ?? state.sortAscending,
      selectedIds: selectedIds ?? state.selectedIds,
      lastDeleted: identical(lastDeleted, _kPatchKeep)
          ? state.lastDeleted
          : lastDeleted as List<CategoryModel>?,
      focusedRowIndex:
          keepFocusedRow ? state.focusedRowIndex : focusedRow,
      columnOrder: columnOrder ?? state.columnOrder,
      visibleColumnKeys: visibleColumnKeys ?? state.visibleColumnKeys,
    );
  }

  void setFocusedRowIndex(int? index) {
    final len = state.filteredCategories.length;
    final clamped = index == null || len == 0
        ? null
        : index.clamp(0, len - 1);
    _patch(focusedRow: clamped, keepFocusedRow: false);
  }

  void setSearchQuery(String q) {
    _patch(searchQuery: q);
    filterAndSort();
  }

  void setSort(String? column, bool ascending) {
    _patch(sortColumn: column, sortAscending: ascending);
    filterAndSort();
  }

  void toggleSelection(int id) {
    if (!state.visibleColumnKeys
        .contains(CategoryDirectoryColumn.selection.key)) {
      return;
    }
    final next = Set<int>.from(state.selectedIds);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    _patch(selectedIds: next);
  }

  Future<void> reorderCategoryColumns(int oldIndex, int newIndex) async {
    final sel = CategoryDirectoryColumn.selection;
    final full = List<CategoryDirectoryColumn>.from(state.columnOrder);
    final rest = full.where((c) => c != sel).toList();
    if (oldIndex < newIndex) newIndex -= 1;
    final item = rest.removeAt(oldIndex);
    rest.insert(newIndex, item);
    final newOrder = CategoryDirectoryColumn.pinSelectionFirst([sel, ...rest]);
    _patch(columnOrder: newOrder);
    await _persistCategoryColumnLayout(state);
  }

  Future<void> setCategoryColumnVisible(
    CategoryDirectoryColumn col,
    bool visible,
  ) async {
    var keys = Set<String>.from(state.visibleColumnKeys);
    if (visible) {
      keys.add(col.key);
    } else {
      keys.remove(col.key);
    }
    if (keys.isEmpty) {
      keys = {
        CategoryDirectoryColumn.selection.key,
        CategoryDirectoryColumn.name.key,
      };
    }
    var selectedIds = state.selectedIds;
    if (!keys.contains(CategoryDirectoryColumn.selection.key)) {
      selectedIds = {};
    }
    state = CategoryDirectoryState(
      allCategories: state.allCategories,
      filteredCategories: state.filteredCategories,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: selectedIds,
      lastDeleted: state.lastDeleted,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: CategoryDirectoryColumn.pinSelectionFirst(
        List<CategoryDirectoryColumn>.from(state.columnOrder),
      ),
      visibleColumnKeys: keys,
    );
    await _persistCategoryColumnLayout(state);
    filterAndSort();
  }

  /// Επιστρέφει `true` αν επαναφέρθηκε soft-deleted κατηγορία (ίδιο normalized όνομα).
  Future<bool> addCategory(String name) async {
    final r = await DatabaseHelper.instance.insertCategoryAndGetId(name);
    _invalidateCategoryLists();
    await loadCategories();
    return r.restored;
  }

  Future<void> renameCategory(int id, String newCanonicalName) async {
    await DatabaseHelper.instance.updateCategoryNameAndSyncCalls(
      id: id,
      newCanonicalName: newCanonicalName,
    );
    _invalidateCategoryLists();
    await loadCategories();
  }

  Future<void> deleteSelected() async {
    await deleteByIds(state.selectedIds.toList());
  }

  /// Διαγραφή με undo (από μπάρα επιλογής ή διάλογο επεξεργασίας).
  Future<void> deleteByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final toDelete = state.allCategories
        .where((c) => c.id != null && ids.contains(c.id))
        .toList();
    await DatabaseHelper.instance.softDeleteCategories(ids);
    _invalidateCategoryLists();
    if (!ref.mounted) return;
    state = CategoryDirectoryState(
      allCategories: state.allCategories,
      filteredCategories: state.filteredCategories,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: {},
      lastDeleted: toDelete,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: state.columnOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
    await loadCategories();
  }

  Future<void> undoLastDelete() async {
    final list = state.lastDeleted;
    if (list == null || list.isEmpty) return;
    final ids = list.map((c) => c.id).whereType<int>().toList();
    await DatabaseHelper.instance.restoreCategories(ids);
    _invalidateCategoryLists();
    if (!ref.mounted) return;
    _patch(lastDeleted: null);
    await loadCategories();
  }
}

final categoryDirectoryProvider = NotifierProvider<
    CategoryDirectoryNotifier, CategoryDirectoryState>(
  CategoryDirectoryNotifier.new,
);
