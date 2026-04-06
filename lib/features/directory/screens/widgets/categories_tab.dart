import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category_directory_column.dart';
import '../../models/category_model.dart';
import '../../providers/category_directory_provider.dart';
import 'catalog_column_selector_shell.dart';
import 'categories_data_table.dart';
import 'category_form_dialog.dart';
import 'category_undo_snackbar.dart';

/// Καρτέλα «Διάφορα»: κατηγορίες κλήσεων.
class CategoriesTab extends ConsumerStatefulWidget {
  const CategoriesTab({super.key});

  @override
  ConsumerState<CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends ConsumerState<CategoriesTab> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(categoryDirectoryProvider.notifier).loadCategories();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(categoryDirectoryProvider);
    final notifier = ref.read(categoryDirectoryProvider.notifier);
    final visibleColumns = state.orderedVisibleColumns;
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
                    hintText: 'Όνομα κατηγορίας...',
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
          child: CategoriesDataTable(
            categories: state.filteredCategories,
            selectedIds: state.selectedIds,
            sortColumn: state.sortColumn,
            sortAscending: state.sortAscending,
            visibleColumns: visibleColumns,
            onToggleSelection: notifier.toggleSelection,
            onSetSort: notifier.setSort,
            onEditCategory: (c, {focusedField}) =>
                _openForm(context, ref, c),
            focusedRowIndex: state.focusedRowIndex,
            onSetFocusedRowIndex: notifier.setFocusedRowIndex,
            onRequestDelete: () => _confirmAndDeleteSelected(context, ref),
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
        child: _CategoryColumnSelectorOverlay(
          onClose: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    CategoryModel? category,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => CategoryFormDialog(
        initialCategory: category,
        notifier: ref.read(categoryDirectoryProvider.notifier),
      ),
    );
  }

  Future<void> _confirmAndDeleteSelected(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final state = ref.read(categoryDirectoryProvider);
    if (state.selectedIds.isEmpty) return;
    final count = state.selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή κατηγοριών'),
        content: Text('Μόνιμη σήμανση ως διαγραμμένα για $count κατηγορίες;'),
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
    final notifier = ref.read(categoryDirectoryProvider.notifier);
    await notifier.deleteSelected();
    if (!context.mounted) return;
    final deleted = ref.read(categoryDirectoryProvider).lastDeleted ?? [];
    final deletedCount = deleted.length;
    final names = deleted
        .map((c) => c.name.trim().isEmpty ? '?' : c.name)
        .toList();
    const maxNamesLength = 70;
    var take = 0;
    var len = 0;
    for (; take < names.length; take++) {
      final add = (take == 0 ? '' : ', ') + names[take];
      if (len + add.length > maxNamesLength) break;
      len += add.length;
    }
    final truncated = take < names.length;
    final displayNames =
        truncated ? '${names.sublist(0, take).join(', ')}...' : names.join(', ');
    final isOne = deletedCount == 1;
    final label = isOne ? 'κατηγορία' : 'κατηγορίες';
    final message = names.isEmpty
        ? 'Σημειώθηκαν ως διαγραμμένα $deletedCount $label.'
        : 'Σημειώθηκαν ως διαγραμμένα $deletedCount $label: $displayNames';
    final tooltipAllNames = names.isEmpty ? null : names.join(', ');

    CategoryUndoSnackBar.show(
      ScaffoldMessenger.of(context),
      message: message,
      tooltipMessage: tooltipAllNames,
      showCloseIcon: true,
      onUndo: () {
        ref.read(categoryDirectoryProvider.notifier).undoLastDelete();
      },
    );
  }
}

class _CategoryColumnSelectorOverlay extends ConsumerWidget {
  const _CategoryColumnSelectorOverlay({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(categoryDirectoryProvider);
    final notifier = ref.read(categoryDirectoryProvider.notifier);
    final theme = Theme.of(context);
    final order = state.columnOrder;
    final keys = state.visibleColumnKeys;
    final sel = CategoryDirectoryColumn.selection;
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
              onTap: () => notifier.setCategoryColumnVisible(sel, !selOn),
              leading: Checkbox(
                value: selOn,
                onChanged: (v) {
                  if (v != null) notifier.setCategoryColumnVisible(sel, v);
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
              onReorder: notifier.reorderCategoryColumns,
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
                        notifier.setCategoryColumnVisible(col, !isOn),
                    leading: Checkbox(
                      value: isOn,
                      onChanged: (v) {
                        if (v != null) {
                          notifier.setCategoryColumnVisible(col, v);
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
        ],
      ),
    );
  }
}
