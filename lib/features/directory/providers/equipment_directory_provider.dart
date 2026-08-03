import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/department_repository.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/settings_repository.dart';
import '../../../core/database/user_repository.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/id_search_query.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../../calls/models/equipment_model.dart';
import '../../calls/provider/lookup_provider.dart';
import '../../calls/models/user_model.dart';
import '../../../core/database/sqlite_types.dart';
import '../models/equipment_column.dart';
import '../services/bulk_action_undo_record.dart';
import '../services/bulk_equipment_actions.dart';
import 'bulk_action_undo_provider.dart';
import 'directory_cache_refresh.dart';

const _catalogEquipmentLayoutKey = 'catalog_equipment_columns';

typedef _EquipmentColumnLayout = ({
  List<EquipmentColumn> order,
  Set<String> visible,
  String? sortKey,
  bool sortAscending,
});

/// Μία εγγραφή για αναίρεση διαγραφής ή αφαίρεσης συσχέτισης εξοπλισμού–χρήστη.
class EquipmentDeleteUndoEntry {
  const EquipmentDeleteUndoEntry({
    required this.equipmentId,
    required this.equipmentSnapshot,
    this.ownerSnapshot,
    this.unlinkedUserId,
    required this.feedbackLine,
  });

  final int equipmentId;
  final EquipmentModel equipmentSnapshot;
  final UserModel? ownerSnapshot;

  /// Μη null όταν η ενέργεια ήταν μόνο αφαίρεση συσχέτισης (όχι soft delete εξοπλισμού).
  final int? unlinkedUserId;
  final String feedbackLine;

  bool get wasUnlinkOnly => unlinkedUserId != null;
}

String _equipmentCodeForMessage(EquipmentModel equipment) {
  final raw = (equipment.code ?? '').trim();
  return raw.isEmpty ? '(χωρίς κωδικό)' : raw;
}

String _equipmentDeleteFeedbackLine({
  required bool unlinkOnly,
  required EquipmentModel equipment,
  required UserModel? owner,
  String? departmentName,
}) {
  final code = _equipmentCodeForMessage(equipment);
  if (unlinkOnly) {
    final n = (owner?.name ?? '').trim().isEmpty
        ? 'χρήστη'
        : owner!.name!.trim();
    return 'Αφαιρέθηκε ο εξοπλισμός: $code από τον $n';
  }
  if (owner != null) {
    final n = (owner.name ?? '').trim().isEmpty ? 'χρήστη' : owner.name!.trim();
    return 'Διαγράφηκε οριστικά ο εξοπλισμός: $code από τον $n και τον οργανισμό σας';
  }
  final dept = (departmentName ?? '').trim().isEmpty
      ? 'τμήμα'
      : departmentName!.trim();
  return 'Διαγράφηκε οριστικά ο εξοπλισμός: $code από το $dept';
}

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
        throw StateError(
          'mergeEquipmentVisibleOrderIntoColumnOrder: empty queue',
        );
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
    this.focusedRowIndex,
    this.showBuildingInLocationColumn = true,
    List<EquipmentColumn>? columnOrder,
    Set<String>? visibleColumnKeys,
  }) : columnOrder = _normalizeColumnOrder(columnOrder),
       visibleColumnKeys = _normalizeVisibleKeys(visibleColumnKeys);

  static List<EquipmentColumn> _normalizeColumnOrder(
    List<EquipmentColumn>? raw,
  ) {
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
  final List<EquipmentDeleteUndoEntry>? lastDeleted;
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
      if (visibleColumnKeys.contains(c.key)) c,
  ];

  EquipmentDirectoryState copyWith({
    List<EquipmentRow>? allItems,
    List<EquipmentRow>? filteredItems,
    String? searchQuery,
    Object? sortColumn = _kUnsetSort,
    bool? sortAscending,
    Set<int>? selectedIds,
    bool clearLastDeleted = false,
    List<EquipmentDeleteUndoEntry>? lastDeleted,
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
      lastDeleted: clearLastDeleted ? null : (lastDeleted ?? this.lastDeleted),
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
  bool _loadInFlight = false;

  /// Σε unit tests (override → false) αποφεύγουμε `setSetting` χωρίς binding/βάση.
  bool get shouldPersistEquipmentLayout => true;

  Future<void> _refreshLookupCache() async {
    ref.invalidate(lookupServiceProvider);
    await ref.read(lookupServiceProvider.future);
    if (!ref.mounted) return;
  }

  Future<void> _afterEquipmentMutation({
    bool refreshUsers = true,
    bool refreshDepartments = false,
  }) async {
    await _refreshLookupCache();
    if (!ref.mounted) return;
    await load();
    if (!ref.mounted) return;
    await refreshDirectoryCaches(
      ref,
      users: refreshUsers,
      departments: refreshDepartments,
    );
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
    final dbLayout = await DatabaseHelper.instance.database;
    final raw = await SettingsRepository(
      dbLayout,
    ).getSetting(_catalogEquipmentLayoutKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return _parseEquipmentLayoutFromJson(raw);
  }

  Future<void> _persistEquipmentLayout() async {
    final s = state;
    final payload = jsonEncode({
      'order': s.columnOrder.map((c) => c.key).toList(),
      'visible': [
        for (final c in s.columnOrder)
          if (s.visibleColumnKeys.contains(c.key)) c.key,
      ],
      'sortColumn': s.sortColumn?.key,
      'sortAscending': s.sortAscending,
    });
    final dbPersist = await DatabaseHelper.instance.database;
    await SettingsRepository(
      dbPersist,
    ).saveSetting(_catalogEquipmentLayoutKey, payload);
  }

  void _schedulePersistEquipmentLayout() {
    if (!shouldPersistEquipmentLayout) return;
    unawaited(_persistEquipmentLayout());
  }

  @override
  EquipmentDirectoryState build() {
    return EquipmentDirectoryState();
  }

  Future<List<Map<String, dynamic>>> getEquipmentRows() async {
    final db = await DatabaseHelper.instance.database;
    return EquipmentRepository(db).getAllEquipment();
  }

  Future<List<Map<String, dynamic>>> getUserRows() async {
    final db = await DatabaseHelper.instance.database;
    return UserRepository(db).getAllUsers();
  }

  Future<void> load() async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    try {
      await _loadInternal();
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> _loadInternal() async {
    _EquipmentColumnLayout? parsed;
    if (!_equipmentLayoutHydrated) {
      parsed = await _readEquipmentLayoutFromSettings();
      _equipmentLayoutHydrated = true;
    }
    if (!ref.mounted) return;

    final showBuildingInLocation = await SettingsService().windowUi
        .getEquipmentLocationShowBuilding();
    if (!ref.mounted) return;

    final equipmentRows = await getEquipmentRows();
    if (!ref.mounted) return;
    final userRows = await getUserRows();
    if (!ref.mounted) return;
    final dbLoad = await DatabaseHelper.instance.database;
    final linkRows = await EquipmentRepository(
      dbLoad,
    ).getAllUserEquipmentLinks();
    if (!ref.mounted) return;

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
    await SettingsService().windowUi.setEquipmentLocationShowBuilding(value);
    state = state.copyWith(showBuildingInLocationColumn: value);
    filterAndSort();
  }

  void filterAndSort() {
    final idQuery = IdSearchQuery.parse(state.searchQuery);
    final q = SearchTextNormalizer.normalizeForSearch(idQuery.text);
    var list = state.allItems;
    final visibleCols = state.orderedVisibleColumns;

    if (!idQuery.isEmpty) {
      list = list.where((row) {
        if (!idQuery.matchesEntityId(row.$1.id)) return false;
        if (q.isEmpty) return true;
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
    final clamped = idx != null && idx >= len
        ? (len > 0 ? len - 1 : null)
        : idx;

    state = state.copyWith(filteredItems: list, focusedRowIndex: clamped);
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
    final clamped = index == null || len == 0 ? null : index.clamp(0, len - 1);
    state = state.copyWith(focusedRowIndex: clamped);
  }

  /// Εστιάζει γραμμή στον τρέχοντα φιλτραρισμένο πίνακα αν υπάρχει `equipment.id`.
  void focusEquipmentById(int equipmentId) {
    final items = state.filteredItems;
    for (var i = 0; i < items.length; i++) {
      final id = items[i].$1.id;
      if (id != null && id == equipmentId) {
        setFocusedRowIndex(i);
        return;
      }
    }
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
    _settlePendingBulkUndo();
    final dbEq = await DatabaseHelper.instance.database;
    final equipment = EquipmentRepository(dbEq);
    final id = await equipment.insertEquipmentFromMap(eq.toMap());
    if (ownerUserId != null) {
      await equipment.replaceEquipmentUsers(id, [ownerUserId]);
    }
    await _afterEquipmentMutation();
  }

  Future<void> updateEquipment(EquipmentModel eq, {int? ownerUserId}) async {
    _settlePendingBulkUndo();
    if (eq.id == null) {
      throw ArgumentError.value(eq.id, 'eq.id', 'updateEquipment requires id');
    }
    final dbUp = await DatabaseHelper.instance.database;
    final equipment = EquipmentRepository(dbUp);
    await equipment.updateEquipment(eq.id!, eq.toMap());
    await equipment.replaceEquipmentUsers(
      eq.id!,
      ownerUserId != null ? [ownerUserId] : [],
    );
    await _afterEquipmentMutation();
  }

  /// Διαγράφει την επιλογή, ή μόνο τα [onlyIds] όταν δίνονται.
  ///
  /// Το [onlyIds] υπάρχει επειδή ο χρήστης μπορεί να αφαίρεσε στοιχεία μέσα
  /// στην προεπισκόπηση: αυτά **δεν** διαγράφονται αλλά μένουν επιλεγμένα, για
  /// να τα χειριστεί αμέσως μετά.
  Future<void> deleteSelected({Set<int>? onlyIds}) async {
    if (state.selectedIds.isEmpty) return;
    final targetIds = onlyIds ?? state.selectedIds;
    if (targetIds.isEmpty) return;
    _settlePendingBulkUndo();
    final toProcess = state.allItems
        .where((row) => row.$1.id != null && targetIds.contains(row.$1.id))
        .toList();
    final undo = <EquipmentDeleteUndoEntry>[];

    final dbDel = await DatabaseHelper.instance.database;
    final equipment = EquipmentRepository(dbDel);
    final departments = DepartmentRepository(dbDel);
    await dbDel.transaction((txn) async {
      for (final row in toProcess) {
        final eq = row.$1;
        final owner = row.$2;
        final eid = eq.id;
        if (eid == null) continue;

        final linkCount = await equipment.countUsersLinkedToEquipment(
          eid,
          executor: txn,
        );
        String? deptName;
        if (owner == null && eq.departmentId != null) {
          deptName = await departments.getDepartmentNameById(
            eq.departmentId!,
            executor: txn,
          );
        }

        if (linkCount > 1 && owner?.id == null) {
          await equipment.deleteEquipments([eid], executor: txn);
          final code = _equipmentCodeForMessage(eq);
          undo.add(
            EquipmentDeleteUndoEntry(
              equipmentId: eid,
              equipmentSnapshot: eq,
              ownerSnapshot: null,
              unlinkedUserId: null,
              feedbackLine:
                  'Διαγράφηκε οριστικά ο εξοπλισμός: $code από τον οργανισμό σας',
            ),
          );
          continue;
        }

        if (linkCount > 1 && owner?.id != null) {
          await equipment.unlinkUserFromEquipment(
            owner!.id!,
            eid,
            executor: txn,
          );
          undo.add(
            EquipmentDeleteUndoEntry(
              equipmentId: eid,
              equipmentSnapshot: eq,
              ownerSnapshot: owner,
              unlinkedUserId: owner.id,
              feedbackLine: _equipmentDeleteFeedbackLine(
                unlinkOnly: true,
                equipment: eq,
                owner: owner,
                departmentName: deptName,
              ),
            ),
          );
        } else {
          await equipment.deleteEquipments([eid], executor: txn);
          undo.add(
            EquipmentDeleteUndoEntry(
              equipmentId: eid,
              equipmentSnapshot: eq,
              ownerSnapshot: owner,
              unlinkedUserId: null,
              feedbackLine: _equipmentDeleteFeedbackLine(
                unlinkOnly: false,
                equipment: eq,
                owner: owner,
                departmentName: deptName,
              ),
            ),
          );
        }
      }
    });

    // Ό,τι επέλεξε ο χρήστης και ΔΕΝ διαγράφηκε μένει επιλεγμένο.
    final survivingSelection = state.selectedIds
        .where((id) => !targetIds.contains(id))
        .toSet();
    state = state.copyWith(selectedIds: survivingSelection, lastDeleted: undo);
    await _afterEquipmentMutation();
  }

  Future<void> undoLastDelete() async {
    _settlePendingBulkUndo();
    final list = state.lastDeleted;
    if (list == null || list.isEmpty) return;
    final dbUndo = await DatabaseHelper.instance.database;
    final equipment = EquipmentRepository(dbUndo);
    for (final e in list.reversed) {
      if (e.wasUnlinkOnly) {
        await equipment.linkUserToEquipment(e.unlinkedUserId!, e.equipmentId);
      } else {
        await equipment.restoreEquipment([e.equipmentId]);
      }
    }
    state = state.copyWith(clearLastDeleted: true);
    await _afterEquipmentMutation();
  }

  /// Νέα μεταβολή καταλόγου = σιωπηλή οριστικοποίηση της εκκρεμούς προσφοράς
  /// αναίρεσης (αναίρεση πάνω από νεότερες αλλαγές θα τις πατούσε).
  void _settlePendingBulkUndo() {
    ref.read(pendingBulkUndoProvider.notifier).settleSilently();
  }

  /// Κοινό φινάλε μαζικής ενέργειας: η πράξη έχει ήδη ολοκληρωθεί ατομικά·
  /// εδώ ανανεώνονται τα caches και δημοσιεύεται η προσφορά αναίρεσης.
  Future<void> _finishBulkAction(
    String message,
    BulkActionUndoRecord record,
  ) async {
    state = state.copyWith(selectedIds: {});
    await _afterEquipmentMutation(refreshDepartments: true);
    if (!ref.mounted) return;
    ref
        .read(pendingBulkUndoProvider.notifier)
        .offer(
          scope: BulkUndoScope.equipment,
          message: message,
          record: record,
        );
  }

  Future<void> _runBulkAction(
    String message,
    Future<BulkActionUndoRecord> Function(DatabaseExecutor txn, Database db)
    apply,
  ) async {
    _settlePendingBulkUndo();
    final db = await DatabaseHelper.instance.database;
    late BulkActionUndoRecord record;
    await db.transaction((txn) async {
      record = await apply(txn, db);
    });
    await _finishBulkAction(message, record);
  }

  /// Μαζική μεταφορά εξοπλισμού σε τμήμα (μία ατομική συναλλαγή).
  Future<void> applyBulkTransfer(BulkEquipmentTransferPlan plan) async {
    if (!plan.hasWork) return;
    await _runBulkAction(
      bulkEquipmentTransferResultMessage(plan),
      (txn, db) => applyBulkEquipmentTransferInTxn(txn, db, plan),
    );
  }

  /// Μαζική ανάθεση κατόχου· το τμήμα ακολουθεί τον νέο κάτοχο.
  Future<void> applyBulkOwner(BulkEquipmentOwnerPlan plan) async {
    if (!plan.hasWork) return;
    await _runBulkAction(
      bulkEquipmentOwnerResultMessage(plan),
      (txn, db) => applyBulkEquipmentOwnerInTxn(txn, db, plan),
    );
  }

  /// Μαζική εγγραφή απλής στήλης (τύπος, τοποθεσία, σημειώσεις, κύριο εργαλείο).
  Future<void> applyBulkField({
    required List<EquipmentRow> rows,
    required String column,
    required Object? value,
    required String message,
    BulkEquipmentNotesMode? notesMode,
  }) async {
    if (rows.isEmpty) return;
    await _runBulkAction(
      message,
      (txn, db) => applyBulkEquipmentFieldInTxn(
        txn,
        db,
        rows: rows,
        column: column,
        value: value,
        notesMode: notesMode,
      ),
    );
  }

  /// Μαζικός καθαρισμός πεδίου εξοπλισμού.
  Future<void> applyBulkClear(BulkEquipmentClearPlan plan) async {
    if (!plan.hasWork) return;
    await _runBulkAction(
      bulkEquipmentClearResultMessage(plan),
      (txn, db) => applyBulkEquipmentClearInTxn(txn, db, plan),
    );
  }

  /// Εκτελεί την εκκρεμή αναίρεση μαζικής ενέργειας (πλήρης επαναφορά).
  Future<void> undoPendingBulkAction() async {
    final record = ref.read(pendingBulkUndoProvider.notifier).takeForUndo();
    if (record == null) return;
    final db = await DatabaseHelper.instance.database;
    await applyBulkActionUndo(db, record);
    if (!ref.mounted) return;
    await _afterEquipmentMutation(refreshDepartments: true);
  }
}

final equipmentDirectoryProvider =
    NotifierProvider<EquipmentDirectoryNotifier, EquipmentDirectoryState>(
      EquipmentDirectoryNotifier.new,
    );
