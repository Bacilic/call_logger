import 'package:flutter/material.dart';

import '../services/database_stats_service.dart';

/// Πλέγμα προεπισκόπησης πίνακα (Excel-like) με εικονικοποίηση: χτίζονται ΜΟΝΟ
/// οι ορατές γραμμές (ListView.builder με σταθερό ύψος), ελαφριά κελιά [Text]
/// μέσα σε [SelectionArea] για αντιγραφή, και σελιδοποίηση με ένδειξη «Χ από Ψ».
///
/// Η μεγέθυνση εφαρμόζεται στα πραγματικά μεγέθη διάταξης (πλάτη στηλών, ύψος
/// γραμμής, μέγεθος γραμματοσειράς) ώστε τα όρια κύλισης να μένουν σωστά.
class TablePreviewGrid extends StatefulWidget {
  const TablePreviewGrid({
    super.key,
    required this.tableKey,
    required this.columns,
    required this.rows,
    required this.zoom,
    this.totalRowCount,
    this.hasMoreRows = false,
    this.onLoadMoreRows,
  });

  /// Ταυτότητα πίνακα — σε αλλαγή της μηδενίζονται τα πλάτη στηλών.
  final String tableKey;

  final List<String> columns;
  final List<Map<String, dynamic>> rows;

  /// Μεγέθυνση προβολής 0.5–2.0 (1.0 = 100%).
  final double zoom;

  /// Συνολικές εγγραφές του πίνακα στη βάση (για την ένδειξη «Χ από Ψ»).
  final int? totalRowCount;

  /// Υπάρχουν κι άλλες εγγραφές πέρα από τις φορτωμένες;
  final bool hasMoreRows;

  /// Καλείται όταν η κύλιση πλησιάζει το τέλος και [hasMoreRows] είναι true.
  final VoidCallback? onLoadMoreRows;

  @override
  State<TablePreviewGrid> createState() => _TablePreviewGridState();
}

class _TablePreviewGridState extends State<TablePreviewGrid> {
  static const double _minColWidth = 60.0;
  static const double _maxColWidth = 500.0;
  static const double _cellPadding = 12.0;
  static const double _resizeHandleWidth = 8.0;

  /// Επιπλέον πλάτος ώστε το όνομα της στήλης να μην κόβεται (font metrics).
  static const double _headerWidthBuffer = 20.0;
  static const double _rowHeight = 40.0;
  static const double _headerHeight = 44.0;

  /// Πόσες γραμμές δειγματίζονται για τον υπολογισμό πλάτους στηλών.
  static const int _widthSampleRows = 60;

  /// Απόσταση (px) από το τέλος της κύλισης που πυροδοτεί φόρτωση σελίδας.
  static const double _loadMoreThreshold = 600.0;

  final ScrollController _verticalScrollController = ScrollController();

  /// Οδηγεί το οριζόντιο scroll του **πραγματικού** πίνακα.
  final ScrollController _horizontalScrollController = ScrollController();

  /// «Φάντασμα» controller για την ορατή οριζόντια μπάρα (κάτω του viewport).
  final ScrollController _ghostHScrollController = ScrollController();
  bool _hSyncing = false;

  /// Πλάτη στηλών ΧΩΡΙΣ μεγέθυνση — η κλιμάκωση εφαρμόζεται στο build.
  List<double> _columnWidths = [];
  bool _widthsInitialized = false;

  /// Συνολικό πλάτος διάταξης χωρίς μεγέθυνση (στήλη + χερούλι resize ανά στήλη).
  double get _totalTableLayoutWidth {
    if (_columnWidths.isEmpty) return 0;
    var sum = 0.0;
    for (final w in _columnWidths) {
      sum += w + _resizeHandleWidth;
    }
    return sum;
  }

  void _ensureColumnWidths(BuildContext context) {
    if (_widthsInitialized && _columnWidths.length == widget.columns.length) {
      return;
    }
    final theme = Theme.of(context);
    final headerStyle =
        theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600) ??
        const TextStyle(fontWeight: FontWeight.w600);
    final cellStyle = theme.textTheme.bodySmall ?? const TextStyle();

    final sample = widget.rows.length > _widthSampleRows
        ? widget.rows.sublist(0, _widthSampleRows)
        : widget.rows;
    final widths = <double>[];
    for (var c = 0; c < widget.columns.length; c++) {
      final colName = widget.columns[c];
      double w =
          _textWidth(colName, headerStyle) +
          _cellPadding * 2 +
          _headerWidthBuffer;
      for (final row in sample) {
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
    final width = painter.width;
    painter.dispose();
    return width;
  }

  String _cellText(dynamic value) {
    if (value == null) return '';
    if (value is DateTime) return value.toIso8601String();
    return value.toString();
  }

  @override
  void initState() {
    super.initState();
    _horizontalScrollController.addListener(_onTableHScroll);
    _ghostHScrollController.addListener(_onGhostHScroll);
    _verticalScrollController.addListener(_onVerticalScroll);
  }

  void _onTableHScroll() {
    if (_hSyncing || !_ghostHScrollController.hasClients) return;
    _hSyncing = true;
    final target = _horizontalScrollController.offset;
    if ((_ghostHScrollController.offset - target).abs() > 0.5) {
      _ghostHScrollController.jumpTo(target);
    }
    _hSyncing = false;
  }

  void _onGhostHScroll() {
    if (_hSyncing || !_horizontalScrollController.hasClients) return;
    _hSyncing = true;
    final target = _ghostHScrollController.offset;
    if ((_horizontalScrollController.offset - target).abs() > 0.5) {
      _horizontalScrollController.jumpTo(target);
    }
    _hSyncing = false;
  }

  void _onVerticalScroll() {
    if (!widget.hasMoreRows || widget.onLoadMoreRows == null) return;
    if (!_verticalScrollController.hasClients) return;
    final pos = _verticalScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - _loadMoreThreshold) {
      widget.onLoadMoreRows!();
    }
  }

  @override
  void didUpdateWidget(covariant TablePreviewGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tableKey != widget.tableKey) {
      _widthsInitialized = false;
    }
  }

  @override
  void dispose() {
    _horizontalScrollController.removeListener(_onTableHScroll);
    _ghostHScrollController.removeListener(_onGhostHScroll);
    _verticalScrollController.removeListener(_onVerticalScroll);
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _ghostHScrollController.dispose();
    super.dispose();
  }

  TextStyle? _scaledStyle(TextStyle? base, double zoom) {
    if (base == null) return null;
    if ((zoom - 1.0).abs() < 0.001) return base;
    return base.copyWith(fontSize: (base.fontSize ?? 14) * zoom);
  }

  Widget _buildHeaderRow(ThemeData theme, double zoom, BorderSide borderSide) {
    final headerStyle = _scaledStyle(
      theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      zoom,
    );
    return Container(
      height: _headerHeight * zoom,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(top: borderSide, bottom: borderSide),
      ),
      child: Row(
        children: List.generate(widget.columns.length, (c) {
          return SizedBox(
            width: (_columnWidths[c] + _resizeHandleWidth) * zoom,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(right: borderSide),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: _cellPadding * zoom,
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.columns[c],
                      style: headerStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      final newW = (_columnWidths[c] + details.delta.dx / zoom)
                          .clamp(_minColWidth, _maxColWidth);
                      _columnWidths[c] = newW;
                    });
                  },
                  behavior: HitTestBehavior.opaque,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: SizedBox(
                      width: _resizeHandleWidth * zoom,
                      child: Container(
                        color: theme.colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDataRow(
    BuildContext context,
    int index,
    double zoom,
    TextStyle? cellStyle,
    BorderSide borderSide,
  ) {
    final row = widget.rows[index];
    return Container(
      decoration: BoxDecoration(border: Border(bottom: borderSide)),
      child: Row(
        children: List.generate(widget.columns.length, (c) {
          final text = _cellText(row[widget.columns[c]]);
          return Container(
            width: (_columnWidths[c] + _resizeHandleWidth) * zoom,
            decoration: BoxDecoration(border: Border(right: borderSide)),
            padding: EdgeInsets.symmetric(horizontal: _cellPadding * zoom),
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              style: cellStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildLoadingRow(ThemeData theme, double zoom) {
    // FittedBox: σε στενούς πίνακες το πλάτος γραμμής μπορεί να μη χωρά το μήνυμα.
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16 * zoom,
              height: 16 * zoom,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Φόρτωση επόμενων εγγραφών…',
              style: _scaledStyle(theme.textTheme.bodySmall, zoom),
            ),
          ],
        ),
      ),
    );
  }

  String get _countLabel {
    final shown = widget.rows.length;
    final total = widget.totalRowCount;
    String fmt(int v) => DatabaseStatsService.formatIntegerEl(v);
    if (total == null) {
      return '${fmt(shown)} ${shown == 1 ? 'εγγραφή' : 'εγγραφές'}';
    }
    if (shown < total) {
      return 'Εμφανίζονται ${fmt(shown)} από ${fmt(total)} εγγραφές — '
          'η κύλιση προς τα κάτω φορτώνει τις επόμενες';
    }
    return '${fmt(total)} ${total == 1 ? 'εγγραφή' : 'εγγραφές'} (όλες)';
  }

  @override
  Widget build(BuildContext context) {
    _ensureColumnWidths(context);
    final theme = Theme.of(context);
    final zoom = widget.zoom;
    final cellStyle = _scaledStyle(theme.textTheme.bodySmall, zoom);
    final borderSide = BorderSide(
      color: theme.dividerColor.withValues(alpha: 0.5),
      width: 1,
    );
    final layoutWidth = _totalTableLayoutWidth * zoom;
    final rowExtent = _rowHeight * zoom;
    final extraLoadingRow = widget.hasMoreRows ? 1 : 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            Expanded(
              child: Scrollbar(
                controller: _verticalScrollController,
                thumbVisibility: true,
                trackVisibility: true,
                // Ο κάθετος scrollable (ListView) ζει ΜΕΣΑ στον οριζόντιο (depth 1).
                notificationPredicate: (n) => n.depth == 1,
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  primary: false,
                  child: SizedBox(
                    width: layoutWidth,
                    child: Column(
                      children: [
                        _buildHeaderRow(theme, zoom, borderSide),
                        Expanded(
                          child: SelectionArea(
                            child: ListView.builder(
                              controller: _verticalScrollController,
                              primary: false,
                              itemExtent: rowExtent,
                              itemCount: widget.rows.length + extraLoadingRow,
                              itemBuilder: (context, index) {
                                if (index >= widget.rows.length) {
                                  return _buildLoadingRow(theme, zoom);
                                }
                                return _buildDataRow(
                                  context,
                                  index,
                                  zoom,
                                  cellStyle,
                                  borderSide,
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Ghost οριζόντια μπάρα: σταθερή θέση κάτω, συγχρονισμένη με τον πίνακα.
            if (layoutWidth > constraints.maxWidth)
              SizedBox(
                height: 14,
                child: Scrollbar(
                  controller: _ghostHScrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  child: SingleChildScrollView(
                    controller: _ghostHScrollController,
                    scrollDirection: Axis.horizontal,
                    primary: false,
                    child: SizedBox(height: 14, width: layoutWidth),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _countLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
