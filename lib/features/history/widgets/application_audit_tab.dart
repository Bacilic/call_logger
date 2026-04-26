import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/main_nav_request_provider.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/widgets/main_nav_destination.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../../directory/screens/directory_screen.dart';
import '../../../core/widgets/calendar_range_picker.dart';
import '../../audit/constants/audit_ui_mappings.dart';
import '../../audit/models/audit_filter_model.dart';
import '../../audit/models/audit_log_model.dart';
import '../../audit/models/audit_page_result.dart';
import '../../audit/providers/audit_providers.dart';
import '../../audit/services/audit_formatter_service.dart';
import 'audit_entity_side_panel.dart';

/// Προορισμός «Μετάβαση» από γραμμή audit (null όταν δεν υπάρχει λογική οθόνη).
MainNavRequest? mainNavRequestForAuditEntry(AuditLogModel row) {
  final type = row.entityType?.trim();
  final id = row.entityId;

  switch (type) {
    case AuditEntityTypes.task:
      if (id == null) return null;
      return MainNavRequest(
        destination: MainNavDestination.tasks,
        taskFocusEntityId: id,
      );
    case AuditEntityTypes.user:
      return const MainNavRequest(
        destination: MainNavDestination.directory,
        directoryTabIndex: 0,
      );
    case AuditEntityTypes.phone:
      return const MainNavRequest(
        destination: MainNavDestination.directory,
        directoryTabIndex: 0,
      );
    case AuditEntityTypes.department:
      return const MainNavRequest(
        destination: MainNavDestination.directory,
        directoryTabIndex: 1,
      );
    case AuditEntityTypes.equipment:
      if (id == null) return null;
      return MainNavRequest(
        destination: MainNavDestination.directory,
        directoryTabIndex: 2,
        equipmentFocusEntityId: id,
      );
    case AuditEntityTypes.category:
    case AuditEntityTypes.importData:
      return const MainNavRequest(
        destination: MainNavDestination.directory,
        directoryTabIndex: kDirectoryCategoriesTabIndex,
      );
    case AuditEntityTypes.call:
      if (id == null) return null;
      return MainNavRequest(
        destination: MainNavDestination.history,
        callFocusEntityId: id,
      );
    case AuditEntityTypes.bulkUsers:
      return const MainNavRequest(
        destination: MainNavDestination.directory,
        directoryTabIndex: 0,
      );
    case AuditEntityTypes.bulkDepartments:
      return const MainNavRequest(
        destination: MainNavDestination.directory,
        directoryTabIndex: 1,
      );
    case AuditEntityTypes.bulkEquipment:
      return const MainNavRequest(
        destination: MainNavDestination.directory,
        directoryTabIndex: 2,
      );
    case AuditEntityTypes.maintenance:
      return const MainNavRequest(
        destination: MainNavDestination.database,
      );
    default:
      return null;
  }
}

/// Λίστα ιστορικού εφαρμογής (audit): φίλτρα, σελιδοποίηση, side panel.
class ApplicationAuditTab extends ConsumerStatefulWidget {
  const ApplicationAuditTab({super.key});

  @override
  ConsumerState<ApplicationAuditTab> createState() =>
      _ApplicationAuditTabState();
}

class _ApplicationAuditTabState extends ConsumerState<ApplicationAuditTab> {
  static const Duration _debounceDuration = Duration(milliseconds: 350);
  final TextEditingController _keywordController = TextEditingController();
  Timer? _debounceKeyword;
  final Set<int> _selectedAuditIds = <int>{};
  bool _isSelectingAll = false;
  bool _deleteCountdownActive = false;

  @override
  void initState() {
    super.initState();
    final f = ref.read(auditFilterProvider);
    _keywordController.text = f.keyword;
  }

  @override
  void dispose() {
    _debounceKeyword?.cancel();
    _keywordController.dispose();
    super.dispose();
  }

  void _onKeywordChanged(String value) {
    _debounceKeyword?.cancel();
    _debounceKeyword = Timer(_debounceDuration, () {
      ref.read(auditFilterProvider.notifier).update(
            (s) => s.copyWith(keyword: value.trim()),
          );
      ref.read(auditPageIndexProvider.notifier).reset();
    });
  }

  void _onActionSelected(String? value) {
    final next = value?.trim();
    ref.read(auditFilterProvider.notifier).update(
          (s) => s.copyWith(
            action: (next == null || next.isEmpty) ? null : next,
            clearAction: next == null || next.isEmpty,
          ),
        );
    ref.read(auditPageIndexProvider.notifier).reset();
  }

  void _clearKeyword() {
    _debounceKeyword?.cancel();
    _keywordController.clear();
    ref.read(auditFilterProvider.notifier).update(
          (s) => s.copyWith(keyword: ''),
        );
    ref.read(auditPageIndexProvider.notifier).reset();
  }

  void _clearSelection() {
    if (_selectedAuditIds.isEmpty) return;
    setState(() {
      _selectedAuditIds.clear();
    });
  }

  void _toggleRowSelection(int id, bool? checked) {
    setState(() {
      if (checked == true) {
        _selectedAuditIds.add(id);
      } else {
        _selectedAuditIds.remove(id);
      }
    });
  }

  Future<List<int>> _matchingIdsForCurrentFilter() async {
    final filter = ref.read(auditFilterProvider);
    final service = await ref.read(auditServiceAsyncProvider.future);
    final keyword = SearchTextNormalizer.normalizeForSearch(
      filter.keyword.trim(),
    );
    return service.queryMatchingIds(
      keywordNormalized: keyword.isEmpty ? null : keyword,
      action: filter.action,
      entityType: filter.entityType,
      dateFromInclusiveIso: filter.dateFromInclusiveIso,
      dateToExclusiveIso: filter.dateToExclusiveIso,
    );
  }

  Future<void> _toggleSelectAllByFilter(bool selectAll) async {
    if (_isSelectingAll) return;
    setState(() => _isSelectingAll = true);
    try {
      if (!selectAll) {
        if (!mounted) return;
        setState(() => _selectedAuditIds.clear());
        return;
      }
      final ids = await _matchingIdsForCurrentFilter();
      if (!mounted) return;
      setState(() {
        _selectedAuditIds
          ..clear()
          ..addAll(ids);
      });
    } finally {
      if (mounted) {
        setState(() => _isSelectingAll = false);
      }
    }
  }

  Future<void> _confirmAndDeleteSelection() async {
    final ids = _selectedAuditIds.toList()..sort();
    if (ids.isEmpty || _deleteCountdownActive) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Μόνιμη διαγραφή καταγραφών'),
        content: Text(
          'Θα διαγραφούν μόνιμα από τη βάση δεδομένων ${ids.length} εγγραφές.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Επιβεβαίωση'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    _clearSelection();
    ref.read(selectedAuditEntryIdProvider.notifier).select(null);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deleteCountdownActive = true);
    var undone = false;
    Timer? deleteTimer;
    final deleteIds = ids;

    deleteTimer = Timer(const Duration(seconds: 5), () async {
      if (undone || !mounted) return;
      final service = await ref.read(auditServiceAsyncProvider.future);
      await service.deleteByIds(deleteIds);
      if (!mounted) return;
      ref.invalidate(auditListProvider);
      messenger.hideCurrentSnackBar();
      setState(() => _deleteCountdownActive = false);
    });

    messenger.hideCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Text('Διαγράφηκαν ${deleteIds.length} εγγραφές.'),
            action: SnackBarAction(
              label: 'Αναίρεση',
              onPressed: () {
                undone = true;
                deleteTimer?.cancel();
                if (mounted) {
                  setState(() => _deleteCountdownActive = false);
                }
                ref.invalidate(auditListProvider);
              },
            ),
          ),
        )
        .closed
        .then((_) {
          if (mounted) {
            setState(() => _deleteCountdownActive = false);
          }
        });
  }

  Future<void> _pickDateRange() async {
    final filter = ref.read(auditFilterProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialStart = filter.dateFrom ?? today;
    final initialEnd = filter.dateTo ?? today;
    final result = await showCalendarRangePickerDialog(
      context,
      initialValue: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (!mounted || result == null) return;
    if (result.wasCleared) {
      ref.read(auditFilterProvider.notifier).update(
            (s) => s.copyWith(clearDateRange: true),
          );
      ref.read(auditPageIndexProvider.notifier).reset();
      return;
    }
    final range = result.range;
    if (range == null) return;
    ref.read(auditFilterProvider.notifier).update(
          (s) => s.copyWith(dateFrom: range.start, dateTo: range.end),
        );
    ref.read(auditPageIndexProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(auditPageIndexProvider, (previous, next) {
      ref.read(selectedAuditEntryIdProvider.notifier).select(null);
      _clearSelection();
    });
    ref.listen<AuditFilterModel>(auditFilterProvider, (previous, next) {
      if (previous == null) return;
      final changed = previous.keyword != next.keyword ||
          previous.action != next.action ||
          previous.entityType != next.entityType ||
          previous.dateFrom != next.dateFrom ||
          previous.dateTo != next.dateTo;
      if (changed) _clearSelection();
    });

    final theme = Theme.of(context);
    const formatter = AuditFormatterService();
    final filter = ref.watch(auditFilterProvider);
    final pageIndex = ref.watch(auditPageIndexProvider);
    final panelOpen = ref.watch(auditSidePanelOpenProvider);
    final listAsync = ref.watch(auditListProvider);
    final actionOptionsAsync = ref.watch(auditActionOptionsProvider);
    final selectedId = ref.watch(selectedAuditEntryIdProvider);
    final actionOptions = actionOptionsAsync.maybeWhen(
      data: (items) => items,
      orElse: () => const <String>[],
    );
    final selectedAction = filter.action;
    final selectedActionForField =
        selectedAction != null && actionOptions.contains(selectedAction)
        ? selectedAction
        : null;

    if (selectedAction != null &&
        selectedAction.isNotEmpty &&
        actionOptionsAsync.hasValue &&
        !actionOptions.contains(selectedAction)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(auditFilterProvider.notifier).update(
              (s) => s.copyWith(clearAction: true),
            );
        ref.read(auditPageIndexProvider.notifier).reset();
      });
    }

    final AuditLogModel? selectedEntry = listAsync.maybeWhen(
      data: (AuditPageResult r) {
        if (selectedId == null) return null;
        for (final i in r.items) {
          if (i.id == selectedId) return i;
        }
        return null;
      },
      orElse: () => null,
    );

    String dateRangeLabel = '';
    if (filter.dateFrom != null && filter.dateTo != null) {
      dateRangeLabel =
          '${DateFormat('dd/MM/yyyy').format(filter.dateFrom!)} – ${DateFormat('dd/MM/yyyy').format(filter.dateTo!)}';
    } else if (filter.dateFrom != null) {
      dateRangeLabel =
          'από ${DateFormat('dd/MM/yyyy').format(filter.dateFrom!)}';
    } else if (filter.dateTo != null) {
      dateRangeLabel = 'έως ${DateFormat('dd/MM/yyyy').format(filter.dateTo!)}';
    }
    final hasDateRange = filter.dateFrom != null || filter.dateTo != null;

    final totalPages = listAsync.maybeWhen(
      data: (r) {
        final n = (r.totalCount / kAuditPageSize).ceil();
        return n < 1 ? 1 : n;
      },
      orElse: () => 1,
    );
    final totalCount = listAsync.maybeWhen(
      data: (r) => r.totalCount,
      orElse: () => 0,
    );
    final allSelected = totalCount > 0 && _selectedAuditIds.length == totalCount;
    final someSelected = _selectedAuditIds.isNotEmpty && !allSelected;
    final canDeleteSelection =
        _selectedAuditIds.isNotEmpty && !_isSelectingAll && !_deleteCountdownActive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 1250;
                          final panelButton = IconButton.filled(
                            tooltip: panelOpen
                                ? 'Απόκρυψη πλαισίου λεπτομερειών'
                                : 'Εμφάνιση πλαισίου λεπτομερειών',
                            onPressed: () => ref
                                .read(auditSidePanelOpenProvider.notifier)
                                .toggle(),
                            icon: Icon(
                              panelOpen
                                  ? Icons.vertical_split
                                  : Icons.view_sidebar_outlined,
                            ),
                          );
                          final dateButton = IconButton.filled(
                            onPressed: _pickDateRange,
                            tooltip: 'Εύρος ημερομηνιών',
                            icon: const Icon(Icons.date_range),
                          );
                          final keywordField = TextField(
                            controller: _keywordController,
                            onChanged: _onKeywordChanged,
                            decoration: InputDecoration(
                              hintText:
                                  'Λέξη-κλειδί (λεπτομέρειες, τύπος, ενέργεια…)',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: filter.keyword.trim().isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Καθαρισμός αναζήτησης',
                                      onPressed: _clearKeyword,
                                      icon: const Icon(Icons.clear),
                                    ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              isDense: true,
                            ),
                          );
                          final actionField = DropdownButtonFormField<String?>(
                            key: ValueKey('${filter.entityType}|${filter.action}'),
                            initialValue: selectedActionForField,
                            decoration: InputDecoration(
                              labelText: 'Ενέργεια',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              isDense: true,
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('— Όλες —'),
                              ),
                              ...actionOptions.map(
                                (action) => DropdownMenuItem<String?>(
                                  value: action,
                                  child: Text(action),
                                ),
                              ),
                            ],
                            onChanged: actionOptionsAsync.isLoading
                                ? null
                                : _onActionSelected,
                          );
                          final entityDropdown = DropdownButtonFormField<String?>(
                            key: ValueKey(filter.entityType),
                            initialValue: filter.entityType,
                            decoration: InputDecoration(
                              labelText: 'Τύπος οντότητας',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              isDense: true,
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('— Όλα —'),
                              ),
                              ..._entityTypeDropdownEntries(),
                            ],
                            onChanged: (v) {
                              ref.read(auditFilterProvider.notifier).update(
                                    (s) => s.copyWith(
                                      entityType: v,
                                      clearEntityType: v == null,
                                    ),
                                  );
                              ref.read(auditPageIndexProvider.notifier).reset();
                            },
                          );

                          if (compact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    panelButton,
                                    const SizedBox(width: 8),
                                    Expanded(child: keywordField),
                                    const SizedBox(width: 8),
                                    dateButton,
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(child: actionField),
                                    const SizedBox(width: 8),
                                    Expanded(child: entityDropdown),
                                    const SizedBox(width: 8),
                                    IconButton.filled(
                                      tooltip: 'Μόνιμη διαγραφή επιλεγμένων',
                                      onPressed: canDeleteSelection
                                          ? _confirmAndDeleteSelection
                                          : null,
                                      icon: const Icon(Icons.cleaning_services),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              panelButton,
                              const SizedBox(width: 8),
                              Expanded(flex: 2, child: keywordField),
                              const SizedBox(width: 8),
                              Expanded(child: actionField),
                              const SizedBox(width: 8),
                              SizedBox(width: 200, child: entityDropdown),
                              const SizedBox(width: 8),
                              dateButton,
                              const SizedBox(width: 8),
                              IconButton.filled(
                                tooltip: 'Μόνιμη διαγραφή επιλεγμένων',
                                onPressed: canDeleteSelection
                                    ? _confirmAndDeleteSelection
                                    : null,
                                icon: const Icon(Icons.cleaning_services),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
                if (hasDateRange) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        label: Text(dateRangeLabel),
                        onPressed: _pickDateRange,
                      ),
                      ActionChip(
                        label: const Text('Καθαρισμός ημερομηνιών'),
                        onPressed: () {
                          ref.read(auditFilterProvider.notifier).update(
                                (s) => s.copyWith(clearDateRange: true),
                              );
                          ref.read(auditPageIndexProvider.notifier).reset();
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                children: [
                  Checkbox(
                    tristate: true,
                    value: allSelected ? true : (someSelected ? null : false),
                    onChanged: _isSelectingAll
                        ? null
                        : (v) => _toggleSelectAllByFilter(v == true),
                  ),
                  Text(
                    'Επιλεγμένες: ${_selectedAuditIds.length}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Προηγούμενη σελίδα',
                    onPressed: pageIndex <= 0
                        ? null
                        : () => ref
                            .read(auditPageIndexProvider.notifier)
                            .setPage(pageIndex - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    listAsync.maybeWhen(
                      data: (r) =>
                          'Σελίδα ${pageIndex + 1} / $totalPages · ${r.totalCount} εγγραφές',
                      orElse: () => 'Φόρτωση…',
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                  IconButton(
                    tooltip: 'Επόμενη σελίδα',
                    onPressed: listAsync.maybeWhen(
                      data: (r) =>
                          (pageIndex + 1) * kAuditPageSize >= r.totalCount
                              ? null
                              : () => ref
                                  .read(auditPageIndexProvider.notifier)
                                  .setPage(pageIndex + 1),
                      orElse: () => null,
                    ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              );
            },
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: listAsync.when(
                  loading: () => const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Φόρτωση audit…'),
                      ],
                    ),
                  ),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: SelectableText('$e'),
                    ),
                  ),
                  data: (AuditPageResult r) {
                    if (r.items.isEmpty) {
                      return Center(
                        child: Text(
                          'Δεν βρέθηκαν εγγραφές με τα τρέχοντα κριτήρια.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: r.items.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = r.items[index];
                        final style = auditStyleForAction(
                          row.action,
                          theme.colorScheme,
                        );
                        final selected = row.id == selectedId;
                        final checked = _selectedAuditIds.contains(row.id);
                        final subtitleParts = <String>[
                          formatter.formatAuditTimestamp(row.timestamp),
                        ];
                        if (row.hasMeaningfulPerformingUser) {
                          subtitleParts.add(row.userPerforming!.trim());
                        }
                        final navRequest = mainNavRequestForAuditEntry(row);
                        return ListTile(
                          selected: selected,
                          leading: SizedBox(
                            width: 72,
                            child: Row(
                              children: [
                                Checkbox(
                                  value: checked,
                                  onChanged: _deleteCountdownActive
                                      ? null
                                      : (v) => _toggleRowSelection(row.id, v),
                                ),
                                Icon(style.icon, color: style.color),
                              ],
                            ),
                          ),
                          title: Text(
                            formatter.summaryLine(row),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            subtitleParts.join(' · '),
                            style: theme.textTheme.bodySmall,
                          ),
                          trailing: navRequest == null
                              ? null
                              : TextButton(
                                  onPressed: () {
                                    ref
                                        .read(mainNavRequestProvider.notifier)
                                        .request(navRequest);
                                  },
                                  child: const Text('Μετάβαση'),
                                ),
                          onTap: () {
                            ref
                                .read(selectedAuditEntryIdProvider.notifier)
                                .select(row.id);
                            ref
                                .read(auditSidePanelOpenProvider.notifier)
                                .setOpen(true);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              if (panelOpen &&
                  selectedEntry != null &&
                  selectedId != null) ...[
                const VerticalDivider(width: 1),
                AuditEntitySidePanel(entry: selectedEntry),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static List<DropdownMenuItem<String?>> _entityTypeDropdownEntries() {
    const types = <String>[
      AuditEntityTypes.user,
      AuditEntityTypes.phone,
      AuditEntityTypes.department,
      AuditEntityTypes.equipment,
      AuditEntityTypes.category,
      AuditEntityTypes.task,
      AuditEntityTypes.call,
      AuditEntityTypes.bulkUsers,
      AuditEntityTypes.bulkDepartments,
      AuditEntityTypes.bulkEquipment,
      AuditEntityTypes.importData,
      AuditEntityTypes.maintenance,
    ];
    const labels = <String, String>{
      AuditEntityTypes.user: 'Χρήστης',
      AuditEntityTypes.phone: 'Τηλέφωνο',
      AuditEntityTypes.department: 'Τμήμα',
      AuditEntityTypes.equipment: 'Εξοπλισμός',
      AuditEntityTypes.category: 'Κατηγορία',
      AuditEntityTypes.task: 'Εκκρεμότητα',
      AuditEntityTypes.call: 'Κλήση',
      AuditEntityTypes.bulkUsers: 'Μαζική ενημέρωση χρηστών',
      AuditEntityTypes.bulkDepartments: 'Μαζική ενημέρωση τμημάτων',
      AuditEntityTypes.bulkEquipment: 'Μαζική ενημέρωση εξοπλισμού',
      AuditEntityTypes.importData: 'Εισαγωγή δεδομένων',
      AuditEntityTypes.maintenance: 'Συντήρηση βάσης',
    };
    return types
        .map(
          (t) => DropdownMenuItem<String?>(
            value: t,
            child: Text(labels[t] ?? t),
          ),
        )
        .toList();
  }
}
