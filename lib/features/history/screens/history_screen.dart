import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/history_provider.dart';

/// Οθόνη Ιστορικού Κλήσεων: φίλτρα (keyword, ημερομηνίες, κατηγορία) και πίνακας αποτελεσμάτων.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  static const Duration _debounceDuration = Duration(milliseconds: 350);
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    final filter = ref.read(historyFilterProvider);
    _searchController.text = filter.keyword;
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
      ref.read(historyFilterProvider.notifier).update(
            (s) => s.copyWith(keyword: value.trim()),
          );
    });
  }

  Future<void> _pickDateRange() async {
    final filter = ref.read(historyFilterProvider);
    final now = DateTime.now();
    final initialStart = filter.dateFrom ?? now.subtract(const Duration(days: 30));
    final initialEnd = filter.dateTo ?? now;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (!mounted || range == null) return;
    ref.read(historyFilterProvider.notifier).update(
          (s) => s.copyWith(dateFrom: range.start, dateTo: range.end),
        );
  }

  void _clearDateRange() {
    ref.read(historyFilterProvider.notifier).update(
          (s) => s.copyWith(clearDateRange: true),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = ref.watch(historyFilterProvider);
    final asyncCalls = ref.watch(historyCallsProvider);
    final asyncCategories = ref.watch(historyCategoriesProvider);

    String dateRangeLabel = '';
    if (filter.dateFrom != null && filter.dateTo != null) {
      dateRangeLabel =
          '${DateFormat('dd/MM/yyyy').format(filter.dateFrom!)} – ${DateFormat('dd/MM/yyyy').format(filter.dateTo!)}';
    } else if (filter.dateFrom != null) {
      dateRangeLabel = 'από ${DateFormat('dd/MM/yyyy').format(filter.dateFrom!)}';
    } else if (filter.dateTo != null) {
      dateRangeLabel = 'έως ${DateFormat('dd/MM/yyyy').format(filter.dateTo!)}';
    }
    final hasDateRange = filter.dateFrom != null || filter.dateTo != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ιστορικό Κλήσεων'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ——— Φίλτρα ———
          Material(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText: 'Αναζήτηση (θέμα, λύση, καλούντας, εξοπλισμός)',
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
                      const SizedBox(width: 12),
                      IconButton.filled(
                        onPressed: _pickDateRange,
                        tooltip: 'Εύρος ημερομηνιών',
                        icon: const Icon(Icons.date_range),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: asyncCategories.when(
                          data: (categories) {
                            final options = <String?>[null, ...categories];
                            final current = filter.category;
                            return DropdownButtonFormField<String?>(
                              initialValue: options.contains(current) ? current : null,
                              decoration: InputDecoration(
                                labelText: 'Κατηγορία',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              items: options.map((c) {
                                return DropdownMenuItem<String?>(
                                  value: c,
                                  child: Text(c ?? '— Όλες —'),
                                );
                              }).toList(),
                              onChanged: (v) {
                                ref.read(historyFilterProvider.notifier).update(
                                      (s) => s.copyWith(
                                            category: v,
                                            clearCategory: v == null,
                                          ),
                                    );
                              },
                            );
                          },
                          loading: () => const SizedBox(
                            height: 48,
                            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                          ),
                          error: (_, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
                  if (hasDateRange) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
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
                    ),
                  ],
                ],
              ),
            ),
          ),
          // ——— Πίνακας αποτελεσμάτων ———
          Expanded(
            child: asyncCalls.when(
              loading: () => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Φόρτωση ιστορικού...'),
                  ],
                ),
              ),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                      const SizedBox(height: 16),
                      Text(
                        err.toString(),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => ref.invalidate(historyCallsProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Επανάληψη'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return Center(
                    child: Text(
                      'Δεν βρέθηκαν κλήσεις με τα τρέχοντα κριτήρια.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return _HistoryDataTable(rows: rows);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Πίνακας γραμμών ιστορικού (ημερομηνία, χρήστης, εξοπλισμός, θέμα, διάρκεια).
class _HistoryDataTable extends StatelessWidget {
  const _HistoryDataTable({required this.rows});

  final List<Map<String, dynamic>> rows;

  String _userDisplay(Map<String, dynamic> row) {
    final first = row['user_first_name'] as String? ?? '';
    final last = row['user_last_name'] as String? ?? '';
    final combined = '$first $last'.trim();
    return combined.isEmpty ? '—' : combined;
  }

  String _str(dynamic v) => v?.toString().trim() ?? '';

  /// Μορφοποίηση διάρκειας (δευτερόλεπτα) ως "λλ:δδ". Null → "—".
  String _formatDuration(dynamic duration) {
    if (duration == null) return '—';
    final sec = duration is int ? duration : int.tryParse(duration?.toString() ?? '');
    if (sec == null) return '—';
    final minutes = sec ~/ 60;
    final seconds = sec % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          columns: const [
            DataColumn(label: Text('Ημερομηνία')),
            DataColumn(label: Text('Ώρα')),
            DataColumn(label: Text('Καλούντας')),
            DataColumn(label: Text('Εξοπλισμός')),
            DataColumn(label: Text('Θέμα')),
            DataColumn(label: Text('Διάρκεια')),
          ],
          rows: rows.map((row) {
            final date = _str(row['date']);
            final time = _str(row['time']);
            final user = _userDisplay(row);
            final equipment = _str(row['equipment_code']);
            final issue = _str(row['issue']);
            final durationStr = _formatDuration(row['duration']);
            return DataRow(
              cells: [
                DataCell(Text(date)),
                DataCell(Text(time)),
                DataCell(ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(user, overflow: TextOverflow.ellipsis),
                )),
                DataCell(Text(equipment)),
                DataCell(ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(issue, overflow: TextOverflow.ellipsis),
                )),
                DataCell(Text(durationStr)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
