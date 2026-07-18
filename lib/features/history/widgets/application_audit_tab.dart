import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/main_nav_request_provider.dart';
import '../../../core/database/audit_service.dart';
import '../../../core/widgets/main_nav_destination.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import '../../directory/screens/directory_screen.dart';
import '../../../core/widgets/calendar_range_picker.dart';
import '../../audit/constants/audit_ui_mappings.dart';
import '../../audit/models/audit_filter_model.dart';
import '../../audit/models/audit_log_model.dart';
import '../../audit/models/audit_page_result.dart';
import '../../audit/models/audit_reference_labels.dart';
import '../../audit/providers/audit_providers.dart';
import '../../audit/services/audit_formatter_service.dart';
import 'audit_entity_side_panel.dart';
import '../../../core/widgets/audit_summary_rich_text.dart';

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
    case AuditEntityTypes.backup:
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

  void _onEntityTypeSelected(String? value) {
    ref.read(auditFilterProvider.notifier).update(
          (s) => s.copyWith(
            entityType: value,
            clearEntityType: value == null,
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
    final labelsAsync = ref.watch(auditPageReferenceLabelsProvider);
    final referenceLabels = labelsAsync.maybeWhen(
      data: (labels) => labels,
      orElse: () => AuditReferenceLabels.empty,
    );
    final actionOptionsAsync = ref.watch(auditActionOptionsProvider);
    final selectedId = ref.watch(selectedAuditEntryIdProvider);
    // Κρατάμε τα προηγούμενα δεδομένα κατά τη διάρκεια refresh (valueOrNull)
    // ώστε το πεδίο να μην αδειάζει/απενεργοποιείται στιγμιαία.
    final actionOptions = actionOptionsAsync.value ?? const <String>[];
    final selectedAction = filter.action;
    final entityTypeOptions = _entityTypeAutocompleteOptions();
    String? selectedEntityLabel;
    for (final option in entityTypeOptions) {
      if (option.value == filter.entityType) {
        selectedEntityLabel = option.label;
        break;
      }
    }

    // Καθαρισμός επιλεγμένης ενέργειας ΜΟΝΟ με φρέσκα δεδομένα (όχι εν μέσω
    // loading/refresh) — αλλιώς έσβηνε την επιλογή αμέσως μετά το πρώτο κλικ.
    if (selectedAction != null &&
        selectedAction.isNotEmpty &&
        actionOptionsAsync.hasValue &&
        !actionOptionsAsync.isLoading &&
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
                          // Σταθερά keys: key που αλλάζει με την επιλογή
                          // κατέστρεφε το State (χανόταν focus/πρώτο κλικ).
                          final actionField = _AuditFilterAutocomplete(
                            key: const ValueKey('audit-filter-action'),
                            labelText: 'Ενέργεια',
                            options: actionOptions
                                .map(
                                  (action) => _AuditFilterAutocompleteOption(
                                    value: action,
                                    label: action,
                                  ),
                                )
                                .toList(),
                            selectedValue: selectedAction,
                            selectedLabel: selectedAction,
                            enabled: actionOptionsAsync.hasValue ||
                                !actionOptionsAsync.isLoading,
                            onSelected: _onActionSelected,
                          );
                          final entityDropdown = _AuditFilterAutocomplete(
                            key: const ValueKey('audit-filter-entity'),
                            labelText: 'Τύπος οντότητας',
                            options: entityTypeOptions,
                            selectedValue: filter.entityType,
                            selectedLabel: selectedEntityLabel,
                            onSelected: _onEntityTypeSelected,
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
              final pageLabel = listAsync.maybeWhen(
                data: (r) =>
                    'Σελίδα ${pageIndex + 1} / $totalPages · ${r.totalCount} εγγραφές',
                orElse: () => 'Φόρτωση…',
              );
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
                    pageLabel,
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
                      child: SelectableText(humanizeUserFacingError(e)),
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
                          title: AuditSummaryRichText(
                            text: formatter.summaryLine(
                              row,
                              labels: referenceLabels,
                            ),
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
                AuditEntitySidePanel(
                  entry: selectedEntry,
                  labels: referenceLabels,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static List<_AuditFilterAutocompleteOption> _entityTypeAutocompleteOptions() {
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
      AuditEntityTypes.backup,
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
      AuditEntityTypes.backup: 'Αντίγραφο ασφαλείας',
    };
    return types
        .map(
          (t) => _AuditFilterAutocompleteOption(
            value: t,
            label: labels[t] ?? t,
          ),
        )
        .toList();
  }
}

class _AuditFilterAutocompleteOption {
  const _AuditFilterAutocompleteOption({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;
}

/// Πεδίο φίλτρου με autocomplete (μοτίβο Λάμπας: overlay, Enter, X, κενό = όλα).
class _AuditFilterAutocomplete extends StatefulWidget {
  const _AuditFilterAutocomplete({
    super.key,
    required this.labelText,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    this.selectedLabel,
    this.enabled = true,
  });

  final String labelText;
  final List<_AuditFilterAutocompleteOption> options;
  final String? selectedValue;
  final String? selectedLabel;
  final ValueChanged<String?> onSelected;
  final bool enabled;

  @override
  State<_AuditFilterAutocomplete> createState() =>
      _AuditFilterAutocompleteState();
}

class _AuditFilterAutocompleteState extends State<_AuditFilterAutocomplete> {
  /// Σταθερό ύψος γραμμής πρότασης — απαραίτητο για την κύλιση-στην-επιλογή.
  static const double _kOptionExtent = 44;

  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _overlayScroll = ScrollController();
  OverlayEntry? _overlayEntry;
  List<_AuditFilterAutocompleteOption> _suggestions =
      const <_AuditFilterAutocompleteOption>[];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _syncControllerFromSelection();
    _controller.addListener(_onTextChanged);
    _focusNode.onKeyEvent = _handleKey;
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _AuditFilterAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedValue != widget.selectedValue &&
        !_focusNode.hasFocus) {
      _syncControllerFromSelection();
    }
    if (oldWidget.options != widget.options && _focusNode.hasFocus) {
      _refreshSuggestions();
    }
  }

  @override
  void deactivate() {
    _focusNode.unfocus();
    _removeOverlay();
    super.deactivate();
  }

  @override
  void dispose() {
    _removeOverlay();
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    _overlayScroll.dispose();
    super.dispose();
  }

  /// Κρατά την επισημασμένη πρόταση ορατή όταν η πλοήγηση γίνεται με βέλη.
  void _ensureHighlightedVisible() {
    if (!_overlayScroll.hasClients) return;
    final itemTop = _selectedIndex * _kOptionExtent;
    final itemBottom = itemTop + _kOptionExtent;
    final viewTop = _overlayScroll.offset;
    final viewBottom =
        viewTop + _overlayScroll.position.viewportDimension;
    double? target;
    if (itemTop < viewTop) {
      target = itemTop;
    } else if (itemBottom > viewBottom) {
      target = itemBottom - _overlayScroll.position.viewportDimension;
    }
    if (target != null) {
      _overlayScroll.jumpTo(
        target.clamp(0.0, _overlayScroll.position.maxScrollExtent),
      );
    }
  }

  void _syncControllerFromSelection() {
    final next = widget.selectedLabel ?? widget.selectedValue ?? '';
    if (_controller.text == next) return;
    _controller.text = next;
    _controller.selection = TextSelection.collapsed(offset: next.length);
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _removeOverlay();
      _syncControllerFromSelection();
    } else {
      _refreshSuggestions();
    }
  }

  void _onTextChanged() {
    setState(() {});
    _refreshSuggestions();
  }

  List<_AuditFilterAutocompleteOption> _filteredOptions(String query) {
    final normalized = SearchTextNormalizer.normalizeForSearch(query.trim());
    if (normalized.isEmpty) {
      return widget.options;
    }
    return widget.options
        .where(
          (option) =>
              SearchTextNormalizer.matchesNormalizedQuery(
                option.label,
                normalized,
              ) ||
              SearchTextNormalizer.matchesNormalizedQuery(
                option.value,
                normalized,
              ),
        )
        .toList();
  }

  /// Το overlay ΔΕΝ επιτρέπεται να αλλάξει μέσα σε build (π.χ. κλήση από
  /// didUpdateWidget)· εκτός build εκτελείται άμεσα, αλλιώς στο επόμενο frame.
  void _runOutsideBuild(VoidCallback action) {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      action();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  void _refreshSuggestions() {
    if (!widget.enabled || !_focusNode.hasFocus) {
      _runOutsideBuild(_removeOverlay);
      return;
    }
    final suggestions = _filteredOptions(_controller.text);
    if (suggestions.isEmpty) {
      _runOutsideBuild(_removeOverlay);
      return;
    }
    setState(() {
      _suggestions = suggestions;
      _selectedIndex = 0;
    });
    _runOutsideBuild(() {
      if (!_focusNode.hasFocus) return;
      _showOverlay();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_overlayScroll.hasClients) _overlayScroll.jumpTo(0);
      });
    });
  }

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: 320,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 52),
            child: TextFieldTapRegion(
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    controller: _overlayScroll,
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemExtent: _kOptionExtent,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, index) {
                      final option = _suggestions[index];
                      final selected = index == _selectedIndex;
                      final scheme = Theme.of(context).colorScheme;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        selectedTileColor: scheme.primaryContainer,
                        selectedColor: scheme.onPrimaryContainer,
                        title: Text(
                          option.label,
                          style: selected
                              ? const TextStyle(fontWeight: FontWeight.w700)
                              : null,
                        ),
                        trailing: selected
                            ? Icon(
                                Icons.keyboard_return,
                                size: 16,
                                color: scheme.onPrimaryContainer,
                              )
                            : null,
                        onTap: () => _applySuggestion(option),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    final entry = _overlayEntry;
    if (entry != null) {
      entry.remove();
      entry.dispose();
      _overlayEntry = null;
    }
  }

  void _applySuggestion(_AuditFilterAutocompleteOption option) {
    _controller.text = option.label;
    _controller.selection =
        TextSelection.collapsed(offset: option.label.length);
    widget.onSelected(option.value);
    _removeOverlay();
    _focusNode.requestFocus();
  }

  void _clearSelection() {
    _controller.clear();
    widget.onSelected(null);
    _removeOverlay();
    _focusNode.requestFocus();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (_overlayEntry == null || _suggestions.isEmpty) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _removeOverlay();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % _suggestions.length;
      });
      _overlayEntry?.markNeedsBuild();
      _ensureHighlightedVisible();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex =
            (_selectedIndex - 1 + _suggestions.length) % _suggestions.length;
      });
      _overlayEntry?.markNeedsBuild();
      _ensureHighlightedVisible();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _applySuggestion(_suggestions[_selectedIndex]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _removeOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        focusNode: _focusNode,
        controller: _controller,
        enabled: widget.enabled,
        decoration: InputDecoration(
          labelText: widget.labelText,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          isDense: true,
          suffixIcon: _controller.text.trim().isEmpty
              ? null
              : IconButton(
                  tooltip: 'Καθαρισμός ${widget.labelText.toLowerCase()}',
                  onPressed: widget.enabled ? _clearSelection : null,
                  icon: const Icon(Icons.clear),
                ),
        ),
      ),
    );
  }
}
