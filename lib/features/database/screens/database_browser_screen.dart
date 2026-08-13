import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/database/active_database_generation.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_identity_repository.dart';
import '../../../core/database/database_table_inspection.dart';
import '../../../core/database/settings_repository.dart';
import '../../../core/database/database_init_result.dart';
import '../../../core/providers/app_instances_provider.dart';
import '../../../core/services/app_instance_registry.dart';
import '../../../core/services/crash_log_service.dart';
import '../../../core/services/settings_service.dart';
import '../models/database_stats.dart';
import '../providers/database_browser_stats_provider.dart';
import '../services/database_stats_service.dart';
import '../widgets/database_label_dialog.dart';
import '../widgets/database_maintenance_panel.dart';
import '../widgets/table_preview_grid.dart';

/// Κλειδί `app_settings` για JSON `{ "όνομα_πίνακα": zoom, ... }` (zoom 0.5–2.0).
const String _kDatabaseBrowserZoomByTableSettingsKey =
    'database_browser_preview_zoom_by_table';

/// Αποθηκευμένο επίπεδο μεγέθυνσης ανά πίνακα προεπισκόπησης (0.5–2.0· προεπιλογή 1.0).
final databaseBrowserZoomByTableProvider =
    NotifierProvider.autoDispose<
      DatabaseBrowserZoomByTableNotifier,
      Map<String, double>
    >(DatabaseBrowserZoomByTableNotifier.new);

class DatabaseBrowserZoomByTableNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => {};

  /// Φόρτωση από `app_settings` (καλείται κατά το άνοιγμα της οθόνης).
  Future<void> load() async {
    try {
      final dbZoom = await DatabaseHelper.instance.database;
      final raw = await SettingsRepository(
        dbZoom,
      ).getSetting(_kDatabaseBrowserZoomByTableSettingsKey);
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
    } catch (e, stack) {
      // Το zoom είναι προαιρετική άνεση — η οθόνη συνεχίζει με 100%,
      // αλλά το σφάλμα (π.χ. χαλασμένο JSON) αφήνει ίχνος στο ημερολόγιο.
      CrashLogService.instanceOrNull?.logError(e, stack, fatal: false);
      state = {};
    }
  }

  double zoomFor(String tableName) => state[tableName] ?? 1.0;

  Future<void> _persist() async {
    final dbZoom = await DatabaseHelper.instance.database;
    await SettingsRepository(
      dbZoom,
    ).saveSetting(_kDatabaseBrowserZoomByTableSettingsKey, jsonEncode(state));
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
    } catch (e, stack) {
      // Η προβολή έχει ήδη το νέο zoom — μόνο η αποθήκευση απέτυχε.
      CrashLogService.instanceOrNull?.logError(e, stack, fatal: false);
    }
  }

  Future<void> zoomOutFor(String tableName) {
    return setZoomForTable(tableName, zoomFor(tableName) - 0.1);
  }

  Future<void> zoomInFor(String tableName) {
    return setZoomForTable(tableName, zoomFor(tableName) + 0.1);
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
  'knowledge_base': 'Βάση Γνώσης',
  'remote_tools': 'Εργαλεία απομακρυσμένης επιφάνειας',
  'remote_tool_args': 'Ορίσματα απομακρυσμένου εργαλείου',
  'user_dictionary': 'Προσωπικό λεξικό',
  'full_dictionary': 'Πλήρες λεξικό (συσσωρευτής)',
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
  'remote_tools',
  'remote_tool_args',
  'user_dictionary',
  'full_dictionary',
];

List<String> _orderedTableNames(List<String> raw) {
  final orderMap = {
    for (var i = 0; i < _kMenuTableOrder.length; i++) _kMenuTableOrder[i]: i,
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

  /// Συνολικές εγγραφές του επιλεγμένου πίνακα (για «Χ από Ψ» + σελιδοποίηση).
  int? _totalRowCount;
  bool _loadingMoreRows = false;

  /// Κάρτα στατιστικών: false = συμπτυγμένη (προεπιλογή μέχρι φόρτωση ρύθμισης).
  bool _statsCardExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadTables();
    _loadStatsCardExpandedPref();
  }

  Future<void> _loadStatsCardExpandedPref() async {
    final v = await SettingsService().windowUi
        .getDatabaseBrowserStatsCardExpanded();
    if (mounted) setState(() => _statsCardExpanded = v);
  }

  Future<void> _toggleStatsCardExpanded() async {
    final next = !_statsCardExpanded;
    setState(() => _statsCardExpanded = next);
    await SettingsService().windowUi.setDatabaseBrowserStatsCardExpanded(next);
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
        DatabaseHelper.instance.tableInspection.getTableNames(),
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

  /// Ξαναδιαβάζει τα πάντα από τη βάση που είναι ανοιχτή **τώρα**.
  ///
  /// Ο πίνακας που κοιτούσε ο χρήστης διατηρείται όταν υπάρχει και στη νέα
  /// βάση — η συνηθισμένη χρήση είναι η σύγκριση του ίδιου πίνακα ανάμεσα σε
  /// δύο βάσεις, και μια επιστροφή στη λίστα θα την έκανε χειροκίνητη κάθε
  /// φορά. Όταν ο πίνακας δεν υπάρχει εκεί, η λίστα είναι η μόνη τίμια απάντηση.
  Future<void> _reloadAfterDatabaseSwitch() async {
    final previouslySelected = _selectedTable;
    await _loadTables();
    if (!mounted || previouslySelected == null) return;
    if (!_tableNames.contains(previouslySelected)) return;
    await _selectTable(previouslySelected);
  }

  Future<void> _selectTable(String tableName) async {
    setState(() {
      _selectedTable = tableName;
      _preview = null;
      _tableSchema = '';
      _previewLoading = true;
      _totalRowCount = null;
      _error = null;
    });
    try {
      final inspection = DatabaseHelper.instance.tableInspection;
      final results = await Future.wait<dynamic>([
        inspection.getTablePreview(tableName),
        inspection.getTableSchema(tableName),
        inspection.getTableRowCount(tableName),
      ]);
      if (!mounted || _selectedTable != tableName) return;
      setState(() {
        _preview = results[0] as TablePreviewResult;
        _tableSchema = results[1] as String;
        _totalRowCount = results[2] as int;
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

  bool get _hasMorePreviewRows {
    final total = _totalRowCount;
    final preview = _preview;
    return total != null && preview != null && preview.rows.length < total;
  }

  /// Φόρτωση επόμενης σελίδας εγγραφών όταν η κύλιση φτάνει προς το τέλος.
  Future<void> _loadMorePreviewRows() async {
    if (_loadingMoreRows || !_hasMorePreviewRows) return;
    final tableName = _selectedTable;
    final current = _preview;
    if (tableName == null || current == null) return;
    _loadingMoreRows = true;
    try {
      final page = await DatabaseHelper.instance.tableInspection
          .getTablePreview(tableName, offset: current.rows.length);
      if (!mounted || _selectedTable != tableName) return;
      setState(() {
        _preview = TablePreviewResult(
          columns: current.columns,
          rows: [...current.rows, ...page.rows],
        );
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      _loadingMoreRows = false;
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedTable = null;
      _preview = null;
      _tableSchema = '';
      _totalRowCount = null;
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
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          alignment: Alignment.topCenter,
          onPressed: widget.onOpenDatabaseSettings,
        ),
        IconButton(
          tooltip: 'Συντήρηση',
          icon: const Icon(Icons.cleaning_services_outlined),
          padding: const EdgeInsets.only(left: 4),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
        color: theme.colorScheme.errorContainer.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.45 : 0.95,
        ),
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

  /// Μόνιμη λίστα των αντιγράφων της εφαρμογής που μοιράζονται αυτές τις
  /// ρυθμίσεις — εδώ οδηγεί ο σύνδεσμος της λωρίδας.
  ///
  /// Εμφανίζεται μόνο όταν υπάρχει δεύτερο αντίγραφο: σε υπολογιστή με μία
  /// εγκατάσταση δεν έχει τίποτα να πει.
  Widget _buildAppInstancesCard(ThemeData theme) {
    final status = ref.watch(appInstancesProvider).value;
    if (status == null || !status.isSharedWithOthers) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        key: const ValueKey('app_instances_card'),
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
                'Αντίγραφα της εφαρμογής',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                currentAppInstancesSharedScopeText(),
                key: const Key('app_instances_scope_text'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              for (final record in status.all)
                _appInstanceRow(theme, record, status.isCurrent(record)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appInstanceRow(
    ThemeData theme,
    AppInstanceRecord record,
    bool isCurrent,
  ) {
    final seen = record.lastSeen;
    final stamp =
        '${seen.day.toString().padLeft(2, '0')}/'
        '${seen.month.toString().padLeft(2, '0')}/${seen.year} '
        '${seen.hour.toString().padLeft(2, '0')}:'
        '${seen.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isCurrent ? Icons.play_circle_outline : Icons.circle_outlined,
            size: 18,
            color: isCurrent
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  record.executablePath,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Consolas', 'monospace'],
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                Text(
                  [
                    if (isCurrent) 'εκτελείται τώρα',
                    if (record.version.isNotEmpty) 'έκδοση ${record.version}',
                    if (record.schemaVersion != null)
                      'διαβάζει βάσεις έως την έκδοση ${record.schemaVersion}',
                    'τελευταία εκκίνηση $stamp',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
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
              ? DateFormat.yMMMd(
                  'el',
                ).add_Hm().format(stats.lastBackupTime!.toLocal())
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: _toggleStatsCardExpanded,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Στατιστικά Βάσης Δεδομένων',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: _statsCardExpanded ? 'Σύμπτυξη' : 'Επέκταση',
                      child: Icon(
                        _statsCardExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _statsCardExpanded
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        final left = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _fileColumn(
                            theme: theme,
                            connText: connText,
                            connOk: connOk,
                            details: r.details,
                            statsAsync: statsAsync,
                            statRow: statRow,
                            sizeLabel: sizeLabel,
                            backupText: backupText,
                            pathText: pathText,
                          ),
                        );
                        final right = _identityColumn(theme, stats, statsAsync);
                        // Κάτω από αυτό το πλάτος οι δύο στήλες στριμώχνονται
                        // τόσο που η διαδρομή σπάει σε πέντε γραμμές: τότε η
                        // μία κάτω από την άλλη διαβάζεται καλύτερα.
                        if (constraints.maxWidth < 900) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              left,
                              const SizedBox(height: 12),
                              right,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: left),
                            const SizedBox(width: 14),
                            Expanded(child: right),
                          ],
                        );
                      },
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  /// Η αριστερή στήλη: το **αρχείο** — πού είναι, πόσο πιάνει, πότε σώθηκε.
  List<Widget> _fileColumn({
    required ThemeData theme,
    required String connText,
    required bool connOk,
    required String? details,
    required AsyncValue<DatabaseStats> statsAsync,
    required Widget Function(String, String, {TextStyle? valueStyle}) statRow,
    required String sizeLabel,
    required String backupText,
    required String pathText,
  }) {
    return [
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
                        if (!connOk &&
                            details != null &&
                            details.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            details,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error.withValues(
                                alpha: 0.85,
                              ),
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
                                    fontFamilyFallback: const [
                                      'Consolas',
                                      'monospace',
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
    ];
  }

  /// Η δεξιά στήλη: **ταυτότητα και υγεία** του περιεχομένου.
  ///
  /// Ξεχωριστή επιφάνεια, όχι μόνο για διαχωρισμό: το όνομα δέχεται κλικ, και
  /// ένα πεδίο που πατιέται χρειάζεται ορατό όριο για να μη μοιάζει με ακόμη
  /// μία ετικέτα ανάμεσα σε ετικέτες.
  Widget _identityColumn(
    ThemeData theme,
    DatabaseStats? stats,
    AsyncValue<DatabaseStats> statsAsync,
  ) {
    final pending = statsAsync.isLoading ? '…' : '—';

    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
          ],
        ),
      );
    }

    final label = stats?.label;
    final schema = stats?.schemaVersion;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: stats == null ? null : () => _editDatabaseLabel(label),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label ?? 'Χωρίς όνομα',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: label == null
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                        fontStyle: label == null ? FontStyle.italic : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.edit_outlined,
                    size: 15,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          row('Έκδοση σχήματος', schema == null ? pending : '$schema'),
          row('Τελευταία αλλαγή', _formatLastChange(stats?.lastChangeAt, pending)),
          row('Κλήσεις', _formatCallRange(stats, pending)),
          row('Χαμένος χώρος', _formatOptionalSize(stats?.reclaimableBytes, pending)),
          row('Εκκρεμείς εγγραφές', _formatPendingWal(stats?.pendingWalBytes, pending)),
        ],
      ),
    );
  }

  String _formatLastChange(DateTime? value, String pending) {
    if (value == null) return pending;
    return DateFormat('dd/MM/yyyy, HH:mm').format(value);
  }

  /// «από–έως» με ελληνικές ημερομηνίες· μία μέρα δεν γράφεται δύο φορές.
  String _formatCallRange(DatabaseStats? stats, String pending) {
    final first = stats?.firstCallDate;
    final last = stats?.lastCallDate;
    if (first == null || last == null) {
      return stats == null ? pending : 'καμία';
    }
    final a = _formatIsoDay(first);
    final b = _formatIsoDay(last);
    return a == b ? a : '$a – $b';
  }

  String _formatIsoDay(String isoDay) {
    final parsed = DateTime.tryParse(isoDay);
    if (parsed == null) return isoDay;
    return DateFormat('dd/MM/yyyy').format(parsed);
  }

  String _formatOptionalSize(int? bytes, String pending) {
    if (bytes == null) return pending;
    if (bytes <= 0) return 'κανένας';
    return DatabaseStatsService.formatFileSizeBytes(bytes);
  }

  String _formatPendingWal(int? bytes, String pending) {
    if (bytes == null) return 'καμία';
    if (bytes <= 0) return 'καμία';
    return DatabaseStatsService.formatFileSizeBytes(bytes);
  }

  Future<void> _editDatabaseLabel(String? current) async {
    final next = await showDatabaseLabelDialog(
      context: context,
      currentLabel: current,
    );
    if (next == null || !mounted) return;
    try {
      final db = await DatabaseHelper.instance.database;
      await DatabaseIdentityRepository(db).writeLabel(next.value);
      ref.invalidate(databaseBrowserStatsProvider);
    } catch (e, stack) {
      CrashLogService.instanceOrNull?.logError(e, stack, fatal: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Το όνομα της βάσης δεν αποθηκεύτηκε.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Οι Ρυθμίσεις βάσης ανοίγουν ως διάλογος **πάνω από αυτή την οθόνη**, οπότε
    // η εναλλαγή βάσης τη βρίσκει ζωντανή: το δέντρο δεν ξηλώνεται και οι
    // φορτωμένες γραμμές θα έμεναν εκεί, δείχνοντας βάση που δεν διαβάζουμε πια.
    ref.listen<int>(activeDatabaseGenerationProvider, (_, _) {
      unawaited(_reloadAfterDatabaseSwitch());
    });
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
                : TablePreviewGrid(
                    tableKey: selected,
                    columns: _preview!.columns,
                    rows: _preview!.rows,
                    zoom: tableZoom,
                    totalRowCount: _totalRowCount,
                    hasMoreRows: _hasMorePreviewRows,
                    onLoadMoreRows: _loadMorePreviewRows,
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
          _buildAppInstancesCard(theme),
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
      subtitle: Text(display != name ? name : 'Πάτα για προεπισκόπηση'),
      onTap: () => _selectTable(name),
      dense: true,
      visualDensity: VisualDensity.compact,
    );
  }
}
