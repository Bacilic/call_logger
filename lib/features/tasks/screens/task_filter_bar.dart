import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/calendar_range_picker.dart';
import '../models/task.dart';
import '../models/task_filter.dart';
import '../providers/tasks_provider.dart';
import '../widgets/task_analytics_bottom_sheet.dart';

/// Μπάρα αναζήτησης και φίλτρων: κείμενο (debounce 300ms), status chips, εύρος ημερομηνιών.
class TaskFilterBar extends ConsumerStatefulWidget {
  const TaskFilterBar({super.key});

  @override
  ConsumerState<TaskFilterBar> createState() => _TaskFilterBarState();
}

class _TaskFilterBarState extends ConsumerState<TaskFilterBar> {
  static const Duration _debounceDuration = Duration(milliseconds: 300);

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    final filter = ref.read(taskFilterProvider);
    _searchController.text = filter.searchQuery;
    _searchController.addListener(_onSearchControllerChanged);
  }

  void _onSearchControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchControllerChanged);
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _debounceTimer?.cancel();
    _searchController.clear();
    ref
        .read(taskFilterProvider.notifier)
        .update((s) => s.copyWith(searchQuery: ''));
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      ref
          .read(taskFilterProvider.notifier)
          .update((s) => s.copyWith(searchQuery: value.trim()));
    });
  }

  void _toggleStatus(TaskStatus status) {
    ref.read(taskFilterProvider.notifier).update((s) {
      final list = List<TaskStatus>.from(s.statuses);
      if (list.contains(status)) {
        list.remove(status);
      } else {
        list.add(status);
      }
      return s.copyWith(statuses: list);
    });
  }

  Future<void> _pickDateRange() async {
    final filter = ref.read(taskFilterProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialStart = filter.startDate ?? today;
    final initialEnd = filter.endDate ?? today;
    final result = await showCalendarRangePickerDialog(
      context,
      initialValue: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (!mounted || result == null) return;
    if (result.wasCleared) {
      _clearDateRange();
      return;
    }
    final range = result.range;
    if (range == null) return;
    ref
        .read(taskFilterProvider.notifier)
        .update((s) => s.copyWith(startDate: range.start, endDate: range.end));
  }

  void _clearDateRange() {
    ref
        .read(taskFilterProvider.notifier)
        .update((s) => s.copyWith(clearDateRange: true));
  }

  /// Αποφυγή «Build scheduled during frame» όταν η ενημέρωση Riverpod γίνεται
  /// ενώ κλείνει overlay (π.χ. PopupMenuButton μετά την επιλογή ταξινόμησης).
  void _deferProviderUpdate(VoidCallback fn) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      fn();
    });
  }

  Widget _statusChipLabel(
    TaskStatus status,
    AsyncValue<Map<TaskStatus, int>> countsAsync,
    TaskFilter filter,
  ) {
    final count = countsAsync.value?[status];
    var showCount =
        count != null &&
        count > 0 &&
        !countsAsync.isLoading &&
        !countsAsync.hasError;
    // Μεγάλα πλήθη «ολοκληρωμένων» μόνο όταν το chip είναι ενεργό ή «Εμφάνιση όλων».
    if (status == TaskStatus.closed &&
        !filter.statuses.contains(TaskStatus.closed) &&
        !filter.allFiltersOff) {
      showCount = false;
    }
    if (!showCount) {
      return Text(switch (status) {
        TaskStatus.open => 'Ανοιχτές',
        TaskStatus.snoozed => 'Αναβολές',
        TaskStatus.closed => 'Ολοκληρωμένες',
      });
    }
    return Text('${status.displayLabelEl} ($count)');
  }

  String _getSortOptionLabel(TaskSortOption option) {
    switch (option) {
      case TaskSortOption.createdAt:
        return 'Δημιουργία';
      case TaskSortOption.dueAt:
        return 'Λήξη';
      case TaskSortOption.priority:
        return 'Προτεραιότητα';
      case TaskSortOption.department:
        return 'Τμήμα';
      case TaskSortOption.user:
        return 'Χρήστης';
      case TaskSortOption.equipment:
        return 'Εξοπλισμός';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(taskFilterProvider);
    final countsAsync = ref.watch(taskStatusCountsProvider);
    final theme = Theme.of(context);
    final hasDateRange = filter.startDate != null || filter.endDate != null;
    final allFiltersOff = filter.allFiltersOff;
    String dateRangeLabel = '';
    if (filter.startDate != null && filter.endDate != null) {
      dateRangeLabel =
          '${DateFormat('dd/MM').format(filter.startDate!)} – ${DateFormat('dd/MM').format(filter.endDate!)}';
    } else if (filter.startDate != null) {
      dateRangeLabel = 'από ${DateFormat('dd/MM').format(filter.startDate!)}';
    } else if (filter.endDate != null) {
      dateRangeLabel = 'έως ${DateFormat('dd/MM').format(filter.endDate!)}';
    }

    return Material(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Αναζήτηση τίτλου / περιγραφής',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Καθαρισμός αναζήτησης',
                              icon: const Icon(Icons.clear),
                              onPressed: _clearSearch,
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _pickDateRange,
                  tooltip: 'Εύρος ημερομηνιών',
                  icon: const Icon(Icons.date_range),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      backgroundColor: Colors.transparent,
                      constraints: const BoxConstraints(maxWidth: 1200),
                      builder: (_) => const FractionallySizedBox(
                        heightFactor: 0.96,
                        widthFactor: 1,
                        child: TaskAnalyticsBottomSheet(),
                      ),
                    );
                  },
                  tooltip: 'Στατιστικά εκκρεμοτήτων',
                  icon: const Icon(Icons.analytics_outlined),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilterChip(
                  label: _statusChipLabel(TaskStatus.open, countsAsync, filter),
                  selected: filter.statuses.contains(TaskStatus.open),
                  onSelected: (_) => _toggleStatus(TaskStatus.open),
                ),
                FilterChip(
                  label: _statusChipLabel(
                    TaskStatus.snoozed,
                    countsAsync,
                    filter,
                  ),
                  selected: filter.statuses.contains(TaskStatus.snoozed),
                  onSelected: (_) => _toggleStatus(TaskStatus.snoozed),
                ),
                FilterChip(
                  label: _statusChipLabel(
                    TaskStatus.closed,
                    countsAsync,
                    filter,
                  ),
                  selected: filter.statuses.contains(TaskStatus.closed),
                  onSelected: (_) => _toggleStatus(TaskStatus.closed),
                ),
                if (allFiltersOff)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Text(
                      'Εμφάνιση Όλων',
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                  ),
                if (hasDateRange) ...[
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.calendar_today, size: 18),
                    label: Text(dateRangeLabel),
                    onPressed: _pickDateRange,
                  ),
                  ActionChip(
                    label: const Text('Καθαρισμός ημερομηνιών'),
                    onPressed: _clearDateRange,
                  ),
                ],
                const SizedBox(width: 8),
                PopupMenuButton<TaskSortOption>(
                  tooltip: 'Ταξινόμηση',
                  onSelected: (value) {
                    _deferProviderUpdate(() {
                      ref
                          .read(taskFilterProvider.notifier)
                          .update((s) => s.copyWith(sortBy: value));
                    });
                  },
                  itemBuilder: (context) => TaskSortOption.values
                      .map(
                        (o) => PopupMenuItem<TaskSortOption>(
                          value: o,
                          child: Text(_getSortOptionLabel(o)),
                        ),
                      )
                      .toList(),
                  child: Chip(
                    avatar: const Icon(Icons.sort, size: 18),
                    label: Text(_getSortOptionLabel(filter.sortBy)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                IconButton.filledTonal(
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  tooltip: filter.sortAscending
                      ? 'Αύξουσα ταξινόμηση'
                      : 'Φθίνουσα ταξινόμηση',
                  onPressed: () {
                    _deferProviderUpdate(() {
                      ref
                          .read(taskFilterProvider.notifier)
                          .update(
                            (s) => s.copyWith(sortAscending: !s.sortAscending),
                          );
                    });
                  },
                  icon: Icon(
                    filter.sortAscending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 20,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
