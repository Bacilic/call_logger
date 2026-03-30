import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/nexus_calendar_picker.dart';
import '../providers/history_provider.dart';

/// Επίπεδο μεγέθυνσης πίνακα ιστορικού (0.5–2.0).
final historyTableZoomProvider =
    NotifierProvider.autoDispose<HistoryTableZoomNotifier, double>(
  HistoryTableZoomNotifier.new,
);

class HistoryTableZoomNotifier extends Notifier<double> {
  @override
  double build() => 1.0;

  void zoomOut() {
    state = (state - 0.1).clamp(0.5, 2.0);
  }

  void zoomIn() {
    state = (state + 0.1).clamp(0.5, 2.0);
  }

  void reset() {
    state = 1.0;
  }
}

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
    final range = await showNexusDateRangePickerDialog(
      context,
      initialValue: DateTimeRange(start: initialStart, end: initialEnd),
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
    final tableZoom = ref.watch(historyTableZoomProvider);

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
                            hintText: 'Αναζήτηση (Σε όλα τα πεδία, εκτός από ώρα και διάρκεια)',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _searchController,
                              builder: (context, value, _) {
                                if (value.text.isEmpty) return const SizedBox.shrink();
                                return IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    _debounceTimer?.cancel();
                                    _searchController.clear();
                                    ref.read(historyFilterProvider.notifier).update(
                                          (s) => s.copyWith(keyword: ''),
                                        );
                                  },
                                  tooltip: 'Καθαρισμός αναζήτησης',
                                );
                              },
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Μέγεθος πίνακα',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(tableZoom * 100).round()}%',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Σμίκρυνση',
                        icon: const Icon(Icons.zoom_out),
                        onPressed: () =>
                            ref.read(historyTableZoomProvider.notifier).zoomOut(),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(historyTableZoomProvider.notifier).reset(),
                        child: const Text('100%'),
                      ),
                      IconButton(
                        tooltip: 'Μεγέθυνση',
                        icon: const Icon(Icons.zoom_in),
                        onPressed: () =>
                            ref.read(historyTableZoomProvider.notifier).zoomIn(),
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
                      Expanded(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            err.toString(),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
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

/// Πίνακας γραμμών ιστορικού (ημ/νία & ώρα, καλούντας, τηλέφωνο, τμήμα, εξοπλισμός, σημειώσεις, διάρκεια).
class _HistoryDataTable extends ConsumerStatefulWidget {
  const _HistoryDataTable({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  ConsumerState<_HistoryDataTable> createState() => _HistoryDataTableState();
}

class _HistoryDataTableState extends ConsumerState<_HistoryDataTable> {
  late final ScrollController _horizontalScrollController;
  late final ScrollController _verticalScrollController;
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _horizontalScrollController = ScrollController();
    _verticalScrollController = ScrollController();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

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

  /// Τιμή για σύγκριση ταξινόμησης ανά ευρετήριο στήλης (0..6).
  Comparable<Object> _valueForSort(Map<String, dynamic> row, int columnIndex) {
    switch (columnIndex) {
      case 0:
        final d = _str(row['date']);
        final t = _str(row['time']);
        return '$d $t'.trim();
      case 1:
        return _userDisplay(row);
      case 2:
        return row['user_phone']?.toString().trim() ?? '';
      case 3:
        return _str(row['user_department']);
      case 4:
        return _str(row['equipment_code']);
      case 5:
        return _str(row['issue']);
      case 6:
        final dur = row['duration'];
        if (dur == null) return -1;
        return dur is int ? dur : int.tryParse(dur?.toString() ?? '') ?? -1;
      default:
        return '';
    }
  }

  List<Map<String, dynamic>> _sortedRows(
    List<Map<String, dynamic>> rows,
    int columnIndex,
    bool ascending,
  ) {
    final list = List<Map<String, dynamic>>.from(rows);
    list.sort((a, b) {
      final va = _valueForSort(a, columnIndex);
      final vb = _valueForSort(b, columnIndex);
      final c = va.compareTo(vb);
      return ascending ? c : -c;
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zoomLevel = ref.watch(historyTableZoomProvider);
    final rowsToShow = _sortColumnIndex != null
        ? _sortedRows(widget.rows, _sortColumnIndex!, _sortAscending)
        : widget.rows;

    return Scrollbar(
      controller: _horizontalScrollController,
      thumbVisibility: true,
      trackVisibility: true,
      child: SingleChildScrollView(
        controller: _horizontalScrollController,
        scrollDirection: Axis.horizontal,
        child: Scrollbar(
          controller: _verticalScrollController,
          thumbVisibility: true,
          trackVisibility: true,
          child: SingleChildScrollView(
            controller: _verticalScrollController,
            scrollDirection: Axis.vertical,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(zoomLevel),
              ),
              child: IconTheme(
                data: IconThemeData(size: 24.0 * zoomLevel),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  ),
                  dataRowMinHeight: 48.0 * zoomLevel,
                  dataRowMaxHeight: 48.0 * zoomLevel,
                  headingRowHeight: 56.0 * zoomLevel,
                  columnSpacing: 56.0 * zoomLevel,
                  horizontalMargin: 24.0 * zoomLevel,
                  sortColumnIndex: _sortColumnIndex,
                  sortAscending: _sortAscending,
                columns: [
                  DataColumn(
                    label: const Text('Ημ/νία & Ώρα'),
                    onSort: (_, asc) => setState(() {
                      _sortColumnIndex = 0;
                      _sortAscending = asc;
                    }),
                  ),
                  DataColumn(
                    label: const Text('Καλούντας'),
                    onSort: (_, asc) => setState(() {
                      _sortColumnIndex = 1;
                      _sortAscending = asc;
                    }),
                  ),
                  DataColumn(
                    label: const Text('Τηλέφωνο'),
                    onSort: (_, asc) => setState(() {
                      _sortColumnIndex = 2;
                      _sortAscending = asc;
                    }),
                  ),
                  DataColumn(
                    label: const Text('Τμήμα'),
                    onSort: (_, asc) => setState(() {
                      _sortColumnIndex = 3;
                      _sortAscending = asc;
                    }),
                  ),
                  DataColumn(
                    label: const Text('Εξοπλισμός'),
                    onSort: (_, asc) => setState(() {
                      _sortColumnIndex = 4;
                      _sortAscending = asc;
                    }),
                  ),
                  DataColumn(
                    label: const Text('Σημειώσεις'),
                    onSort: (_, asc) => setState(() {
                      _sortColumnIndex = 5;
                      _sortAscending = asc;
                    }),
                  ),
                  DataColumn(
                    label: const Text('Διάρκεια'),
                    onSort: (_, asc) => setState(() {
                      _sortColumnIndex = 6;
                      _sortAscending = asc;
                    }),
                  ),
                ],
                rows: rowsToShow.map((row) {
                  final date = _str(row['date']);
                  final time = _str(row['time']);
                  final dateTime = '$date $time'.trim();
                  final user = _userDisplay(row);
                  final phone = row['user_phone']?.toString().trim() ?? '—';
                  final department = _str(row['user_department']);
                  final equipment = _str(row['equipment_code']);
                  final issue = _str(row['issue']);
                  final durationStr = _formatDuration(row['duration']);
                  return DataRow(
                    cells: [
                      DataCell(Text(dateTime.isEmpty ? '—' : dateTime)),
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(user, overflow: TextOverflow.ellipsis),
                      )),
                      DataCell(Text(phone.isEmpty ? '—' : phone)),
                      DataCell(Text(department.isEmpty ? '—' : department)),
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
            ),
          ),
        ),
      ),
    );
  }
}
