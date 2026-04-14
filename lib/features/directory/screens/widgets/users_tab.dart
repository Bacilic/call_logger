import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/directory_repository.dart';
import '../../../calls/models/user_model.dart';
import '../../../calls/provider/lookup_provider.dart';
import '../../models/department_model.dart';
import '../../models/non_user_phone_entry.dart';
import '../../models/user_catalog_mode.dart';
import '../../models/user_directory_column.dart';
import '../../providers/department_directory_provider.dart';
import '../../providers/directory_provider.dart';
import 'bulk_user_edit_dialog.dart';
import 'catalog_column_selector_shell.dart';
import 'department_form_dialog.dart';
import 'non_user_phones_data_table.dart';
import 'user_form_dialog.dart';
import 'users_data_table.dart';

/// Καρτέλα χρηστών: αναζήτηση, πίνακας, επιλογή, διαγραφή με undo, προσθήκη.
class UsersTab extends ConsumerStatefulWidget {
  const UsersTab({super.key});

  @override
  ConsumerState<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<UsersTab> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(directoryProvider.notifier).loadUsers();
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
    final state = ref.watch(directoryProvider);
    final notifier = ref.read(directoryProvider.notifier);
    final visibleColumns = state.orderedVisibleColumns;
    final personal = state.catalogMode == UserCatalogMode.personal;
    final hasQuery = state.searchQuery.trim().isNotEmpty;
    final personalBadgeCount =
        (!personal && hasQuery) ? state.filteredUsers.length : 0;
    final sharedBadgeCount =
        (personal && hasQuery) ? state.filteredNonUserPhones.length : 0;
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
                    hintText: personal
                        ? 'Όνομα, τηλέφωνο, τμήμα...'
                        : 'Τηλέφωνο, τμήμα...',
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
              const SizedBox(width: 8),
              _CatalogModeToggle(
                mode: state.catalogMode,
                personalBadgeCount: personalBadgeCount,
                sharedBadgeCount: sharedBadgeCount,
                onPersonal: () =>
                    notifier.setCatalogMode(UserCatalogMode.personal),
                onShared: () =>
                    notifier.setCatalogMode(UserCatalogMode.shared),
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
                  onRequestDelete: () => _confirmAndDeleteSelected(context, ref),
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

  Future<void> _confirmAndDeleteSelected(BuildContext context, WidgetRef ref) async {
    final state = ref.read(directoryProvider);
    if (state.selectedIds.isEmpty) return;
    final count = state.selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή χρηστών'),
        content: Text('Διαγραφή $count χρηστών;'),
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
    final notifier = ref.read(directoryProvider.notifier);
    await notifier.deleteSelected();
    if (!context.mounted) return;
    final deleted = ref.read(directoryProvider).lastDeleted ?? [];
    final deletedCount = deleted.length;
    final names = deleted.map((u) => u.name?.trim().isEmpty ?? true ? '?' : u.name!).toList();
    const maxNamesLength = 70;
    final namesPart = names.join(', ');
    int take = 0;
    int len = 0;
    for (; take < names.length; take++) {
      final add = (take == 0 ? '' : ', ') + names[take];
      if (len + add.length > maxNamesLength) break;
      len += add.length;
    }
    final truncated = take < names.length;
    final displayNames = truncated ? '${names.sublist(0, take).join(', ')}...' : namesPart;
    final isOne = deletedCount == 1;
    final label = isOne ? 'χρήστης' : 'χρήστες';
    final message = names.isEmpty
        ? 'Διαγράφηκαν $deletedCount $label.'
        : 'Διαγράφηκαν $deletedCount $label: $displayNames';
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
              onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
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
            await ref.read(directoryProvider.notifier).undoLastDelete();
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
          content: Text(
            'Δεν υπάρχει συσχετισμένο τμήμα για αυτόν τον αριθμό.',
          ),
        ),
      );
      return;
    }
    await ref.read(departmentDirectoryProvider.notifier).loadDepartments();
    final db = await DatabaseHelper.instance.database;
    final row = await DirectoryRepository(db).getDepartmentRowById(deptId);
    if (!context.mounted) return;
    if (row == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Δεν βρέθηκε το τμήμα.')),
      );
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
          message: 'Μόνο τηλέφωνα χρηστών',
          child: _modeButton(
            context: context,
            selected: personal,
            badgeCount: personalBadgeCount,
            onTap: onPersonal,
            child: Image.asset(
              'assets/phone_personal.png',
              width: 28,
              height: 28,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.phone_in_talk,
                color: scheme.primary,
                size: 28,
              ),
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
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.business,
                color: scheme.primary,
                size: 28,
              ),
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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Material(
            color: selected
                ? scheme.primaryContainer.withValues(alpha: 0.92)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: child,
              ),
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
    final theme = Theme.of(context);
    final order = state.columnOrder;
    final keys = state.visibleColumnKeys;
    final sel = UserDirectoryColumn.selection;
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
              onReorder: notifier.reorderUserColumns,
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
        ],
      ),
    );
  }
}
