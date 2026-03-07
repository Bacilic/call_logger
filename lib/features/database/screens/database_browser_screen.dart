import 'package:flutter/material.dart';

import '../../../core/database/database_helper.dart';

/// Οθόνη Βάσης Δεδομένων: λίστα πινάκων και προεπισκόπηση σε μορφή πίνακα (Excel-like).
class DatabaseBrowserScreen extends StatefulWidget {
  const DatabaseBrowserScreen({super.key});

  @override
  State<DatabaseBrowserScreen> createState() => _DatabaseBrowserScreenState();
}

class _DatabaseBrowserScreenState extends State<DatabaseBrowserScreen> {
  List<String> _tableNames = [];
  bool _loading = true;
  String? _error;
  String? _selectedTable;
  TablePreviewResult? _preview;
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
    });
    try {
      final names = await DatabaseHelper.instance.getTableNames();
      if (mounted) {
        setState(() {
          _tableNames = names;
          _loading = false;
        });
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
      _previewLoading = true;
    });
    try {
      final result = await DatabaseHelper.instance.getTablePreview(tableName);
      if (mounted) {
        setState(() {
          _preview = result;
          _previewLoading = false;
        });
      }
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
    });
  }

  @override
  Widget build(BuildContext context) {
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall,
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Πίσω στη λίστα πινάκων',
                  onPressed: _clearSelection,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Πίνακας: $_selectedTable',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _previewLoading
                ? const Center(child: CircularProgressIndicator())
                : _preview == null || _preview!.columns.isEmpty
                    ? Center(
                        child: Text(
                          'Δεν υπάρχουν στήλες ή δεδομένα.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      )
                    : _TablePreviewGrid(preview: _preview!),
          ),
        ],
      );
    }

    // Λίστα πινάκων
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _tableNames.length,
      itemBuilder: (context, index) {
        final name = _tableNames[index];
        return ListTile(
          leading: const Icon(Icons.table_chart),
          title: Text(name),
          subtitle: const Text('Πάτα για προεπισκόπηση'),
          onTap: () => _selectTable(name),
        );
      },
    );
  }
}

/// Πλέγμα προεπισκόπησης πίνακα (Excel-like): πλάτη από περιεχόμενο, ονόματα στηλών ολόκληρα, ευμετάβλητα πλάτη (resize).
class _TablePreviewGrid extends StatefulWidget {
  const _TablePreviewGrid({required this.preview});

  final TablePreviewResult preview;

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

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
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
        ),
      ),
    );
  }
}
