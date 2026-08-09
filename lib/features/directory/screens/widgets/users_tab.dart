import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/user_form_edit_intent_provider.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/database/department_repository.dart';
import '../../../../core/database/settings_repository.dart';
import '../../../../core/database/user_delete_equipment_policy.dart';
import '../../../../core/database/user_delete_phone_policy.dart';
import '../../../calls/layout/call_form_clear.dart';
import '../../../calls/models/user_model.dart';
import '../../../calls/provider/lookup_provider.dart';
import '../../../../core/services/lookup_service.dart';
import '../../models/department_model.dart';
import '../../models/non_user_phone_entry.dart';
import '../../models/user_catalog_mode.dart';
import '../../models/user_directory_column.dart';
import '../../providers/bulk_action_undo_provider.dart';
import '../../providers/department_directory_provider.dart';
import '../../providers/directory_provider.dart';
import '../../services/user_bulk_deletion_runner.dart';
import '../../services/department_deletion_inventory.dart';
import '../../services/user_deletion_messages.dart';
import '../../services/user_deletion_zones.dart';
import 'user_deletion_preview_dialog.dart';
import 'bulk_undo_bar.dart';
import 'bulk_user_edit_dialog.dart';
import 'catalog_column_selector_shell.dart';
import 'department_form_dialog.dart';
import 'non_user_phones_data_table.dart';
import 'shared_asset_disconnect_dialog.dart';
import 'user_form_dialog.dart';
import 'catalog_tab_lookup_reload_mixin.dart';
import 'catalog_search_field_sync.dart';
import 'users_data_table.dart';
import '../../../../core/widgets/compact_tooltip.dart';

/// Καρτέλα χρηστών: αναζήτηση, πίνακας, επιλογή, διαγραφή με undo, προσθήκη.
class UsersTab extends ConsumerStatefulWidget {
  const UsersTab({super.key});

  @override
  ConsumerState<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<UsersTab>
    with CatalogTabLookupReloadMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    attachCatalogLookupReloadListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(directoryProvider.notifier).loadUsers();
      final pending = ref.read(userFormEditIntentProvider);
      if (pending != null && mounted) {
        ref.read(userFormEditIntentProvider.notifier).clear();
        _openForm(context, ref, pending);
      }
    });
  }

  @override
  void dispose() {
    detachCatalogLookupReloadListener();
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UserModel?>(userFormEditIntentProvider, (previous, next) {
      if (next == null || !mounted) return;
      ref.read(userFormEditIntentProvider.notifier).clear();
      _openForm(context, ref, next);
    });
    final state = ref.watch(directoryProvider);
    final notifier = ref.read(directoryProvider.notifier);
    final visibleColumns = state.orderedVisibleColumns;
    final personal = state.catalogMode == UserCatalogMode.personal;
    final hasQuery = state.searchQuery.trim().isNotEmpty;
    final personalBadgeCount = (!personal && hasQuery)
        ? state.filteredUsers.length
        : 0;
    final sharedBadgeCount = (personal && hasQuery)
        ? state.filteredNonUserPhones.length
        : 0;
    final continuousScrollAsync = ref.watch(
      catalogUsersContinuousScrollProvider,
    );
    final continuousScroll = continuousScrollAsync.value ?? true;
    syncCatalogSearchControllerFromState(
      controller: _searchController,
      focusNode: _searchFocus,
      query: state.searchQuery,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: notifier.setSearchQuery,
                  decoration: InputDecoration(
                    labelText: 'Αναζήτηση',
                    hintText: personal
                        ? 'Όνομα, τηλέφωνο, τμήμα...'
                        : 'Τηλέφωνο, τμήμα...',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: state.searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Καθαρισμός',
                            onPressed: () => clearCatalogSearchField(
                              controller: _searchController,
                              setSearchQuery: notifier.setSearchQuery,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _CatalogModeToggle(
                mode: state.catalogMode,
                personalBadgeCount: personalBadgeCount,
                sharedBadgeCount: sharedBadgeCount,
                onPersonal: () =>
                    notifier.setCatalogMode(UserCatalogMode.personal),
                onShared: () => notifier.setCatalogMode(UserCatalogMode.shared),
              ),
              if (personal) ...[
                IconButton(
                  tooltip: 'Στήλες πίνακα',
                  icon: const Icon(Icons.view_column_outlined),
                  onPressed: () => _openColumnSelector(context, ref),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => _openForm(context, ref, null),
                  icon: const Icon(Icons.add),
                  label: const Text('Προσθήκη'),
                ),
              ],
            ],
          ),
        ),
        const BulkUndoBar(scope: BulkUndoScope.users),
        Expanded(
          child: personal
              ? UsersDataTable(
                  users: state.filteredUsers,
                  selectedIds: state.selectedIds,
                  sortColumn: state.sortColumn,
                  sortAscending: state.sortAscending,
                  visibleColumns: visibleColumns,
                  onToggleSelection: notifier.toggleSelection,
                  onSetSort: notifier.setSort,
                  onEditUser: (user, {focusedField}) =>
                      _openForm(context, ref, user, focusedField: focusedField),
                  focusedRowIndex: state.focusedRowIndex,
                  onSetFocusedRowIndex: notifier.setFocusedRowIndex,
                  onRequestDelete: () =>
                      _confirmAndDeleteSelected(context, ref),
                  onRequestBulkEdit: () => _openBulkEdit(context, ref),
                  continuousScroll: continuousScroll,
                )
              : NonUserPhonesDataTable(
                  entries: state.filteredNonUserPhones,
                  sortColumn: state.sortColumn,
                  sortAscending: state.sortAscending,
                  onSetSort: notifier.setSort,
                  onOpenDepartment: (e) =>
                      _openDepartmentForSharedPhone(context, ref, e),
                  focusedRowIndex: state.focusedRowIndex,
                  onSetFocusedRowIndex: notifier.setFocusedRowIndex,
                  continuousScroll: continuousScroll,
                ),
        ),
        if (personal && state.selectedIds.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text(
                  '${state.selectedIds.length} επιλεγμένοι',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(width: 16),
                FilledButton.tonal(
                  onPressed: () => _openBulkEdit(context, ref),
                  child: const Text('Επεξεργασία'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: state.selectedIds.length == 1
                      ? () {
                          final id = state.selectedIds.single;
                          final candidates = state.allUsers
                              .where((u) => u.id == id)
                              .toList();
                          if (candidates.isNotEmpty) {
                            _openForm(
                              context,
                              ref,
                              candidates.first,
                              isClone: true,
                            );
                          }
                        }
                      : null,
                  child: const Text('Αντίγραφο'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () => _confirmAndDeleteSelected(context, ref),
                  child: const Text('Διαγραφή'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _openColumnSelector(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.4),
      builder: (ctx) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: _UserColumnSelectorOverlay(
          onClose: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  Future<void> _openBulkEdit(BuildContext context, WidgetRef ref) async {
    final state = ref.read(directoryProvider);
    final selectedUsers = state.allUsers
        .where((u) => u.id != null && state.selectedIds.contains(u.id))
        .toList();
    if (selectedUsers.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => BulkUserEditDialog(
        selectedUsers: selectedUsers,
        notifier: ref.read(directoryProvider.notifier),
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    UserModel? user, {
    bool isClone = false,
    String? focusedField,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => UserFormDialog(
        initialUser: user,
        notifier: ref.read(directoryProvider.notifier),
        isClone: isClone,
        focusedField: focusedField,
      ),
    );
  }

  Future<void> _confirmAndDeleteSelected(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final state = ref.read(directoryProvider);
    if (state.selectedIds.isEmpty) return;
    final selectedUsers = state.allUsers
        .where((u) => u.id != null && state.selectedIds.contains(u.id))
        .toList();
    final confirmLabels = selectedUsers
        .map(
          (u) => employeeDisplayLabel(
            (u.name ?? '').trim().isEmpty ? '?' : u.name!.trim(),
            u.departmentName,
          ),
        )
        .toList();
    // Η προετοιμασία τρέχει ΠΡΙΝ τον διάλογο: μόνο έτσι η σύνοψη ξέρει πόσα
    // τηλέφωνα και εξοπλισμοί θα ζητήσουν απόφαση. Είναι μόνο αναγνώσεις —
    // αν ο χρήστης ακυρώσει, δεν έχει γραφτεί τίποτα.
    final db = await DatabaseHelper.instance.database;
    final fullPlan = await prepareUserBulkDeletion(
      db: db,
      users: selectedUsers,
    );
    if (!context.mounted) return;

    // Απογραφή ανά υπάλληλο: πόσα δικά του στοιχεία θα ζητήσουν απόφαση.
    final phonesByUser = <int, int>{};
    for (final p in fullPlan.exclusivePhones) {
      phonesByUser[p.userId] = (phonesByUser[p.userId] ?? 0) + 1;
    }
    final equipmentByUser = <int, int>{};
    for (final e in fullPlan.exclusiveEquipment) {
      equipmentByUser[e.userId] = (equipmentByUser[e.userId] ?? 0) + 1;
    }
    final inventories = [
      for (var i = 0; i < selectedUsers.length; i++)
        if (selectedUsers[i].id case final id?)
          UserDeletionInventory(
            userId: id,
            displayLabel: confirmLabels[i],
            exclusivePhoneCount: phonesByUser[id] ?? 0,
            exclusiveEquipmentCount: equipmentByUser[id] ?? 0,
          ),
    ];

    final preview = await showUserDeletionPreviewDialog(
      context: context,
      inventories: inventories,
    );
    if (preview == null || !preview.confirmed || !context.mounted) return;

    // Ο χρήστης μπορεί να αφαίρεσε υπαλλήλους μέσα στον διάλογο· από εδώ και
    // πέρα μετράει μόνο ό,τι έμεινε.
    final keptIds = preview.keptUserIds.toSet();
    final usersToDelete = selectedUsers
        .where((u) => keptIds.contains(u.id))
        .toList();
    if (usersToDelete.isEmpty) return;

    // Το σχέδιο ξαναχτίζεται για όσους έμειναν: αλλιώς η διαγραφή θα έπαιρνε
    // μαζί και τα στοιχεία όσων αφαιρέθηκαν.
    final plan = keptIds.length == selectedUsers.length
        ? fullPlan
        : await prepareUserBulkDeletion(db: db, users: usersToDelete);
    if (!context.mounted) return;

    final completedUsers = <UserModel>[];
    // Η διέξοδος προσφέρεται μέσα στον ίδιο διάλογο με την «Ακύρωση όλων»: το
    // «Συνέχεια» μπορεί να επιστρέψει στο βήμα ΜΟΝΟ όσο η ροή είναι ανοιχτή.
    final disconnectSession = plan.createDisconnectSession(
      completedWork: () {
        if (completedUsers.isEmpty) return null;
        return (
          summary: userDeletionCompletedSummary(
            completed: completedUsers.length,
            total: usersToDelete.length,
          ),
          applyHint: userDeletionApplyCompletedHint(completedUsers.length),
        );
      },
    );

    final phonesByUserId = <int, List<ExclusivePhoneForUserDelete>>{};
    for (final p in plan.exclusivePhones) {
      phonesByUserId.putIfAbsent(p.userId, () => []).add(p);
    }
    final equipmentByUserId = <int, List<ExclusiveEquipmentForUserDelete>>{};
    for (final e in plan.exclusiveEquipment) {
      equipmentByUserId.putIfAbsent(e.userId, () => []).add(e);
    }

    final availableDepartments = LookupService.instance.departments
        .where((d) => !d.isDeleted && d.name.trim().isNotEmpty)
        .toList();

    final phoneBatches = <UserDisconnectBatch>[];
    final equipmentBatches = <UserDisconnectBatch>[];
    var aborted = false;

    // Ένας γύρος ανά υπάλληλο, με τα τηλέφωνα και τον εξοπλισμό του μαζί.
    //
    // Πριν, η συλλογή έτρεχε έναν γύρο ανά **είδος** (πρώτα όλα τα τηλέφωνα
    // όλων, μετά όλος ο εξοπλισμός), οπότε στη μέση της ροής κανένας υπάλληλος
    // δεν ήταν βέβαιο ότι είχε απαντηθεί πλήρως — και η ακύρωση δεν είχε τι να
    // κρατήσει. Εδώ ο υπάλληλος μπαίνει στους ολοκληρωμένους μόνο αφού
    // απαντηθούν **και** τα δύο είδη.
    for (final user in usersToDelete) {
      final id = user.id;
      if (id == null) continue;
      final phones = phonesByUserId[id] ?? const [];
      final equipment = equipmentByUserId[id] ?? const [];

      final ownPhoneBatches = <UserDisconnectBatch>[];
      final ownEquipmentBatches = <UserDisconnectBatch>[];

      if (phones.isNotEmpty) {
        if (!context.mounted) return;
        final batch = await _askUserPersonalPhones(
          context,
          user: user,
          phones: phones,
          availableDepartments: availableDepartments,
          session: disconnectSession,
        );
        if (batch == null) {
          aborted = true;
          break;
        }
        ownPhoneBatches.add((
          batch: batch,
          sourceDepartmentId: phones.first.departmentId,
        ));
      }

      if (equipment.isNotEmpty) {
        if (!context.mounted) return;
        final batch = await _askUserPersonalEquipment(
          context,
          user: user,
          equipment: equipment,
          availableDepartments: availableDepartments,
          session: disconnectSession,
        );
        if (batch == null) {
          aborted = true;
          break;
        }
        ownEquipmentBatches.add((
          batch: batch,
          sourceDepartmentId: equipment.first.departmentId,
        ));
      }

      // Οι αποφάσεις κρατιούνται μόνο ολόκληρες: μισοαπαντημένος υπάλληλος δεν
      // αφήνει ίχνος.
      phoneBatches.addAll(ownPhoneBatches);
      equipmentBatches.addAll(ownEquipmentBatches);
      completedUsers.add(user);
    }

    if (!context.mounted) return;
    if (aborted) {
      // Η απόφαση πάρθηκε ήδη μέσα στη ροή, στον ίδιο διάλογο με την ακύρωση.
      if (disconnectSession.stopKind !=
          AssetDisconnectStopKind.applyCompleted) {
        _showDeletionCancelledSnackBar(context, usersToDelete.length);
        return;
      }
    }

    // Με τη διέξοδο διαγράφονται ΜΟΝΟ οι ολοκληρωμένοι, οπότε το σχέδιο
    // ξαναχτίζεται γι' αυτούς — αλλιώς θα έπαιρνε μαζί και τα στοιχεία όσων
    // έμειναν αναπάντητοι.
    final executedUsers = aborted ? completedUsers : usersToDelete;
    final executionPlan = aborted
        ? await prepareUserBulkDeletion(db: db, users: executedUsers)
        : plan;
    if (!context.mounted) return;

    final notifier = ref.read(directoryProvider.notifier);
    final undoRecord = await applyUserBulkDeletion(
      db: db,
      plan: executionPlan,
      phoneBatches: phoneBatches,
      equipmentBatches: equipmentBatches,
    );
    // Ό,τι επέλεξε ο χρήστης και ΔΕΝ διαγράφηκε μένει επιλεγμένο: το «✕» της
    // προεπισκόπησης σημαίνει «αυτούς αργότερα», όχι «αυτούς ποτέ».
    final deletedIds = {for (final u in executedUsers) u.id};
    final survivingSelection = state.selectedIds
        .where((id) => !deletedIds.contains(id))
        .toSet();

    await notifier.finalizeExternalDeletion(
      executedUsers,
      keepSelectedIds: survivingSelection,
    );
    notifier.rememberUserDeletionUndo(undoRecord);
    // Η μετάλλαξη ακύρωσε το lookup· η αλυσίδα των Κλήσεων δεν έχει listeners
    // όσο είμαστε στον Κατάλογο και πρέπει να ξεπλυθεί εκτός φάσης build.
    flushCallsChainAfterDirectoryMutation(ref);

    if (phoneBatches.isNotEmpty || equipmentBatches.isNotEmpty) {
      await notifier.loadUsers();
      ref.invalidate(lookupServiceProvider);
      await ref.read(lookupServiceProvider.future);
    }
    if (!context.mounted) return;

    final deleted = ref.read(directoryProvider).lastDeleted ?? [];
    final names = deleted
        .map((u) => u.name?.trim().isEmpty ?? true ? '?' : u.name!)
        .toList();
    // Το lookup έχει ήδη ξαναχτιστεί, οπότε η ερώτηση «έμεινε κενό;» απαντιέται
    // στα τωρινά δεδομένα.
    final emptiedDepartments = emptiedDepartmentNames(
      deleted.map((u) => u.departmentId),
    );
    final message = userDeletionSummaryMessage(
      employeeNames: names,
      assetActions: userDeletionAssetActions(
        phoneBatches: phoneBatches,
        equipmentBatches: equipmentBatches,
      ),
      emptiedDepartments: emptiedDepartments,
    );
    final tooltipAllNames = names.isEmpty ? null : names.join(', ');

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Expanded(
              child: tooltipAllNames != null
                  ? Tooltip(message: tooltipAllNames, child: Text(message))
                  : Text(message),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => messenger.hideCurrentSnackBar(),
              style: IconButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onInverseSurface,
                padding: const EdgeInsets.all(4),
                minimumSize: const Size(32, 32),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Αναίρεση',
          onPressed: () async {
            await notifier.undoLastDelete();
          },
        ),
      ),
    );
  }

  Future<void> _openDepartmentForSharedPhone(
    BuildContext context,
    WidgetRef ref,
    NonUserPhoneEntry entry,
  ) async {
    final deptId = entry.primaryDepartmentId;
    if (deptId == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν υπάρχει συσχετισμένο τμήμα για αυτόν τον αριθμό.'),
        ),
      );
      return;
    }
    await ref.read(departmentDirectoryProvider.notifier).loadDepartments();
    final db = await DatabaseHelper.instance.database;
    final row = await DepartmentRepository(db).getDepartmentRowById(deptId);
    if (!context.mounted) return;
    if (row == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Δεν βρέθηκε το τμήμα.')));
      return;
    }
    final model = DepartmentModel.fromMap(row);
    await showDialog<void>(
      context: context,
      builder: (ctx) => DepartmentFormDialog(
        initialDepartment: model,
        notifier: ref.read(departmentDirectoryProvider.notifier),
      ),
    );
    if (!context.mounted) return;
    ref.invalidate(lookupServiceProvider);
    await ref.read(lookupServiceProvider.future);
    if (!context.mounted) return;
    await ref.read(directoryProvider.notifier).loadUsers();
  }

  void _showDeletionCancelledSnackBar(BuildContext context, int userCount) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(userDeletionCancelledMessage(userCount))),
    );
  }

  /// Τα προσωπικά τηλέφωνα **ενός** υπαλλήλου. `null` = ο χρήστης διέκοψε.
  Future<SharedAssetDisconnectBatchResult?> _askUserPersonalPhones(
    BuildContext context, {
    required UserModel user,
    required List<ExclusivePhoneForUserDelete> phones,
    required List<DepartmentModel> availableDepartments,
    required AssetDisconnectSession session,
  }) async {
    final numbers = phones
        .map((p) => p.number)
        .where((n) => n.isNotEmpty)
        .toList();
    if (numbers.isEmpty) return const SharedAssetDisconnectBatchResult();

    final first = phones.first;
    return showSharedAssetDisconnectFlow(
      context: context,
      sourceDepartmentId: first.departmentId,
      sourceDepartmentName: first.departmentName,
      phones: numbers,
      availableDepartments: availableDepartments,
      mode: SharedAssetDisconnectMode.personalPhone,
      personalPhoneUserDisplayName: '${user.firstName} ${user.lastName}'.trim(),
      session: session,
    );
  }

  /// Ο προσωπικός εξοπλισμός **ενός** υπαλλήλου. `null` = ο χρήστης διέκοψε.
  Future<SharedAssetDisconnectBatchResult?> _askUserPersonalEquipment(
    BuildContext context, {
    required UserModel user,
    required List<ExclusiveEquipmentForUserDelete> equipment,
    required List<DepartmentModel> availableDepartments,
    required AssetDisconnectSession session,
  }) async {
    final codes = equipment
        .map((e) => e.codeEquipment)
        .where((c) => c.isNotEmpty)
        .toList();
    if (codes.isEmpty) return const SharedAssetDisconnectBatchResult();

    final first = equipment.first;
    return showSharedAssetDisconnectFlow(
      context: context,
      sourceDepartmentId: first.departmentId,
      sourceDepartmentName: first.departmentName,
      equipmentCodes: codes,
      availableDepartments: availableDepartments,
      mode: SharedAssetDisconnectMode.personalEquipment,
      personalPhoneUserDisplayName: '${user.firstName} ${user.lastName}'.trim(),
      allowKeepInDepartment: true,
      session: session,
    );
  }
}

/// Διακόπτης Προσωπικά / Κοινόχρηστα (εικονίδια asset).
class _CatalogModeToggle extends StatelessWidget {
  const _CatalogModeToggle({
    required this.mode,
    required this.personalBadgeCount,
    required this.sharedBadgeCount,
    required this.onPersonal,
    required this.onShared,
  });

  final UserCatalogMode mode;
  final int personalBadgeCount;
  final int sharedBadgeCount;
  final VoidCallback onPersonal;
  final VoidCallback onShared;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final personal = mode == UserCatalogMode.personal;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Μόνο τηλέφωνα υπαλλήλων',
          child: _modeButton(
            context: context,
            selected: personal,
            badgeCount: personalBadgeCount,
            onTap: onPersonal,
            child: Image.asset(
              'assets/phone_personal.png',
              width: 28,
              height: 28,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.phone_in_talk, color: scheme.primary, size: 28),
            ),
          ),
        ),
        const SizedBox(width: 4),
        CompactTooltip(
          message:
              'Κοινόχρηστα τηλέφωνα (τηλέφωνα που δεν σχετίζονται με υπαλλήλους)',
          child: _modeButton(
            context: context,
            selected: !personal,
            badgeCount: sharedBadgeCount,
            onTap: onShared,
            child: Image.asset(
              'assets/phone_department.png',
              width: 28,
              height: 28,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.business, color: scheme.primary, size: 28),
            ),
          ),
        ),
      ],
    );
  }

  Widget _modeButton({
    required BuildContext context,
    required bool selected,
    required int badgeCount,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final badgeText = badgeCount > 99 ? '99+' : badgeCount.toString();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
          child: Material(
            color: selected
                ? scheme.primaryContainer.withValues(alpha: 0.92)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Padding(padding: const EdgeInsets.all(6), child: child),
            ),
          ),
        ),
        if (badgeCount > 0)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                badgeText,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Overlay επιλογής στηλών: [selection] μόνο ορατότητα (πάντα πρώτη)· οι υπόλοιπες με σύρσιμο.
class _UserColumnSelectorOverlay extends ConsumerWidget {
  const _UserColumnSelectorOverlay({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(directoryProvider);
    final notifier = ref.read(directoryProvider.notifier);
    final continuousScrollAsync = ref.watch(
      catalogUsersContinuousScrollProvider,
    );
    final continuousScroll = continuousScrollAsync.value ?? true;
    final theme = Theme.of(context);
    final order = state.columnOrder;
    final keys = state.visibleColumnKeys;
    final sel = UserDirectoryColumn.selection;
    final orderRest = order.where((c) => c != sel).toList(growable: false);
    final selOn = keys.contains(sel.key);

    return CatalogColumnSelectorShell(
      onClose: onClose,
      title: 'Στήλες',
      listChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              onTap: () => notifier.setUserColumnVisible(sel, !selOn),
              leading: Checkbox(
                value: selOn,
                onChanged: (v) {
                  if (v != null) notifier.setUserColumnVisible(sel, v);
                },
              ),
              title: Text(
                sel.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: orderRest.length,
              onReorderItem: notifier.reorderUserColumns,
              proxyDecorator: (child, index, animation) => Material(
                elevation: 2,
                color: theme.colorScheme.surfaceContainerHighest,
                child: child,
              ),
              itemBuilder: (context, index) {
                final col = orderRest[index];
                final isOn = keys.contains(col.key);
                return Material(
                  key: ValueKey(col.key),
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    onTap: () => notifier.setUserColumnVisible(col, !isOn),
                    leading: Checkbox(
                      value: isOn,
                      onChanged: (v) {
                        if (v != null) {
                          notifier.setUserColumnVisible(col, v);
                        }
                      },
                    ),
                    title: Text(
                      col.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: ReorderableDragStartListener(
                      index: index,
                      child: Icon(
                        Icons.drag_handle,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: const Text(
              'Συνεχής κύλιση πίνακα',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: const Text(
              'Mouse wheel γραμμή-γραμμή αντί για αλλαγή σελίδας.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            value: continuousScroll,
            onChanged: (bool val) async {
              final db = await DatabaseHelper.instance.database;
              await SettingsRepository(
                db,
              ).saveSetting(kCatalogContinuousScrollUsersKey, val.toString());
              ref.invalidate(catalogUsersContinuousScrollProvider);
            },
          ),
        ],
      ),
    );
  }
}
