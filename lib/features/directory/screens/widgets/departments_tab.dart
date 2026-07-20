import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/models/building_map_floor.dart';
import '../../../../core/database/settings_repository.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/widgets/database_persistence_error_snackbar.dart';
import '../../services/department_deletion_inventory.dart';
import '../../services/department_deletion_orchestrator.dart';
import '../../services/department_deletion_undo_policy.dart';
import '../../services/department_rename_heuristic.dart';
import 'shared_asset_disconnect_dialog.dart';
import 'department_deletion_preview_dialog.dart';
import 'department_employee_reassign_dialog.dart';
import 'department_rename_guard_dialog.dart';
import '../../models/department_directory_column.dart';
import '../../models/department_model.dart';
import '../../building_map/providers/building_map_providers.dart';
import '../../providers/department_directory_provider.dart';
import '../../providers/directory_provider.dart';
import 'bulk_department_edit_dialog.dart';
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
      for (final f in floorsCatalogAsync.value ?? <BuildingMapFloor>[])
        f.id: f,
    };
    final state = ref.watch(departmentDirectoryProvider);
    final notifier = ref.read(departmentDirectoryProvider.notifier);
    final visibleColumns = state.orderedVisibleColumns;
    final continuousScrollAsync =
        ref.watch(catalogDepartmentsContinuousScrollProvider);
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
                            _openForm(context, ref, candidates.first,
                                isClone: true);
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

  Future<void> _confirmAndDeleteSelected(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final state = ref.read(departmentDirectoryProvider);
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

    final inventories = [
      for (final d in toDelete)
        DepartmentDeletionInventory.fromLookup(d.id!, d.name),
    ];
    final choice = await showDepartmentDeletionPreviewDialog(
      context: context,
      inventories: inventories,
    );
    if (choice == null ||
        choice == DepartmentDeletionChoice.cancel ||
        !context.mounted) {
      return;
    }

    final lookup = LookupService.instance;
    final deletingIds = state.selectedIds.toSet();
    var movedEmployeeCount = 0;
    var movedOrDeletedAssetCount = 0;
    final plans = <DepartmentDeletionPlan>[];

    // Φάση συλλογής: μόνο διάλογοι — χωρίς εγγραφές στη βάση.
    if (choice == DepartmentDeletionChoice.detailed) {
      for (final dept in toDelete) {
        final deptId = dept.id;
        if (deptId == null) continue;

        var employeeBatch = const DepartmentEmployeeReassignBatch(
          transfers: {},
        );
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
        if (employees.isNotEmpty) {
          final availableDepartments = lookup.departments
              .where(
                (d) =>
                    d.id != null &&
                    !d.isDeleted &&
                    !deletingIds.contains(d.id) &&
                    d.name.trim().isNotEmpty,
              )
              .toList();

          if (!context.mounted) return;
          final collected = await showDepartmentEmployeeReassignFlow(
            context: context,
            sourceDepartmentName: dept.name,
            employees: employees,
            availableDepartments: availableDepartments,
            sourceDepartmentId: deptId,
          );
          if (!context.mounted || collected == null) return;
          employeeBatch = collected;
          movedEmployeeCount += employeeBatch.transfers.length;
        }

        var sharedBatch = const SharedAssetDisconnectBatchResult();
        final phones = lookup.getDirectPhonesByDepartment(deptId);
        final equipment = lookup.getSharedEquipmentCodesByDepartment(deptId);
        if (phones.isNotEmpty || equipment.isNotEmpty) {
          final availableDepartments = lookup.departments
              .where(
                (d) =>
                    d.id != null &&
                    !d.isDeleted &&
                    !deletingIds.contains(d.id) &&
                    d.name.trim().isNotEmpty,
              )
              .toList();

          if (!context.mounted) return;
          final collected = await showSharedAssetDisconnectFlow(
            context: context,
            sourceDepartmentId: deptId,
            sourceDepartmentName: dept.name,
            phones: phones,
            equipmentCodes: equipment,
            availableDepartments: availableDepartments,
            allowKeepInDepartment: false,
          );
          if (!context.mounted || collected == null) return;
          sharedBatch = collected;
          movedOrDeletedAssetCount += sharedBatch.phoneTransfers.length +
              sharedBatch.phonesToDelete.length +
              sharedBatch.equipmentTransfers.length +
              sharedBatch.equipmentToDelete.length;
        }

        plans.add(
          DepartmentDeletionPlan(
            departmentId: deptId,
            employeeBatch: employeeBatch,
            sharedBatch: sharedBatch,
          ),
        );
      }
    } else {
      for (final dept in toDelete) {
        final deptId = dept.id;
        if (deptId == null) continue;

        final availableDepartments = lookup.departments
            .where(
              (d) =>
                  d.id != null &&
                  !d.isDeleted &&
                  !deletingIds.contains(d.id) &&
                  d.name.trim().isNotEmpty,
            )
            .toList();

        if (!context.mounted) return;
        final target = await showAssetTransferTargetPicker(
          context: context,
          headerLabel:
              'Πού μεταφέρονται όλα από «${dept.name.trim().isEmpty ? '—' : dept.name.trim()}»;',
          availableDepartments: availableDepartments,
          sourceDepartmentId: deptId,
        );
        if (!context.mounted || target == null) return;

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
        final movedTotal =
            employees.length + phones.length + equipment.length;
        final proposedNewName = target.newDepartmentName?.trim() ?? '';
        final dominantTargetIsNew = proposedNewName.isNotEmpty;

        if (looksLikeDepartmentRename(
          movedTotal: movedTotal,
          movedToDominantTarget: movedTotal,
          dominantTargetIsNew: dominantTargetIsNew,
        )) {
          if (!context.mounted) return;
          final guard = await showDepartmentRenameGuardDialog(
            context: context,
            sourceDepartmentName: dept.name,
            proposedNewName: proposedNewName,
          );
          if (!context.mounted) return;
          if (guard == null ||
              guard == DepartmentRenameGuardChoice.cancel) {
            return;
          }
          if (guard == DepartmentRenameGuardChoice.renameInstead) {
            await _openForm(
              context,
              ref,
              dept.copyWith(name: proposedNewName),
              focusedField: 'name',
            );
            return;
          }
        }

        var employeeBatch = const DepartmentEmployeeReassignBatch(
          transfers: {},
        );
        if (employees.isNotEmpty) {
          employeeBatch = DepartmentEmployeeReassignBatch(
            transfers: {
              for (final e in employees) e.id: target,
            },
          );
          movedEmployeeCount += employees.length;
        }

        var sharedBatch = const SharedAssetDisconnectBatchResult();
        if (phones.isNotEmpty || equipment.isNotEmpty) {
          final newDeptNames = <String, Set<String>>{};
          if (dominantTargetIsNew) {
            newDeptNames[proposedNewName] = {...phones};
          }
          sharedBatch = SharedAssetDisconnectBatchResult(
            phoneTransfers: {
              for (final p in phones) p: target,
            },
            equipmentTransfers: {
              for (final c in equipment) c: target,
            },
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
    if (plans.isEmpty) return;

    final db = await DatabaseHelper.instance.database;
    try {
      await applyDepartmentDeletionPlansAtomic(db, plans);
    } catch (e, st) {
      if (!context.mounted) return;
      showDatabasePersistenceErrorSnackBar(
        context,
        Exception(
          'Η διαγραφή τμήματος απέτυχε και καμία αλλαγή δεν έγινε. $e',
        ),
        st,
      );
      return;
    }

    final notifier = ref.read(departmentDirectoryProvider.notifier);
    await notifier.finalizeExternalDeletion(toDelete);
    if (!context.mounted) return;
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
    final displayNames =
        truncated ? '${names.sublist(0, take).join(', ')}...' : namesPart;
    final tooltipAllNames = names.isEmpty ? null : names.join(', ');

    final undoPolicy = resolveDepartmentDeletionUndo(
      deletedDepartmentCount: deletedCount,
      movedEmployeeCount: movedEmployeeCount,
      movedOrDeletedAssetCount: movedOrDeletedAssetCount,
    );
    final String message;
    if (undoPolicy.canOfferUndo) {
      message = names.isEmpty
          ? undoPolicy.snackbarMessage
          : '${undoPolicy.snackbarMessage.substring(0, undoPolicy.snackbarMessage.length - 1)}: $displayNames';
    } else {
      message = undoPolicy.snackbarMessage;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Expanded(
              child: tooltipAllNames != null
                  ? Tooltip(
                      message: tooltipAllNames,
                      child: Text(message),
                    )
                  : Text(message),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => messenger.hideCurrentSnackBar(),
              style: IconButton.styleFrom(
                foregroundColor:
                    Theme.of(context).colorScheme.onInverseSurface,
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
  }
}

class _DepartmentColumnSelectorOverlay extends ConsumerWidget {
  const _DepartmentColumnSelectorOverlay({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(departmentDirectoryProvider);
    final notifier = ref.read(departmentDirectoryProvider.notifier);
    final continuousScrollAsync =
        ref.watch(catalogDepartmentsContinuousScrollProvider);
    final continuousScroll = continuousScrollAsync.value ?? true;
    final theme = Theme.of(context);
    final order = state.columnOrder;
    final keys = state.visibleColumnKeys;
    final sel = DepartmentDirectoryColumn.selection;
    final orderRest =
        order.where((c) => c != sel).toList(growable: false);
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
                    onTap: () => notifier.setDepartmentColumnVisible(col, !isOn),
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
