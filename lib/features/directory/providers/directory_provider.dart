import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_repository.dart';
import '../../../core/services/lookup_service.dart';
import '../../../core/utils/phone_list_parser.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../../../core/utils/user_identity_normalizer.dart';
import '../../calls/models/equipment_model.dart';
import '../../calls/models/user_model.dart';
import '../../calls/provider/lookup_provider.dart';
import '../models/user_directory_column.dart';

const _catalogUsersVisibleColumnsKey = 'catalog_users_visible_columns';

/// Αποτέλεσμα ανάγνωσης ρυθμίσεων στηλών χρηστών (σειρά πλήρους λίστας + ποια κλειδιά είναι ορατά).
typedef _UserColumnLayout = ({
  List<UserDirectoryColumn> order,
  Set<String> visible,
});

/// Κατάσταση του κατάλογου χρηστών: πλήρης λίστα, φιλτραρισμένη λίστα, αναζήτηση, sort, επιλογές, undo, focused row.
class DirectoryState {
  DirectoryState({
    this.allUsers = const [],
    this.filteredUsers = const [],
    this.searchQuery = '',
    this.sortColumn,
    this.sortAscending = true,
    this.selectedIds = const {},
    this.lastDeleted,
    this.lastBulkUpdatedUsers,
    this.focusedRowIndex,
    List<UserDirectoryColumn>? columnOrder,
    Set<String>? visibleColumnKeys,
  })  : columnOrder = UserDirectoryColumn.pinSelectionFirst(
          List<UserDirectoryColumn>.from(
            columnOrder ?? UserDirectoryColumn.all,
          ),
        ),
        visibleColumnKeys = visibleColumnKeys != null
            ? Set<String>.from(visibleColumnKeys)
            : {for (final c in UserDirectoryColumn.all) c.key};

  final List<UserModel> allUsers;
  final List<UserModel> filteredUsers;
  final String searchQuery;
  final String? sortColumn;
  final bool sortAscending;
  final Set<int> selectedIds;
  final List<UserModel>? lastDeleted;
  /// Πριν την τελευταία μαζική επεξεργασία (για undo).
  final List<UserModel>? lastBulkUpdatedUsers;
  /// Ευρετήριο στη [filteredUsers] για keyboard navigation (πάνω/κάτω, Enter).
  final int? focusedRowIndex;
  /// Πλήρης σειρά όλων των στηλών (κρυφές παραμένουν στη λίστα).
  final List<UserDirectoryColumn> columnOrder;
  /// Ποια στήλες εμφανίζονται στον πίνακα.
  final Set<String> visibleColumnKeys;

  /// Ορατές στήλες στον πίνακα, κατά [columnOrder].
  List<UserDirectoryColumn> get orderedVisibleColumns {
    return [
      for (final c in columnOrder)
        if (visibleColumnKeys.contains(c.key)) c
    ];
  }
}

/// Notifier για τη διαχείριση κατάλογου χρηστών: φόρτωση, φιλτράρισμα, ταξινόμηση, επιλογή, CRUD, undo διαγραφής.
class DirectoryNotifier extends Notifier<DirectoryState> {
  /// Διάταξη στηλών φορτώνεται από ρυθμίσεις μία φορά ανά ζωή notifier (όχι σε κάθε loadUsers).
  bool _columnLayoutHydrated = false;

  @override
  DirectoryState build() {
    return DirectoryState();
  }

  /// Όλοι οι χρήστες καταλόγου για έλεγχους από UI (π.χ. συνωνυμία) χωρίς πρόσβαση στο protected [state].
  List<UserModel> get allUsersForUi => state.allUsers;

  /// Ανανέωση in-memory [LookupService] ώστε η φόρμα κλήσης (καλούντας) να βλέπει διαγραφές/επαναφορές χωρίς restart.
  Future<void> _refreshLookupCache() async {
    ref.invalidate(lookupServiceProvider);
    await ref.read(lookupServiceProvider.future);
    if (!ref.mounted) return;
  }

  _UserColumnLayout? _parseColumnLayoutFromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final o = decoded['order'];
        final v = decoded['visible'];
        final rawOrder = <UserDirectoryColumn>[];
        if (o is List) {
          for (final e in o) {
            if (e is! String) continue;
            final c = UserDirectoryColumn.fromKey(e);
            if (c != null) rawOrder.add(c);
          }
        }
        final seenKeys = <String>{};
        final order = <UserDirectoryColumn>[];
        for (final c in rawOrder) {
          if (seenKeys.add(c.key)) order.add(c);
        }
        for (final c in UserDirectoryColumn.all) {
          if (!seenKeys.contains(c.key)) order.add(c);
        }
        Set<String> visible;
        if (v is List && v.isNotEmpty) {
          visible = {};
          for (final e in v) {
            if (e is String && UserDirectoryColumn.fromKey(e) != null) {
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
          order: UserDirectoryColumn.pinSelectionFirst(order),
          visible: visible,
        );
      }
      if (decoded is List) {
        final ordered = <UserDirectoryColumn>[];
        final seen = <String>{};
        for (final e in decoded) {
          if (e is! String) continue;
          final c = UserDirectoryColumn.fromKey(e);
          if (c != null && seen.add(c.key)) ordered.add(c);
        }
        if (ordered.isEmpty) return null;
        for (final c in UserDirectoryColumn.all) {
          if (!seen.contains(c.key)) ordered.add(c);
        }
        return (
          order: UserDirectoryColumn.pinSelectionFirst(ordered),
          visible: Set<String>.from(seen),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<_UserColumnLayout?> _readColumnLayoutFromSettings() async {
    final dbRead = await DatabaseHelper.instance.database;
    final raw =
        await DirectoryRepository(dbRead).getSetting(_catalogUsersVisibleColumnsKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return _parseColumnLayoutFromJson(raw);
  }

  Future<void> _persistUserColumnLayout(DirectoryState s) async {
    final order = s.columnOrder;
    final vis = s.visibleColumnKeys;
    final payload = jsonEncode({
      'order': order.map((c) => c.key).toList(),
      'visible': [
        for (final c in order)
          if (vis.contains(c.key)) c.key
      ],
    });
    final dbPersist = await DatabaseHelper.instance.database;
    await DirectoryRepository(dbPersist).setSetting(
      _catalogUsersVisibleColumnsKey,
      payload,
    );
  }

  /// Φόρτωση χρηστών από τη βάση και εφαρμογή filter/sort.
  Future<void> loadUsers() async {
    _UserColumnLayout? parsed;
    if (!_columnLayoutHydrated) {
      parsed = await _readColumnLayoutFromSettings();
      _columnLayoutHydrated = true;
    }
    final dbUsers = await DatabaseHelper.instance.database;
    final rows = await DirectoryRepository(dbUsers).getAllUsers();
    if (!ref.mounted) return;
    final list = rows.map((m) => UserModel.fromMap(m)).toList();
    state = DirectoryState(
      allUsers: list,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: state.selectedIds,
      lastDeleted: state.lastDeleted,
      lastBulkUpdatedUsers: state.lastBulkUpdatedUsers,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: parsed != null
          ? List<UserDirectoryColumn>.from(parsed.order)
          : List<UserDirectoryColumn>.from(state.columnOrder),
      visibleColumnKeys: parsed != null
          ? Set<String>.from(parsed.visible)
          : Set<String>.from(state.visibleColumnKeys),
    );
    filterAndSort();
  }

  /// Φιλτράρισμα in-memory σε ενιαίο κείμενο ανά χρήστη: όνομα, επώνυμο, τηλέφωνο,
  /// σημειώσεις, τμήμα ([LookupService] μέσω [UserModel.departmentName]).
  /// Όλα τα tokens του query πρέπει να περιέχονται στο κανονικοποιημένο blob
  /// ([SearchTextNormalizer.containsAllTokens]).
  void filterAndSort() {
    final q = SearchTextNormalizer.normalizeForSearch(state.searchQuery);
    var list = state.allUsers;
    if (q.isNotEmpty) {
      list = list.where((u) {
        final blob = [
          u.firstName ?? '',
          u.lastName ?? '',
          u.phoneJoined,
          u.notes ?? '',
          u.departmentName ?? '',
          u.location ?? '',
        ].join(' ');
        return SearchTextNormalizer.containsAllTokens(blob, state.searchQuery);
      }).toList();
    }
    final col = state.sortColumn;
    final asc = state.sortAscending;
    if (col != null && col.isNotEmpty) {
      list = List<UserModel>.from(list);
      list.sort((a, b) {
        int cmp;
        switch (col) {
          case 'id':
            cmp = ((a.id ?? 0).compareTo(b.id ?? 0));
            break;
          case 'last_name':
            cmp = (a.lastName ?? '').compareTo(b.lastName ?? '');
            break;
          case 'first_name':
            cmp = (a.firstName ?? '').compareTo(b.firstName ?? '');
            break;
          case 'phone':
            cmp = a.phoneJoined.compareTo(b.phoneJoined);
            break;
          case 'department':
            cmp = (a.departmentName ?? '').compareTo(b.departmentName ?? '');
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
    state = DirectoryState(
      allUsers: state.allUsers,
      filteredUsers: list,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: state.selectedIds,
      lastDeleted: state.lastDeleted,
      lastBulkUpdatedUsers: state.lastBulkUpdatedUsers,
      focusedRowIndex: clamped,
      columnOrder: state.columnOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
  }

  void setFocusedRowIndex(int? index) {
    final len = state.filteredUsers.length;
    final clamped = index == null || len == 0
        ? null
        : index.clamp(0, len - 1);
    state = DirectoryState(
      allUsers: state.allUsers,
      filteredUsers: state.filteredUsers,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: state.selectedIds,
      lastDeleted: state.lastDeleted,
      lastBulkUpdatedUsers: state.lastBulkUpdatedUsers,
      focusedRowIndex: clamped,
      columnOrder: state.columnOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
  }

  void setSearchQuery(String q) {
    state = DirectoryState(
      allUsers: state.allUsers,
      filteredUsers: state.filteredUsers,
      searchQuery: q,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: state.selectedIds,
      lastDeleted: state.lastDeleted,
      lastBulkUpdatedUsers: state.lastBulkUpdatedUsers,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: state.columnOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
    filterAndSort();
  }

  void setSort(String? column, bool ascending) {
    state = DirectoryState(
      allUsers: state.allUsers,
      filteredUsers: state.filteredUsers,
      searchQuery: state.searchQuery,
      sortColumn: column,
      sortAscending: ascending,
      selectedIds: state.selectedIds,
      lastDeleted: state.lastDeleted,
      lastBulkUpdatedUsers: state.lastBulkUpdatedUsers,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: state.columnOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
    filterAndSort();
  }

  void toggleSelection(int id) {
    if (!state.visibleColumnKeys.contains(UserDirectoryColumn.selection.key)) {
      return;
    }
    final next = Set<int>.from(state.selectedIds);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    state = DirectoryState(
      allUsers: state.allUsers,
      filteredUsers: state.filteredUsers,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: next,
      lastDeleted: state.lastDeleted,
      lastBulkUpdatedUsers: state.lastBulkUpdatedUsers,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: state.columnOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
  }

  void clearSelection() {
    state = DirectoryState(
      allUsers: state.allUsers,
      filteredUsers: state.filteredUsers,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: {},
      lastDeleted: state.lastDeleted,
      lastBulkUpdatedUsers: state.lastBulkUpdatedUsers,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: state.columnOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
  }

  /// Αλλαγή σειράς στο διάλογος Στήλες (δείκτες χωρίς τη στήλη [UserDirectoryColumn.selection]).
  Future<void> reorderUserColumns(int oldIndex, int newIndex) async {
    final sel = UserDirectoryColumn.selection;
    final full = List<UserDirectoryColumn>.from(state.columnOrder);
    final rest = full.where((c) => c != sel).toList();
    if (oldIndex < newIndex) newIndex -= 1;
    final item = rest.removeAt(oldIndex);
    rest.insert(newIndex, item);
    final newOrder = UserDirectoryColumn.pinSelectionFirst([sel, ...rest]);
    state = DirectoryState(
      allUsers: state.allUsers,
      filteredUsers: state.filteredUsers,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: state.selectedIds,
      lastDeleted: state.lastDeleted,
      lastBulkUpdatedUsers: state.lastBulkUpdatedUsers,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: newOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
    await _persistUserColumnLayout(state);
  }

  /// Ορατότητα στήλης χωρίς αλλαγή θέσης στη [columnOrder].
  Future<void> setUserColumnVisible(UserDirectoryColumn col, bool visible) async {
    var keys = Set<String>.from(state.visibleColumnKeys);
    if (visible) {
      keys.add(col.key);
    } else {
      keys.remove(col.key);
    }
    if (keys.isEmpty) {
      keys = {for (final c in UserDirectoryColumn.all) c.key};
    }
    var selectedIds = state.selectedIds;
    if (!keys.contains(UserDirectoryColumn.selection.key)) {
      selectedIds = {};
    }
    state = DirectoryState(
      allUsers: state.allUsers,
      filteredUsers: state.filteredUsers,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: selectedIds,
      lastDeleted: state.lastDeleted,
      lastBulkUpdatedUsers: state.lastBulkUpdatedUsers,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: UserDirectoryColumn.pinSelectionFirst(
        List<UserDirectoryColumn>.from(state.columnOrder),
      ),
      visibleColumnKeys: keys,
    );
    await _persistUserColumnLayout(state);
    filterAndSort();
  }

  /// True αν υπάρχει ήδη χρήστης με ίδιο κανονικοποιημένο ονοματεπώνυμο
  /// ([UserIdentityNormalizer]), ίδιο κείμενο τηλεφώνου (`trim`) και ίδιο σύνολο
  /// κωδικών συνδεδεμένου εξοπλισμού (`user_equipment` → `code_equipment`).
  ///
  /// [excludeId]: αγνόηση τρέχουσας εγγραφής (επεξεργασία).
  /// [mirrorEquipmentFromUserId]: για χρήστη χωρίς `id` που μετά την αποθήκευση
  /// θα έχει τις ίδιες συνδέσεις με αυτόν το id (π.χ. ροή «νέος υπάλληλος»).
  static String _phonesComparable(UserModel u) {
    final list = u.phones
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList()
      ..sort();
    return PhoneListParser.joinPhones(list);
  }

  bool hasDuplicateUser(
    UserModel u, {
    int? excludeId,
    int? mirrorEquipmentFromUserId,
  }) {
    final nameKey = UserIdentityNormalizer.identityKeyForPerson(
      u.firstName,
      u.lastName,
    );
    final ph = _phonesComparable(u);
    final candidateEquip = _equipmentCodeKeySet(
      userId: u.id,
      mirrorEquipmentFromUserId: mirrorEquipmentFromUserId,
    );
    for (final existing in state.allUsers) {
      if (excludeId != null && existing.id == excludeId) continue;
      final eKey = UserIdentityNormalizer.identityKeyForPerson(
        existing.firstName,
        existing.lastName,
      );
      final ePh = _phonesComparable(existing);
      final eEquip = existing.id != null
          ? _equipmentCodeKeySet(userId: existing.id)
          : <String>{};
      if (nameKey == eKey &&
          ph == ePh &&
          _sameStringSets(candidateEquip, eEquip)) {
        return true;
      }
    }
    return false;
  }

  static Set<String> _equipmentCodeKeySet({
    int? userId,
    int? mirrorEquipmentFromUserId,
  }) {
    final int? sourceId =
        mirrorEquipmentFromUserId ?? userId;
    if (sourceId == null) return {};
    final list = LookupService.instance.findEquipmentsForUser(sourceId);
    return {for (final e in list) _equipmentCodeKey(e)};
  }

  static String _equipmentCodeKey(EquipmentModel e) {
    final c = e.code?.trim() ?? '';
    if (c.isNotEmpty) return c.toLowerCase();
    final id = e.id;
    if (id != null) return 'id:$id';
    return 'eq:unknown';
  }

  static bool _sameStringSets(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  Future<void> addUser(UserModel u) async {
    final db = await DatabaseHelper.instance.database;
    await DirectoryRepository(db).insertUserFromMap(u.toMap());
    await _refreshLookupCache();
    await loadUsers();
  }

  /// Εισαγωγή χρήστη και αντιγραφή συνδέσεων `user_equipment` από [sourceUserId].
  /// Επιστρέφει το νέο `id` ή null αν αποτύχει το insert.
  Future<int?> addUserCloningEquipmentFrom(
    UserModel u,
    int sourceUserId,
  ) async {
    final dbClone = await DatabaseHelper.instance.database;
    final dir = DirectoryRepository(dbClone);
    final newId = await dir.insertUserFromMap(u.toMap());
    await dir.copyUserEquipmentLinks(sourceUserId, newId);
    await _refreshLookupCache();
    await loadUsers();
    return newId;
  }

  Future<void> updateUser(UserModel u) async {
    if (u.id == null) return;
    final dbUp = await DatabaseHelper.instance.database;
    await DirectoryRepository(dbUp).updateUser(u.id!, u.toMap());
    await _refreshLookupCache();
    await loadUsers();
  }

  Future<void> deleteSelected() async {
    if (state.selectedIds.isEmpty) return;
    final toDelete = state.allUsers
        .where((u) => u.id != null && state.selectedIds.contains(u.id))
        .toList();
    final dbDel = await DatabaseHelper.instance.database;
    await DirectoryRepository(dbDel).deleteUsers(state.selectedIds.toList());
    await _refreshLookupCache();
    if (!ref.mounted) return;
    state = DirectoryState(
      allUsers: state.allUsers,
      filteredUsers: state.filteredUsers,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: {},
      lastDeleted: toDelete,
      lastBulkUpdatedUsers: state.lastBulkUpdatedUsers,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: state.columnOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
    await loadUsers();
  }

  Future<void> undoLastDelete() async {
    final list = state.lastDeleted;
    if (list == null || list.isEmpty) return;
    final ids = list.map((u) => u.id).whereType<int>().toList();
    final dbRestore = await DatabaseHelper.instance.database;
    await DirectoryRepository(dbRestore).restoreUsers(ids);
    await _refreshLookupCache();
    if (!ref.mounted) return;
    state = DirectoryState(
      allUsers: state.allUsers,
      filteredUsers: state.filteredUsers,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: state.selectedIds,
      lastDeleted: null,
      lastBulkUpdatedUsers: state.lastBulkUpdatedUsers,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: state.columnOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
    await loadUsers();
  }

  /// Μαζική ενημέρωση: εφαρμόζει [changes] σε όλα τα [ids]. Αποθηκεύει παλιές τιμές για undo.
  Future<void> bulkUpdate(List<int> ids, Map<String, dynamic> changes) async {
    if (ids.isEmpty || changes.isEmpty) return;
    final toUpdate = state.allUsers
        .where((u) => u.id != null && ids.contains(u.id))
        .toList();
    if (toUpdate.isEmpty) return;
    final dbBulk = await DatabaseHelper.instance.database;
    await DirectoryRepository(dbBulk).bulkUpdateUsers(ids, changes);
    await _refreshLookupCache();
    if (!ref.mounted) return;
    state = DirectoryState(
      allUsers: state.allUsers,
      filteredUsers: state.filteredUsers,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: state.selectedIds,
      lastDeleted: state.lastDeleted,
      lastBulkUpdatedUsers: toUpdate,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: state.columnOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
    await loadUsers();
  }

  /// Αναίρεση τελευταίας μαζικής επεξεργασίας (επαναφορά παλιών τιμών).
  Future<void> undoLastBulkUpdate() async {
    final list = state.lastBulkUpdatedUsers;
    if (list == null || list.isEmpty) return;
    for (final u in list) {
      if (u.id != null) {
        final dbUndo = await DatabaseHelper.instance.database;
        await DirectoryRepository(dbUndo).updateUser(u.id!, u.toMap());
        if (!ref.mounted) return;
      }
    }
    state = DirectoryState(
      allUsers: state.allUsers,
      filteredUsers: state.filteredUsers,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: state.selectedIds,
      lastDeleted: state.lastDeleted,
      lastBulkUpdatedUsers: null,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: state.columnOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
    await _refreshLookupCache();
    await loadUsers();
  }
}

final directoryProvider = NotifierProvider<DirectoryNotifier, DirectoryState>(
  DirectoryNotifier.new,
);

/// Ρύθμιση «Συνεχής κύλιση πίνακα Καταλόγου». Default: true (συνεχής κύλιση).
final catalogContinuousScrollProvider = FutureProvider.autoDispose<bool>((ref) async {
  final db = await DatabaseHelper.instance.database;
  final value = await DirectoryRepository(db).getSetting('catalog_continuous_scroll');
  return value == null || value == 'true';
});
