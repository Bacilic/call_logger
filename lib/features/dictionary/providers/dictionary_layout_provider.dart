import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/dictionary_repository.dart';
import '../dictionary_table_layout.dart';

/// Προεπιλεγμένο layout μέχρι τον πρώτο υπολογισμό.
const kDictionaryLayoutFallback = DictionaryTableLayout(
  wordWidth: kLexiconWordColumnMin,
  sourceWidth: 72,
  categoryWidth: 80,
);

/// Cache αποτελέσματος layout πίνακα λεξικού (πολλαπλές ομάδες στηλών).
@immutable
class DictionaryLayoutState {
  const DictionaryLayoutState({
    this.tableLayout = kDictionaryLayoutFallback,
    this.groupLayouts = const [kDictionaryLayoutFallback],
    this.columnsCount = 1,
    this.scrollWidth = 0,
    this.gridRowCount = 0,
    this.viewportWidth = 0,
    this.viewportHeight = 0,
  });

  /// Κοινό layout πηγής/κατηγορίας + βάση πλάτους λέξης.
  final DictionaryTableLayout tableLayout;
  final List<DictionaryTableLayout> groupLayouts;
  final int columnsCount;
  final double scrollWidth;
  final int gridRowCount;
  final double viewportWidth;
  final double viewportHeight;

  /// Εφαρμογή προσωρινών πλατών από σύρσιμο λαβής (χωρίς επανυπολογισμό provider).
  List<DictionaryTableLayout> groupLayoutsWithLiveDrag(
    List<double?> liveDragWidths,
  ) {
    return List.generate(groupLayouts.length, (groupIndex) {
      final live = groupIndex < liveDragWidths.length
          ? liveDragWidths[groupIndex]
          : null;
      if (live == null) return groupLayouts[groupIndex];
      final wordWidth = live.clamp(kLexiconWordColumnMin, kLexiconWordColumnMax);
      final base = groupLayouts[groupIndex];
      return DictionaryTableLayout(
        wordWidth: wordWidth,
        sourceWidth: base.sourceWidth,
        categoryWidth: base.categoryWidth,
      );
    });
  }

  double effectiveScrollWidth(List<DictionaryTableLayout> layouts) {
    final total = lexiconGroupsTotalWidth(layouts, columnsCount);
    return math.max(viewportWidth, total);
  }
}

/// Notifier layout πίνακα λεξικού — επανυπολογίζει μόνο όταν αλλάζουν rows ή constraints.
class DictionaryLayoutNotifier extends Notifier<DictionaryLayoutState> {
  List<Map<String, dynamic>>? _rows;
  double? _viewportWidth;
  double? _viewportHeight;
  int? _columnGroups;
  List<double?>? _userWordWidths;
  DictionaryLayoutMetrics? _metrics;

  @override
  DictionaryLayoutState build() => const DictionaryLayoutState();

  /// Υπολογισμός layout· no-op αν δεν άλλαξαν είσοδοι (αποφυγή jank σε scroll/rebuild).
  void calculateLayout({
    required List<Map<String, dynamic>> rows,
    required double viewportWidth,
    required double viewportHeight,
    required int? columnGroups,
    required List<double?> userWordColumnWidths,
    required DictionaryLayoutMetrics metrics,
  }) {
    if (identical(_rows, rows) &&
        _viewportWidth == viewportWidth &&
        _viewportHeight == viewportHeight &&
        _columnGroups == columnGroups &&
        listEquals(_userWordWidths, userWordColumnWidths) &&
        _metrics == metrics) {
      return;
    }

    _rows = rows;
    _viewportWidth = viewportWidth;
    _viewportHeight = viewportHeight;
    _columnGroups = columnGroups;
    _userWordWidths = userWordColumnWidths;
    _metrics = metrics;

    final tableLayout = _computeTableLayout(
      metrics: metrics,
      rows: rows,
    );
    final autoColumns = math.max(
      1,
      (viewportWidth + kLexiconGroupSeparatorWidth) ~/
          (tableLayout.baseTotal + kLexiconGroupSeparatorWidth),
    );
    final columnsCount = columnGroups == null
        ? autoColumns
        : math.min(kLexiconMaxColumnGroups, math.max(1, columnGroups));
    final groupLayouts = computeLexiconGroupLayouts(
      metrics: metrics,
      rowsForLayout: rows,
      sharedLayout: tableLayout,
      columnsCount: columnsCount,
      userWordColumnWidths: userWordColumnWidths,
    );
    final totalWidthNeeded = lexiconGroupsTotalWidth(groupLayouts, columnsCount);
    final scrollWidth = math.max(viewportWidth, totalWidthNeeded);
    final gridRowCount =
        columnsCount == 0 ? 0 : (rows.length / columnsCount).ceil();

    state = DictionaryLayoutState(
      tableLayout: tableLayout,
      groupLayouts: groupLayouts,
      columnsCount: columnsCount,
      scrollWidth: scrollWidth,
      gridRowCount: gridRowCount,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
    );
  }

  /// Λογική [computeDictionaryTableLayout] — πλάτη στηλών από δεδομένα σελίδας.
  DictionaryTableLayout _computeTableLayout({
    required DictionaryLayoutMetrics metrics,
    required List<Map<String, dynamic>> rows,
  }) {
    const padSrc = 16.0;
    const padCat = 16.0;

    var wWord = computeLexiconWordColumnWidth(
      metrics: metrics,
      rows: rows,
    );
    var wSrc = dictionaryMeasureTextWidth('Πηγή', metrics.headerStyle) + padSrc;
    var wCat =
        dictionaryMeasureTextWidth('Κατηγορία', metrics.headerStyle) + padCat;

    for (final r in rows) {
      final src = r['src'] as String? ?? '';
      final cat = r['cat'] as String? ?? '';
      wSrc = math.max(
        wSrc,
        dictionaryMeasureTextWidth(
              DictionaryRepository.lexiconSourceUiLabel(src),
              metrics.smallStyle,
            ) +
            padSrc,
      );
      wCat = math.max(
        wCat,
        dictionaryMeasureTextWidth(cat, metrics.catCellStyle) + padCat,
      );
    }

    wSrc = wSrc.clamp(72.0, 220.0);
    wCat = wCat.clamp(80.0, 280.0);

    return DictionaryTableLayout(
      wordWidth: wWord,
      sourceWidth: wSrc,
      categoryWidth: wCat,
    );
  }
}

/// Provider layout λεξικού — cached, χωρίς επανυπολογισμό κατά την κύλιση.
final dictionaryLayoutProvider =
    NotifierProvider<DictionaryLayoutNotifier, DictionaryLayoutState>(
  DictionaryLayoutNotifier.new,
);
