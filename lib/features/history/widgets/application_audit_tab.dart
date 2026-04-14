import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/main_nav_request_provider.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/widgets/main_nav_destination.dart';
import '../../directory/screens/directory_screen.dart';
import '../../../core/widgets/calendar_range_picker.dart';
import '../../audit/constants/audit_ui_mappings.dart';
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
  final TextEditingController _actionController = TextEditingController();
  Timer? _debounceKeyword;
  Timer? _debounceAction;

  @override
  void initState() {
    super.initState();
    final f = ref.read(auditFilterProvider);
    _keywordController.text = f.keyword;
    _actionController.text = f.action ?? '';
  }

  @override
  void dispose() {
    _debounceKeyword?.cancel();
    _debounceAction?.cancel();
    _keywordController.dispose();
    _actionController.dispose();
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

  void _onActionChanged(String value) {
    _debounceAction?.cancel();
    _debounceAction = Timer(_debounceDuration, () {
      final t = value.trim();
      ref.read(auditFilterProvider.notifier).update(
            (s) => s.copyWith(
              action: t.isEmpty ? null : t,
              clearAction: t.isEmpty,
            ),
          );
      ref.read(auditPageIndexProvider.notifier).reset();
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
    });

    final theme = Theme.of(context);
    const formatter = AuditFormatterService();
    final filter = ref.watch(auditFilterProvider);
    final pageIndex = ref.watch(auditPageIndexProvider);
    final panelOpen = ref.watch(auditSidePanelOpenProvider);
    final listAsync = ref.watch(auditListProvider);
    final selectedId = ref.watch(selectedAuditEntryIdProvider);

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
                    IconButton.filled(
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
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _keywordController,
                        onChanged: _onKeywordChanged,
                        decoration: InputDecoration(
                          hintText: 'Λέξη-κλειδί (λεπτομέρειες, τύπος, ενέργεια…)',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _actionController,
                        onChanged: _onActionChanged,
                        decoration: InputDecoration(
                          hintText: 'Ενέργεια (ακριβές κείμενο)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 200,
                      child: DropdownButtonFormField<String?>(
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
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _pickDateRange,
                      tooltip: 'Εύρος ημερομηνιών',
                      icon: const Icon(Icons.date_range),
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
          child: Row(
            children: [
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
                        final subtitleParts = <String>[
                          formatter.formatAuditTimestamp(row.timestamp),
                        ];
                        if (row.hasMeaningfulPerformingUser) {
                          subtitleParts.add(row.userPerforming!.trim());
                        }
                        final navRequest = mainNavRequestForAuditEntry(row);
                        return ListTile(
                          selected: selected,
                          leading: Icon(style.icon, color: style.color),
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
    return types
        .map(
          (t) => DropdownMenuItem<String?>(
            value: t,
            child: Text(t),
          ),
        )
        .toList();
  }
}
