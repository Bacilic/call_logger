import 'dart:io';

import 'package:custom_mouse_cursor/custom_mouse_cursor.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path/path.dart' as p;

import '../../../core/database/database_helper.dart' show TablePreviewResult;
import '../../../core/database/old_database/lamp_table_browser_api.dart';
import '../../../core/database/old_database/lamp_table_greek_names.dart';
import '../../../core/database/old_database/lamp_settings_store.dart';
import '../../../core/database/old_database/old_equipment_repository.dart';
import '../../database/services/database_stats_service.dart';

final _kLampFileDateFmt = DateFormat.yMMMd('el').add_Hm();

/// Καρτέλα «Πίνακες»: στατιστικά αρχείου + κατάλογος πινάκων με αριθμό εγγραφών, απλή προεπισκόπηση
/// (χωρίς schema, zoom, resize). Απαιτεί ήδη έγκυρη βάνα ανάγνωσης.
class LampDbTablesTab extends StatefulWidget {
  const LampDbTablesTab({
    super.key,
    required this.databasePath,
    required this.repository,
    this.onAfterDataIssuesPurge,
  });

  final String databasePath;
  final OldEquipmentRepository repository;

  /// Καλείται μετά επιτυχή `DELETE` στο `data_issues` ώστε η μητρική οθόνη να
  /// ξαναφορτώσει τη λίστα προβλημάτων ETL.
  final Future<void> Function()? onAfterDataIssuesPurge;

  @override
  State<LampDbTablesTab> createState() => _LampDbTablesTabState();
}

class _LampDbTablesTabState extends State<LampDbTablesTab> {
  static final _api = LampTableBrowserApi.instance;
  static const double _kDefaultTablesPaneWidth = 320;
  static const double _kMinTablesPaneWidth = 220;
  static const double _kMinPreviewPaneWidth = 320;
  static const double _kSplitterWidth = 10;

  final _settings = LampSettingsStore();
  bool _loading = true;
  String? _error;
  int? _fileSizeBytes;
  DateTime? _fileLastModified;
  LampFileTableSummary? _summary;
  String? _selected;
  bool _previewLoading = false;
  String? _previewError;
  TablePreviewResult? _preview;
  double _tablesPaneWidth = _kDefaultTablesPaneWidth;
  CustomMouseCursor? _splitterCursor;
  /// `'data_issues'` ή `'search_index'` όταν τρέχει η αντίστοιχη ενέργεια.
  String? _tableMaintenanceBusy;

  @override
  void initState() {
    super.initState();
    _loadPersistedTablesPaneWidth();
    _preloadSplitCursor();
    _load();
  }

  @override
  void didUpdateWidget(covariant LampDbTablesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.databasePath != widget.databasePath) {
      _load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    CustomMouseCursor.ensurePointersMatchDevicePixelRatio(context);
  }

  Future<void> _loadPersistedTablesPaneWidth() async {
    final saved = await _settings.getTablesPaneWidthPx();
    if (!mounted || saved == null) return;
    setState(() => _tablesPaneWidth = saved);
  }

  Future<void> _saveTablesPaneWidth(double widthPx) async {
    await _settings.setTablesPaneWidthPx(widthPx);
  }

  Future<void> _preloadSplitCursor() async {
    try {
      final c = await CustomMouseCursor.icon(
        Icons.swap_horiz,
        size: 24,
        hotX: 12,
        hotY: 12,
        color: const Color(0xFF212121),
      );
      if (!mounted) return;
      setState(() => _splitterCursor = c);
    } catch (_) {
      // fallback σε SystemMouseCursors.resizeColumn
    }
  }

  Future<void> _load() async {
    final p = widget.databasePath.trim();
    if (p.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Κενή διαδρομή βάσης.';
          _fileSizeBytes = null;
          _fileLastModified = null;
          _summary = null;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final f = File(p);
      if (!await f.exists()) {
        throw const FileSystemException('Το αρχείο δεν υπάρχει.');
      }
      final size = await f.length();
      final modified = await f.lastModified();
      final summary = await _api.getFileAndTableSummary(p);
      if (!mounted) return;
      setState(() {
        _fileSizeBytes = size;
        _fileLastModified = modified;
        _summary = summary;
        _selected = null;
        _preview = null;
        _previewError = null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _onSelectTable(String name) async {
    setState(() {
      _selected = name;
      _previewLoading = true;
      _preview = null;
      _previewError = null;
    });
    final p = widget.databasePath.trim();
    try {
      final preview = await _api.getTablePreview(p, name);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _previewLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _previewLoading = false;
          _previewError = e.toString();
        });
      }
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _onDeleteAllDataIssuesPressed() async {
    final path = widget.databasePath.trim();
    if (path.isEmpty) return;
    int count;
    try {
      count = await widget.repository.dataIssueCount(path);
    } catch (e) {
      _showSnack('Αποτυχία ανάγνωσης πλήθους εγγραφών: $e', isError: true);
      return;
    }
    if (!mounted) return;
    if (count == 0) {
      _showSnack('Ο πίνακας data_issues είναι ήδη άδειος.');
      return;
    }
    final countLabel = DatabaseStatsService.formatIntegerEl(count);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή όλων των προβλημάτων ETL'),
        content: SingleChildScrollView(
          child: Text(
            'Πρόκειται να διαγραφούν οριστικά $countLabel εγγραφές από τον πίνακα '
            'data_issues (προβλήματα εισαγωγής/ελέγχου).\n\n'
            'Η ενέργεια δεν αναιρείται. Θέλετε να συνεχίσετε;',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Διαγραφή όλων'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _tableMaintenanceBusy = 'data_issues');
    try {
      final deleted = await widget.repository.deleteAllDataIssues(path);
      if (!mounted) return;
      await widget.onAfterDataIssuesPurge?.call();
      if (!mounted) return;
      final deletedLabel = DatabaseStatsService.formatIntegerEl(deleted);
      _showSnack('Διαγράφηκαν $deletedLabel εγγραφές από τον πίνακα data_issues.');
      await _load();
      if (_selected == 'data_issues') {
        await _onSelectTable('data_issues');
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Αποτυχία διαγραφής: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _tableMaintenanceBusy = null);
      }
    }
  }

  Future<void> _onRebuildSearchIndexPressed() async {
    final path = widget.databasePath.trim();
    if (path.isEmpty) return;
    int indexCount;
    int equipmentCount;
    try {
      indexCount = await _api.getTableRowCount(path, 'search_index');
      equipmentCount = await _api.getTableRowCount(path, 'equipment');
    } catch (e) {
      _showSnack('Αποτυχία ανάγνωσης στατιστικών πινάκων: $e', isError: true);
      return;
    }
    if (!mounted) return;
    final indexLabel = DatabaseStatsService.formatIntegerEl(indexCount);
    final equipLabel = DatabaseStatsService.formatIntegerEl(equipmentCount);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Αναδόμηση ευρετηρίου αναζήτησης'),
        content: SingleChildScrollView(
          child: Text(
            'Ο πίνακας search_index περιέχει τώρα $indexLabel εγγραφές.\n\n'
            'Όλες θα διαγραφούν· στη συνέχεια θα δημιουργηθούν ξανά $equipLabel '
            'εγγραφές (μία ανά γραμμή εξοπλισμού), με την ισχύουσα λογική '
            'κανονικοποιημένου κειμένου αναζήτησης.\n\n'
            'Η λειτουργία αναζήτησης στη Λάμπα ενημερώνεται αμέσως μετά.\n\n'
            'Να συνεχιστεί;',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Αναδόμηση'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _tableMaintenanceBusy = 'search_index');
    try {
      final r = await widget.repository.rebuildLampSearchIndex(path);
      if (!mounted) return;
      final prevLabel = DatabaseStatsService.formatIntegerEl(r.previousRowCount);
      final newLabel = DatabaseStatsService.formatIntegerEl(r.newRowCount);
      _showSnack(
        'Αναδόμηση search_index: $prevLabel → $newLabel εγγραφές.',
      );
      await _load();
      if (_selected == 'search_index') {
        await _onSelectTable('search_index');
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Αποτυχία αναδόμησης search_index: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _tableMaintenanceBusy = null);
      }
    }
  }

  Widget? _buildTableTrailingActions(String tableName) {
    if (tableName != 'data_issues' && tableName != 'search_index') {
      return null;
    }
    final busyHere = _tableMaintenanceBusy == tableName;
    final busyOther = _tableMaintenanceBusy != null && !busyHere;
    final theme = Theme.of(context);
    Widget iconButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
      required bool showSpinner,
    }) {
      return IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: showSpinner
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              )
            : Icon(icon, size: 20),
      );
    }

    if (tableName == 'data_issues') {
      return iconButton(
        icon: Icons.delete_sweep_outlined,
        tooltip: 'Διαγραφή όλων των εγγραφών data_issues',
        showSpinner: busyHere,
        onPressed: busyHere || busyOther ? null : _onDeleteAllDataIssuesPressed,
      );
    }
    return iconButton(
      icon: Icons.restart_alt_outlined,
      tooltip: 'Αναδόμηση πίνακα search_index',
      showSpinner: busyHere,
      onPressed: busyHere || busyOther ? null : _onRebuildSearchIndexPressed,
    );
  }

  double _clampTablesPaneWidth(double requested, double maxTotalWidth) {
    final maxByPreview = (maxTotalWidth - _kSplitterWidth - _kMinPreviewPaneWidth)
        .clamp(_kMinTablesPaneWidth, maxTotalWidth)
        .toDouble();
    return requested.clamp(_kMinTablesPaneWidth, maxByPreview).toDouble();
  }

  Widget _buildSplitter({
    required ThemeData theme,
    required double maxTotalWidth,
  }) {
    final cursor = _splitterCursor ?? SystemMouseCursors.resizeColumn;
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          setState(() {
            _tablesPaneWidth = _clampTablesPaneWidth(
              _tablesPaneWidth + details.delta.dx,
              maxTotalWidth,
            );
          });
        },
        onHorizontalDragEnd: (_) {
          _saveTablesPaneWidth(_tablesPaneWidth);
        },
        child: SizedBox(
          width: _kSplitterWidth,
          child: Center(
            child: Container(
              width: 2,
              height: double.infinity,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.9),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Δεν φορτώθηκε ο κατάλογος πινάκων: $_error',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: _LampFileStatsCard(
            fullPath: widget.databasePath,
            sizeBytes: _fileSizeBytes,
            lastModified: _fileLastModified,
            totalRowCount: _summary?.totalRowCount,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxTotal = constraints.maxWidth;
              final effectiveTablesWidth = _clampTablesPaneWidth(
                _tablesPaneWidth,
                maxTotal,
              );
              if ((effectiveTablesWidth - _tablesPaneWidth).abs() > 0.1) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() => _tablesPaneWidth = effectiveTablesWidth);
                });
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: effectiveTablesWidth,
                    child: _summary == null
                        ? const SizedBox.shrink()
                        : ListView.builder(
                            itemCount: _summary!.tableNamesOrdered.length,
                            itemBuilder: (context, index) {
                              final name = _summary!.tableNamesOrdered[index];
                              final count = _summary!.rowCountByTable[name] ?? 0;
                              final friendly = lampTableDisplayGreek(name);
                              final titleText = friendly == name
                                  ? name
                                  : '$friendly - $name';
                              final isSel = _selected == name;
                              final trailing = _buildTableTrailingActions(name);
                              final tile = ListTile(
                                selected: isSel,
                                title: Text(titleText),
                                subtitle: Text(
                                  _recordPhrase(count),
                                  style: theme.textTheme.bodySmall,
                                ),
                                trailing: trailing,
                                onTap: () => _onSelectTable(name),
                                dense: true,
                              );
                              if (trailing != null) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 4, top: 2),
                                  child: Card(
                                    margin: EdgeInsets.zero,
                                    elevation: 0,
                                    color: theme.colorScheme.surfaceContainerHighest
                                        .withValues(alpha: 0.65),
                                    clipBehavior: Clip.antiAlias,
                                    child: tile,
                                  ),
                                );
                              }
                              return tile;
                            },
                          ),
                  ),
                  _buildSplitter(theme: theme, maxTotalWidth: maxTotal),
                  Expanded(
                    child: _buildPreviewPanel(theme),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  String _recordPhrase(int count) {
    return '${DatabaseStatsService.formatIntegerEl(count)} ${count == 1 ? 'εγγραφή' : 'εγγραφές'}';
  }

  Widget _buildPreviewPanel(ThemeData theme) {
    if (_selected == null) {
      return Center(
        child: Text(
          'Επίλεξε πίνακα για προεπισκόπηση δεδομένων (χωρίς schema).',
          style: theme.textTheme.bodyLarge,
        ),
      );
    }
    if (_previewLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_previewError != null) {
      return Center(
        child: Text(
          _previewError!,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      );
    }
    final pre = _preview;
    if (pre == null || pre.columns.isEmpty) {
      return const Center(
        child: Text('Δεν υπάρχουν στήλες ή σειρές προς εμφάνιση.'),
      );
    }
    return _SimpleDataPreview(
      result: pre,
    );
  }
}

String _elSize(int? b) {
  if (b == null) return '—';
  return DatabaseStatsService.formatFileSizeBytes(b);
}

class _LampFileStatsCard extends StatefulWidget {
  const _LampFileStatsCard({
    required this.fullPath,
    required this.sizeBytes,
    required this.lastModified,
    required this.totalRowCount,
  });

  final String fullPath;
  final int? sizeBytes;
  final DateTime? lastModified;
  final int? totalRowCount;

  @override
  State<_LampFileStatsCard> createState() => _LampFileStatsCardState();
}

class _LampFileStatsCardState extends State<_LampFileStatsCard> {
  bool _isExpanded = false;

  String get _collapsedSummary {
    final name = p.basename(widget.fullPath.trim());
    final sz = _elSize(widget.sizeBytes);
    final total = widget.totalRowCount == null
        ? '—'
        : DatabaseStatsService.formatIntegerEl(widget.totalRowCount!);
    return '$name · $sz · $total εγγραφές (συν.)';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      elevation: 0,
      color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: t.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          maintainState: true,
          onExpansionChanged: (expanded) {
            setState(() => _isExpanded = expanded);
          },
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(
            'Στατιστικά αρχείου βάσης (Λάμπα)',
            style: t.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: _isExpanded
              ? null
              : Text(
                  _collapsedSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurfaceVariant,
                  ),
                ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 2),
                _row(t, 'Διαδρομή (πλήρης):', widget.fullPath),
                _row(
                  t,
                  'Μέγεθος αρχείου:',
                  _elSize(widget.sizeBytes),
                ),
                _row(
                  t,
                  'Χρόνος αλλαγής αρχείου (τελευταίο modified):',
                  widget.lastModified == null
                      ? '—'
                      : _kLampFileDateFmt.format(
                          widget.lastModified!.toLocal(),
                        ),
                ),
                _row(
                  t,
                  'Άθροισμα εγγραφών (όλοι οι πίνακες):',
                  widget.totalRowCount == null
                      ? '—'
                      : DatabaseStatsService.formatIntegerEl(
                          widget.totalRowCount!,
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Η στιγμή «created» αρχείου εξαρτάται από το σύστημα (συνήθως: τελευταίο αποθηκευμένο modified/χρόνος αρχείου).',
                  style: t.textTheme.labelSmall?.copyWith(
                    color: t.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _row(ThemeData t, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: Text(
              label,
              style: t.textTheme.bodySmall?.copyWith(
                color: t.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: t.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Απλό grid: οριζόντιο + κάθετο scroll, **χωρίς** zoom, χωρίς resize, χωρίς εμφάνιση schema.
///
/// [Scrollbar] δένει ρητά `ScrollController` (ίδιο με το κάθετο [SingleChildScrollView]) ώστε
/// να μην σπάει το paint σε αλλαγή μεγέθους παραθύρου / Windows (χωρίς `PrimaryScrollController`).
class _SimpleDataPreview extends StatefulWidget {
  const _SimpleDataPreview({required this.result});

  final TablePreviewResult result;

  @override
  State<_SimpleDataPreview> createState() => _SimpleDataPreviewState();
}

class _SimpleDataPreviewState extends State<_SimpleDataPreview> {
  final ScrollController _verticalScroll = ScrollController();
  final ScrollController _horizontalScroll = ScrollController();

  @override
  void dispose() {
    _verticalScroll.dispose();
    _horizontalScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          controller: _verticalScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _verticalScroll,
            primary: false,
            child: SingleChildScrollView(
              controller: _horizontalScroll,
              primary: false,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth,
                ),
                child: DataTable(
                  showCheckboxColumn: false,
                  columnSpacing: 8,
                  horizontalMargin: 8,
                  headingRowHeight: 40,
                  dataRowMaxHeight: 64,
                  columns: widget.result.columns
                      .map(
                        (c) => DataColumn(
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 64,
                              maxWidth: 180,
                            ),
                            child: Text(
                              c,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  rows: widget.result.rows.map((r) {
                    return DataRow(
                      cells: widget.result.columns.map((c) {
                        final v = r[c];
                        final s = v?.toString() ?? '';
                        return DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 64,
                              maxWidth: 220,
                            ),
                            child: Text(
                              s,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
