import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../../calls/models/equipment_model.dart';
import '../../calls/provider/lookup_provider.dart';
import '../../calls/models/user_model.dart';
import '../models/equipment_column.dart';

const _catalogEquipmentLayoutKey = 'catalog_equipment_columns';

typedef _EquipmentColumnLayout = ({
  List<EquipmentColumn> order,
  Set<String> visible,
  String? sortKey,
  bool sortAscending,
});

/// Ενσωματώνει νέα σειρά ορατών στηλών (π.χ. chips) στη [columnOrder] χωρίς να ανακατεύει τις κρυφές.
List<EquipmentColumn> mergeEquipmentVisibleOrderIntoColumnOrder(
  List<EquipmentColumn> columnOrder,
  List<EquipmentColumn> newVisibleOrder,
  Set<String> visibleKeys,
) {
  final queue = List<EquipmentColumn>.from(newVisibleOrder);
  final out = <EquipmentColumn>[];
  for (final col in columnOrder) {
    if (visibleKeys.contains(col.key)) {
      if (queue.isEmpty) {
        throw StateError('mergeEquipmentVisibleOrderIntoColumnOrder: empty queue');
      }
      out.add(queue.removeAt(0));
    } else {
      out.add(col);
    }
  }
  return out;
}

/// Κατάσταση καρτέλας εξοπλισμού: πλήρης σειρά στηλών + κλειδιά ορατών (όπως DirectoryState χρηστών).
class EquipmentDirectoryState {
  static const Object _kUnsetSort = Object();

  EquipmentDirectoryState({
    this.allItems = const [],
    this.filteredItems = const [],
    this.searchQuery = '',
    this.sortColumn,
    this.sortAscending = true,
    this.selectedIds = const {},
    this.lastDeleted,
    this.lastBulkUpdated,
    this.focusedRowIndex,
    this.showBuildingInLocationColumn = true,
    List<EquipmentColumn>? columnOrder,
    Set<String>? visibleColumnKeys,
  })  : columnOrder = _normalizeColumnOrder(columnOrder),
        visibleColumnKeys = _normalizeVisibleKeys(visibleColumnKeys);

  static List<EquipmentColumn> _normalizeColumnOrder(List<EquipmentColumn>? raw) {
    final order = <EquipmentColumn>[];
    final seen = <String>{};
    for (final c in raw ?? EquipmentColumn.all) {
      if (seen.add(c.key)) order.add(c);
    }
    for (final c in EquipmentColumn.all) {
      if (!seen.contains(c.key)) order.add(c);
    }
    return EquipmentColumn.pinSelectionFirst(order);
  }

  static Set<String> _normalizeVisibleKeys(Set<String>? raw) {
    if (raw != null && raw.isNotEmpty) {
      final s = <String>{};
      for (final k in raw) {
        if (EquipmentColumn.fromKey(k) != null) s.add(k);
      }
      if (s.isEmpty) {
        return {for (final c in EquipmentColumn.defaults) c.key};
      }
      return s;
    }
    return {for (final c in EquipmentColumn.defaults) c.key};
  }

  final List<EquipmentRow> allItems;
  final List<EquipmentRow> filteredItems;
  final String searchQuery;
  final EquipmentColumn? sortColumn;
  final bool sortAscending;
  final Set<int> selectedIds;
  final List<EquipmentRow>? lastDeleted;
  final List<EquipmentRow>? lastBulkUpdated;
  final int? focusedRowIndex;
  /// Πλήρης σειρά όλων των στηλών (κρυφές παραμένουν στη λίστα).
  final List<EquipmentColumn> columnOrder;
  /// Ποια στήλη εμφανίζεται στον πίνακα.
  final Set<String> visibleColumnKeys;
  /// Πρόθεμα `[Κτίριο]` στη στήλη Τοποθεσία (πίνακας εξοπλισμού).
  final bool showBuildingInLocationColumn;

  /// Ορατές στήλες κατά [columnOrder].
  List<EquipmentColumn> get orderedVisibleColumns => [
        for (final c in columnOrder)
          if (visibleColumnKeys.contains(c.key)) c
      ];

  EquipmentDirectoryState copyWith({
    List<EquipmentRow>? allItems,
    List<EquipmentRow>? filteredItems,
    String? searchQuery,
    Object? sortColumn = _kUnsetSort,
    bool? sortAscending,
    Set<int>? selectedIds,
    List<EquipmentRow>? lastDeleted,
    List<EquipmentRow>? lastBulkUpdated,
    int? focusedRowIndex,
    bool? showBuildingInLocationColumn,
    List<EquipmentColumn>? columnOrder,
    Set<String>? visibleColumnKeys,
  }) {
    return EquipmentDirectoryState(
      allItems: allItems ?? this.allItems,
      filteredItems: filteredItems ?? this.filteredItems,
      searchQuery: searchQuery ?? this.searchQuery,
      sortColumn: identical(sortColumn, _kUnsetSort)
          ? this.sortColumn
          : sortColumn as EquipmentColumn?,
      sortAscending: sortAscending ?? this.sortAscending,
      selectedIds: selectedIds ?? this.selectedIds,
      lastDeleted: lastDeleted ?? this.lastDeleted,
      lastBulkUpdated: lastBulkUpdated ?? this.lastBulkUpdated,
      focusedRowIndex: focusedRowIndex ?? this.focusedRowIndex,
      showBuildingInLocationColumn:
          showBuildingInLocationColumn ?? this.showBuildingInLocationColumn,
      columnOrder: columnOrder ?? this.columnOrder,
      visibleColumnKeys: visibleColumnKeys ?? this.visibleColumnKeys,
    );
  }
}

/// Notifier: φόρτωση, φιλτράρισμα, ταξινόμηση, επιλογή, CRUD, undo, μαζική επεξεργασία.
class EquipmentDirectoryNotifier extends Notifier<EquipmentDirectoryState> {
  bool _equipmentLayoutHydrated = false;

  /// Σε unit tests (override → false) αποφεύγουμε `setSetting` χωρίς binding/βάση.
  bool get shouldPersistEquipmentLayout => true;

  void _invalidateLookupCache() {
    ref.invalidate(lookupServiceProvider);
  }

  String _cellTextForColumn(EquipmentRow row, EquipmentColumn col) {
    if (col.key == EquipmentColumn.location.key) {
      return equipmentRowLocationFormattedLine(
        row,
        showBuilding: state.showBuildingInLocationColumn,
      );
    }
    return col.displayValue(row);
  }

  Comparable? _sortComparableForRow(EquipmentRow row, EquipmentColumn col) {
    if (col.key == EquipmentColumn.location.key) {
      return equipmentRowLocationFormattedLine(
        row,
        showBuilding: state.showBuildingInLocationColumn,
      );
    }
    return col.sortValue?.call(row);
  }

  EquipmentColumn? _resolveSortColumn(String? key) {
    if (key == null || key.isEmpty) return null;
    final c = EquipmentColumn.fromKey(key);
    if (c == null || c.sortValue == null) return null;
    return c;
  }

  _EquipmentColumnLayout? _parseEquipmentLayoutFromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final o = decoded['order'];
        final v = decoded['visible'];
        final rawOrder = <EquipmentColumn>[];
        if (o is List) {
          for (final e in o) {
            if (e is! String) continue;
            final c = EquipmentColumn.fromKey(e);
            if (c != null) rawOrder.add(c);
          }
        }
        final seenKeys = <String>{};
        final order = <EquipmentColumn>[];
        for (final c in rawOrder) {
          if (seenKeys.add(c.key)) order.add(c);
        }
        for (final c in EquipmentColumn.all) {
          if (!seenKeys.contains(c.key)) order.add(c);
        }
        Set<String> visible;
        if (v is List && v.isNotEmpty) {
          visible = {};
          for (final e in v) {
            if (e is String && EquipmentColumn.fromKey(e) != null) {
              visible.add(e);
            }
          }
          if (visible.isEmpty) {
            visible = {for (final c in order) c.key};
          }
        } else {
          visible = {for (final c in order) c.key};
        }
        final sk = decoded['sortColumn'];
        final sortKey = sk is String ? sk : null;
        final sa = decoded['sortAscending'];
        final sortAscending = sa is bool ? sa : true;
        return (
          order: EquipmentColumn.pinSelectionFirst(order),
          visible: visible,
          sortKey: sortKey,
          sortAscending: sortAscending,
        );
      }
      if (decoded is List) {
        final ordered = <EquipmentColumn>[];
        final seen = <String>{};
        for (final e in decoded) {
          if (e is! String) continue;
          final c = EquipmentColumn.fromKey(e);
          if (c != null && seen.add(c.key)) ordered.add(c);
        }
        if (ordered.isEmpty) return null;
        for (final c in EquipmentColumn.all) {
          if (!seen.contains(c.key)) ordered.add(c);
        }
        return (
          order: EquipmentColumn.pinSelectionFirst(ordered),
          visible: Set<String>.from(seen),
          sortKey: null,
          sortAscending: true,
        );
      }
    } catch (_) {}
    return null;
  }

  Future<_EquipmentColumnLayout?> _readEquipmentLayoutFromSettings() async {
    final raw =
        await DatabaseHelper.instance.getSetting(_catalogEquipmentLayoutKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return _parseEquipmentLayoutFromJson(raw);
  }

  Future<void> _persistEquipmentLayout() async {
    final s = state;
    final payload = jsonEncode({
      'order': s.columnOrder.map((c) => c.key).toList(),
      'visible': [
        for (final c in s.columnOrder)
          if (s.visibleColumnKeys.contains(c.key)) c.key
      ],
      'sortColumn': s.sortColumn?.key,
      'sortAscending': s.sortAscending,
    });
    await DatabaseHelper.instance.setSetting(
      _catalogEquipmentLayoutKey,
      payload,
    );
  }

  void _schedulePersistEquipmentLayout() {
    if (!shouldPersistEquipmentLayout) return;
    unawaited(_persistEquipmentLayout());
  }

  @override
  EquipmentDirectoryState build() {
    final initial = EquipmentDirectoryState();
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
    _EquipmentColumnLayout? parsed;
    if (!_equipmentLayoutHydrated) {
      parsed = await _readEquipmentLayoutFromSettings();
      _equipmentLayoutHydrated = true;
    }

    final showBuildingInLocation =
        await SettingsService().getEquipmentLocationShowBuilding();

    final equipmentRows = await getEquipmentRows();
    final userRows = await getUserRows();
    final linkRows = await DatabaseHelper.instance.getAllUserEquipmentLinks();

    final usersMap = <int, UserModel>{};
    for (final map in userRows) {
      final u = UserModel.fromMap(map);
      if (u.id != null) usersMap[u.id!] = u;
    }

    final equipmentIdToUserIds = <int, List<int>>{};
    for (final row in linkRows) {
      final uid = row['user_id'] as int?;
      final eid = row['equipment_id'] as int?;
      if (uid == null || eid == null) continue;
      equipmentIdToUserIds.putIfAbsent(eid, () => []).add(uid);
    }
    for (final list in equipmentIdToUserIds.values) {
      list.sort();
    }

    final List<EquipmentRow> items = [];
    for (final eq in equipmentRows) {
      final equipment = EquipmentModel.fromMap(eq);
      final eid = equipment.id;
      UserModel? owner;
      if (eid != null) {
        final uids = equipmentIdToUserIds[eid];
        if (uids != null && uids.isNotEmpty) {
          owner = usersMap[uids.first];
        }
      }
      items.add((equipment, owner));
    }

    if (parsed != null) {
      final sortCol = _resolveSortColumn(parsed.sortKey);
      state = state.copyWith(
        allItems: items,
        columnOrder: parsed.order,
        visibleColumnKeys: parsed.visible,
        sortColumn: sortCol,
        sortAscending: parsed.sortAscending,
        showBuildingInLocationColumn: showBuildingInLocation,
      );
    } else {
      state = state.copyWith(
        allItems: items,
        showBuildingInLocationColumn: showBuildingInLocation,
      );
    }
    filterAndSort();
  }

  Future<void> setEquipmentLocationShowBuilding(bool value) async {
    await SettingsService().setEquipmentLocationShowBuilding(value);
    state = state.copyWith(showBuildingInLocationColumn: value);
    filterAndSort();
  }

  void filterAndSort() {
    final q = SearchTextNormalizer.normalizeForSearch(state.searchQuery);
    var list = state.allItems;
    final visibleCols = state.orderedVisibleColumns;

    if (q.isNotEmpty) {
      list = list.where((row) {
        for (final col in visibleCols) {
          final text = _cellTextForColumn(row, col);
          if (text.isEmpty) continue;
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
        final va = _sortComparableForRow(a, col);
        final vb = _sortComparableForRow(b, col);
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
    _schedulePersistEquipmentLayout();
  }

  void toggleSelection(int id) {
    if (!state.visibleColumnKeys.contains(EquipmentColumn.selection.key)) {
      return;
    }
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
    if (newList.isEmpty) return;
    final pinned = EquipmentColumn.pinSelectionFirst(newList);
    final keys = {for (final c in pinned) c.key};
    final merged = mergeEquipmentVisibleOrderIntoColumnOrder(
      state.columnOrder,
      pinned,
      keys,
    );
    state = state.copyWith(columnOrder: merged, visibleColumnKeys: keys);
    filterAndSort();
    _schedulePersistEquipmentLayout();
  }

  /// Αλλαγή σειράς στο διάλογος Στήλες (δείκτες χωρίς τη στήλη [EquipmentColumn.selection]).
  void reorderEquipmentColumns(int oldIndex, int newIndex) {
    final sel = EquipmentColumn.selection;
    final full = List<EquipmentColumn>.from(state.columnOrder);
    final rest = full.where((c) => c.key != sel.key).toList();
    if (oldIndex < newIndex) newIndex -= 1;
    final item = rest.removeAt(oldIndex);
    rest.insert(newIndex, item);
    final newOrder = EquipmentColumn.pinSelectionFirst([sel, ...rest]);
    state = state.copyWith(columnOrder: newOrder);
    _schedulePersistEquipmentLayout();
  }

  /// Μετακίνηση ορατών στηλών (chips): ενημερώνει [columnOrder] διατηρώντας τις κρυφές.
  void reorderColumn(int oldIndex, int newIndex) {
    final visible = state.orderedVisibleColumns;
    final list = List<EquipmentColumn>.from(visible);
    if (oldIndex < newIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    final pinned = EquipmentColumn.pinSelectionFirst(list);
    final merged = mergeEquipmentVisibleOrderIntoColumnOrder(
      state.columnOrder,
      pinned,
      state.visibleColumnKeys,
    );
    state = state.copyWith(columnOrder: merged);
    _schedulePersistEquipmentLayout();
  }

  void setEquipmentColumnVisible(EquipmentColumn col, bool visible) {
    var keys = Set<String>.from(state.visibleColumnKeys);
    if (visible) {
      keys.add(col.key);
    } else {
      keys.remove(col.key);
    }
    if (keys.isEmpty) {
      keys = {for (final c in EquipmentColumn.defaults) c.key};
    }
    final keepSelection = keys.contains(EquipmentColumn.selection.key);
    state = state.copyWith(
      visibleColumnKeys: keys,
      selectedIds: keepSelection ? state.selectedIds : {},
      columnOrder: EquipmentColumn.pinSelectionFirst(
        List<EquipmentColumn>.from(state.columnOrder),
      ),
    );
    filterAndSort();
    _schedulePersistEquipmentLayout();
  }

  void toggleColumn(EquipmentColumn col) {
    final on = state.visibleColumnKeys.contains(col.key);
    setEquipmentColumnVisible(col, !on);
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

  Future<void> addEquipment(EquipmentModel eq, {int? ownerUserId}) async {
    final id = await DatabaseHelper.instance.insertEquipmentFromMap(eq.toMap());
    if (ownerUserId != null) {
      await DatabaseHelper.instance.replaceEquipmentUsers(id, [ownerUserId]);
    }
    await load();
    _invalidateLookupCache();
  }

  Future<void> updateEquipment(EquipmentModel eq, {int? ownerUserId}) async {
    if (eq.id == null) return;
    await DatabaseHelper.instance.updateEquipment(eq.id!, eq.toMap());
    await DatabaseHelper.instance.replaceEquipmentUsers(
      eq.id!,
      ownerUserId != null ? [ownerUserId] : [],
    );
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
    final ids = list.map((row) => row.$1.id).whereType<int>().toList();
    await DatabaseHelper.instance.restoreEquipment(ids);
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
    final map = Map<String, dynamic>.from(changes);
    final ownerUpdate = map.containsKey('user_id');
    final ownerId = map.remove('user_id') as int?;
    if (map.isNotEmpty) {
      await DatabaseHelper.instance.bulkUpdateEquipments(ids, map);
    }
    if (ownerUpdate) {
      for (final id in ids) {
        await DatabaseHelper.instance.replaceEquipmentUsers(
          id,
          ownerId != null ? [ownerId] : [],
        );
      }
    }
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
        final uid = row.$2?.id;
        await DatabaseHelper.instance.replaceEquipmentUsers(
          row.$1.id!,
          uid != null ? [uid] : [],
        );
      }
    }
    state = state.copyWith(lastBulkUpdated: null);
    await load();
    _invalidateLookupCache();
  }
}

final equipmentDirectoryProvider = NotifierProvider<EquipmentDirectoryNotifier,
    EquipmentDirectoryState>(EquipmentDirectoryNotifier.new);
