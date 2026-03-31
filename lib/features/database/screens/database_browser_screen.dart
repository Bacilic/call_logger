import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/database/database_helper.dart';
import '../../../core/database/database_init_result.dart';
import '../models/database_stats.dart';
import '../providers/database_browser_stats_provider.dart';
import '../services/database_stats_service.dart';
import '../widgets/database_maintenance_panel.dart';

/// Κλειδί `app_settings` για JSON `{ "όνομα_πίνακα": zoom, ... }` (zoom 0.5–2.0).
const String _kDatabaseBrowserZoomByTableSettingsKey =
    'database_browser_preview_zoom_by_table';

/// Αποθηκευμένο επίπεδο μεγέθυνσης ανά πίνακα προεπισκόπησης (0.5–2.0· προεπιλογή 1.0).
final databaseBrowserZoomByTableProvider = NotifierProvider.autoDispose<
    DatabaseBrowserZoomByTableNotifier, Map<String, double>>(
  DatabaseBrowserZoomByTableNotifier.new,
);

class DatabaseBrowserZoomByTableNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => {};

  /// Φόρτωση από `app_settings` (καλείται κατά το άνοιγμα της οθόνης).
  Future<void> load() async {
    try {
      final raw = await DatabaseHelper.instance
          .getSetting(_kDatabaseBrowserZoomByTableSettingsKey);
      if (raw == null || raw.trim().isEmpty) {
        state = {};
        return;
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, double>{};
      for (final e in decoded.entries) {
        final z = (e.value as num?)?.toDouble();
        if (z == null) continue;
        final clamped = z.clamp(0.5, 2.0);
        if ((clamped - 1.0).abs() >= 0.001) {
          out[e.key] = clamped;
        }
      }
      state = out;
    } catch (_) {
      state = {};
    }
  }

  double zoomFor(String tableName) => state[tableName] ?? 1.0;

  Future<void> _persist() async {
    await DatabaseHelper.instance.setSetting(
      _kDatabaseBrowserZoomByTableSettingsKey,
      jsonEncode(state),
    );
  }

  Future<void> setZoomForTable(String tableName, double zoom) async {
    final z = zoom.clamp(0.5, 2.0);
    final next = Map<String, double>.from(state);
    if ((z - 1.0).abs() < 0.001) {
      next.remove(tableName);
    } else {
      next[tableName] = z;
    }
    state = next;
    try {
      await _persist();
    } catch (_) {}
  }

  Future<void> zoomOutFor(String tableName) {
    return setZoomForTable(
      tableName,
      zoomFor(tableName) - 0.1,
    );
  }

  Future<void> zoomInFor(String tableName) {
    return setZoomForTable(
      tableName,
      zoomFor(tableName) + 0.1,
    );
  }

  Future<void> resetFor(String tableName) {
    return setZoomForTable(tableName, 1.0);
  }
}

/// Αγγλικά ονόματα πινάκων → φιλικά ελληνικά για το UI.
const Map<String, String> _kTableDisplayNames = {
  'app_settings': 'Ρυθμίσεις εφαρμογής',
  'tasks': 'Εκκρεμότητες',
  'calls': 'Κλήσεις',
  'users': 'Χρήστες',
  'equipment': 'Εξοπλισμός',
  'departments': 'Τμήματα',
  'categories': 'Κατηγορίες',
  'audit_log': 'Αρχείο καταγραφής (audit)',
  'phones': 'Τηλέφωνα',
  'user_phones': 'Συσχέτιση χρήστη–τηλεφώνου',
  'department_phones': 'Συσχέτιση τμήματος–τηλεφώνου',
  'user_equipment': 'Συσχέτιση χρήστη–εξοπλισμού',
  'knowledge_base': 'Βάση γνώσεων',
  'remote_tool_args': 'Ορίσματα απομακρυσμένου εργαλείου',
  'user_dictionary': 'Προσωπικό λεξικό',
};

String _displayNameForTable(String tableName) =>
    _kTableDisplayNames[tableName] ?? tableName;

/// Σειρά πινάκων όπως η πλευρική μπάρα της εφαρμογής: Κλήσεις → Εκκρεμότητες →
/// Κατάλογος → (Ιστορικό: ίδια δεδομένα με `calls`) → ρυθμίσεις/εποπτεία.
const List<String> _kMenuTableOrder = [
  // Κλήσεις
  'calls',
  'categories',
  // Εκκρεμότητες
  'tasks',
  // Κατάλογος
  'users',
  'departments',
  'equipment',
  'phones',
  'user_phones',
  'department_phones',
  'user_equipment',
  // Βάση Δεδομένων / λοιπά
  'app_settings',
  'audit_log',
  'knowledge_base',
  'remote_tool_args',
  'user_dictionary',
];

List<String> _orderedTableNames(List<String> raw) {
  final orderMap = {
    for (var i = 0; i < _kMenuTableOrder.length; i++)
      _kMenuTableOrder[i]: i,
  };
  final copy = List<String>.from(raw);
  copy.sort((a, b) {
    final ia = orderMap[a];
    final ib = orderMap[b];
    if (ia != null && ib != null) return ia.compareTo(ib);
    if (ia != null) return -1;
    if (ib != null) return 1;
    return a.compareTo(b);
  });
  return copy;
}

/// Οθόνη Βάσης Δεδομένων: λίστα πινάκων και προεπισκόπηση σε μορφή πίνακα (Excel-like).
class DatabaseBrowserScreen extends ConsumerStatefulWidget {
  const DatabaseBrowserScreen({
    super.key,
    required this.databaseResult,
    required this.onOpenDatabaseSettings,
    this.onDatabaseReopened,
  });

  final DatabaseInitResult databaseResult;
  final VoidCallback onOpenDatabaseSettings;
  /// Μετά από νέα βάση / επανασύνδεση — ίδιο με `MainShell.onDatabaseReopened`.
  final Future<void> Function()? onDatabaseReopened;

  @override
  ConsumerState<DatabaseBrowserScreen> createState() =>
      _DatabaseBrowserScreenState();
}

class _DatabaseBrowserScreenState extends ConsumerState<DatabaseBrowserScreen> {
  List<String> _tableNames = [];
  bool _loading = true;
  String? _error;
  String? _selectedTable;
  TablePreviewResult? _preview;
  String _tableSchema = '';
  bool _previewLoading = false;

  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  Future<void> _loadTables() async {
    setState(() {
      _loading = true;
      _error = null;
      _tableNames = [];
      _selectedTable = null;
      _preview = null;
      _tableSchema = '';
    });
    try {
      final results = await Future.wait<dynamic>([
        DatabaseHelper.instance.getTableNames(),
        ref.read(databaseBrowserZoomByTableProvider.notifier).load(),
      ]);
      final names = results[0] as List<String>;
      if (mounted) {
        setState(() {
          _tableNames = names;
          _loading = false;
        });
        ref.invalidate(databaseBrowserStatsProvider);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _selectTable(String tableName) async {
    setState(() {
      _selectedTable = tableName;
      _preview = null;
      _tableSchema = '';
      _previewLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        DatabaseHelper.instance.getTablePreview(tableName),
        DatabaseHelper.instance.getTableSchema(tableName),
      ]);
      if (!mounted) return;
      final preview = results[0] as TablePreviewResult;
      final schema = results[1] as String;
      setState(() {
        _preview = preview;
        _tableSchema = schema;
        _previewLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _previewLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedTable = null;
      _preview = null;
      _tableSchema = '';
    });
  }

  Future<void> _openDatabaseMaintenance() async {
    await DatabaseMaintenancePanel.show(
      context,
      onDatabaseReopened: widget.onDatabaseReopened ?? () async {},
    );
  }

  /// Κουμπιά ρυθμίσεων και συντήρησης (δεξιά στην κάρτα στατιστικών / προβολή πίνακα).
  Widget _databaseToolbarActions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          tooltip: 'Ρυθμίσεις βάσης δεδομένων',
          icon: const Icon(Icons.dataset_linked),
          padding: const EdgeInsets.only(left: 4, top: 2),
          constraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
          alignment: Alignment.topCenter,
          onPressed: widget.onOpenDatabaseSettings,
        ),
        IconButton(
          tooltip: 'Συντήρηση',
          icon: const Icon(Icons.cleaning_services_outlined),
          padding: const EdgeInsets.only(left: 4),
          constraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
          alignment: Alignment.topCenter,
          onPressed: _openDatabaseMaintenance,
        ),
      ],
    );
  }

  String _recordCountPhrase(int count) {
    final unit = count == 1 ? 'εγγραφή' : 'εγγραφές';
    return '${DatabaseStatsService.formatIntegerEl(count)} $unit';
  }

  Widget _buildStatsErrorBanner(
    BuildContext context,
    ThemeData theme,
    AsyncValue<DatabaseStats> statsAsync,
  ) {
    if (!statsAsync.hasError) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.colorScheme.errorContainer
            .withValues(alpha: theme.brightness == Brightness.dark ? 0.45 : 0.95),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 22,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Δεν ήταν δυνατή η φόρτωση στατιστικών: ${statsAsync.error}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDatabaseStatsCard(
    BuildContext context,
    ThemeData theme,
    AsyncValue<DatabaseStats> statsAsync,
  ) {
    final r = widget.databaseResult;
    final stats = statsAsync.asData?.value;
    final connOk = r.isSuccess;
    final connText = connOk
        ? (r.message ?? 'Η σύνδεση με τη βάση δεδομένων πέτυχε.')
        : (r.message ?? 'Άγνωστο σφάλμα με τη βάση δεδομένων.');

    final backupText = stats != null
        ? (stats.lastBackupTime != null
            ? DateFormat.yMMMd('el').add_Hm().format(
                  stats.lastBackupTime!.toLocal(),
                )
            : 'Δεν έχει γίνει ακόμα')
        : (statsAsync.isLoading ? '…' : '—');

    final sizeLabel = stats != null
        ? DatabaseStatsService.formatFileSizeBytes(stats.fileSizeBytes)
        : (statsAsync.isLoading ? '…' : '—');

    final pathText = stats?.dbPath ?? (statsAsync.isLoading ? '…' : '—');

    Widget statRow(String label, String value, {TextStyle? valueStyle}) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 200,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: valueStyle ?? theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Στατιστικά Βάσης Δεδομένων',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              connText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: connOk
                    ? Colors.green.shade700
                    : theme.colorScheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (!connOk && r.details != null && r.details!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                r.details!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error.withValues(alpha: 0.85),
                ),
              ),
            ],
            if (statsAsync.isLoading) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Φόρτωση στατιστικών…',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
            statRow('Μέγεθος αρχείου', sizeLabel),
            statRow('Τελευταίο αντίγραφο ασφαλείας', backupText),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 200,
                    child: Text(
                      'Διαδρομή βάσης',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      pathText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontFamilyFallback: const ['Consolas', 'monospace'],
                      ),
                    ),
                  ),
                ],
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
    final zoomByTable = ref.watch(databaseBrowserZoomByTableProvider);
    final statsAsync = ref.watch(databaseBrowserStatsProvider);

    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_error != null && _tableNames.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Σφάλμα φόρτωσης πινάκων',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadTables,
                icon: const Icon(Icons.refresh),
                label: const Text('Δοκιμή ξανά'),
              ),
            ],
          ),
        ),
      );
    }

    // Επιλεγμένος πίνακας: εμφάνιση προεπισκόψης (Excel-like)
    if (_selectedTable != null) {
      final selected = _selectedTable!;
      final displayName = _displayNameForTable(selected);
      final tableZoom = zoomByTable[selected] ?? 1.0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Πίσω στη λίστα πινάκων',
                  onPressed: _clearSelection,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Πίνακας: $displayName',
                        style: theme.textTheme.titleMedium,
                      ),
                      if (displayName != selected)
                        Text(
                          selected,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                _databaseToolbarActions(),
              ],
            ),
          ),
          if (!_previewLoading &&
              _preview != null &&
              _preview!.columns.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Σχήμα (προς αντιγραφή)',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    _tableSchema.isEmpty
                        ? '$selected: —'
                        : '$selected: $_tableSchema',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontFamilyFallback: const ['Consolas', 'monospace'],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Μέγεθος προβολής',
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
                        onPressed: () => ref
                            .read(databaseBrowserZoomByTableProvider.notifier)
                            .zoomOutFor(selected),
                      ),
                      TextButton(
                        onPressed: () => ref
                            .read(databaseBrowserZoomByTableProvider.notifier)
                            .resetFor(selected),
                        child: const Text('100%'),
                      ),
                      IconButton(
                        tooltip: 'Μεγέθυνση',
                        icon: const Icon(Icons.zoom_in),
                        onPressed: () => ref
                            .read(databaseBrowserZoomByTableProvider.notifier)
                            .zoomInFor(selected),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 1),
          Expanded(
            child: _previewLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _preview == null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Σφάλμα προεπισκόπησης',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                style: theme.textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : _preview == null || _preview!.columns.isEmpty
                        ? Center(
                            child: Text(
                              'Δεν υπάρχουν στήλες ή δεδομένα.',
                              style: theme.textTheme.bodyLarge,
                            ),
                          )
                        : _TablePreviewGrid(
                            preview: _preview!,
                            zoom: tableZoom,
                          ),
          ),
        ],
      );
    }

    // Λίστα πινάκων: δύο στήλες, σειρά όπως το μενού (μισά αριστερά, μισά δεξιά).
    final ordered = _orderedTableNames(_tableNames);
    final mid = (ordered.length + 1) ~/ 2;
    final left = ordered.sublist(0, mid);
    final right = ordered.sublist(mid);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatsErrorBanner(context, theme, statsAsync),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildDatabaseStatsCard(context, theme, statsAsync),
              ),
              _databaseToolbarActions(),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      for (final name in left)
                        _buildTableListTile(context, name, statsAsync),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ListView(
                    children: [
                      for (final name in right)
                        _buildTableListTile(context, name, statsAsync),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableListTile(
    BuildContext context,
    String name,
    AsyncValue<DatabaseStats> statsAsync,
  ) {
    final theme = Theme.of(context);
    final display = _displayNameForTable(name);
    final stats = statsAsync.asData?.value;
    final count = stats?.rowCountsByTable[name];
    final grey = theme.colorScheme.onSurfaceVariant.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.78 : 0.62,
    );

    return ListTile(
      leading: const Icon(Icons.table_chart),
      title: Text.rich(
        TextSpan(
          style: theme.textTheme.titleMedium,
          children: [
            TextSpan(text: display),
            if (count != null)
              TextSpan(
                text: ' (${_recordCountPhrase(count)})',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: grey,
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
      ),
      subtitle: Text(
        display != name ? name : 'Πάτα για προεπισκόπηση',
      ),
      onTap: () => _selectTable(name),
      dense: true,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Πλέγμα προεπισκόπησης πίνακα (Excel-like): πλάτη από περιεχόμενο, ονόματα στηλών ολόκληρα, ευμετάβλητα πλάτη (resize).
class _TablePreviewGrid extends StatefulWidget {
  const _TablePreviewGrid({
    required this.preview,
    required this.zoom,
  });

  final TablePreviewResult preview;
  final double zoom;

  @override
  State<_TablePreviewGrid> createState() => _TablePreviewGridState();
}

class _TablePreviewGridState extends State<_TablePreviewGrid> {
  static const double _minColWidth = 60.0;
  static const double _maxColWidth = 500.0;
  static const double _cellPadding = 12.0;
  static const double _resizeHandleWidth = 8.0;
  /// Επιπλέον πλάτος ώστε το όνομα της στήλης να μην κόβεται (SelectableText + font metrics).
  static const double _headerWidthBuffer = 20.0;
  static const double _rowHeight = 40.0;
  static const double _headerHeight = 44.0;

  List<double> _columnWidths = [];
  bool _widthsInitialized = false;

  TablePreviewResult get preview => widget.preview;

  void _ensureColumnWidths(BuildContext context) {
    if (_widthsInitialized && _columnWidths.length == preview.columns.length) {
      return;
    }
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    ) ?? const TextStyle(fontWeight: FontWeight.w600);
    final cellStyle = theme.textTheme.bodySmall ?? const TextStyle();

    final widths = <double>[];
    for (var c = 0; c < preview.columns.length; c++) {
      final colName = preview.columns[c];
      double w = _textWidth(colName, headerStyle) + _cellPadding * 2 + _headerWidthBuffer;
      for (final row in preview.rows) {
        final cellStr = _cellText(row[colName]);
        final cellW = _textWidth(cellStr, cellStyle) + _cellPadding * 2;
        if (cellW > w) w = cellW;
      }
      widths.add(w.clamp(_minColWidth, _maxColWidth));
    }
    _columnWidths = widths;
    _widthsInitialized = true;
  }

  double _textWidth(String text, TextStyle style) {
    if (text.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(minWidth: 0, maxWidth: double.infinity);
    return painter.width;
  }

  String _cellText(dynamic value) {
    if (value == null) return '';
    if (value is DateTime) return value.toIso8601String();
    return value.toString();
  }

  @override
  void didUpdateWidget(covariant _TablePreviewGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preview != widget.preview) {
      _widthsInitialized = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureColumnWidths(context);
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final cellStyle = theme.textTheme.bodySmall;
    final borderSide = BorderSide(
      color: theme.dividerColor.withValues(alpha: 0.5),
      width: 1,
    );

    final table = Table(
      columnWidths: {
        for (var i = 0; i < _columnWidths.length; i++)
          i: FixedColumnWidth(_columnWidths[i] + _resizeHandleWidth),
      },
      border: TableBorder(
        horizontalInside: borderSide,
        verticalInside: borderSide,
        top: borderSide,
        left: borderSide,
        right: borderSide,
        bottom: borderSide,
      ),
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          children: List.generate(preview.columns.length, (c) {
            return SizedBox(
              height: _headerHeight,
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _cellPadding,
                        vertical: 8,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          preview.columns[c],
                          style: headerStyle,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        final newW =
                            (_columnWidths[c] + details.delta.dx)
                                .clamp(_minColWidth, _maxColWidth);
                        _columnWidths[c] = newW;
                      });
                    },
                    behavior: HitTestBehavior.opaque,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      child: SizedBox(
                        width: _resizeHandleWidth,
                        child: Container(
                          color: theme.colorScheme.outline
                              .withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
        ...preview.rows.map((row) {
          return TableRow(
            children: preview.columns.map((col) {
              final text = _cellText(row[col]);
              return SizedBox(
                height: _rowHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _cellPadding,
                    vertical: 6,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      text,
                      style: cellStyle,
                      maxLines: 1,
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        }),
      ],
    );

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Transform.scale(
          scale: widget.zoom,
          alignment: Alignment.topLeft,
          filterQuality: FilterQuality.medium,
          child: table,
        ),
      ),
    );
  }
}
