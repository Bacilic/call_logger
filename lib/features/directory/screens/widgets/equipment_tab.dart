// Προσωρινή χρήση DataTable – σε επόμενη φάση εξέτασε custom Table για sticky headers & row selection.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../calls/models/equipment_model.dart';
import '../../../calls/models/user_model.dart';
import '../../models/equipment_column.dart';
import '../../providers/directory_provider.dart';
import '../../providers/equipment_directory_provider.dart';
import 'bulk_equipment_edit_dialog.dart';
import 'catalog_column_selector_shell.dart';
import 'equipment_data_table.dart';
import 'equipment_form_dialog.dart';

/// Καρτέλα εξοπλισμού: mirror του UsersTab – αναζήτηση, πίνακας, επιλογή, διαγραφή με undo, προσθήκη, μαζική επεξεργασία.
class EquipmentTab extends ConsumerStatefulWidget {
  const EquipmentTab({super.key});

  @override
  ConsumerState<EquipmentTab> createState() => _EquipmentTabState();
}

class _EquipmentTabState extends ConsumerState<EquipmentTab> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(equipmentDirectoryProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(equipmentDirectoryProvider);
    final notifier = ref.read(equipmentDirectoryProvider.notifier);
    final visibleColumns = state.orderedVisibleColumns;
    final continuousScrollAsync = ref.watch(catalogContinuousScrollProvider);
    final continuousScroll = continuousScrollAsync.value ?? true;

    if (_searchController.text != state.searchQuery) {
      _searchController.text = state.searchQuery;
      _searchController.selection = TextSelection.collapsed(
        offset: _searchController.text.length,
      );
    }

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
                  onChanged: notifier.setSearchQuery,
                  decoration: InputDecoration(
                    labelText: 'Αναζήτηση',
                    hintText: 'Κωδικός, τύπος, κάτοχος...',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: state.searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Καθαρισμός',
                            onPressed: () => notifier.setSearchQuery(''),
                          )
                        : null,
                  ),
                ),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ReorderableListView(
                    scrollDirection: Axis.horizontal,
                    buildDefaultDragHandles: false,
                    onReorder: (oldIndex, newIndex) {
                      notifier.reorderColumn(oldIndex, newIndex);
                    },
                    proxyDecorator: (child, index, animation) => Material(
                      elevation: 2,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: child,
                    ),
                    children: [
                      for (var i = 0; i < visibleColumns.length; i++)
                        ReorderableDelayedDragStartListener(
                          key: ValueKey(visibleColumns[i].key),
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              label: Text(
                                visibleColumns[i].label,
                                style: theme.textTheme.labelMedium,
                              ),
                              deleteIcon: Icon(
                                Icons.close,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              onDeleted: () =>
                                  notifier.toggleColumn(visibleColumns[i]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Προσθήκη / αφαίρεση στηλών',
                icon: const Icon(Icons.add),
                onPressed: () => _openColumnSelector(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: EquipmentDataTable(
            items: state.filteredItems,
            selectedIds: state.selectedIds,
            sortColumn: state.sortColumn,
            sortAscending: state.sortAscending,
            visibleColumns: state.orderedVisibleColumns,
            showBuildingInLocationColumn: state.showBuildingInLocationColumn,
            onToggleSelection: notifier.toggleSelection,
            onSetSort: notifier.setSort,
            onEditEquipment: (row, {focusedField}) => _openForm(
              context,
              ref,
              row.$1,
              initialOwner: row.$2,
              focusedField: focusedField,
            ),
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
                          final candidates = state.allItems
                              .where((r) => r.$1.id == id)
                              .toList();
                          if (candidates.isNotEmpty) {
                            _openForm(
                              context,
                              ref,
                              candidates.first.$1,
                              initialOwner: candidates.first.$2,
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

  Future<void> _openBulkEdit(BuildContext context, WidgetRef ref) async {
    final state = ref.read(equipmentDirectoryProvider);
    final selectedRows = state.allItems
        .where((r) =>
            r.$1.id != null && state.selectedIds.contains(r.$1.id))
        .toList();
    if (selectedRows.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => BulkEquipmentEditDialog(
        selectedRows: selectedRows,
        notifier: ref.read(equipmentDirectoryProvider.notifier),
        ref: ref,
      ),
    );
  }

  void _openColumnSelector(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.4),
      builder: (ctx) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: _EquipmentColumnSelectorOverlay(
          onClose: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    EquipmentModel? initialEquipment, {
    UserModel? initialOwner,
    bool isClone = false,
    String? focusedField,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => EquipmentFormDialog(
        initialEquipment: initialEquipment,
        initialOwner: initialOwner,
        notifier: ref.read(equipmentDirectoryProvider.notifier),
        ref: ref,
        isClone: isClone,
        focusedField: focusedField,
      ),
    );
  }

  Future<void> _confirmAndDeleteSelected(
      BuildContext context, WidgetRef ref) async {
    final state = ref.read(equipmentDirectoryProvider);
    if (state.selectedIds.isEmpty) return;
    final count = state.selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή εξοπλισμού'),
        content: Text('Διαγραφή $count εγγραφών εξοπλισμού;'),
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
    );
    if (ok != true || !context.mounted) return;
    final notifier = ref.read(equipmentDirectoryProvider.notifier);
    await notifier.deleteSelected();
    if (!context.mounted) return;
    final entries = ref.read(equipmentDirectoryProvider).lastDeleted;
    final bodyText = entries == null || entries.isEmpty
        ? 'Η διαγραφή ολοκληρώθηκε.'
        : entries.map((e) => e.feedbackLine).join('\n');

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        dismissDirection: DismissDirection.horizontal,
        showCloseIcon: false,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Text(bodyText),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: () => messenger.hideCurrentSnackBar(),
                  child: const Text('Επιβεβαίωση'),
                ),
                TextButton(
                  onPressed: () async {
                    messenger.hideCurrentSnackBar();
                    await ref
                        .read(equipmentDirectoryProvider.notifier)
                        .undoLastDelete();
                  },
                  child: const Text('Αναίρεση'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Overlay επιλογής στηλών: [selection] μόνο ορατότητα (πάντα πρώτη)· οι υπόλοιπες με σύρσιμο.
class _EquipmentColumnSelectorOverlay extends ConsumerWidget {
  const _EquipmentColumnSelectorOverlay({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(equipmentDirectoryProvider);
    final notifier = ref.read(equipmentDirectoryProvider.notifier);
    final order = state.columnOrder;
    final keys = state.visibleColumnKeys;
    final theme = Theme.of(context);
    final sel = EquipmentColumn.selection;
    final orderRest = order
        .where((c) => c.key != sel.key)
        .toList(growable: false);
    final selOn = keys.contains(sel.key);

    return CatalogColumnSelectorShell(
      onClose: onClose,
      title: 'Στήλες',
      maxHeight: 480,
      listChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              onTap: () => notifier.setEquipmentColumnVisible(sel, !selOn),
              leading: Checkbox(
                value: selOn,
                onChanged: (v) {
                  if (v != null) {
                    notifier.setEquipmentColumnVisible(sel, v);
                  }
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
              onReorder: notifier.reorderEquipmentColumns,
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
                    onTap: () => notifier.setEquipmentColumnVisible(col, !isOn),
                    leading: Checkbox(
                      value: isOn,
                      onChanged: (v) {
                        if (v != null) {
                          notifier.setEquipmentColumnVisible(col, v);
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
              'Εμφάνιση κτιρίου',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: const Text(
              'Στη στήλη «Τοποθεσία» (πρόθεμα [Κτίριο])',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            value: state.showBuildingInLocationColumn,
            onChanged: (v) {
              notifier.setEquipmentLocationShowBuilding(v);
            },
          ),
        ],
      ),
    );
  }
}
