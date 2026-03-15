// Προσωρινή χρήση DataTable – σε επόμενη φάση εξέτασε custom Table για sticky headers & row selection.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../calls/models/equipment_model.dart';
import '../../providers/directory_provider.dart';
import '../../providers/equipment_directory_provider.dart';
import '../../models/equipment_column.dart';
import 'bulk_equipment_edit_dialog.dart';
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
    final visibleColumns = state.visibleColumns;
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
            visibleColumns: state.visibleColumns,
            onToggleSelection: notifier.toggleSelection,
            onSetSort: notifier.setSort,
            onEditEquipment: (row, {focusedField}) =>
                _openForm(context, ref, row.$1, focusedField: focusedField),
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
                            _openForm(context, ref, candidates.first.$1,
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
      builder: (ctx) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: _ColumnSelectorOverlay(
          onClose: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    EquipmentModel? initialEquipment, {
    bool isClone = false,
    String? focusedField,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => EquipmentFormDialog(
        initialEquipment: initialEquipment,
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
    final deletedCount =
        ref.read(equipmentDirectoryProvider).lastDeleted?.length ?? count;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Διαγράφηκαν $deletedCount εγγραφές εξοπλισμού.'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Αναίρεση',
          onPressed: () async {
            await ref.read(equipmentDirectoryProvider.notifier).undoLastDelete();
          },
        ),
      ),
    );
  }
}

/// Overlay επιλογής στηλών: μένει ανοιχτός κατά το toggle, κλείνει με κλικ έξω ή με το χ.
class _ColumnSelectorOverlay extends ConsumerWidget {
  const _ColumnSelectorOverlay({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(equipmentDirectoryProvider);
    final notifier = ref.read(equipmentDirectoryProvider.notifier);
    final visibleColumns = state.visibleColumns;
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: theme.colorScheme.surfaceContainerHighest,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280, maxHeight: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
                    child: Row(
                      children: [
                        Text(
                          'Στήλες',
                          style: theme.textTheme.titleSmall,
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          tooltip: 'Κλείσιμο',
                          onPressed: onClose,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(32, 32),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: EquipmentColumn.all
                          .map(
                            (col) => CheckboxListTile(
                              title: Text(col.label),
                              value: visibleColumns.contains(col),
                              onChanged: (_) => notifier.toggleColumn(col),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
