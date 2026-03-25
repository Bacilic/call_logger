import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/errors/department_exists_exception.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../../calls/provider/lookup_provider.dart';
import '../models/department_directory_column.dart';
import '../models/department_model.dart';

const _catalogDepartmentsVisibleColumnsKey =
    'catalog_departments_visible_columns';

/// Sentinel για [_patch]: κράτα την προηγούμενη τιμή πεδίων που επιτρέπουν explicit null.
class _PatchKeep {
  const _PatchKeep();
}

const _kPatchKeep = _PatchKeep();

typedef _DepartmentColumnLayout = ({
  List<DepartmentDirectoryColumn> order,
  Set<String> visible,
});

/// Κατάσταση καταλόγου τμημάτων.
class DepartmentDirectoryState {
  DepartmentDirectoryState({
    this.allDepartments = const [],
    this.filteredDepartments = const [],
    this.searchQuery = '',
    this.sortColumn,
    this.sortAscending = true,
    this.selectedIds = const {},
    this.lastDeleted,
    this.lastBulkUpdatedDepartments,
    this.focusedRowIndex,
    List<DepartmentDirectoryColumn>? columnOrder,
    Set<String>? visibleColumnKeys,
  })  : columnOrder = DepartmentDirectoryColumn.pinSelectionFirst(
          List<DepartmentDirectoryColumn>.from(
            columnOrder ?? DepartmentDirectoryColumn.all,
          ),
        ),
        visibleColumnKeys = visibleColumnKeys != null
            ? Set<String>.from(visibleColumnKeys)
            : {for (final c in DepartmentDirectoryColumn.all) c.key};

  final List<DepartmentModel> allDepartments;
  final List<DepartmentModel> filteredDepartments;
  final String searchQuery;
  final String? sortColumn;
  final bool sortAscending;
  final Set<int> selectedIds;
  final List<DepartmentModel>? lastDeleted;
  final List<DepartmentModel>? lastBulkUpdatedDepartments;
  final int? focusedRowIndex;
  final List<DepartmentDirectoryColumn> columnOrder;
  final Set<String> visibleColumnKeys;

  List<DepartmentDirectoryColumn> get orderedVisibleColumns {
    return [
      for (final c in columnOrder)
        if (visibleColumnKeys.contains(c.key)) c
    ];
  }
}

/// Notifier καταλόγου τμημάτων.
class DepartmentDirectoryNotifier
    extends Notifier<DepartmentDirectoryState> {
  bool _columnLayoutHydrated = false;

  @override
  DepartmentDirectoryState build() => DepartmentDirectoryState();

  Future<void> _refreshLookupCache() async {
    ref.invalidate(lookupServiceProvider);
    await ref.read(lookupServiceProvider.future);
    if (!ref.mounted) return;
  }

  _DepartmentColumnLayout? _parseColumnLayoutFromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final o = decoded['order'];
        final v = decoded['visible'];
        final rawOrder = <DepartmentDirectoryColumn>[];
        if (o is List) {
          for (final e in o) {
            if (e is! String) continue;
            final c = DepartmentDirectoryColumn.fromKey(e);
            if (c != null) rawOrder.add(c);
          }
        }
        final seenKeys = <String>{};
        final order = <DepartmentDirectoryColumn>[];
        for (final c in rawOrder) {
          if (seenKeys.add(c.key)) order.add(c);
        }
        for (final c in DepartmentDirectoryColumn.all) {
          if (!seenKeys.contains(c.key)) order.add(c);
        }
        Set<String> visible;
        if (v is List && v.isNotEmpty) {
          visible = {};
          for (final e in v) {
            if (e is String && DepartmentDirectoryColumn.fromKey(e) != null) {
              visible.add(e);
            }
          }
          if (visible.isEmpty) {
            visible = {for (final c in order) c.key};
          }
        } else {
          visible = {for (final c in order) c.key};
        }
        return (
          order: DepartmentDirectoryColumn.pinSelectionFirst(order),
          visible: visible,
        );
      }
      if (decoded is List) {
        final ordered = <DepartmentDirectoryColumn>[];
        final seen = <String>{};
        for (final e in decoded) {
          if (e is! String) continue;
          final c = DepartmentDirectoryColumn.fromKey(e);
          if (c != null && seen.add(c.key)) ordered.add(c);
        }
        if (ordered.isEmpty) return null;
        for (final c in DepartmentDirectoryColumn.all) {
          if (!seen.contains(c.key)) ordered.add(c);
        }
        return (
          order: DepartmentDirectoryColumn.pinSelectionFirst(ordered),
          visible: Set<String>.from(seen),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<_DepartmentColumnLayout?> _readColumnLayoutFromSettings() async {
    final raw = await DatabaseHelper.instance
        .getSetting(_catalogDepartmentsVisibleColumnsKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return _parseColumnLayoutFromJson(raw);
  }

  Future<void> _persistDepartmentColumnLayout(DepartmentDirectoryState s) async {
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
      _catalogDepartmentsVisibleColumnsKey,
      payload,
    );
  }

  Future<void> loadDepartments() async {
    _DepartmentColumnLayout? parsed;
    if (!_columnLayoutHydrated) {
      parsed = await _readColumnLayoutFromSettings();
      _columnLayoutHydrated = true;
    }
    final rows = await DatabaseHelper.instance.getDepartments();
    if (!ref.mounted) return;
    final list = rows.map((m) => DepartmentModel.fromMap(m)).toList();
    state = DepartmentDirectoryState(
      allDepartments: list,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: state.selectedIds,
      lastDeleted: state.lastDeleted,
      lastBulkUpdatedDepartments: state.lastBulkUpdatedDepartments,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: parsed != null
          ? List<DepartmentDirectoryColumn>.from(parsed.order)
          : List<DepartmentDirectoryColumn>.from(state.columnOrder),
      visibleColumnKeys: parsed != null
          ? Set<String>.from(parsed.visible)
          : Set<String>.from(state.visibleColumnKeys),
    );
    filterAndSort();
  }

  void filterAndSort() {
    final q = SearchTextNormalizer.normalizeForSearch(state.searchQuery);
    var list = state.allDepartments;
    if (q.isNotEmpty) {
      list = list.where((d) {
        final blob = [
          d.name,
          d.building ?? '',
          d.notes ?? '',
          d.color ?? '',
          '${d.id ?? ''}',
          if (d.isDeleted) 'Διεγραμμένο',
        ].join(' ');
        return SearchTextNormalizer.containsAllTokens(blob, state.searchQuery);
      }).toList();
    }
    final col = state.sortColumn;
    final asc = state.sortAscending;
    if (col != null && col.isNotEmpty) {
      list = List<DepartmentModel>.from(list);
      list.sort((a, b) {
        int cmp;
        switch (col) {
          case 'id':
            cmp = (a.id ?? 0).compareTo(b.id ?? 0);
            break;
          case 'name':
            cmp = a.name.compareTo(b.name);
            break;
          case 'building':
            cmp = (a.building ?? '').compareTo(b.building ?? '');
            break;
          case 'color':
            cmp = (a.color ?? '').compareTo(b.color ?? '');
            break;
          case 'notes':
            cmp = (a.notes ?? '').compareTo(b.notes ?? '');
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
    state = DepartmentDirectoryState(
      allDepartments: state.allDepartments,
      filteredDepartments: list,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: state.selectedIds,
      lastDeleted: state.lastDeleted,
      lastBulkUpdatedDepartments: state.lastBulkUpdatedDepartments,
      focusedRowIndex: clamped,
      columnOrder: state.columnOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
  }

  void setFocusedRowIndex(int? index) {
    final len = state.filteredDepartments.length;
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

  void _patch({
    List<DepartmentModel>? allDepartments,
    List<DepartmentModel>? filteredDepartments,
    String? searchQuery,
    String? sortColumn,
    bool? sortAscending,
    Set<int>? selectedIds,
    Object? lastDeleted = _kPatchKeep,
    Object? lastBulkUpdatedDepartments = _kPatchKeep,
    int? focusedRow,
    bool keepFocusedRow = true,
    List<DepartmentDirectoryColumn>? columnOrder,
    Set<String>? visibleColumnKeys,
  }) {
    state = DepartmentDirectoryState(
      allDepartments: allDepartments ?? state.allDepartments,
      filteredDepartments: filteredDepartments ?? state.filteredDepartments,
      searchQuery: searchQuery ?? state.searchQuery,
      sortColumn: sortColumn ?? state.sortColumn,
      sortAscending: sortAscending ?? state.sortAscending,
      selectedIds: selectedIds ?? state.selectedIds,
      lastDeleted: identical(lastDeleted, _kPatchKeep)
          ? state.lastDeleted
          : lastDeleted as List<DepartmentModel>?,
      lastBulkUpdatedDepartments:
          identical(lastBulkUpdatedDepartments, _kPatchKeep)
              ? state.lastBulkUpdatedDepartments
              : lastBulkUpdatedDepartments as List<DepartmentModel>?,
      focusedRowIndex:
          keepFocusedRow ? state.focusedRowIndex : focusedRow,
      columnOrder: columnOrder ?? state.columnOrder,
      visibleColumnKeys: visibleColumnKeys ?? state.visibleColumnKeys,
    );
  }

  void toggleSelection(int id) {
    if (!state.visibleColumnKeys
        .contains(DepartmentDirectoryColumn.selection.key)) {
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

  Future<void> reorderDepartmentColumns(int oldIndex, int newIndex) async {
    final sel = DepartmentDirectoryColumn.selection;
    final full = List<DepartmentDirectoryColumn>.from(state.columnOrder);
    final rest = full.where((c) => c != sel).toList();
    if (oldIndex < newIndex) newIndex -= 1;
    final item = rest.removeAt(oldIndex);
    rest.insert(newIndex, item);
    final newOrder = DepartmentDirectoryColumn.pinSelectionFirst([sel, ...rest]);
    _patch(columnOrder: newOrder);
    await _persistDepartmentColumnLayout(state);
  }

  Future<void> setDepartmentColumnVisible(
    DepartmentDirectoryColumn col,
    bool visible,
  ) async {
    var keys = Set<String>.from(state.visibleColumnKeys);
    if (visible) {
      keys.add(col.key);
    } else {
      keys.remove(col.key);
    }
    if (keys.isEmpty) {
      keys = {for (final c in DepartmentDirectoryColumn.all) c.key};
    }
    var selectedIds = state.selectedIds;
    if (!keys.contains(DepartmentDirectoryColumn.selection.key)) {
      selectedIds = {};
    }
    state = DepartmentDirectoryState(
      allDepartments: state.allDepartments,
      filteredDepartments: state.filteredDepartments,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: selectedIds,
      lastDeleted: state.lastDeleted,
      lastBulkUpdatedDepartments: state.lastBulkUpdatedDepartments,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: DepartmentDirectoryColumn.pinSelectionFirst(
        List<DepartmentDirectoryColumn>.from(state.columnOrder),
      ),
      visibleColumnKeys: keys,
    );
    await _persistDepartmentColumnLayout(state);
    filterAndSort();
  }

  /// Εισαγωγή νέου τμήματος. Προωθεί [DepartmentExistsException] στο UI (δεν καταπίνεται).
  Future<void> addDepartment(DepartmentModel d) async {
    try {
      await DatabaseHelper.instance.insertDepartment(d.toMap());
    } on DepartmentExistsException {
      rethrow;
    }
    await _refreshLookupCache();
    await loadDepartments();
  }

  /// Επαναφορά soft-deleted τμήματος με ακριβές όνομα + προαιρετική ενημέρωση πεδίων από τη φόρμα.
  Future<void> restoreDepartmentByName(
    String name, {
    String? building,
    String? color,
    String? notes,
  }) async {
    await DatabaseHelper.instance.restoreDepartmentByName(
      name,
      building: building,
      color: color,
      notes: notes,
    );
    await _refreshLookupCache();
    await loadDepartments();
  }

  Future<void> updateDepartment(DepartmentModel d) async {
    if (d.id == null) return;
    final nameTaken = await DatabaseHelper.instance
        .departmentNameExistsExcluding(d.name, d.id!);
    if (nameTaken) {
      throw StateError('Υπάρχει ήδη άλλο τμήμα με αυτό το όνομα.');
    }
    await DatabaseHelper.instance.updateDepartment(d.id!, d.toMap());
    await _refreshLookupCache();
    await loadDepartments();
  }

  Future<void> deleteSelected() async {
    if (state.selectedIds.isEmpty) return;
    final toDelete = state.allDepartments
        .where((d) => d.id != null && state.selectedIds.contains(d.id))
        .toList();
    await DatabaseHelper.instance
        .softDeleteDepartments(state.selectedIds.toList());
    await _refreshLookupCache();
    if (!ref.mounted) return;
    state = DepartmentDirectoryState(
      allDepartments: state.allDepartments,
      filteredDepartments: state.filteredDepartments,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: {},
      lastDeleted: toDelete,
      lastBulkUpdatedDepartments: state.lastBulkUpdatedDepartments,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: state.columnOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
    await loadDepartments();
  }

  Future<void> undoLastDelete() async {
    final list = state.lastDeleted;
    if (list == null || list.isEmpty) return;
    final ids = list.map((d) => d.id).whereType<int>().toList();
    await DatabaseHelper.instance.restoreDepartments(ids);
    await _refreshLookupCache();
    if (!ref.mounted) return;
    _patch(lastDeleted: null);
    await loadDepartments();
  }

  Future<void> bulkUpdate(List<int> ids, Map<String, dynamic> changes) async {
    if (ids.isEmpty || changes.isEmpty) return;
    final toUpdate = state.allDepartments
        .where((d) => d.id != null && ids.contains(d.id))
        .toList();
    if (toUpdate.isEmpty) return;
    await DatabaseHelper.instance.bulkUpdateDepartments(ids, changes);
    await _refreshLookupCache();
    if (!ref.mounted) return;
    state = DepartmentDirectoryState(
      allDepartments: state.allDepartments,
      filteredDepartments: state.filteredDepartments,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: state.selectedIds,
      lastDeleted: state.lastDeleted,
      lastBulkUpdatedDepartments: toUpdate,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: state.columnOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
    await loadDepartments();
  }

  Future<void> undoLastBulkUpdate() async {
    final list = state.lastBulkUpdatedDepartments;
    if (list == null || list.isEmpty) return;
    for (final d in list) {
      if (d.id != null) {
        await DatabaseHelper.instance.updateDepartment(d.id!, d.toMap());
        if (!ref.mounted) return;
      }
    }
    _patch(lastBulkUpdatedDepartments: null);
    await _refreshLookupCache();
    await loadDepartments();
  }
}

final departmentDirectoryProvider = NotifierProvider<
    DepartmentDirectoryNotifier, DepartmentDirectoryState>(
  DepartmentDirectoryNotifier.new,
);
