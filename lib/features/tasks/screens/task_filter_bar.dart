import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../providers/tasks_provider.dart';

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
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      ref.read(taskFilterProvider.notifier).update((s) => s.copyWith(searchQuery: value.trim()));
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
    final initialStart = filter.startDate ?? now;
    final initialEnd = filter.endDate ?? now.add(const Duration(days: 7));
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (!mounted || range == null) return;
    ref.read(taskFilterProvider.notifier).update((s) => s.copyWith(
          startDate: range.start,
          endDate: range.end,
        ));
  }

  void _clearDateRange() {
    ref.read(taskFilterProvider.notifier).update((s) => s.copyWith(clearDateRange: true));
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(taskFilterProvider);
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
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilterChip(
                  label: const Text('Ανοιχτές'),
                  selected: filter.statuses.contains(TaskStatus.open),
                  onSelected: (_) => _toggleStatus(TaskStatus.open),
                ),
                FilterChip(
                  label: const Text('Αναβολές'),
                  selected: filter.statuses.contains(TaskStatus.snoozed),
                  onSelected: (_) => _toggleStatus(TaskStatus.snoozed),
                ),
                FilterChip(
                  label: const Text('Ολοκληρωμένες'),
                  selected: filter.statuses.contains(TaskStatus.closed),
                  onSelected: (_) => _toggleStatus(TaskStatus.closed),
                ),
                if (allFiltersOff)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Text(
                      'Εμφάνιση Όλων',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}
