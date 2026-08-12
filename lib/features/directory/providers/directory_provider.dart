import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/phone_repository.dart';
import '../../../core/database/settings_repository.dart';
import '../../../core/database/user_repository.dart';
import '../../../core/services/lookup_service.dart';
import '../../../core/utils/id_search_query.dart';
import '../../../core/utils/phone_list_parser.dart';
import '../../../core/utils/user_identity_normalizer.dart';
import '../../calls/models/equipment_model.dart';
import '../../calls/models/user_model.dart';
import '../../calls/provider/lookup_provider.dart';
import '../models/non_user_phone_entry.dart';
import '../models/user_catalog_mode.dart';
import '../models/user_column_layout.dart';
import '../models/user_directory_column.dart';
import '../services/bulk_action_undo_record.dart';
import '../services/bulk_user_actions.dart';
import '../services/catalog_search_evaluation.dart';
import '../services/user_deletion_undo_record.dart';
import '../services/user_equipment_codes.dart';
import 'bulk_action_undo_provider.dart';
import 'directory_cache_refresh.dart';

const _catalogUsersVisibleColumnsKey = 'catalog_users_visible_columns';

class _UnsetFocus {
  const _UnsetFocus();
}

const _kUnsetFocus = _UnsetFocus();

class _UnsetDeletionUndo {
  const _UnsetDeletionUndo();
}

const _kUnsetDeletionUndo = _UnsetDeletionUndo();

class _UnsetLastDeleted {
  const _UnsetLastDeleted();
}

const _kUnsetLastDeleted = _UnsetLastDeleted();

/// Κατάσταση του κατάλογου χρηστών: πλήρης λίστα, φιλτραρισμένη λίστα, αναζήτηση, sort, επιλογές, undo, focused row.
class DirectoryState {
  DirectoryState({
    this.allUsers = const [],
    this.filteredUsers = const [],
    this.allNonUserPhones = const [],
    this.filteredNonUserPhones = const [],
    this.catalogMode = UserCatalogMode.personal,
    this.searchQuery = '',
    this.sortColumn,
    this.sortAscending = true,
    this.selectedIds = const {},
    this.lastDeleted,
    this.lastUserDeletionUndo,
    this.focusedRowIndex,
    this.searchSummary = CatalogSearchSummary.empty,
    List<UserDirectoryColumn>? columnOrder,
    Set<String>? visibleColumnKeys,
  }) : columnOrder = UserDirectoryColumn.pinSelectionFirst(
         List<UserDirectoryColumn>.from(columnOrder ?? UserDirectoryColumn.all),
       ),
       visibleColumnKeys = visibleColumnKeys != null
           ? Set<String>.from(visibleColumnKeys)
           : {for (final c in UserDirectoryColumn.all) c.key};

  final List<UserModel> allUsers;
  final List<UserModel> filteredUsers;

  /// Τηλέφωνα στη βάση χωρίς `user_phones` (λειτουργία «Κοινόχρηστα»).
  final List<NonUserPhoneEntry> allNonUserPhones;
  final List<NonUserPhoneEntry> filteredNonUserPhones;
  final UserCatalogMode catalogMode;
  final String searchQuery;
  final String? sortColumn;
  final bool sortAscending;
  final Set<int> selectedIds;
  final List<UserModel>? lastDeleted;

  /// Φάκελος πλήρους αναίρεσης διαγραφής υπαλλήλου (τηλέφωνα/εξοπλισμός).
  final UserDeletionUndoRecord? lastUserDeletionUndo;

  /// Ευρετήριο στη [filteredUsers] για keyboard navigation (πάνω/κάτω, Enter).
  final int? focusedRowIndex;

  /// Σύνοψη τρέχουσας αναζήτησης (πλήθος + ευρήματα σε κρυφά πεδία).
  final CatalogSearchSummary searchSummary;

  /// Πλήρης σειρά όλων των στηλών (κρυφές παραμένουν στη λίστα).
  final List<UserDirectoryColumn> columnOrder;

  /// Ποια στήλες εμφανίζονται στον πίνακα.
  final Set<String> visibleColumnKeys;

  /// Ορατές στήλες στον πίνακα, κατά [columnOrder].
  List<UserDirectoryColumn> get orderedVisibleColumns {
    return [
      for (final c in columnOrder)
        if (visibleColumnKeys.contains(c.key)) c,
    ];
  }

  DirectoryState copyWith({
    List<UserModel>? allUsers,
    List<UserModel>? filteredUsers,
    List<NonUserPhoneEntry>? allNonUserPhones,
    List<NonUserPhoneEntry>? filteredNonUserPhones,
    UserCatalogMode? catalogMode,
    String? searchQuery,
    String? sortColumn,
    bool? sortAscending,
    Set<int>? selectedIds,
    Object? lastDeleted = _kUnsetLastDeleted,
    Object? lastUserDeletionUndo = _kUnsetDeletionUndo,
    Object? focusedRowIndex = _kUnsetFocus,
    CatalogSearchSummary? searchSummary,
    List<UserDirectoryColumn>? columnOrder,
    Set<String>? visibleColumnKeys,
  }) {
    final nextFocus = identical(focusedRowIndex, _kUnsetFocus)
        ? this.focusedRowIndex
        : focusedRowIndex as int?;
    final nextUndo = identical(lastUserDeletionUndo, _kUnsetDeletionUndo)
        ? this.lastUserDeletionUndo
        : lastUserDeletionUndo as UserDeletionUndoRecord?;
    final nextLastDeleted = identical(lastDeleted, _kUnsetLastDeleted)
        ? this.lastDeleted
        : lastDeleted as List<UserModel>?;
    return DirectoryState(
      allUsers: allUsers ?? this.allUsers,
      filteredUsers: filteredUsers ?? this.filteredUsers,
      allNonUserPhones: allNonUserPhones ?? this.allNonUserPhones,
      filteredNonUserPhones:
          filteredNonUserPhones ?? this.filteredNonUserPhones,
      catalogMode: catalogMode ?? this.catalogMode,
      searchQuery: searchQuery ?? this.searchQuery,
      sortColumn: sortColumn ?? this.sortColumn,
      sortAscending: sortAscending ?? this.sortAscending,
      selectedIds: selectedIds ?? this.selectedIds,
      lastDeleted: nextLastDeleted,
      lastUserDeletionUndo: nextUndo,
      focusedRowIndex: nextFocus,
      searchSummary: searchSummary ?? this.searchSummary,
      columnOrder: columnOrder ?? this.columnOrder,
      visibleColumnKeys: visibleColumnKeys ?? this.visibleColumnKeys,
    );
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

  /// Νέα μεταβολή καταλόγου = σιωπηλή οριστικοποίηση της εκκρεμούς προσφοράς
  /// αναίρεσης μαζικής ενέργειας (αναίρεση πάνω από νεότερες αλλαγές θα τις
  /// πατούσε).
  void _settlePendingBulkUndo() {
    ref.read(pendingBulkUndoProvider.notifier).settleSilently();
  }

  Future<UserColumnLayout?> _readColumnLayoutFromSettings() async {
    final dbRead = await DatabaseHelper.instance.database;
    final raw = await SettingsRepository(
      dbRead,
    ).getSetting(_catalogUsersVisibleColumnsKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return parseUserColumnLayoutJson(raw);
  }

  Future<void> _persistUserColumnLayout(DirectoryState s) async {
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
    ).saveSetting(_catalogUsersVisibleColumnsKey, payload);
  }

  /// Φόρτωση χρηστών από τη βάση και εφαρμογή filter/sort.
  Future<void> loadUsers() async {
    UserColumnLayout? parsed;
    if (!_columnLayoutHydrated) {
      parsed = await _readColumnLayoutFromSettings();
      _columnLayoutHydrated = true;
    }
    final dbUsers = await DatabaseHelper.instance.database;
    final repo = UserRepository(dbUsers);
    final rows = await repo.getAllUsers();
    final nonUserRows = await PhoneRepository(
      dbUsers,
    ).getNonUserPhonesCatalogRows();
    if (!ref.mounted) return;
    final list = rows.map((m) => UserModel.fromMap(m)).toList();
    final nonUserList = <NonUserPhoneEntry>[];
    for (final m in nonUserRows) {
      final pid = m['phone_id'];
      final rawNum = (m['number'] as String?)?.trim() ?? '';
      if (pid is! int || rawNum.isEmpty) continue;
      final deptNames = m['dept_names'] as String?;
      final primary = m['primary_department_id'];
      nonUserList.add(
        NonUserPhoneEntry(
          phoneId: pid,
          number: rawNum,
          departmentNamesDisplay:
              deptNames != null && deptNames.trim().isNotEmpty
              ? deptNames
              : null,
          primaryDepartmentId: primary is int ? primary : null,
        ),
      );
    }
    state = DirectoryState(
      allUsers: list,
      allNonUserPhones: nonUserList,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: state.selectedIds,
      lastDeleted: state.lastDeleted,
      lastUserDeletionUndo: state.lastUserDeletionUndo,
      focusedRowIndex: state.focusedRowIndex,
      catalogMode: state.catalogMode,
      columnOrder: parsed != null
          ? List<UserDirectoryColumn>.from(parsed.order)
          : List<UserDirectoryColumn>.from(state.columnOrder),
      visibleColumnKeys: parsed != null
          ? Set<String>.from(parsed.visible)
          : Set<String>.from(state.visibleColumnKeys),
    );
    filterAndSort();
  }

  /// Φιλτράρισμα in-memory στα γεγονότα κάθε χρήστη (όνομα, τηλέφωνα, τμήμα,
  /// εξοπλισμός, σημειώσεις, τοποθεσία) — **ανεξάρτητα** από τις ορατές
  /// στήλες: οι στήλες ρυθμίζουν τι βλέπεις, όχι τι βρίσκεται. Η σύνοψη
  /// καταγράφει πόσα ευρήματα ταίριαξαν μόνο σε κρυφά πεδία.
  void filterAndSort() {
    final builder = CatalogSearchSummaryBuilder();
    final users = _filterAndSortPersonalUsers(builder);
    final shared = _filterAndSortSharedPhones(builder);
    final len = state.catalogMode == UserCatalogMode.shared
        ? shared.length
        : users.length;
    final idx = state.focusedRowIndex;
    final clamped = idx != null && idx >= len
        ? (len > 0 ? len - 1 : null)
        : idx;
    final idQuery = IdSearchQuery.parse(state.searchQuery);
    state = state.copyWith(
      filteredUsers: users,
      filteredNonUserPhones: shared,
      focusedRowIndex: clamped,
      searchSummary: idQuery.isEmpty
          ? CatalogSearchSummary.empty
          : builder.build(),
    );
  }

  /// Γεγονότα χρήστη με τις ετικέτες των στηλών τους· η «Τοποθεσία» και το
  /// «Αναγνωριστικό Lansweeper» δεν έχουν στήλη στον πίνακα, οπότε μετρούν
  /// πάντα ως κρυφά πεδία — η γραμμή αποτελεσμάτων το λέει ρητά, ώστε ένα
  /// εύρημα «από το πουθενά» να έχει εξήγηση.
  List<CatalogSearchFact> _searchFactsForUser(UserModel u) {
    bool visible(String key) => state.visibleColumnKeys.contains(key);
    return [
      CatalogSearchFact(
        label: UserDirectoryColumn.id.label,
        text: '${u.id ?? ''}',
        isVisible: visible(UserDirectoryColumn.id.key),
      ),
      CatalogSearchFact(
        label: UserDirectoryColumn.lastName.label,
        text: u.lastName ?? '',
        isVisible: visible(UserDirectoryColumn.lastName.key),
      ),
      CatalogSearchFact(
        label: UserDirectoryColumn.firstName.label,
        text: u.firstName ?? '',
        isVisible: visible(UserDirectoryColumn.firstName.key),
      ),
      CatalogSearchFact(
        label: UserDirectoryColumn.phone.label,
        text: u.phoneJoined,
        isVisible: visible(UserDirectoryColumn.phone.key),
      ),
      CatalogSearchFact(
        label: UserDirectoryColumn.department.label,
        text: u.departmentName ?? '',
        isVisible: visible(UserDirectoryColumn.department.key),
      ),
      CatalogSearchFact(
        label: UserDirectoryColumn.equipment.label,
        text: UserEquipmentCodes.textForUser(u.id),
        isVisible: visible(UserDirectoryColumn.equipment.key),
      ),
      CatalogSearchFact(
        label: UserDirectoryColumn.notes.label,
        text: u.notes ?? '',
        isVisible: visible(UserDirectoryColumn.notes.key),
      ),
      CatalogSearchFact(
        label: 'Τοποθεσία',
        text: u.location ?? '',
        isVisible: false,
      ),
      // Το «plakogianni» βρίσκει τον υπάλληλο μέσα από το «gnk\e.plakogianni»:
      // η αναζήτηση κοιτά μέσα στο κείμενο, οπότε ο τομέας δεν χρειάζεται.
      CatalogSearchFact(
        label: 'Αναγνωριστικό Lansweeper',
        text: u.lansweeperUsername ?? '',
        isVisible: false,
      ),
    ];
  }

  List<UserModel> _filterAndSortPersonalUsers(
    CatalogSearchSummaryBuilder builder,
  ) {
    final idQuery = IdSearchQuery.parse(state.searchQuery);
    var list = state.allUsers;
    if (!idQuery.isEmpty) {
      final countTowardsSummary =
          state.catalogMode == UserCatalogMode.personal;
      list = list.where((u) {
        if (!idQuery.matchesEntityId(u.id)) return false;
        final result = evaluateCatalogSearchRow(
          _searchFactsForUser(u),
          idQuery.text,
        );
        if (countTowardsSummary) builder.addMatch(result);
        return result.matches;
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
          case 'equipment':
            cmp = UserEquipmentCodes.textForUser(
              a.id,
            ).compareTo(UserEquipmentCodes.textForUser(b.id));
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
    return list;
  }

  List<NonUserPhoneEntry> _filterAndSortSharedPhones(
    CatalogSearchSummaryBuilder builder,
  ) {
    var list = state.allNonUserPhones;
    final idQuery = IdSearchQuery.parse(state.searchQuery);
    if (!idQuery.isEmpty) {
      final countTowardsSummary = state.catalogMode == UserCatalogMode.shared;
      list = list.where((e) {
        if (!idQuery.matchesEntityId(e.phoneId)) return false;
        final result = evaluateCatalogSearchRow([
          CatalogSearchFact(
            label: 'Τηλέφωνο',
            text: e.number,
            isVisible: true,
          ),
          CatalogSearchFact(
            label: 'Τμήμα',
            text: e.departmentLabel,
            isVisible: true,
          ),
        ], idQuery.text);
        if (countTowardsSummary) builder.addMatch(result);
        return result.matches;
      }).toList();
    }
    final col = state.sortColumn;
    final asc = state.sortAscending;
    if (col != null && col.isNotEmpty) {
      list = List<NonUserPhoneEntry>.from(list);
      list.sort((a, b) {
        int cmp;
        switch (col) {
          case 'phone':
            cmp = a.number.toLowerCase().compareTo(b.number.toLowerCase());
            break;
          case 'department':
            cmp = a.departmentLabel.toLowerCase().compareTo(
              b.departmentLabel.toLowerCase(),
            );
            break;
          default:
            cmp = a.number.toLowerCase().compareTo(b.number.toLowerCase());
        }
        return asc ? cmp : -cmp;
      });
    }
    return list;
  }

  /// Προσωπικά (χρήστες) vs κοινόχρηστα τηλέφωνα χωρίς σύνδεση χρήστη.
  void setCatalogMode(UserCatalogMode mode) {
    if (mode == state.catalogMode) return;
    String? col = state.sortColumn;
    if (mode == UserCatalogMode.shared) {
      if (col != 'phone' && col != 'department') {
        col = 'phone';
      }
    }
    state = state.copyWith(
      catalogMode: mode,
      selectedIds: {},
      focusedRowIndex: null,
      sortColumn: col,
    );
    filterAndSort();
  }

  void setFocusedRowIndex(int? index) {
    final len = state.catalogMode == UserCatalogMode.shared
        ? state.filteredNonUserPhones.length
        : state.filteredUsers.length;
    final clamped = index == null || len == 0 ? null : index.clamp(0, len - 1);
    state = state.copyWith(focusedRowIndex: clamped);
  }

  void setSearchQuery(String q) {
    state = state.copyWith(searchQuery: q);
    filterAndSort();
  }

  void setSort(String? column, bool ascending) {
    state = state.copyWith(sortColumn: column, sortAscending: ascending);
    filterAndSort();
  }

  void toggleSelection(int id) {
    if (state.catalogMode == UserCatalogMode.shared) {
      return;
    }
    if (!state.visibleColumnKeys.contains(UserDirectoryColumn.selection.key)) {
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

  /// Αλλαγή σειράς στο διάλογος Στήλες (δείκτες χωρίς τη στήλη [UserDirectoryColumn.selection]).
  Future<void> reorderUserColumns(int oldIndex, int newIndex) async {
    final sel = UserDirectoryColumn.selection;
    final full = List<UserDirectoryColumn>.from(state.columnOrder);
    final rest = full.where((c) => c != sel).toList();
    final item = rest.removeAt(oldIndex);
    rest.insert(newIndex, item);
    final newOrder = UserDirectoryColumn.pinSelectionFirst([sel, ...rest]);
    state = state.copyWith(columnOrder: newOrder);
    await _persistUserColumnLayout(state);
  }

  /// Ορατότητα στήλης χωρίς αλλαγή θέσης στη [columnOrder].
  Future<void> setUserColumnVisible(
    UserDirectoryColumn col,
    bool visible,
  ) async {
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
    state = state.copyWith(
      selectedIds: selectedIds,
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
    final list =
        u.phones.map((p) => p.trim()).where((p) => p.isNotEmpty).toList()
          ..sort();
    return PhoneListParser.joinPhones(list);
  }

  /// Έλεγχος διπλότυπου με φρέσκο lookup cache (πριν από αποθήκευση).
  Future<bool> hasDuplicateUserFresh(
    UserModel u, {
    int? excludeId,
    int? mirrorEquipmentFromUserId,
  }) async {
    await _refreshLookupCache();
    if (!ref.mounted) return false;
    return hasDuplicateUser(
      u,
      excludeId: excludeId,
      mirrorEquipmentFromUserId: mirrorEquipmentFromUserId,
    );
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
    final int? sourceId = mirrorEquipmentFromUserId ?? userId;
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
    _settlePendingBulkUndo();
    final db = await DatabaseHelper.instance.database;
    await UserRepository(db).insertUserFromMap(u.toMap());
    await _refreshLookupCache();
    await loadUsers();
    await refreshDirectoryCaches(ref, equipment: true);
  }

  /// Εισαγωγή χρήστη και αντιγραφή συνδέσεων `user_equipment` από [sourceUserId].
  /// Επιστρέφει το νέο `id` ή null αν αποτύχει το insert.
  Future<int?> addUserCloningEquipmentFrom(
    UserModel u,
    int sourceUserId,
  ) async {
    _settlePendingBulkUndo();
    final dbClone = await DatabaseHelper.instance.database;
    final users = UserRepository(dbClone);
    final newId = await users.insertUserFromMap(u.toMap());
    await EquipmentRepository(
      dbClone,
    ).copyUserEquipmentLinks(sourceUserId, newId);
    await _refreshLookupCache();
    await loadUsers();
    await refreshDirectoryCaches(ref, equipment: true);
    return newId;
  }

  Future<void> updateUser(UserModel u) async {
    if (u.id == null) return;
    _settlePendingBulkUndo();
    final dbUp = await DatabaseHelper.instance.database;
    // Η καρτέλα γράφεται ΟΛΟΚΛΗΡΗ: το toMap παραλείπει τα null κλειδιά, οπότε
    // χωρίς τη ρητή συμπλήρωση το άδειασμα Σημειώσεων/Τοποθεσίας/Τμήματος δεν
    // έφτανε ποτέ στη βάση — η παλιά τιμή έμενε σιωπηλά.
    final map = u.toMap()
      ..['location'] = u.location
      ..['notes'] = u.notes
      ..['department_id'] = u.departmentId
      ..['lansweeper_username'] = u.lansweeperUsername;
    await UserRepository(dbUp).updateUser(u.id!, map);
    await _refreshLookupCache();
    await loadUsers();
    await refreshDirectoryCaches(ref, equipment: true);
  }

  /// Μετά από ατομική soft-delete εκτός notifier (μία συναλλαγή με τις
  /// διαθέσεις τηλεφώνων/εξοπλισμού): ενημερώνει μόνο UI/cache, χωρίς νέο
  /// γράψιμο στη βάση.
  /// Το [keepSelectedIds] κρατά επιλεγμένους όσους **δεν** διαγράφηκαν: ο
  /// χρήστης μπορεί να τους αφαίρεσε από τη λίστα για να τους χειριστεί μετά.
  Future<void> finalizeExternalDeletion(
    List<UserModel> toDelete, {
    Set<int> keepSelectedIds = const {},
  }) async {
    if (toDelete.isEmpty) return;
    _settlePendingBulkUndo();
    await _refreshLookupCache();
    if (!ref.mounted) return;
    state = state.copyWith(
      selectedIds: Set<int>.from(keepSelectedIds),
      lastDeleted: toDelete,
      lastUserDeletionUndo: null,
    );
    await loadUsers();
    await refreshDirectoryCaches(ref, equipment: true);
  }

  /// Αποθηκεύει τον φάκελο πλήρους αναίρεσης μετά την εφαρμογή διαθέσεων.
  void rememberUserDeletionUndo(UserDeletionUndoRecord record) {
    state = state.copyWith(lastUserDeletionUndo: record);
  }

  Future<void> undoLastDelete() async {
    _settlePendingBulkUndo();
    final undoRecord = state.lastUserDeletionUndo;
    final list = state.lastDeleted;
    if (undoRecord != null) {
      final dbRestore = await DatabaseHelper.instance.database;
      await applyUserDeletionUndo(dbRestore, undoRecord);
    } else {
      if (list == null || list.isEmpty) return;
      final ids = list.map((u) => u.id).whereType<int>().toList();
      final dbRestore = await DatabaseHelper.instance.database;
      await UserRepository(dbRestore).restoreUsers(ids);
    }
    await _refreshLookupCache();
    if (!ref.mounted) return;
    state = state.copyWith(lastDeleted: null, lastUserDeletionUndo: null);
    await loadUsers();
    await refreshDirectoryCaches(ref, equipment: true);
  }

  /// Κοινό φινάλε μαζικής ενέργειας: ανανέωση caches/λίστας και δημοσίευση
  /// της προσφοράς αναίρεσης (η πράξη έχει ήδη ολοκληρωθεί ατομικά).
  Future<void> _finishBulkAction(
    String message,
    BulkActionUndoRecord record,
  ) async {
    await _refreshLookupCache();
    if (!ref.mounted) return;
    state = state.copyWith(selectedIds: {});
    await loadUsers();
    await refreshDirectoryCaches(ref, equipment: true, departments: true);
    if (!ref.mounted) return;
    ref
        .read(pendingBulkUndoProvider.notifier)
        .offer(scope: BulkUndoScope.users, message: message, record: record);
  }

  /// Μαζική μεταφορά υπαλλήλων σε τμήμα (μία ατομική συναλλαγή).
  Future<void> applyBulkTransfer(BulkUserTransferPlan plan) async {
    if (!plan.hasWork) return;
    _settlePendingBulkUndo();
    final db = await DatabaseHelper.instance.database;
    late BulkActionUndoRecord record;
    await db.transaction((txn) async {
      record = await applyBulkUserTransferInTxn(txn, db, plan);
    });
    await _finishBulkAction(bulkTransferResultMessage(plan), record);
  }

  /// Μαζικές σημειώσεις (προσθήκη ή αντικατάσταση) σε μία συναλλαγή.
  Future<void> applyBulkNotes({
    required List<UserModel> users,
    required String text,
    required BulkNotesMode mode,
    required String message,
  }) async {
    if (users.isEmpty) return;
    _settlePendingBulkUndo();
    final db = await DatabaseHelper.instance.database;
    late BulkActionUndoRecord record;
    await db.transaction((txn) async {
      record = await applyBulkUserNotesInTxn(
        txn,
        db,
        users: users,
        text: text,
        mode: mode,
      );
    });
    await _finishBulkAction(message, record);
  }

  /// Μαζικός καθαρισμός πεδίου (τηλέφωνα/εξοπλισμός/σημειώσεις) σε μία συναλλαγή.
  Future<void> applyBulkClear(BulkUserClearPlan plan) async {
    if (!plan.hasWork) return;
    _settlePendingBulkUndo();
    final db = await DatabaseHelper.instance.database;
    late BulkActionUndoRecord record;
    await db.transaction((txn) async {
      record = await applyBulkUserClearInTxn(txn, db, plan);
    });
    await _finishBulkAction(bulkClearResultMessage(plan), record);
  }

  /// Εκτελεί την εκκρεμή αναίρεση μαζικής ενέργειας (πλήρης επαναφορά).
  Future<void> undoPendingBulkAction() async {
    final record = ref.read(pendingBulkUndoProvider.notifier).takeForUndo();
    if (record == null) return;
    final db = await DatabaseHelper.instance.database;
    await applyBulkActionUndo(db, record);
    await _refreshLookupCache();
    if (!ref.mounted) return;
    await loadUsers();
    await refreshDirectoryCaches(ref, equipment: true, departments: true);
  }
}

final directoryProvider = NotifierProvider<DirectoryNotifier, DirectoryState>(
  DirectoryNotifier.new,
);

/// Παλαιό global κλειδί· αν λείπει το per-tab, διαβάζεται για συμβατότητα.
const kCatalogContinuousScrollLegacyKey = 'catalog_continuous_scroll';

const kCatalogContinuousScrollEquipmentKey =
    'catalog_continuous_scroll_equipment';
const kCatalogContinuousScrollUsersKey = 'catalog_continuous_scroll_users';
const kCatalogContinuousScrollDepartmentsKey =
    'catalog_continuous_scroll_departments';

Future<bool> _readCatalogContinuousScrollPerTable(
  SettingsRepository settings,
  String perTableKey,
) async {
  final specific = await settings.getSetting(perTableKey);
  if (specific != null) return specific == 'true';
  final legacy = await settings.getSetting(kCatalogContinuousScrollLegacyKey);
  if (legacy != null) return legacy == 'true';
  return true;
}

/// Συνεχής κύλιση πίνακα εξοπλισμού (ανά καρτέλα). Default: true.
final catalogEquipmentContinuousScrollProvider =
    FutureProvider.autoDispose<bool>((ref) async {
      final db = await DatabaseHelper.instance.database;
      return _readCatalogContinuousScrollPerTable(
        SettingsRepository(db),
        kCatalogContinuousScrollEquipmentKey,
      );
    });

/// Συνεχής κύλιση πινάκων χρηστών (προσωπικά / κοινόχρηστα). Default: true.
final catalogUsersContinuousScrollProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final db = await DatabaseHelper.instance.database;
  return _readCatalogContinuousScrollPerTable(
    SettingsRepository(db),
    kCatalogContinuousScrollUsersKey,
  );
});

/// Συνεχής κύλιση πίνακα τμημάτων. Default: true.
final catalogDepartmentsContinuousScrollProvider =
    FutureProvider.autoDispose<bool>((ref) async {
      final db = await DatabaseHelper.instance.database;
      return _readCatalogContinuousScrollPerTable(
        SettingsRepository(db),
        kCatalogContinuousScrollDepartmentsKey,
      );
    });
