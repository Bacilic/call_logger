import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/history_audit_immersive_provider.dart';
import '../../../core/providers/lexicon_full_mode_provider.dart';
import '../../../core/providers/shell_navigation_intent_provider.dart';
import '../../../core/widgets/calendar_range_picker.dart';
import '../../../core/widgets/ellipsis_tooltip_text.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/widgets/main_nav_destination.dart';
import '../../../core/utils/history_entity_display_utils.dart';
import '../providers/history_application_audit_view_provider.dart';
import '../providers/history_provider.dart';
import '../widgets/call_delete_dialog.dart';
import '../widgets/call_edit_dialog.dart';
import '../widgets/history_deleted_entity_text.dart';
import '../widgets/application_audit_tab.dart';
import 'dashboard_screen.dart';

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
      ref
          .read(historyFilterProvider.notifier)
          .update((s) => s.copyWith(keyword: value.trim()));
    });
  }

  Future<void> _pickDateRange() async {
    final filter = ref.read(historyFilterProvider);
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
      _clearDateRange();
      return;
    }
    final range = result.range;
    if (range == null) return;
    ref
        .read(historyFilterProvider.notifier)
        .update((s) => s.copyWith(dateFrom: range.start, dateTo: range.end));
  }

  void _clearDateRange() {
    ref
        .read(historyFilterProvider.notifier)
        .update((s) => s.copyWith(clearDateRange: true));
  }

  void _toggleApplicationAuditView() {
    final next = !ref.read(historyApplicationAuditViewProvider);
    ref.read(historyApplicationAuditViewProvider.notifier).set(next);
    if (next) {
      ref.read(historyAuditImmersiveProvider.notifier).setTrue();
      ref.read(lexiconFullModeProvider.notifier).setFalse();
    } else {
      ref.read(historyAuditImmersiveProvider.notifier).setFalse();
    }
  }

  void _navigateFromImmersiveHistory(MainNavDestination destination) {
    ref.read(shellNavigationIntentProvider.notifier).setPending(destination);
    ref.read(historyAuditImmersiveProvider.notifier).setFalse();
    ref.read(historyApplicationAuditViewProvider.notifier).setFalse();
  }

  static Widget _navMenuRow(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    );
  }

  Widget _immersiveNavigationMenuButton() {
    final showDb = ref
        .watch(showDatabaseNavProvider)
        .maybeWhen(data: (v) => v, orElse: () => true);
    return PopupMenuButton<MainNavDestination>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tooltip: 'Μετάβαση σε άλλη οθόνη',
      icon: const Icon(Icons.menu),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      onSelected: _navigateFromImmersiveHistory,
      itemBuilder: (context) {
        return <PopupMenuEntry<MainNavDestination>>[
          PopupMenuItem(
            value: MainNavDestination.calls,
            child: _navMenuRow(Icons.phone_in_talk, 'Κλήσεις'),
          ),
          PopupMenuItem(
            value: MainNavDestination.tasks,
            child: _navMenuRow(Icons.task_alt, 'Εκκρεμότητες'),
          ),
          PopupMenuItem(
            value: MainNavDestination.directory,
            child: _navMenuRow(Icons.contacts, 'Κατάλογος'),
          ),
          PopupMenuItem(
            value: MainNavDestination.history,
            child: _navMenuRow(Icons.history, 'Ιστορικό (κλήσεις)'),
          ),
          if (showDb)
            PopupMenuItem(
              value: MainNavDestination.database,
              child: _navMenuRow(Icons.storage, 'Βάση Δεδομένων'),
            ),
        ];
      },
    );
  }

  Widget _auditToggleButton({
    required String tooltip,
    required bool backToCallHistory,
  }) {
    final asset = backToCallHistory
        ? 'assets/back_to_call_history.png'
        : 'assets/audit_log_icon.png';
    final fallbackIcon = backToCallHistory
        ? Icons.history
        : Icons.fact_check_outlined;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        onPressed: _toggleApplicationAuditView,
        icon: Image.asset(
          asset,
          width: 24,
          height: 24,
          errorBuilder: (context, error, stackTrace) =>
              Icon(fallbackIcon, size: 24),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<HistoryFilterModel>(historyFilterProvider, (_, _) {
      ref.read(historySelectedCallIdsProvider.notifier).clear();
    });
    final theme = Theme.of(context);
    final filter = ref.watch(historyFilterProvider);
    final asyncCalls = ref.watch(historyCallsProvider);
    final asyncCallCount = ref.watch(historyCategoryDateCallCountProvider);
    final asyncCategories = ref.watch(historyCategoriesProvider);
    final tableZoom = ref.watch(historyTableZoomProvider);
    final filtersEnabled = asyncCalls.maybeWhen(
      data: (rows) => rows.isNotEmpty,
      orElse: () => false,
    );
    final databaseDisplayName = ref.watch(historyDatabaseDisplayNameProvider);
    final appAudit = ref.watch(historyApplicationAuditViewProvider);
    final immersive = ref.watch(historyAuditImmersiveProvider);
    final selectedCallIds = ref.watch(historySelectedCallIdsProvider);

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

    if (appAudit) {
      return Scaffold(
        appBar: AppBar(
          leading: immersive ? _immersiveNavigationMenuButton() : null,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  'Ιστορικό Εφαρμογής',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _auditToggleButton(
                tooltip: 'Εναλλαγή σε ιστορικό κλήσεων',
                backToCallHistory: true,
              ),
            ],
          ),
        ),
        body: const ApplicationAuditTab(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Expanded(
              child: Text('Ιστορικό Κλήσεων', overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              tooltip: 'Στατιστικά κλήσεων / Αναφορές',
              onPressed: filtersEnabled
                  ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DashboardScreen(),
                        ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.analytics_outlined),
            ),
            _auditToggleButton(
              tooltip: 'Εναλλαγή σε ιστορικό εφαρμογής (audit)',
              backToCallHistory: false,
            ),
          ],
        ),
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 980;
                      final keywordField = TextField(
                        controller: _searchController,
                        enabled: filtersEnabled,
                        onChanged: filtersEnabled ? _onSearchChanged : null,
                        decoration: InputDecoration(
                          hintText: compact
                              ? 'Αναζήτηση ιστορικού'
                              : 'Αναζήτηση (Σε όλα τα πεδία, εκτός από ώρα και διάρκεια)',
                          hintMaxLines: 1,
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _searchController,
                            builder: (context, value, _) {
                              if (value.text.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: filtersEnabled
                                    ? () {
                                        _debounceTimer?.cancel();
                                        _searchController.clear();
                                        ref
                                            .read(
                                              historyFilterProvider.notifier,
                                            )
                                            .update(
                                              (s) => s.copyWith(keyword: ''),
                                            );
                                      }
                                    : null,
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
                      );
                      final categoryDropdown = asyncCategories.when(
                        data: (categories) {
                          final options = <String?>[null, ...categories];
                          final current = filter.category;
                          return DropdownButtonFormField<String?>(
                            initialValue: options.contains(current)
                                ? current
                                : null,
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
                            onChanged: filtersEnabled
                                ? (v) {
                                    ref
                                        .read(historyFilterProvider.notifier)
                                        .update(
                                          (s) => s.copyWith(
                                            category: v,
                                            clearCategory: v == null,
                                          ),
                                        );
                                  }
                                : null,
                          );
                        },
                        loading: () => const SizedBox(
                          height: 48,
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        error: (_, _) => const SizedBox.shrink(),
                      );
                      final dateButton = IconButton.filled(
                        onPressed: filtersEnabled ? _pickDateRange : null,
                        tooltip: 'Εύρος ημερομηνιών',
                        icon: const Icon(Icons.date_range),
                      );

                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(child: keywordField),
                                const SizedBox(width: 8),
                                dateButton,
                              ],
                            ),
                            const SizedBox(height: 8),
                            categoryDropdown,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: keywordField),
                          const SizedBox(width: 12),
                          dateButton,
                          const SizedBox(width: 8),
                          Expanded(child: categoryDropdown),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      asyncCallCount.when(
                        data: (count) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Κλήσεις',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$count',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        loading: () => SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Σμίκρυνση',
                        icon: const Icon(Icons.zoom_out),
                        onPressed: filtersEnabled
                            ? () => ref
                                .read(historyTableZoomProvider.notifier)
                                .zoomOut()
                            : null,
                      ),
                      IconButton(
                        tooltip: 'Επαναφορά μεγέθους (100%)',
                        icon: const Icon(Icons.restart_alt),
                        onPressed: filtersEnabled
                            ? () => ref
                                .read(historyTableZoomProvider.notifier)
                                .reset()
                            : null,
                      ),
                      IconButton(
                        tooltip: 'Μεγέθυνση',
                        icon: const Icon(Icons.zoom_in),
                        onPressed: filtersEnabled
                            ? () => ref
                                .read(historyTableZoomProvider.notifier)
                                .zoomIn()
                            : null,
                      ),
                      const SizedBox(width: 8),
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
                          onPressed: filtersEnabled ? _pickDateRange : null,
                        ),
                        ActionChip(
                          label: const Text('Καθαρισμός ημερομηνιών'),
                          onPressed: filtersEnabled ? _clearDateRange : null,
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
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      databaseDisplayName.when(
                        loading: () => Text(
                          'Υπάρχει σφάλμα στη βάση δεδομένων: …',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        error: (_, _) => Text(
                          'Υπάρχει σφάλμα στη βάση δεδομένων: —',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        data: (dbName) => Text(
                          'Υπάρχει σφάλμα στη βάση δεδομένων: $dbName',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.error,
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
                  final emptyMessage = filter.hasActiveFilters
                      ? 'Δεν βρέθηκαν κλήσεις με τα τρέχοντα κριτήρια.'
                      : 'Δεν υπάρχουν εγγραφές';
                  return Center(
                    child: Text(
                      emptyMessage,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                final visibleRowIds = rows
                    .map((r) => r['id'])
                    .whereType<int>()
                    .toSet();
                final visibleSelectedIds = selectedCallIds
                    .where(visibleRowIds.contains)
                    .toSet();

                if (visibleSelectedIds.length != selectedCallIds.length) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    ref
                        .read(historySelectedCallIdsProvider.notifier)
                        .setAll(visibleSelectedIds);
                  });
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (visibleSelectedIds.isNotEmpty)
                      Container(
                        color: theme.colorScheme.secondaryContainer.withValues(
                          alpha: 0.35,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Επιλεγμένες κλήσεις: ${visibleSelectedIds.length}',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(width: 12),
                            TextButton(
                              onPressed: () {
                                ref
                                    .read(
                                      historySelectedCallIdsProvider.notifier,
                                    )
                                    .clear();
                              },
                              child: const Text('Καθαρισμός'),
                            ),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: () async {
                                await showCallBulkDeleteDialog(
                                  context,
                                  callIds: visibleSelectedIds.toList(),
                                );
                                if (!mounted) return;
                                ref
                                    .read(
                                      historySelectedCallIdsProvider.notifier,
                                    )
                                    .clear();
                              },
                              icon: const Icon(Icons.delete_sweep_outlined),
                              label: const Text('Μαζική διαγραφή'),
                            ),
                          ],
                        ),
                      ),
                    Expanded(child: _HistoryDataTable(rows: rows)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Πίνακας γραμμών ιστορικού (ημ/νία & ώρα, καλούντας, τηλέφωνο, τμήμα, εξοπλισμός, κατηγορία, σημειώσεις, διάρκεια).
class _HistoryDataTable extends ConsumerStatefulWidget {
  const _HistoryDataTable({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  ConsumerState<_HistoryDataTable> createState() => _HistoryDataTableState();
}

class _HistoryDataTableState extends ConsumerState<_HistoryDataTable> {
  /// Βασικά πλάτη στηλών (checkbox, ημ/νία, καλούντας, τηλέφωνο, τμήμα,
  /// εξοπλισμός, κατηγορία, σημειώσεις, διάρκεια, ενέργειες).
  static const List<double> _baseColumnWidths = [
    50,
    130,
    160,
    110,
    140,
    130,
    140,
    220,
    90,
    110,
  ];

  static const List<String> _dataColumnLabels = [
    'Ημ/νία & Ώρα',
    'Καλούντας',
    'Τηλέφωνο',
    'Τμήμα',
    'Εξοπλισμός',
    'Κατηγορία',
    'Σημειώσεις',
    'Διάρκεια',
  ];

  late final ScrollController _horizontalScrollController;
  late final ScrollController _verticalScrollController;
  int? _sortColumnIndex;
  bool _sortAscending = true;
  int? _hoveredRowIndex;

  int? _rowId(Map<String, dynamic> row) => row['id'] as int?;

  void _toggleSelection(int callId, bool selected) {
    final current = ref.read(historySelectedCallIdsProvider);
    final next = <int>{...current};
    if (selected) {
      next.add(callId);
    } else {
      next.remove(callId);
    }
    ref.read(historySelectedCallIdsProvider.notifier).setAll(next);
  }

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

  static final DateFormat _callDateParse = DateFormat('yyyy-MM-dd');
  static final DateFormat _callDateTimeParse = DateFormat('yyyy-MM-dd HH:mm');
  static final DateFormat _callDateTimeDisplay = DateFormat('dd-MM-yyyy HH:mm');

  /// Ανάλυση ημ/νίας & ώρας όπως αποθηκεύονται στη βάση (date: yyyy-MM-dd, time: HH:mm).
  DateTime? _parseCallDateTime(Map<String, dynamic> row) {
    final d = _str(row['date']);
    final t = _str(row['time']);
    if (d.isEmpty) return null;
    try {
      if (t.isEmpty) {
        return _callDateParse.parseStrict(d);
      }
      return _callDateTimeParse.parseStrict('$d $t');
    } catch (_) {
      return null;
    }
  }

  /// Εμφάνιση ως "ηη-μμ-εεεε ωω:λλ" (dd-MM-yyyy HH:mm).
  String _formatCallDateTimeDisplay(Map<String, dynamic> row) {
    final dt = _parseCallDateTime(row);
    if (dt != null) {
      return _callDateTimeDisplay.format(dt);
    }
    final raw = '${_str(row['date'])} ${_str(row['time'])}'.trim();
    return raw.isEmpty ? '—' : raw;
  }

  /// Μορφοποίηση διάρκειας (δευτερόλεπτα) ως "λλ:δδ". Null → "—".
  String _formatDuration(dynamic duration) {
    if (duration == null) return '—';
    final sec = duration is int
        ? duration
        : int.tryParse(duration?.toString() ?? '');
    if (sec == null) return '—';
    final minutes = sec ~/ 60;
    final seconds = sec % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Τιμή για σύγκριση ταξινόμησης ανά ευρετήριο στήλης (0..7).
  Comparable<Object> _valueForSort(Map<String, dynamic> row, int columnIndex) {
    switch (columnIndex) {
      case 0:
        final dt = _parseCallDateTime(row);
        return dt?.millisecondsSinceEpoch ?? -1;
      case 1:
        return _userDisplay(row);
      case 2:
        return row['user_phone']?.toString().trim() ?? '';
      case 3:
        return _str(row['user_department']);
      case 4:
        return _str(row['equipment_code']);
      case 5:
        return _str(row['category']);
      case 6:
        return _str(row['issue']);
      case 7:
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

  List<double> _scaledColumnWidths(double zoomLevel) =>
      _baseColumnWidths.map((w) => w * zoomLevel).toList();

  double _totalTableWidth(double zoomLevel) =>
      _scaledColumnWidths(zoomLevel).fold(0.0, (a, b) => a + b);

  void _onSortHeaderTap(int columnIndex) {
    setState(() {
      if (_sortColumnIndex == columnIndex) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumnIndex = columnIndex;
        _sortAscending = true;
      }
    });
  }

  Widget _headerCell({
    required double width,
    required double horizontalPadding,
    required Widget child,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: child,
    );
    if (onTap == null) {
      return SizedBox(width: width, child: content);
    }
    return SizedBox(
      width: width,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          hoverColor: theme.colorScheme.onSurface.withValues(alpha: 0.04),
          child: content,
        ),
      ),
    );
  }

  Widget _buildHeaderRow({
    required ThemeData theme,
    required double zoomLevel,
    required List<double> columnWidths,
    required double headingRowHeight,
    required double horizontalPadding,
    required bool allVisibleSelected,
    required Set<int> visibleIds,
    required Set<int> selectedCallIds,
  }) {
    final headingStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    );

    Widget sortableLabel(int columnIndex, String label) {
      final isActive = _sortColumnIndex == columnIndex;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              style: headingStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isActive) ...[
            const SizedBox(width: 4),
            Icon(
              _sortAscending
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              size: 16 * zoomLevel,
              color: theme.colorScheme.primary,
            ),
          ],
        ],
      );
    }

    final cells = <Widget>[
      _headerCell(
        width: columnWidths[0],
        horizontalPadding: horizontalPadding,
        child: Transform.scale(
          scale: zoomLevel.clamp(0.85, 1.4),
          child: Checkbox(
            value: allVisibleSelected,
            onChanged: (v) {
              final target = v == true;
              final next = <int>{...selectedCallIds};
              if (target) {
                next.addAll(visibleIds);
              } else {
                next.removeAll(visibleIds);
              }
              ref.read(historySelectedCallIdsProvider.notifier).setAll(next);
            },
          ),
        ),
      ),
      for (var i = 0; i < _dataColumnLabels.length; i++)
        _headerCell(
          width: columnWidths[i + 1],
          horizontalPadding: horizontalPadding,
          onTap: () => _onSortHeaderTap(i + 1),
          child: sortableLabel(i + 1, _dataColumnLabels[i]),
        ),
      _headerCell(
        width: columnWidths[9],
        horizontalPadding: horizontalPadding,
        child: Text('Ενέργειες', style: headingStyle),
      ),
    ];

    return Container(
      height: headingRowHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.5,
        ),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.6),
          ),
        ),
      ),
      child: Row(children: cells),
    );
  }

  Widget _dataCell({
    required double width,
    required double horizontalPadding,
    required Widget child,
  }) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }

  Widget _buildDataRow({
    required Map<String, dynamic> row,
    required int rowIndex,
    required ThemeData theme,
    required double zoomLevel,
    required List<double> columnWidths,
    required double dataRowHeight,
    required double horizontalPadding,
    required Set<int> selectedCallIds,
  }) {
    final callId = _rowId(row);
    final isSelected = callId != null && selectedCallIds.contains(callId);
    final isHovered = _hoveredRowIndex == rowIndex;

    Color? rowColor;
    if (isSelected) {
      rowColor = theme.colorScheme.primaryContainer.withValues(alpha: 0.35);
    } else if (isHovered) {
      rowColor = theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.45,
      );
    }

    final dateTime = _formatCallDateTimeDisplay(row);
    final user = _userDisplay(row);
    final callerDeleted = historyEntityIsDeleted(row['caller_is_deleted']);
    final phone = row['user_phone']?.toString().trim() ?? '—';
    final department = _str(row['user_department']);
    final equipment = _str(row['equipment_code']);
    final equipmentDeleted = historyEntityIsDeleted(row['equipment_is_deleted']);
    final category = _str(row['category']);
    final categoryDeleted = historyEntityIsDeleted(row['category_is_deleted']);
    final issue = _str(row['issue']);
    final durationStr = _formatDuration(row['duration']);

    final bodyStyle = theme.textTheme.bodyMedium;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredRowIndex = rowIndex),
      onExit: (_) {
        if (_hoveredRowIndex == rowIndex) {
          setState(() => _hoveredRowIndex = null);
        }
      },
      child: Container(
        height: dataRowHeight,
        decoration: BoxDecoration(
          color: rowColor,
          border: Border(
            bottom: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.35),
            ),
          ),
        ),
        child: Row(
          children: [
            _dataCell(
              width: columnWidths[0],
              horizontalPadding: horizontalPadding,
              child: Transform.scale(
                scale: zoomLevel.clamp(0.85, 1.4),
                child: Checkbox(
                  value: isSelected,
                  onChanged: callId == null
                      ? null
                      : (value) =>
                            _toggleSelection(callId, value == true),
                ),
              ),
            ),
            _dataCell(
              width: columnWidths[1],
              horizontalPadding: horizontalPadding,
              child: Text(dateTime, style: bodyStyle),
            ),
            _dataCell(
              width: columnWidths[2],
              horizontalPadding: horizontalPadding,
              child: HistoryDeletedEntityText(
                text: user,
                isDeleted: callerDeleted && user != '—',
                style: bodyStyle,
              ),
            ),
            _dataCell(
              width: columnWidths[3],
              horizontalPadding: horizontalPadding,
              child: Text(
                phone.isEmpty ? '—' : phone,
                style: bodyStyle,
              ),
            ),
            _dataCell(
              width: columnWidths[4],
              horizontalPadding: horizontalPadding,
              child: EllipsisTooltipText(
                text: department.isEmpty ? '—' : department,
                style: bodyStyle,
              ),
            ),
            _dataCell(
              width: columnWidths[5],
              horizontalPadding: horizontalPadding,
              child: HistoryDeletedEntityText(
                text: equipment.isEmpty ? '—' : equipment,
                isDeleted: equipmentDeleted && equipment.isNotEmpty,
                style: bodyStyle,
              ),
            ),
            _dataCell(
              width: columnWidths[6],
              horizontalPadding: horizontalPadding,
              child: HistoryDeletedEntityText(
                text: category.isEmpty ? '—' : category,
                isDeleted: categoryDeleted && category.isNotEmpty,
                style: bodyStyle,
              ),
            ),
            _dataCell(
              width: columnWidths[7],
              horizontalPadding: horizontalPadding,
              child: EllipsisTooltipText(
                text: issue.isEmpty ? '—' : issue,
                style: bodyStyle,
              ),
            ),
            _dataCell(
              width: columnWidths[8],
              horizontalPadding: horizontalPadding,
              child: Text(durationStr, style: bodyStyle),
            ),
            _dataCell(
              width: columnWidths[9],
              horizontalPadding: horizontalPadding,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Επεξεργασία',
                      visualDensity: VisualDensity.compact,
                      onPressed: callId == null
                          ? null
                          : () => showCallEditDialog(
                              context,
                              callId: callId,
                            ),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Διαγραφή',
                      visualDensity: VisualDensity.compact,
                      onPressed: callId == null
                          ? null
                          : () => showCallDeleteDialog(
                              context,
                              callId: callId,
                              callerId: row['caller_id'] as int?,
                              equipmentCode: _str(row['equipment_code']),
                            ),
                      icon: Icon(
                        Icons.delete_outline,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zoomLevel = ref.watch(historyTableZoomProvider);
    final selectedCallIds = ref.watch(historySelectedCallIdsProvider);
    final rowsToShow = _sortColumnIndex != null
        ? _sortedRows(widget.rows, _sortColumnIndex! - 1, _sortAscending)
        : widget.rows;
    final visibleIds = rowsToShow.map(_rowId).whereType<int>().toSet();
    final allVisibleSelected =
        visibleIds.isNotEmpty && visibleIds.every(selectedCallIds.contains);

    final columnWidths = _scaledColumnWidths(zoomLevel);
    final tableWidth = _totalTableWidth(zoomLevel);
    final headingRowHeight = 56.0 * zoomLevel;
    final dataRowHeight = 48.0 * zoomLevel;
    final horizontalPadding = 12.0 * zoomLevel;

    return Scrollbar(
      controller: _horizontalScrollController,
      thumbVisibility: true,
      trackVisibility: true,
      child: SingleChildScrollView(
        controller: _horizontalScrollController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(zoomLevel),
            ),
            child: IconTheme(
              data: IconThemeData(size: 24.0 * zoomLevel),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderRow(
                    theme: theme,
                    zoomLevel: zoomLevel,
                    columnWidths: columnWidths,
                    headingRowHeight: headingRowHeight,
                    horizontalPadding: horizontalPadding,
                    allVisibleSelected: allVisibleSelected,
                    visibleIds: visibleIds,
                    selectedCallIds: selectedCallIds,
                  ),
                  Expanded(
                    child: Scrollbar(
                      controller: _verticalScrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      child: ListView.builder(
                        controller: _verticalScrollController,
                        itemCount: rowsToShow.length,
                        itemExtent: dataRowHeight,
                        itemBuilder: (context, index) => _buildDataRow(
                          row: rowsToShow[index],
                          rowIndex: index,
                          theme: theme,
                          zoomLevel: zoomLevel,
                          columnWidths: columnWidths,
                          dataRowHeight: dataRowHeight,
                          horizontalPadding: horizontalPadding,
                          selectedCallIds: selectedCallIds,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
