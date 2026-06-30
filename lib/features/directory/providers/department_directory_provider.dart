import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/building_map_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/department_repository.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/phone_repository.dart';
import '../../../core/database/settings_repository.dart';
import '../../../core/errors/department_exists_exception.dart';
import '../../../core/services/lookup_service.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../../../core/utils/department_floor_sync.dart';
import '../../calls/provider/lookup_provider.dart';
import '../models/department_directory_column.dart';
import '../models/department_model.dart';
import 'directory_cache_refresh.dart';

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
  }) : columnOrder = DepartmentDirectoryColumn.pinSelectionFirst(
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
        if (visibleColumnKeys.contains(c.key)) c,
    ];
  }
}

/// Notifier καταλόγου τμημάτων.
class DepartmentDirectoryNotifier extends Notifier<DepartmentDirectoryState> {
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
    final dbCols = await DatabaseHelper.instance.database;
    final raw = await SettingsRepository(
      dbCols,
    ).getSetting(_catalogDepartmentsVisibleColumnsKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return _parseColumnLayoutFromJson(raw);
  }

  Future<void> _persistDepartmentColumnLayout(
    DepartmentDirectoryState s,
  ) async {
    final order = s.columnOrder;
    final vis = s.visibleColumnKeys;
    final payload = jsonEncode({
      'order': order.map((c) => c.key).toList(),
      'visible': [
        for (final c in order)
          if (vis.contains(c.key)) c.key,
      ],
    });
    final dbPersist = await DatabaseHelper.instance.database;
    await SettingsRepository(
      dbPersist,
    ).saveSetting(_catalogDepartmentsVisibleColumnsKey, payload);
  }

  Future<void> loadDepartments() async {
    _DepartmentColumnLayout? parsed;
    if (!_columnLayoutHydrated) {
      parsed = await _readColumnLayoutFromSettings();
      _columnLayoutHydrated = true;
    }
    final dbLoad = await DatabaseHelper.instance.database;
    final rows = await DepartmentRepository(dbLoad).getActiveDepartments();
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
        final did = d.id;
        final phonesText = did == null
            ? ''
            : LookupService.instance.getPhonesByDepartment(did).join(' ');
        final equipmentText = did == null
            ? ''
            : LookupService.instance
                  .getAllEquipmentByDepartment(did)
                  .map((e) {
                    final code = e.code?.trim();
                    if (code != null && code.isNotEmpty) return code;
                    return e.displayLabel.trim();
                  })
                  .where((v) => v.isNotEmpty)
                  .join(' ');
        final blob = [
          d.name,
          d.building ?? '',
          d.groupName ?? '',
          d.notes ?? '',
          d.color ?? '',
          d.floorDisplay ?? '',
          phonesText,
          equipmentText,
          '${d.id ?? ''}',
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
          case 'phones':
            final aPhones = LookupService.instance
                .getPhonesByDepartment(a.id ?? -1)
                .join(', ');
            final bPhones = LookupService.instance
                .getPhonesByDepartment(b.id ?? -1)
                .join(', ');
            cmp = aPhones.compareTo(bPhones);
            break;
          case 'equipment':
            final aEquipment = LookupService.instance
                .getAllEquipmentByDepartment(a.id ?? -1)
                .map(
                  (e) => e.code?.trim().isNotEmpty == true
                      ? e.code!.trim()
                      : e.displayLabel.trim(),
                )
                .where((v) => v.isNotEmpty)
                .join(', ');
            final bEquipment = LookupService.instance
                .getAllEquipmentByDepartment(b.id ?? -1)
                .map(
                  (e) => e.code?.trim().isNotEmpty == true
                      ? e.code!.trim()
                      : e.displayLabel.trim(),
                )
                .where((v) => v.isNotEmpty)
                .join(', ');
            cmp = aEquipment.compareTo(bEquipment);
            break;
          default:
            cmp = 0;
        }
        return asc ? cmp : -cmp;
      });
    }
    final len = list.length;
    final idx = state.focusedRowIndex;
    final clamped = idx != null && idx >= len
        ? (len > 0 ? len - 1 : null)
        : idx;
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
    final clamped = index == null || len == 0 ? null : index.clamp(0, len - 1);
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
      focusedRowIndex: keepFocusedRow ? state.focusedRowIndex : focusedRow,
      columnOrder: columnOrder ?? state.columnOrder,
      visibleColumnKeys: visibleColumnKeys ?? state.visibleColumnKeys,
    );
  }

  void toggleSelection(int id) {
    if (!state.visibleColumnKeys.contains(
      DepartmentDirectoryColumn.selection.key,
    )) {
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
    final item = rest.removeAt(oldIndex);
    rest.insert(newIndex, item);
    final newOrder = DepartmentDirectoryColumn.pinSelectionFirst([
      sel,
      ...rest,
    ]);
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
      final dbAdd = await DatabaseHelper.instance.database;
      await DepartmentRepository(dbAdd).insertDepartment(d.toMap());
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
    final dbRestoreName = await DatabaseHelper.instance.database;
    await DepartmentRepository(dbRestoreName).restoreDepartmentByName(
      name,
      building: building,
      color: color,
      notes: notes,
    );
    await _refreshLookupCache();
    await loadDepartments();
  }

  Future<void> updateDepartment(
    DepartmentModel d, {
    bool clearBuildingMapPlacement = false,
  }) async {
    if (d.id == null) {
      throw ArgumentError.value(d.id, 'd.id', 'updateDepartment requires id');
    }
    final dbUpd = await DatabaseHelper.instance.database;
    final departments = DepartmentRepository(dbUpd);
    final nameTaken =
        await departments.departmentNameExistsExcluding(d.name, d.id!);
    if (nameTaken) {
      throw StateError('Υπάρχει ήδη άλλο τμήμα με αυτό το όνομα.');
    }
    var map = Map<String, dynamic>.from(d.toMap());
    if (d.floorId != null) {
      map = DepartmentFloorSync.mergeFloorContext(
        map,
        manualFloorId: d.floorId,
      );
    } else {
      map['floor_id'] = null;
      if (clearBuildingMapPlacement) {
        map.addAll(
          BuildingMapRepository.clearedBuildingMapPlacementColumns(
            clearFloorId: false,
            clearDepartmentHex: false,
          ),
        );
      }
    }
    await departments.updateDepartment(d.id!, map);
    await _refreshLookupCache();
    await loadDepartments();
    await refreshDirectoryCaches(ref, users: true, equipment: true);
  }

  Future<void> updateDepartmentSharedAssets(
    int departmentId, {
    required List<String> sharedPhones,
    required List<String> sharedEquipmentCodes,
    Set<String> phonesToMoveFromUsers = const {},
    Set<String> equipmentToMoveFromUsers = const {},
    Map<String, int> phoneTransfers = const {},
    Map<String, int> equipmentTransfers = const {},
    List<String> phonesToSoftDelete = const [],
    List<String> equipmentToSoftDelete = const [],
  }) async {
    final lookup = LookupService.instance;
    final existingPhones = lookup
        .getDirectPhonesByDepartment(departmentId)
        .toSet();
    final nextPhones = sharedPhones
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet();

    final dbShared = await DatabaseHelper.instance.database;
    final phones = PhoneRepository(dbShared);
    final equipment = EquipmentRepository(dbShared);
    for (final p in nextPhones.difference(existingPhones)) {
      if (phonesToMoveFromUsers.contains(p)) {
        await phones.removePhoneFromAllUsers(p);
      }
      await phones.addDepartmentDirectPhone(departmentId, p);
    }
    for (final p in existingPhones.difference(nextPhones)) {
      await phones.removeDepartmentDirectPhone(departmentId, p);
    }

    final existingEq = lookup
        .getSharedEquipmentCodesByDepartment(departmentId)
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet();
    final nextEq = sharedEquipmentCodes
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet();

    for (final code in nextEq.difference(existingEq)) {
      if (equipmentToMoveFromUsers.contains(code)) {
        await equipment.removeEquipmentFromAllUsers(code);
      }
      await equipment.updateEquipmentDepartment(code, departmentId);
    }
    for (final code in existingEq.difference(nextEq)) {
      await equipment.clearEquipmentSharedDepartment(code, departmentId);
    }

    for (final entry in phoneTransfers.entries) {
      final phone = entry.key.trim();
      final targetId = entry.value;
      if (phone.isEmpty) continue;
      await phones.removeDepartmentDirectPhone(departmentId, phone);
      await phones.addDepartmentDirectPhone(targetId, phone);
    }
    for (final entry in equipmentTransfers.entries) {
      final code = entry.key.trim();
      final targetId = entry.value;
      if (code.isEmpty) continue;
      await equipment.clearEquipmentSharedDepartment(code, departmentId);
      await equipment.updateEquipmentDepartment(code, targetId);
    }

    if (phonesToSoftDelete.isNotEmpty) {
      final phoneIds = <int>[];
      for (final p in phonesToSoftDelete) {
        final id = await phones.getPhoneIdByNumber(p);
        if (id != null) phoneIds.add(id);
      }
      if (phoneIds.isNotEmpty) {
        await phones.softDeletePhones(phoneIds);
      }
    }
    if (equipmentToSoftDelete.isNotEmpty) {
      final equipmentIds = <int>[];
      for (final code in equipmentToSoftDelete) {
        final id = await equipment.getEquipmentIdByCode(code);
        if (id != null) equipmentIds.add(id);
      }
      if (equipmentIds.isNotEmpty) {
        await equipment.deleteEquipments(equipmentIds);
      }
    }

    await _refreshLookupCache();
    await loadDepartments();
    await refreshDirectoryCaches(ref, users: true, equipment: true);
  }

  Future<void> deleteSelected() async {
    if (state.selectedIds.isEmpty) return;
    final toDelete = state.allDepartments
        .where(
          (d) =>
              d.id != null &&
              !d.isDeleted &&
              state.selectedIds.contains(d.id),
        )
        .toList();
    if (toDelete.isEmpty) return;
    final ids = toDelete.map((d) => d.id!).toList();
    final dbDel = await DatabaseHelper.instance.database;
    await DepartmentRepository(dbDel).softDeleteDepartments(ids);
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
    final dbUndoDel = await DatabaseHelper.instance.database;
    await DepartmentRepository(dbUndoDel).restoreDepartments(ids);
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
    final dbBulk = await DatabaseHelper.instance.database;
    await DepartmentRepository(dbBulk).bulkUpdateDepartments(ids, changes);
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
    final dbUndoBulk = await DatabaseHelper.instance.database;
    final departments = DepartmentRepository(dbUndoBulk);
    try {
      for (final d in list) {
        if (d.id != null) {
          await departments.updateDepartment(d.id!, d.toMap());
          if (!ref.mounted) break;
        }
      }
    } finally {
      _patch(lastBulkUpdatedDepartments: null);
      await _refreshLookupCache();
      if (ref.mounted) {
        await loadDepartments();
      }
    }
  }
}

final departmentDirectoryProvider =
    NotifierProvider<DepartmentDirectoryNotifier, DepartmentDirectoryState>(
      DepartmentDirectoryNotifier.new,
    );
