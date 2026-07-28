import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/user_form_edit_intent_provider.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/database/department_repository.dart';
import '../../../../core/database/equipment_repository.dart';
import '../../../../core/database/settings_repository.dart';
import '../../../../core/database/user_delete_equipment_policy.dart';
import '../../../../core/database/user_delete_phone_policy.dart';
import '../../../../core/database/user_repository.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../../calls/models/user_model.dart';
import '../../../calls/provider/lookup_provider.dart';
import '../../../../core/services/lookup_service.dart';
import '../../models/department_model.dart';
import '../../models/non_user_phone_entry.dart';
import '../../models/user_catalog_mode.dart';
import '../../models/user_directory_column.dart';
import '../../providers/department_directory_provider.dart';
import '../../providers/directory_provider.dart';
import '../../services/shared_asset_disconnect_apply.dart';
import '../../services/user_deletion_messages.dart';
import '../../services/user_deletion_undo_record.dart';
import 'bulk_user_edit_dialog.dart';
import 'catalog_column_selector_shell.dart';
import 'department_form_dialog.dart';
import 'non_user_phones_data_table.dart';
import 'shared_asset_disconnect_dialog.dart';
import 'user_form_dialog.dart';
import 'catalog_tab_lookup_reload_mixin.dart';
import 'catalog_search_field_sync.dart';
import 'users_data_table.dart';

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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => DraggableDialogShell(
        title: Text(userDeletionConfirmTitle(confirmLabels.length)),
        builder: (titleHandle) => AlertDialog(
          title: titleHandle,
          content: Text(userDeletionConfirmMessage(confirmLabels)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Ακύρωση'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Διαγραφή'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;

    final ids = state.selectedIds.toList();
    final db = await DatabaseHelper.instance.database;
    final userRepo = UserRepository(db);
    final exclusivePhones = await userRepo.findExclusivePhonesForUserDelete(
      ids,
    );
    final exclusiveEquipment = await userRepo
        .findExclusiveEquipmentForUserDelete(ids);
    final usersToDelete = selectedUsers;

    final originalUserPhones = <int, List<String>>{};
    final originalUserEquipmentIds = <int, List<int>>{};
    for (final u in usersToDelete) {
      final uid = u.id;
      if (uid == null) continue;
      originalUserPhones[uid] = await userRepo.userPhoneNumbersOrdered(db, uid);
      originalUserEquipmentIds[uid] = (await userRepo.equipmentIdsForUser(
        uid,
      )).toList();
    }

    final pendingPhoneBatches =
        <({SharedAssetDisconnectBatchResult batch, int? sourceDepartmentId})>[];
    if (exclusivePhones.isNotEmpty) {
      if (!context.mounted) return;
      final confirmed = await _collectExclusivePhoneDisconnectBatches(
        context,
        exclusivePhones: exclusivePhones,
        usersToDelete: usersToDelete,
        onBatch: (batch, sourceDepartmentId) {
          pendingPhoneBatches.add((
            batch: batch,
            sourceDepartmentId: sourceDepartmentId,
          ));
        },
      );
      if (!context.mounted || !confirmed) return;
    }

    final pendingEquipmentBatches =
        <({SharedAssetDisconnectBatchResult batch, int? sourceDepartmentId})>[];
    if (exclusiveEquipment.isNotEmpty) {
      if (!context.mounted) return;
      final confirmed = await _collectExclusiveEquipmentDisconnectBatches(
        context,
        exclusiveEquipment: exclusiveEquipment,
        usersToDelete: usersToDelete,
        onBatch: (batch, sourceDepartmentId) {
          pendingEquipmentBatches.add((
            batch: batch,
            sourceDepartmentId: sourceDepartmentId,
          ));
        },
      );
      if (!context.mounted || !confirmed) return;
    }

    final notifier = ref.read(directoryProvider.notifier);
    // Διαγραφή υπαλλήλων + διαθέσεις τηλεφώνων/εξοπλισμού σε ΜΙΑ συναλλαγή:
    // διακοπή στη μέση δεν αφήνει διαγραμμένους υπαλλήλους με τα τηλέφωνά
    // τους σε ενδιάμεση κατάσταση.
    await db.transaction((txn) async {
      await userRepo.deleteUsers(ids, executor: txn);
      for (final pending in pendingPhoneBatches) {
        await applyPersonalPhoneDisconnectBatch(
          db,
          pending.batch,
          sourceDepartmentId: pending.sourceDepartmentId,
          executor: txn,
        );
      }
      for (final pending in pendingEquipmentBatches) {
        await applyPersonalEquipmentDisconnectBatch(
          db,
          pending.batch,
          sourceDepartmentId: pending.sourceDepartmentId,
          executor: txn,
        );
      }
    });
    await notifier.finalizeExternalDeletion(usersToDelete);

    final phoneDeptAdds = <PhoneDeptAdd>[];
    final equipmentDeptSets = <EquipmentDeptSet>[];
    final softDeletedPhoneNumbers = <String>[];
    final softDeletedEquipmentCodes = <String>[];
    final equipmentRepo = EquipmentRepository(db);

    Future<int?> resolveTransferDeptId(SharedAssetTransferTarget target) async {
      if (target.departmentId != null) return target.departmentId;
      final name = target.newDepartmentName?.trim();
      if (name == null || name.isEmpty) return null;
      final key = SearchTextNormalizer.normalizeForSearch(name);
      final rows = await db.query(
        'departments',
        columns: ['id'],
        where: 'name_key = ? AND COALESCE(is_deleted, 0) = 0',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['id'] as int?;
    }

    for (final pending in pendingPhoneBatches) {
      final sourceDeptId = pending.sourceDepartmentId;
      for (final phone in pending.batch.phonesToKeep) {
        if (sourceDeptId != null) {
          phoneDeptAdds.add(
            PhoneDeptAdd(departmentId: sourceDeptId, phoneNumber: phone),
          );
        }
      }
      for (final entry in pending.batch.phoneTransfers.entries) {
        final deptId = await resolveTransferDeptId(entry.value);
        if (deptId != null) {
          phoneDeptAdds.add(
            PhoneDeptAdd(departmentId: deptId, phoneNumber: entry.key),
          );
        }
      }
      softDeletedPhoneNumbers.addAll(pending.batch.phonesToDelete);
    }

    for (final pending in pendingEquipmentBatches) {
      final sourceDeptId = pending.sourceDepartmentId;
      for (final code in pending.batch.equipmentToKeep) {
        if (sourceDeptId == null) continue;
        final eid = await equipmentRepo.getEquipmentIdByCode(code);
        if (eid != null) {
          equipmentDeptSets.add(
            EquipmentDeptSet(equipmentId: eid, departmentId: sourceDeptId),
          );
        }
      }
      for (final entry in pending.batch.equipmentTransfers.entries) {
        final deptId = await resolveTransferDeptId(entry.value);
        if (deptId == null) continue;
        final eid = await equipmentRepo.getEquipmentIdByCode(entry.key);
        if (eid != null) {
          equipmentDeptSets.add(
            EquipmentDeptSet(equipmentId: eid, departmentId: deptId),
          );
        }
      }
      softDeletedEquipmentCodes.addAll(pending.batch.equipmentToDelete);
    }

    notifier.rememberUserDeletionUndo(
      UserDeletionUndoRecord(
        deletedUserIds: ids,
        originalUserPhones: originalUserPhones,
        originalUserEquipmentIds: originalUserEquipmentIds,
        phoneDeptAdds: phoneDeptAdds,
        equipmentDeptSets: equipmentDeptSets,
        softDeletedPhoneNumbers: softDeletedPhoneNumbers,
        softDeletedEquipmentCodes: softDeletedEquipmentCodes,
      ),
    );

    if (pendingPhoneBatches.isNotEmpty || pendingEquipmentBatches.isNotEmpty) {
      await notifier.loadUsers();
      ref.invalidate(lookupServiceProvider);
      await ref.read(lookupServiceProvider.future);
    }
    if (!context.mounted) return;
    final deleted = ref.read(directoryProvider).lastDeleted ?? [];
    final names = deleted
        .map((u) => u.name?.trim().isEmpty ?? true ? '?' : u.name!)
        .toList();
    final assetActions = <UserDeletionAssetAction>[];
    for (final pending in pendingPhoneBatches) {
      final batch = pending.batch;
      for (final phone in batch.phoneTransfers.keys) {
        assetActions.add(
          UserDeletionAssetAction(
            kind: UserDeletionAssetActionKind.transfer,
            identifier: phone,
            isPhone: true,
          ),
        );
      }
      for (final phone in batch.phonesToDelete) {
        assetActions.add(
          UserDeletionAssetAction(
            kind: UserDeletionAssetActionKind.delete,
            identifier: phone,
            isPhone: true,
          ),
        );
      }
      for (final phone in batch.phonesToKeep) {
        assetActions.add(
          UserDeletionAssetAction(
            kind: UserDeletionAssetActionKind.keep,
            identifier: phone,
            isPhone: true,
          ),
        );
      }
    }
    for (final pending in pendingEquipmentBatches) {
      final batch = pending.batch;
      for (final code in batch.equipmentTransfers.keys) {
        assetActions.add(
          UserDeletionAssetAction(
            kind: UserDeletionAssetActionKind.transfer,
            identifier: code,
            isPhone: false,
          ),
        );
      }
      for (final code in batch.equipmentToDelete) {
        assetActions.add(
          UserDeletionAssetAction(
            kind: UserDeletionAssetActionKind.delete,
            identifier: code,
            isPhone: false,
          ),
        );
      }
      for (final code in batch.equipmentToKeep) {
        assetActions.add(
          UserDeletionAssetAction(
            kind: UserDeletionAssetActionKind.keep,
            identifier: code,
            isPhone: false,
          ),
        );
      }
    }
    final message = userDeletionSummaryMessage(
      employeeNames: names,
      assetActions: assetActions,
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

  Future<bool> _collectExclusivePhoneDisconnectBatches(
    BuildContext context, {
    required List<ExclusivePhoneForUserDelete> exclusivePhones,
    required List<UserModel> usersToDelete,
    required void Function(
      SharedAssetDisconnectBatchResult batch,
      int? sourceDepartmentId,
    )
    onBatch,
  }) async {
    final lookup = LookupService.instance;
    final departments = lookup.departments
        .where((d) => !d.isDeleted && d.name.trim().isNotEmpty)
        .toList();

    final byUser = <int, List<ExclusivePhoneForUserDelete>>{};
    for (final phone in exclusivePhones) {
      byUser.putIfAbsent(phone.userId, () => []).add(phone);
    }

    for (final entry in byUser.entries) {
      final phones = entry.value
          .map((p) => p.number)
          .where((n) => n.isNotEmpty)
          .toList();
      if (phones.isEmpty) continue;

      final first = entry.value.first;
      UserModel? user;
      for (final u in usersToDelete) {
        if (u.id == entry.key) {
          user = u;
          break;
        }
      }
      final displayName = user == null
          ? null
          : '${user.firstName} ${user.lastName}'.trim();

      if (!context.mounted) return false;
      final batch = await showSharedAssetDisconnectFlow(
        context: context,
        sourceDepartmentId: first.departmentId,
        sourceDepartmentName: first.departmentName,
        phones: phones,
        availableDepartments: departments,
        mode: SharedAssetDisconnectMode.personalPhone,
        personalPhoneUserDisplayName: displayName,
      );
      if (!context.mounted || batch == null) return false;
      onBatch(batch, first.departmentId);
    }
    return true;
  }

  Future<bool> _collectExclusiveEquipmentDisconnectBatches(
    BuildContext context, {
    required List<ExclusiveEquipmentForUserDelete> exclusiveEquipment,
    required List<UserModel> usersToDelete,
    required void Function(
      SharedAssetDisconnectBatchResult batch,
      int? sourceDepartmentId,
    )
    onBatch,
  }) async {
    final lookup = LookupService.instance;
    final departments = lookup.departments
        .where((d) => !d.isDeleted && d.name.trim().isNotEmpty)
        .toList();

    final byUser = <int, List<ExclusiveEquipmentForUserDelete>>{};
    for (final item in exclusiveEquipment) {
      byUser.putIfAbsent(item.userId, () => []).add(item);
    }

    for (final entry in byUser.entries) {
      final codes = entry.value
          .map((e) => e.codeEquipment)
          .where((c) => c.isNotEmpty)
          .toList();
      if (codes.isEmpty) continue;

      final first = entry.value.first;
      UserModel? user;
      for (final u in usersToDelete) {
        if (u.id == entry.key) {
          user = u;
          break;
        }
      }
      final displayName = user == null
          ? null
          : '${user.firstName} ${user.lastName}'.trim();

      if (!context.mounted) return false;
      final batch = await showSharedAssetDisconnectFlow(
        context: context,
        sourceDepartmentId: first.departmentId,
        sourceDepartmentName: first.departmentName,
        equipmentCodes: codes,
        availableDepartments: departments,
        mode: SharedAssetDisconnectMode.personalEquipment,
        personalPhoneUserDisplayName: displayName,
        allowKeepInDepartment: true,
      );
      if (!context.mounted || batch == null) return false;
      onBatch(batch, first.departmentId);
    }
    return true;
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
        Tooltip(
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
