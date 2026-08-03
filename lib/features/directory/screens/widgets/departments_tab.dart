import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/department_repository.dart';
import '../../../../core/database/user_delete_equipment_policy.dart';
import '../../../../core/database/user_delete_phone_policy.dart';
import '../../../../core/database/user_repository.dart';
import '../../../../core/models/building_map_floor.dart';
import '../../../../core/database/settings_repository.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/widgets/database_persistence_error_snackbar.dart';
import '../../../calls/layout/call_form_clear.dart';
import '../../services/department_deletion_inventory.dart';
import '../../services/department_deletion_messages.dart';
import '../../services/department_deletion_orchestrator.dart';
import '../../services/department_deletion_undo_policy.dart';
import '../../services/department_deletion_undo_record.dart';
import '../../services/department_rename_heuristic.dart';
import '../../services/user_deletion_undo_record.dart';
import 'shared_asset_disconnect_dialog.dart';
import 'bulk_deletion_partial_dialog.dart';
import 'department_deletion_partial_dialog.dart';
import 'department_deletion_preview_dialog.dart';
import 'department_employee_reassign_dialog.dart';
import 'department_rename_guard_dialog.dart';
import '../../models/department_directory_column.dart';
import '../../models/department_model.dart';
import '../../building_map/providers/building_map_providers.dart';
import '../../providers/bulk_action_undo_provider.dart';
import '../../providers/department_directory_provider.dart';
import '../../providers/directory_provider.dart';
import 'bulk_department_edit_dialog.dart';
import 'bulk_undo_bar.dart';
import 'catalog_column_selector_shell.dart';
import 'department_form_dialog.dart';
import 'departments_data_table.dart';
import '../../building_map/screens/building_map_dialog.dart';
import 'catalog_tab_lookup_reload_mixin.dart';
import 'catalog_search_field_sync.dart';

/// Καρτέλα τμημάτων: αναζήτηση, πίνακας, επιλογή, διαγραφή με undo, προσθήκη.
class DepartmentsTab extends ConsumerStatefulWidget {
  const DepartmentsTab({super.key});

  @override
  ConsumerState<DepartmentsTab> createState() => _DepartmentsTabState();
}

class _DepartmentsTabState extends ConsumerState<DepartmentsTab>
    with CatalogTabLookupReloadMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    attachCatalogLookupReloadListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(departmentDirectoryProvider.notifier).loadDepartments();
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
    final floorsCatalogAsync = ref.watch(buildingMapFloorsCatalogProvider);
    final floorsById = <int, BuildingMapFloor>{
      for (final f in floorsCatalogAsync.value ?? <BuildingMapFloor>[]) f.id: f,
    };
    final state = ref.watch(departmentDirectoryProvider);
    final notifier = ref.read(departmentDirectoryProvider.notifier);
    final visibleColumns = state.orderedVisibleColumns;
    final continuousScrollAsync = ref.watch(
      catalogDepartmentsContinuousScrollProvider,
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
                    hintText: 'Όνομα, κτίριο, σημειώσεις...',
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
              IconButton(
                tooltip: 'Στήλες πίνακα',
                icon: const Icon(Icons.view_column_outlined),
                onPressed: () => _openColumnSelector(context, ref),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => showBuildingMapDialog(context, ref),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Χάρτης'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _openForm(context, ref, null),
                icon: const Icon(Icons.add),
                label: const Text('Προσθήκη'),
              ),
            ],
          ),
        ),
        const BulkUndoBar(scope: BulkUndoScope.departments),
        Expanded(
          child: DepartmentsDataTable(
            floorsById: floorsById,
            departments: state.filteredDepartments,
            selectedIds: state.selectedIds,
            sortColumn: state.sortColumn,
            sortAscending: state.sortAscending,
            visibleColumns: visibleColumns,
            onToggleSelection: notifier.toggleSelection,
            onSetSort: notifier.setSort,
            onEditDepartment: (d, {focusedField}) =>
                _openForm(context, ref, d, focusedField: focusedField),
            focusedRowIndex: state.focusedRowIndex,
            onSetFocusedRowIndex: notifier.setFocusedRowIndex,
            onRequestDelete: () => _confirmAndDeleteSelected(context, ref),
            onRequestBulkEdit: () => _openBulkEdit(context, ref),
            continuousScroll: continuousScroll,
          ),
        ),
        if (state.selectedIds.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text(
                  '${state.selectedIds.length} επιλεγμένα',
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
                          final candidates = state.allDepartments
                              .where((d) => d.id == id)
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
        child: _DepartmentColumnSelectorOverlay(
          onClose: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  Future<void> _openBulkEdit(BuildContext context, WidgetRef ref) async {
    final state = ref.read(departmentDirectoryProvider);
    final selected = state.allDepartments
        .where((d) => d.id != null && state.selectedIds.contains(d.id))
        .toList();
    if (selected.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => BulkDepartmentEditDialog(
        selectedDepartments: selected,
        notifier: ref.read(departmentDirectoryProvider.notifier),
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    DepartmentModel? department, {
    bool isClone = false,
    String? focusedField,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => DepartmentFormDialog(
        initialDepartment: department,
        notifier: ref.read(departmentDirectoryProvider.notifier),
        isClone: isClone,
        focusedField: focusedField,
      ),
    );
  }

  /// Ξαναδείχνει την προεπισκόπηση όσες φορές χρειαστεί.
  ///
  /// Η «Ακύρωση» σε διάλογο της συλλογής, πριν ολοκληρωθεί οτιδήποτε, ακυρώνει
  /// **μόνο εκείνο το βήμα**: ο χρήστης γυρίζει στη λίστα, αφαιρεί τμήματα και
  /// ξαναπροσπαθεί, αντί να χάσει τη ροή και να ξαναρχίσει από το κουμπί.
  Future<void> _confirmAndDeleteSelected(
    BuildContext context,
    WidgetRef ref,
  ) async {
    while (true) {
      if (!context.mounted) return;
      final retry = await _runDepartmentDeletionRound(context, ref);
      if (!retry) return;
    }
  }

  /// Ένας γύρος προεπισκόπησης + συλλογής + εκτέλεσης.
  ///
  /// Επιστρέφει `true` όταν πρέπει να ξαναδειχθεί η προεπισκόπηση.
  Future<bool> _runDepartmentDeletionRound(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final state = ref.read(departmentDirectoryProvider);
    if (state.selectedIds.isEmpty) return false;

    final selected = state.allDepartments
        .where(
          (d) =>
              d.id != null && !d.isDeleted && state.selectedIds.contains(d.id),
        )
        .toList();
    if (selected.isEmpty) return false;

    final inventories = [
      for (final d in selected)
        DepartmentDeletionInventory.fromLookup(d.id!, d.name),
    ];
    final preview = await showDepartmentDeletionPreviewDialog(
      context: context,
      inventories: inventories,
    );
    if (preview == null ||
        preview.choice == DepartmentDeletionChoice.cancel ||
        !context.mounted) {
      return false;
    }
    final choice = preview.choice;

    // Ο χρήστης μπορεί να αφαίρεσε τμήματα μέσα στον διάλογο· από εδώ και πέρα
    // μετράει μόνο ό,τι έμεινε — και για τη διαγραφή, και για το ποια τμήματα
    // είναι έγκυροι προορισμοί μεταφοράς.
    final keptIds = preview.keptDepartmentIds.toSet();
    final toDelete = selected.where((d) => keptIds.contains(d.id)).toList();
    if (toDelete.isEmpty) return false;

    final lookup = LookupService.instance;
    final deletingIds = keptIds;
    // Δεν αρκεί να λείπουν από τον κατάλογο προορισμών: αν ο χρήστης γράψει το
    // όνομα με το χέρι, ο επιλυτής βρίσκει το ζωντανό ακόμα τμήμα και στέλνει
    // εκεί τα στοιχεία — λίγο πριν αυτό διαγραφεί.
    final deletingNames = [for (final d in toDelete) d.name];
    var movedEmployeeCount = 0;
    var movedOrDeletedAssetCount = 0;
    final plans = <DepartmentDeletionPlan>[];

    // Ο χρήστης ακύρωσε διάλογο μέσα στη συλλογή. Επιστρέφει `null` όταν η ροή
    // πρέπει να συνεχίσει με ό,τι μαζεύτηκε· αλλιώς την τιμή που επιστρέφει ο
    // γύρος (`true` = ξανά από την προεπισκόπηση, `false` = τέλος).
    /// [alreadyAnswered] = ο χρήστης απάντησε ήδη μέσα στη ροή αποδέσμευσης,
    /// στον ίδιο διάλογο με την ακύρωση· δεν ξαναρωτιέται εδώ.
    Future<bool?> handleAbort({
      AssetDisconnectStopKind? alreadyAnswered,
    }) async {
      if (!context.mounted) return false;
      // Τίποτα ολοκληρωμένο: δεν υπάρχει δουλειά να χαθεί, οπότε γυρνάμε στην
      // προεπισκόπηση αντί να κλείσουμε τη ροή. Έτσι η «Ακύρωση» εδώ ακυρώνει
      // μόνο αυτό το βήμα, και ο χρήστης μπορεί να αφαιρέσει τμήματα.
      if (plans.isEmpty) return true;
      if (alreadyAnswered != null) {
        return alreadyAnswered == AssetDisconnectStopKind.applyCompleted
            ? null
            : false;
      }
      final partial = await showDepartmentDeletionPartialDialog(
        context: context,
        completed: plans.length,
        total: toDelete.length,
      );
      return partial == BulkDeletionPartialChoice.applyCompleted ? null : false;
    }

    // Φάση συλλογής: μόνο διάλογοι — χωρίς εγγραφές στη βάση.
    if (choice == DepartmentDeletionChoice.detailed) {
      final dbEx = await DatabaseHelper.instance.database;
      final userRepo = UserRepository(dbEx);
      var departmentIndex = 0;

      collectLoop:
      for (final dept in toDelete) {
        final deptId = dept.id;
        if (deptId == null) continue;
        departmentIndex++;

        final availableDepartments = lookup.departments
            .where(
              (d) =>
                  d.id != null &&
                  !d.isDeleted &&
                  !deletingIds.contains(d.id) &&
                  d.name.trim().isNotEmpty,
            )
            .toList();

        var employeeBatch = const DepartmentEmployeeReassignBatch(
          transfers: {},
        );
        final deletedEmployees = <DepartmentEmployeeDeletion>[];
        final users = lookup.getUsersByDepartment(deptId);
        final employees = <DepartmentEmployeeReassignCandidate>[
          for (final u in users)
            if (u.id != null)
              DepartmentEmployeeReassignCandidate(
                id: u.id!,
                name: (u.name ?? '').trim().isEmpty
                    ? '?'
                    : (u.name ?? '').trim(),
              ),
        ];

        var userIdsToDelete = const <int>[];
        var exclusivePhones = const <ExclusivePhoneForUserDelete>[];
        var exclusiveEquipment = const <ExclusiveEquipmentForUserDelete>[];

        if (employees.isNotEmpty) {
          if (!context.mounted) return false;
          final collected = await showDepartmentEmployeeReassignFlow(
            context: context,
            sourceDepartmentName: dept.name,
            employees: employees,
            availableDepartments: availableDepartments,
            sourceDepartmentId: deptId,
            blockedDepartmentNames: deletingNames,
          );
          if (!context.mounted) return false;
          if (collected == null) {
            final r = await handleAbort();
            if (r != null) return r;
            break collectLoop;
          }
          employeeBatch = collected;
          movedEmployeeCount += employeeBatch.transfers.length;
          userIdsToDelete = collected.toDelete.toList();

          if (userIdsToDelete.isNotEmpty) {
            // ΕΝΑ ερώτημα για όλους μαζί: το κριτήριο «μένει ορφανό»
            // εξαιρεί τους διαγραφόμενους, οπότε με ερώτημα ανά υπάλληλο
            // ένας εξοπλισμός που τον μοιράζονται δύο διαγραφόμενοι δεν
            // εμφανιζόταν σε καμία κλήση και έμενε χωρίς κάτοχο.
            exclusivePhones = await userRepo.findExclusivePhonesForUserDelete(
              userIdsToDelete,
            );
            exclusiveEquipment = await userRepo
                .findExclusiveEquipmentForUserDelete(userIdsToDelete);
          }
        }

        final phones = lookup.getDirectPhonesByDepartment(deptId);
        final equipment = lookup.getSharedEquipmentCodesByDepartment(deptId);

        // Σταθερός μετρητής: το σύνολο των ερωτήσεων αυτού του τμήματος είναι
        // πλέον γνωστό πριν ανοίξει ο πρώτος διάλογος, οπότε το «X από Y» δεν
        // μεγαλώνει στη μέση. Με τη σειρά που θα καταναλωθούν.
        final nameByUserId = <int, String>{
          for (final e in employees) e.id: e.name,
        };

        final disconnectSession = AssetDisconnectSession(
          items: <AssetDisconnectItem>[
            for (final userId in userIdsToDelete) ...[
              for (final p in exclusivePhones)
                if (p.userId == userId)
                  AssetDisconnectItem.phone(
                    p.number,
                    ownerName: nameByUserId[userId],
                    departmentId: deptId,
                    departmentName: dept.name,
                  ),
              for (final e in exclusiveEquipment)
                if (e.userId == userId)
                  AssetDisconnectItem.equipment(
                    e.codeEquipment,
                    ownerName: nameByUserId[userId],
                    departmentId: deptId,
                    departmentName: dept.name,
                  ),
            ],
            for (final p in phones)
              AssetDisconnectItem.phone(
                p,
                departmentId: deptId,
                departmentName: dept.name,
              ),
            for (final c in equipment)
              AssetDisconnectItem.equipment(
                c,
                departmentId: deptId,
                departmentName: dept.name,
              ),
          ],
          contextLabel: departmentDeletionContextLabel(
            departmentIndex: departmentIndex,
            departmentCount: toDelete.length,
          ),
          cancelScopeDescription: departmentDeletionCancelScopeDescription(
            toDelete.length,
          ),
          // Η διέξοδος προσφέρεται μέσα στον ίδιο διάλογο με την «Ακύρωση
          // όλων»: το «Συνέχεια» μπορεί να επιστρέψει στο βήμα ΜΟΝΟ όσο η ροή
          // είναι ανοιχτή.
          completedWork: () {
            if (plans.isEmpty) return null;
            return (
              summary: departmentDeletionCompletedSummary(
                completed: plans.length,
                total: toDelete.length,
              ),
              applyHint: departmentDeletionApplyCompletedHint(plans.length),
            );
          },
        );

        for (final userId in userIdsToDelete) {
          final phonesForUser = <String>[
            for (final p in exclusivePhones)
              if (p.userId == userId) p.number,
          ];
          final equipmentForUser = <String>[
            for (final e in exclusiveEquipment)
              if (e.userId == userId) e.codeEquipment,
          ];

          var phoneBatch = const SharedAssetDisconnectBatchResult();
          if (phonesForUser.isNotEmpty) {
            if (!context.mounted) return false;
            final b = await showSharedAssetDisconnectFlow(
              context: context,
              sourceDepartmentId: deptId,
              sourceDepartmentName: dept.name,
              phones: phonesForUser,
              availableDepartments: availableDepartments,
              blockedDepartmentNames: deletingNames,
              mode: SharedAssetDisconnectMode.personalPhone,
              allowKeepInDepartment: false,
              session: disconnectSession,
            );
            if (!context.mounted) return false;
            if (b == null) {
              final r = await handleAbort(
                alreadyAnswered: disconnectSession.stopKind,
              );
              if (r != null) return r;
              break collectLoop;
            }
            phoneBatch = b;
          }

          var equipmentBatch = const SharedAssetDisconnectBatchResult();
          if (equipmentForUser.isNotEmpty) {
            if (!context.mounted) return false;
            final b = await showSharedAssetDisconnectFlow(
              context: context,
              sourceDepartmentId: deptId,
              sourceDepartmentName: dept.name,
              equipmentCodes: equipmentForUser,
              availableDepartments: availableDepartments,
              blockedDepartmentNames: deletingNames,
              mode: SharedAssetDisconnectMode.personalEquipment,
              allowKeepInDepartment: false,
              session: disconnectSession,
            );
            if (!context.mounted) return false;
            if (b == null) {
              final r = await handleAbort(
                alreadyAnswered: disconnectSession.stopKind,
              );
              if (r != null) return r;
              break collectLoop;
            }
            equipmentBatch = b;
          }

          deletedEmployees.add(
            DepartmentEmployeeDeletion(
              userId: userId,
              phoneBatch: phoneBatch,
              equipmentBatch: equipmentBatch,
            ),
          );
        }

        var sharedBatch = const SharedAssetDisconnectBatchResult();
        if (phones.isNotEmpty || equipment.isNotEmpty) {
          if (!context.mounted) return false;
          final collected = await showSharedAssetDisconnectFlow(
            context: context,
            sourceDepartmentId: deptId,
            sourceDepartmentName: dept.name,
            phones: phones,
            equipmentCodes: equipment,
            availableDepartments: availableDepartments,
            blockedDepartmentNames: deletingNames,
            allowKeepInDepartment: false,
            session: disconnectSession,
          );
          if (!context.mounted) return false;
          if (collected == null) {
            final r = await handleAbort(
              alreadyAnswered: disconnectSession.stopKind,
            );
            if (r != null) return r;
            break collectLoop;
          }
          sharedBatch = collected;
          movedOrDeletedAssetCount +=
              sharedBatch.phoneTransfers.length +
              sharedBatch.phonesToDelete.length +
              sharedBatch.equipmentTransfers.length +
              sharedBatch.equipmentToDelete.length;
        }

        plans.add(
          DepartmentDeletionPlan(
            departmentId: deptId,
            employeeBatch: employeeBatch,
            sharedBatch: sharedBatch,
            deletedEmployees: deletedEmployees,
          ),
        );
      }
    } else {
      // ΜΙΑ ερώτηση για όλα — το κουμπί υπόσχεται «μεταφορά όλων σε ένα τμήμα».
      // Ο επιλογέας ήταν μέσα στον βρόχο, οπότε με εφτά επιλεγμένα τμήματα ο
      // χρήστης απαντούσε εφτά φορές και μπορούσε να φτιάξει εφτά νέα τμήματα.
      final availableDepartments = lookup.departments
          .where(
            (d) =>
                d.id != null &&
                !d.isDeleted &&
                !deletingIds.contains(d.id) &&
                d.name.trim().isNotEmpty,
          )
          .toList();

      if (!context.mounted) return false;
      final target = await showAssetTransferTargetPicker(
        context: context,
        headerLabel: departmentQuickTransferHeader(deletingNames),
        availableDepartments: availableDepartments,
        // Κανένα τμήμα-πηγή: όλα τα διαγραφόμενα λείπουν ήδη από τον κατάλογο
        // και είναι απαγορευμένα και στην πληκτρολόγηση.
        blockedDepartmentNames: deletingNames,
      );
      if (!context.mounted) return false;
      if (target == null) {
        final r = await handleAbort();
        if (r != null) return r;
        return false;
      }

      // Ο φρουρός μετονομασίας έχει νόημα μόνο για ΕΝΑ τμήμα: «όλα από το Χ
      // σε νέο τμήμα Ψ» μοιάζει με μετονομασία. Με πολλά τμήματα σε κοινό νέο
      // προορισμό δεν είναι μετονομασία — είναι συγχώνευση.
      if (toDelete.length == 1) {
        final only = toDelete.first;
        final onlyId = only.id;
        if (onlyId != null) {
          final movedTotal =
              lookup.getUsersByDepartment(onlyId).length +
              lookup.getDirectPhonesByDepartment(onlyId).length +
              lookup.getSharedEquipmentCodesByDepartment(onlyId).length;
          final proposedNewName = target.newDepartmentName?.trim() ?? '';
          if (looksLikeDepartmentRename(
            movedTotal: movedTotal,
            movedToDominantTarget: movedTotal,
            dominantTargetIsNew: proposedNewName.isNotEmpty,
          )) {
            if (!context.mounted) return false;
            final guard = await showDepartmentRenameGuardDialog(
              context: context,
              sourceDepartmentName: only.name,
              proposedNewName: proposedNewName,
            );
            if (!context.mounted) return false;
            if (guard == null || guard == DepartmentRenameGuardChoice.cancel) {
              final r = await handleAbort();
              if (r != null) return r;
              return false;
            }
            if (guard == DepartmentRenameGuardChoice.renameInstead) {
              await _openForm(
                context,
                ref,
                only.copyWith(name: proposedNewName),
                focusedField: 'name',
              );
              return false;
            }
          }
        }
      }

      for (final dept in toDelete) {
        final deptId = dept.id;
        if (deptId == null) continue;

        final users = lookup.getUsersByDepartment(deptId);
        final phones = lookup.getDirectPhonesByDepartment(deptId);
        final equipment = lookup.getSharedEquipmentCodesByDepartment(deptId);
        final employees = <DepartmentEmployeeReassignCandidate>[
          for (final u in users)
            if (u.id != null)
              DepartmentEmployeeReassignCandidate(
                id: u.id!,
                name: (u.name ?? '').trim().isEmpty
                    ? '?'
                    : (u.name ?? '').trim(),
              ),
        ];
        final proposedNewName = target.newDepartmentName?.trim() ?? '';
        final dominantTargetIsNew = proposedNewName.isNotEmpty;

        var employeeBatch = const DepartmentEmployeeReassignBatch(
          transfers: {},
        );
        if (employees.isNotEmpty) {
          employeeBatch = DepartmentEmployeeReassignBatch(
            transfers: {for (final e in employees) e.id: target},
          );
          movedEmployeeCount += employees.length;
        }

        var sharedBatch = const SharedAssetDisconnectBatchResult();
        if (phones.isNotEmpty || equipment.isNotEmpty) {
          final newDeptNames = <String>{
            if (dominantTargetIsNew) proposedNewName,
          };
          sharedBatch = SharedAssetDisconnectBatchResult(
            phoneTransfers: {for (final p in phones) p: target},
            equipmentTransfers: {for (final c in equipment) c: target},
            newDepartmentNamesToCreate: newDeptNames,
          );
          movedOrDeletedAssetCount += phones.length + equipment.length;
        }

        plans.add(
          DepartmentDeletionPlan(
            departmentId: deptId,
            employeeBatch: employeeBatch,
            sharedBatch: sharedBatch,
          ),
        );
      }
    }

    // Φάση εκτέλεσης: ένα ατομικό transaction για όλα τα plans.
    if (plans.isEmpty) return false;

    final db = await DatabaseHelper.instance.database;

    void collectCreateNewName(
      SharedAssetTransferTarget target,
      Set<String> names,
    ) {
      final newName = target.newDepartmentName?.trim();
      if (newName == null || newName.isEmpty) return;
      names.add(newName);
    }

    final candidateNewNames = <String>{};
    for (final plan in plans) {
      for (final target in plan.employeeBatch.transfers.values) {
        collectCreateNewName(target, candidateNewNames);
      }
      for (final target in plan.sharedBatch.phoneTransfers.values) {
        collectCreateNewName(target, candidateNewNames);
      }
      for (final target in plan.sharedBatch.equipmentTransfers.values) {
        collectCreateNewName(target, candidateNewNames);
      }
      for (final deleted in plan.deletedEmployees) {
        for (final target in deleted.phoneBatch.phoneTransfers.values) {
          collectCreateNewName(target, candidateNewNames);
        }
        for (final target in deleted.phoneBatch.equipmentTransfers.values) {
          collectCreateNewName(target, candidateNewNames);
        }
        for (final target in deleted.equipmentBatch.phoneTransfers.values) {
          collectCreateNewName(target, candidateNewNames);
        }
        for (final target in deleted.equipmentBatch.equipmentTransfers.values) {
          collectCreateNewName(target, candidateNewNames);
        }
      }
    }

    final departmentsRepo = DepartmentRepository(db);
    final namesTrulyCreated = <String>[];
    for (final name in candidateNewNames) {
      final existingId = await departmentsRepo.findActiveDepartmentIdByName(
        name,
      );
      if (existingId == null) namesTrulyCreated.add(name);
    }

    final UserDeletionUndoRecord deletedEmployeesUndo;
    try {
      deletedEmployeesUndo = await applyDepartmentDeletionPlansAtomic(
        db,
        plans,
      );
    } catch (e, st) {
      if (!context.mounted) return false;
      showDatabasePersistenceErrorSnackBar(
        context,
        Exception('Η διαγραφή τμήματος απέτυχε και καμία αλλαγή δεν έγινε. $e'),
        st,
      );
      return false;
    }

    final createdDepartmentIds = <int>[];
    for (final name in namesTrulyCreated) {
      final id = await departmentsRepo.findActiveDepartmentIdByName(name);
      if (id != null) createdDepartmentIds.add(id);
    }

    Future<int?> resolveTransferDeptId(SharedAssetTransferTarget target) async {
      if (target.departmentId != null) return target.departmentId;
      return departmentsRepo.findActiveDepartmentIdByName(
        target.newDepartmentName,
      );
    }

    final reassignedEmployees = <DepartmentDeletionReassignedEmployee>[];
    final phoneTransfers = <DepartmentDeletionPhoneTransfer>[];
    final softDeletedPhones = <DepartmentDeletionSoftDeletedPhone>[];
    final equipmentTransfers = <DepartmentDeletionEquipmentTransfer>[];
    final softDeletedEquipment = <DepartmentDeletionSoftDeletedEquipment>[];

    for (final plan in plans) {
      final deletedDeptId = plan.departmentId;
      for (final entry in plan.employeeBatch.transfers.entries) {
        reassignedEmployees.add(
          DepartmentDeletionReassignedEmployee(
            userId: entry.key,
            originalDeletedDeptId: deletedDeptId,
          ),
        );
      }
      for (final entry in plan.sharedBatch.phoneTransfers.entries) {
        final toId = await resolveTransferDeptId(entry.value);
        if (toId == null) continue;
        phoneTransfers.add(
          DepartmentDeletionPhoneTransfer(
            phoneNumber: entry.key,
            fromDeletedDeptId: deletedDeptId,
            toTargetDeptId: toId,
          ),
        );
      }
      for (final phone in plan.sharedBatch.phonesToDelete) {
        softDeletedPhones.add(
          DepartmentDeletionSoftDeletedPhone(
            phoneNumber: phone,
            deletedDeptId: deletedDeptId,
          ),
        );
      }
      for (final entry in plan.sharedBatch.equipmentTransfers.entries) {
        final toId = await resolveTransferDeptId(entry.value);
        if (toId == null) continue;
        equipmentTransfers.add(
          DepartmentDeletionEquipmentTransfer(
            code: entry.key,
            deletedDeptId: deletedDeptId,
            toTargetDeptId: toId,
          ),
        );
      }
      for (final code in plan.sharedBatch.equipmentToDelete) {
        softDeletedEquipment.add(
          DepartmentDeletionSoftDeletedEquipment(
            code: code,
            deletedDeptId: deletedDeptId,
          ),
        );
      }
    }

    final undoRecord = DepartmentDeletionUndoRecord(
      deletedDepartmentIds: [for (final p in plans) p.departmentId],
      reassignedEmployees: reassignedEmployees,
      phoneTransfers: phoneTransfers,
      softDeletedPhones: softDeletedPhones,
      equipmentTransfers: equipmentTransfers,
      softDeletedEquipment: softDeletedEquipment,
      deletedEmployeesUndo: deletedEmployeesUndo.deletedUserIds.isEmpty
          ? null
          : deletedEmployeesUndo,
      createdDepartmentIds: createdDepartmentIds,
    );

    // ΜΟΝΟ όσα πραγματικά εκτελέστηκαν: με τη διέξοδο της διακοπής τα `plans`
    // μπορεί να είναι λιγότερα από τα `toDelete`, και το μήνυμα επιτυχίας
    // διαβάζει από εδώ — αλλιώς ονομάζει τμήματα που δεν διαγράφηκαν.
    final executedIds = {for (final p in plans) p.departmentId};
    final executed = toDelete.where((d) => executedIds.contains(d.id)).toList();

    // Ό,τι επέλεξε ο χρήστης και ΔΕΝ διαγράφηκε μένει επιλεγμένο: το «✕» της
    // προεπισκόπησης σημαίνει «αυτά αργότερα», όχι «αυτά ποτέ».
    final survivingSelection = state.selectedIds
        .where((id) => !executedIds.contains(id))
        .toSet();

    final notifier = ref.read(departmentDirectoryProvider.notifier);
    await notifier.finalizeExternalDeletion(
      executed,
      keepSelectedIds: survivingSelection,
    );
    // Η μετάλλαξη ακύρωσε το lookup· η αλυσίδα των Κλήσεων δεν έχει listeners
    // όσο είμαστε στον Κατάλογο και πρέπει να ξεπλυθεί εκτός φάσης build.
    flushCallsChainAfterDirectoryMutation(ref);
    notifier.rememberDepartmentDeletionUndo(undoRecord);
    if (!context.mounted) return false;
    final deleted = ref.read(departmentDirectoryProvider).lastDeleted ?? [];
    final deletedCount = deleted.length;
    final names = deleted
        .map((d) => d.name.trim().isEmpty ? '?' : d.name)
        .toList();
    const maxNamesLength = 70;
    final namesPart = names.join(', ');
    var take = 0;
    var len = 0;
    for (; take < names.length; take++) {
      final add = (take == 0 ? '' : ', ') + names[take];
      if (len + add.length > maxNamesLength) break;
      len += add.length;
    }
    final truncated = take < names.length;
    final displayNames = truncated
        ? '${names.sublist(0, take).join(', ')}...'
        : namesPart;
    final tooltipAllNames = names.isEmpty ? null : names.join(', ');

    final undoPolicy = resolveDepartmentDeletionUndo(
      deletedDepartmentCount: deletedCount,
      movedEmployeeCount: movedEmployeeCount,
      movedOrDeletedAssetCount: movedOrDeletedAssetCount,
    );

    // Μοναδικοί στόχοι μεταφοράς + κατηγορίες που μετακινήθηκαν, για ακριβές μήνυμα.
    final transferTargets = <String, ({String name, bool isNew})>{};
    var transferredPhones = false;
    var transferredEquipment = false;
    void collectTarget(SharedAssetTransferTarget target) {
      final newName = target.newDepartmentName?.trim();
      if (newName != null && newName.isNotEmpty) {
        transferTargets['new:$newName'] = (name: newName, isNew: true);
      } else if (target.departmentId != null) {
        final match = LookupService.instance.departments.where(
          (d) => d.id == target.departmentId,
        );
        final name = match.isEmpty ? '' : match.first.name.trim();
        transferTargets['id:${target.departmentId}'] = (
          name: name.isEmpty ? 'τμήμα' : name,
          isNew: false,
        );
      }
    }

    for (final plan in plans) {
      for (final target in plan.employeeBatch.transfers.values) {
        collectTarget(target);
      }
      if (plan.sharedBatch.phoneTransfers.isNotEmpty) {
        transferredPhones = true;
        for (final target in plan.sharedBatch.phoneTransfers.values) {
          collectTarget(target);
        }
      }
      if (plan.sharedBatch.equipmentTransfers.isNotEmpty) {
        transferredEquipment = true;
        for (final target in plan.sharedBatch.equipmentTransfers.values) {
          collectTarget(target);
        }
      }
    }
    final transferredEmployees = movedEmployeeCount > 0;

    final String message;
    if (names.isEmpty) {
      message = undoPolicy.snackbarMessage;
    } else {
      final deletedPart = deletedCount == 1
          ? 'Το τμήμα $displayNames διαγράφηκε.'
          : 'Τα τμήματα $displayNames διαγράφηκαν.';
      final movedCategories = <String>[
        if (transferredEmployees) 'υπαλλήλων',
        if (transferredEquipment) 'εξοπλισμού',
        if (transferredPhones) 'τηλεφώνων',
      ];
      var movePart = '';
      if (movedCategories.isNotEmpty && transferTargets.length == 1) {
        final target = transferTargets.values.first;
        final kind = target.isNew ? 'νέο' : 'υπάρχον';
        movePart =
            ' Επιτυχής μεταφορά ${_joinGreekGenitive(movedCategories)} στο $kind ${target.name}.';
      } else if (movedCategories.isNotEmpty) {
        movePart = ' Τα στοιχεία μεταφέρθηκαν σε άλλα τμήματα.';
      }
      message = '$deletedPart$movePart';
    }

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
        action: undoPolicy.canOfferUndo
            ? SnackBarAction(
                label: 'Αναίρεση',
                onPressed: () async {
                  await notifier.undoLastDelete();
                },
              )
            : null,
      ),
    );
    // Η διαγραφή έγινε — η προεπισκόπηση δεν ξαναδείχνεται.
    return false;
  }
}

/// Ένωση με ελληνικά κόμματα και «και» πριν το τελευταίο («α, β και γ»).
String _joinGreekGenitive(List<String> items) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.first;
  if (items.length == 2) return '${items[0]} και ${items[1]}';
  return '${items.sublist(0, items.length - 1).join(', ')} και ${items.last}';
}

class _DepartmentColumnSelectorOverlay extends ConsumerWidget {
  const _DepartmentColumnSelectorOverlay({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(departmentDirectoryProvider);
    final notifier = ref.read(departmentDirectoryProvider.notifier);
    final continuousScrollAsync = ref.watch(
      catalogDepartmentsContinuousScrollProvider,
    );
    final continuousScroll = continuousScrollAsync.value ?? true;
    final theme = Theme.of(context);
    final order = state.columnOrder;
    final keys = state.visibleColumnKeys;
    final sel = DepartmentDirectoryColumn.selection;
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
              onTap: () => notifier.setDepartmentColumnVisible(sel, !selOn),
              leading: Checkbox(
                value: selOn,
                onChanged: (v) {
                  if (v != null) notifier.setDepartmentColumnVisible(sel, v);
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
              onReorderItem: notifier.reorderDepartmentColumns,
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
                    onTap: () =>
                        notifier.setDepartmentColumnVisible(col, !isOn),
                    leading: Checkbox(
                      value: isOn,
                      onChanged: (v) {
                        if (v != null) {
                          notifier.setDepartmentColumnVisible(col, v);
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
              await SettingsRepository(db).saveSetting(
                kCatalogContinuousScrollDepartmentsKey,
                val.toString(),
              );
              ref.invalidate(catalogDepartmentsContinuousScrollProvider);
            },
          ),
        ],
      ),
    );
  }
}
