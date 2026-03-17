import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../../calls/models/user_model.dart';

/// Κατάσταση του κατάλογου χρηστών: πλήρης λίστα, φιλτραρισμένη λίστα, αναζήτηση, sort, επιλογές, undo, focused row.
class DirectoryState {
  const DirectoryState({
    this.allUsers = const [],
    this.filteredUsers = const [],
    this.searchQuery = '',
    this.sortColumn,
    this.sortAscending = true,
    this.selectedIds = const {},
    this.lastDeleted,
    this.lastBulkUpdatedUsers,
    this.focusedRowIndex,
  });

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
}

/// Notifier για τη διαχείριση κατάλογου χρηστών: φόρτωση, φιλτράρισμα, ταξινόμηση, επιλογή, CRUD, undo διαγραφής.
class DirectoryNotifier extends Notifier<DirectoryState> {
  @override
  DirectoryState build() {
    return const DirectoryState();
  }

  /// Φόρτωση χρηστών από τη βάση και εφαρμογή filter/sort.
  Future<void> loadUsers() async {
    final rows = await DatabaseHelper.instance.getAllUsers();
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
    );
    filterAndSort();
  }

  /// Φιλτράρισμα in-memory (name + fullNameWithDepartment + phone + departmentName + notes) και ταξινόμηση.
  /// Χωρίς διάκριση τόνου/διαλυτικών (ι = ί = ϊ = ΐ).
  void filterAndSort() {
    final q = SearchTextNormalizer.normalizeForSearch(state.searchQuery);
    var list = state.allUsers;
    if (q.isNotEmpty) {
      list = list.where((u) {
        final name = SearchTextNormalizer.normalizeForSearch(u.name ?? '');
        final full = SearchTextNormalizer.normalizeForSearch(
          u.fullNameWithDepartment,
        );
        final phone = SearchTextNormalizer.normalizeForSearch(u.phone ?? '');
        final dept = SearchTextNormalizer.normalizeForSearch(
          u.departmentName ?? '',
        );
        final notes = SearchTextNormalizer.normalizeForSearch(u.notes ?? '');
        return name.contains(q) ||
            full.contains(q) ||
            phone.contains(q) ||
            dept.contains(q) ||
            notes.contains(q);
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
            cmp = (a.phone ?? '').compareTo(b.phone ?? '');
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
    );
    filterAndSort();
  }

  void toggleSelection(int id) {
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
    );
  }

  /// True αν υπάρχει ήδη χρήστης με τα ίδια επώνυμο, όνομα, τηλέφωνο, σημειώσεις.
  /// [excludeId] = id χρήστη να αγνοηθεί (π.χ. κατά επεξεργασία).
  bool hasDuplicateExcludingNotes(UserModel u, {int? excludeId}) {
    final ln = (u.lastName ?? '').trim();
    final fn = (u.firstName ?? '').trim();
    final ph = (u.phone ?? '').trim();
    final nt = (u.notes ?? '').trim();
    for (final existing in state.allUsers) {
      if (excludeId != null && existing.id == excludeId) continue;
      final eLn = (existing.lastName ?? '').trim();
      final eFn = (existing.firstName ?? '').trim();
      final ePh = (existing.phone ?? '').trim();
      final eNt = (existing.notes ?? '').trim();
      if (ln == eLn && fn == eFn && ph == ePh && nt == eNt) {
        return true;
      }
    }
    return false;
  }

  Future<void> addUser(UserModel u) async {
    await DatabaseHelper.instance.insertUserFromMap(u.toMap());
    await loadUsers();
  }

  Future<void> updateUser(UserModel u) async {
    if (u.id == null) return;
    await DatabaseHelper.instance.updateUser(u.id!, u.toMap());
    await loadUsers();
  }

  Future<void> deleteSelected() async {
    if (state.selectedIds.isEmpty) return;
    final toDelete = state.allUsers
        .where((u) => u.id != null && state.selectedIds.contains(u.id))
        .toList();
    await DatabaseHelper.instance.deleteUsers(state.selectedIds.toList());
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
    );
    await loadUsers();
  }

  Future<void> undoLastDelete() async {
    final list = state.lastDeleted;
    if (list == null || list.isEmpty) return;
    for (final u in list) {
      final map = u.toMap();
      map.remove('id');
      await DatabaseHelper.instance.insertUserFromMap(map);
    }
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
    await DatabaseHelper.instance.bulkUpdateUsers(ids, changes);
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
    );
    await loadUsers();
  }

  /// Αναίρεση τελευταίας μαζικής επεξεργασίας (επαναφορά παλιών τιμών).
  Future<void> undoLastBulkUpdate() async {
    final list = state.lastBulkUpdatedUsers;
    if (list == null || list.isEmpty) return;
    for (final u in list) {
      if (u.id != null) {
        await DatabaseHelper.instance.updateUser(u.id!, u.toMap());
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
    );
    await loadUsers();
  }
}

final directoryProvider =
    NotifierProvider.autoDispose<DirectoryNotifier, DirectoryState>(
  DirectoryNotifier.new,
);

/// Ρύθμιση «Συνεχής κύλιση πίνακα Καταλόγου». Default: true (συνεχής κύλιση).
final catalogContinuousScrollProvider = FutureProvider.autoDispose<bool>((ref) async {
  final db = DatabaseHelper.instance;
  final value = await db.getSetting('catalog_continuous_scroll');
  return value == null || value == 'true';
});
