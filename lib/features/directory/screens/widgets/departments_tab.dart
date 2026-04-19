import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/directory_repository.dart';
import '../../../calls/provider/lookup_provider.dart';
import '../../models/department_directory_column.dart';
import '../../models/department_model.dart';
import '../../providers/department_directory_provider.dart';
import '../../providers/directory_provider.dart';
import 'bulk_department_edit_dialog.dart';
import 'catalog_column_selector_shell.dart';
import 'department_form_dialog.dart';
import 'departments_data_table.dart';
import '../../building_map/screens/building_map_dialog.dart';

/// Καρτέλα τμημάτων: αναζήτηση, πίνακας, επιλογή, διαγραφή με undo, προσθήκη.
class DepartmentsTab extends ConsumerStatefulWidget {
  const DepartmentsTab({super.key});

  @override
  ConsumerState<DepartmentsTab> createState() => _DepartmentsTabState();
}

class _DepartmentsTabState extends ConsumerState<DepartmentsTab> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(departmentDirectoryProvider.notifier).loadDepartments();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(lookupServiceProvider);
    final state = ref.watch(departmentDirectoryProvider);
    final notifier = ref.read(departmentDirectoryProvider.notifier);
    final visibleColumns = state.orderedVisibleColumns;
    final continuousScrollAsync =
        ref.watch(catalogDepartmentsContinuousScrollProvider);
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
                    hintText: 'Όνομα, κτίριο, σημειώσεις...',
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
    final count = state.selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή τμημάτων'),
        content: Text('Μόνιμη σήμανση ως διαγραμμένα για $count τμήματα;'),
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
    final notifier = ref.read(departmentDirectoryProvider.notifier);
    await notifier.deleteSelected();
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
    final isOne = deletedCount == 1;
    final label = isOne ? 'τμήμα' : 'τμήματα';
    final message = names.isEmpty
        ? 'Σημειώθηκαν ως διαγραμμένα $deletedCount $label.'
        : 'Σημειώθηκαν ως διαγραμμένα $deletedCount $label: $displayNames';
    final tooltipAllNames = names.isEmpty ? null : names.join(', ');

    ScaffoldMessenger.of(context).showSnackBar(
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
              onPressed: () =>
                  ScaffoldMessenger.of(context).hideCurrentSnackBar(),
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
        action: SnackBarAction(
          label: 'Αναίρεση',
          onPressed: () async {
            await ref
                .read(departmentDirectoryProvider.notifier)
                .undoLastDelete();
          },
        ),
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
              onReorder: notifier.reorderDepartmentColumns,
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
              await DirectoryRepository(db).setSetting(
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
