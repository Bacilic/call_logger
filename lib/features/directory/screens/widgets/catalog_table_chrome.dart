// Ο σκελετός των πινάκων καταλόγου (Υπάλληλοι, Τμήματα, Εξοπλισμός,
// Κατηγορίες): σταθερή κεφαλίδα με ταξινόμηση, λαβή πλάτους στήλης και γραμμή
// σελιδοποίησης. Κάθε πίνακας κρατά μόνο τις στήλες και τα κελιά του.

import 'package:flutter/material.dart';

import '../../../../core/widgets/row_navigation_logic.dart';

/// Η σταθερή κεφαλίδα του πίνακα: ετικέτες στηλών, βελάκι ταξινόμησης στη
/// στήλη [sortedIndex] (`-1` όταν καμία) και λαβή πλάτους δεξιά από κάθε στήλη.
class CatalogStickyHeader extends StatelessWidget {
  const CatalogStickyHeader({
    super.key,
    required this.columns,
    required this.headingHeight,
    required this.headingColor,
    required this.headingTextStyle,
    required this.columnWidths,
    required this.sortedIndex,
    required this.sortAscending,
    required this.onResizeColumn,
  });

  final List<DataColumn> columns;
  final double headingHeight;
  final Color? headingColor;
  final TextStyle headingTextStyle;
  final Map<int, TableColumnWidth> columnWidths;
  final int sortedIndex;
  final bool sortAscending;

  /// Τράβηγμα της λαβής της στήλης [index] κατά [delta] pixel.
  final void Function(int index, double delta) onResizeColumn;

  @override
  Widget build(BuildContext context) {
    final asc = sortAscending;
    return Table(
      columnWidths: columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(
            color:
                headingColor ??
                Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          children: [
            for (var i = 0; i < columns.length; i++)
              TableCell(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: columns[i].onSort != null
                              ? () => columns[i].onSort!(
                                  0,
                                  i == sortedIndex ? !asc : true,
                                )
                              : null,
                          child: Container(
                            height: headingHeight,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Expanded(
                                  child: DefaultTextStyle(
                                    style: headingTextStyle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    child: columns[i].label,
                                  ),
                                ),
                                if (i == sortedIndex) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    asc
                                        ? Icons.arrow_drop_up
                                        : Icons.arrow_drop_down,
                                    size: 18,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    CatalogColumnResizeHandle(
                      onResize: (delta) => onResizeColumn(i, delta),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Η λαβή πλάτους στήλης: λεπτή γραμμή που φωτίζεται όταν περνά ή σέρνει το
/// ποντίκι.
class CatalogColumnResizeHandle extends StatefulWidget {
  const CatalogColumnResizeHandle({super.key, required this.onResize});

  final void Function(double delta) onResize;

  @override
  State<CatalogColumnResizeHandle> createState() =>
      _CatalogColumnResizeHandleState();
}

class _CatalogColumnResizeHandleState extends State<CatalogColumnResizeHandle> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showActive = _isHovered || _isDragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _isDragging = true),
        onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
        onHorizontalDragCancel: () => setState(() => _isDragging = false),
        onHorizontalDragUpdate: (details) => widget.onResize(details.delta.dx),
        child: SizedBox(
          width: 12,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 2,
              height: showActive ? 26 : 18,
              decoration: BoxDecoration(
                color: showActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Η γραμμή σελιδοποίησης: «Πρώτη / Προηγούμενη · 16–30 από 42 · Επόμενη /
/// Τελευταία». Η σελίδα αρχίζει από τη γραμμή [firstRowIndex]· κάθε κουμπί
/// ζητά νέα αρχή μέσω [onFirstRowIndexChanged].
class CatalogPaginationBar extends StatelessWidget {
  const CatalogPaginationBar({
    super.key,
    required this.rowCount,
    required this.firstRowIndex,
    required this.pageSize,
    required this.onFirstRowIndexChanged,
  });

  final int rowCount;
  final int firstRowIndex;
  final int pageSize;
  final ValueChanged<int> onFirstRowIndexChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = rowCount;
    if (n == 0) {
      return Material(
        color: theme.colorScheme.surfaceContainerLowest,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Center(
            child: Text(
              '0 από 0',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }
    final start = firstRowIndex;
    final end = (start + pageSize).clamp(0, n);
    final last = lastPageStart(count: n, pageSize: pageSize);
    final next = nextPageStart(start: start, count: n, pageSize: pageSize);

    void goFirst() => onFirstRowIndexChanged(0);
    void goPrev() => onFirstRowIndexChanged(
      previousPageStart(start: start, count: n, pageSize: pageSize),
    );
    void goNext() {
      if (next != null) onFirstRowIndexChanged(next);
    }

    void goLast() => onFirstRowIndexChanged(last);

    return Theme(
      data: theme.copyWith(
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: const Size(32, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.all(4),
            visualDensity: VisualDensity.compact,
            iconSize: 20,
          ),
        ),
      ),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.65,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Πρώτη σελίδα',
                icon: const Icon(Icons.first_page),
                onPressed: start > 0 ? goFirst : null,
              ),
              IconButton(
                tooltip: 'Προηγούμενη',
                icon: const Icon(Icons.chevron_left),
                onPressed: start > 0 ? goPrev : null,
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '${start + 1}–$end από $n',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Επόμενη',
                icon: const Icon(Icons.chevron_right),
                onPressed: end < n ? goNext : null,
              ),
              IconButton(
                tooltip: 'Τελευταία σελίδα',
                icon: const Icon(Icons.last_page),
                onPressed: end < n ? goLast : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
