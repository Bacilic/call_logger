import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/active_database_generation.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_identity_repository.dart';
import '../../../core/database/database_table_inspection.dart';
import '../../../core/database/database_init_result.dart';
import '../../../core/providers/app_instances_provider.dart';
import '../../../core/services/app_instance_registry.dart';
import '../../../core/services/crash_log_service.dart';
import '../../../core/services/profile_settings.dart';
import '../../../core/services/scoped_settings.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import '../../../core/widgets/raw_error_details_tile.dart';
import '../models/database_stats.dart';
import '../providers/database_browser_stats_provider.dart';
import '../services/database_stats_service.dart';
import '../widgets/database_label_dialog.dart';
import '../widgets/database_stats_card.dart';
import '../widgets/table_preview_grid.dart';

/// Αποθηκευμένο επίπεδο μεγέθυνσης ανά πίνακα προεπισκόπησης (0.5–2.0· προεπιλογή 1.0).
///
/// **Προσωπικό**: πόσο μεγάλα διαβάζει κανείς είναι δικό του θέμα. Όσο γραφόταν
/// κατευθείαν στα κοινά — παρά το ότι το κλειδί ήταν δηλωμένο προσωπικό —
/// ρυθμίζοντας το ζουμ το άλλαζες και για τον συνάδελφο.
///
/// **Ζει όσο η εφαρμογή, όχι όσο η οθόνη.** Η φόρτωση ξεκινά από το `initState`,
/// πριν προλάβει το πρώτο build να αρχίσει να παρακολουθεί, και η εναλλαγή
/// βάσης μπορεί να ξηλώσει την οθόνη ενόσω τρέχει: με `autoDispose` ο
/// αποθηκευτής πέθαινε στο πρώτο await και η εγγραφή της τιμής έσκαγε, οπότε
/// το ζουμ του χρήστη γύριζε σιωπηλά στο 100%.
final databaseBrowserZoomByTableProvider =
    NotifierProvider<DatabaseBrowserZoomByTableNotifier, Map<String, double>>(
      DatabaseBrowserZoomByTableNotifier.new,
    );

class DatabaseBrowserZoomByTableNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => {};

  /// Φόρτωση του ζουμ του τρέχοντος χρήστη (καλείται κατά το άνοιγμα της οθόνης).
  Future<void> load() async {
    try {
      final raw = await ScopedSettings.getString(
        ProfileSettingKeys.databaseBrowserPreviewZoomByTable,
      );
      if (!ref.mounted) return;
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
      if (ref.mounted) state = {};
    }
  }

  double zoomFor(String tableName) => state[tableName] ?? 1.0;

  Future<void> _persist(Map<String, double> snapshot) async {
    await ScopedSettings.setString(
      ProfileSettingKeys.databaseBrowserPreviewZoomByTable,
      jsonEncode(snapshot),
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
      await _persist(next);
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Τα στατιστικά δεν φορτώθηκαν. '
                      '${humanizeUserFacingError(statsAsync.error!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    // Το ωμό κείμενο του SQLite δεν το καταλαβαίνει ο
                    // χειριστής, αλλά είναι ό,τι θα ζητήσει όποιος κληθεί να
                    // βοηθήσει. Ένα πάτημα μακριά, ποτέ μέσα στο μήνυμα.
                    RawErrorDetailsTile(error: statsAsync.error!),
                  ],
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
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
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
                child: DatabaseStatsCard(
                  databaseResult: widget.databaseResult,
                  statsAsync: statsAsync,
                  expanded: _statsCardExpanded,
                  onToggleExpanded: () {
                    unawaited(_toggleStatsCardExpanded());
                  },
                  onEditLabel: (current) {
                    unawaited(_editDatabaseLabel(current));
                  },
                ),
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
