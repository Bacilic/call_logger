import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/database/dictionary_repository.dart';
import 'widgets/dictionary_grid_row.dart';

const kLexiconWordColumnMin = 88.0;
const kLexiconWordColumnMax = 2000.0;
const kLexiconMaxColumnGroups = 4;
const kLexiconGroupSeparatorWidth = 3.0;

/// Στυλ κειμένου για μέτρηση πλατών στηλών (χωρίς [BuildContext] στο provider).
class DictionaryLayoutMetrics {
  const DictionaryLayoutMetrics({
    required this.headerStyle,
    required this.wordFieldStyle,
    required this.smallStyle,
    required this.catCellStyle,
  });

  final TextStyle headerStyle;
  final TextStyle wordFieldStyle;
  final TextStyle smallStyle;
  final TextStyle catCellStyle;

  factory DictionaryLayoutMetrics.fromContext(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ) ??
        const TextStyle(fontWeight: FontWeight.w600, fontSize: 14);
    final wordFieldStyle =
        theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16);
    final smallStyle = theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    return DictionaryLayoutMetrics(
      headerStyle: headerStyle,
      wordFieldStyle: wordFieldStyle,
      smallStyle: smallStyle,
      catCellStyle: smallStyle,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DictionaryLayoutMetrics &&
          _styleEqual(headerStyle, other.headerStyle) &&
          _styleEqual(wordFieldStyle, other.wordFieldStyle) &&
          _styleEqual(smallStyle, other.smallStyle) &&
          _styleEqual(catCellStyle, other.catCellStyle);

  @override
  int get hashCode => Object.hash(
        _styleHash(headerStyle),
        _styleHash(wordFieldStyle),
        _styleHash(smallStyle),
        _styleHash(catCellStyle),
      );
}

bool _styleEqual(TextStyle a, TextStyle b) =>
    a.fontSize == b.fontSize &&
    a.fontWeight == b.fontWeight &&
    a.fontFamily == b.fontFamily &&
    a.letterSpacing == b.letterSpacing;

int _styleHash(TextStyle s) =>
    Object.hash(s.fontSize, s.fontWeight, s.fontFamily, s.letterSpacing);

/// Πλάτη στηλών πίνακα λεξικού (τρέχουσα σελίδα + επικεφαλίδες).
class DictionaryTableLayout {
  const DictionaryTableLayout({
    required this.wordWidth,
    required this.sourceWidth,
    required this.categoryWidth,
    this.actionsWidth = kDictionaryGridActionsWidth,
  });

  final double wordWidth;
  final double sourceWidth;
  final double categoryWidth;
  final double actionsWidth;

  double get baseTotal =>
      wordWidth +
      kDictionaryWordColumnResizeHandleWidth +
      sourceWidth +
      categoryWidth +
      actionsWidth;
}

double dictionaryMeasureTextWidth(String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout(minWidth: 0, maxWidth: double.infinity);
  return tp.width;
}

/// Μόνο πλάτος στήλης «Λέξη» από τις δοσμένες γραμμές (επικεφαλίδα + περιεχόμενο).
double computeLexiconWordColumnWidth({
  BuildContext? context,
  DictionaryLayoutMetrics? metrics,
  required List<Map<String, dynamic>> rows,
  double min = kLexiconWordColumnMin,
  double max = kLexiconWordColumnMax,
}) {
  final m = metrics ?? DictionaryLayoutMetrics.fromContext(context!);
  const padWord = 26.0;

  var wWord = dictionaryMeasureTextWidth('Λέξη', m.headerStyle) + padWord;
  for (final r in rows) {
    final dw = r['display_word'] as String? ?? '';
    wWord = math.max(
      wWord,
      dictionaryMeasureTextWidth(dw, m.wordFieldStyle) + padWord,
    );
  }
  return wWord.clamp(min, max);
}

/// Γραμμές που ανήκουν σε μία οπτική ομάδα στηλών (κατανομή εφημερίδας).
List<Map<String, dynamic>> lexiconRowsForColumnGroup({
  required List<Map<String, dynamic>> rows,
  required int groupIndex,
  required int columnsCount,
}) {
  if (columnsCount < 1 || groupIndex < 0 || groupIndex >= columnsCount) {
    return const [];
  }
  final out = <Map<String, dynamic>>[];
  for (var i = groupIndex; i < rows.length; i += columnsCount) {
    out.add(rows[i]);
  }
  return out;
}

/// Υπολογίζει πλάτη από τα δεδομένα της σελίδας· επιπλέον πλάτος viewport
/// δίνεται στη στήλη «Λέξη».
DictionaryTableLayout computeDictionaryTableLayout({
  BuildContext? context,
  DictionaryLayoutMetrics? metrics,
  required List<Map<String, dynamic>> rows,
  required double viewportWidth,
}) {
  final m = metrics ?? DictionaryLayoutMetrics.fromContext(context!);

  const padSrc = 16.0;
  const padCat = 16.0;

  var wWord = computeLexiconWordColumnWidth(
    metrics: m,
    rows: rows,
  );
  var wSrc = dictionaryMeasureTextWidth('Πηγή', m.headerStyle) + padSrc;
  var wCat = dictionaryMeasureTextWidth('Κατηγορία', m.headerStyle) + padCat;

  for (final r in rows) {
    final src = r['src'] as String? ?? '';
    final cat = r['cat'] as String? ?? '';
    wSrc = math.max(
      wSrc,
      dictionaryMeasureTextWidth(
            DictionaryRepository.lexiconSourceUiLabel(src),
            m.smallStyle,
          ) +
          padSrc,
    );
    wCat = math.max(
      wCat,
      dictionaryMeasureTextWidth(cat, m.catCellStyle) + padCat,
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

/// Πλάτη ανά οπτική ομάδα στηλών (κατανομή εφημερίδας).
List<DictionaryTableLayout> computeLexiconGroupLayouts({
  required DictionaryLayoutMetrics metrics,
  required List<Map<String, dynamic>> rowsForLayout,
  required DictionaryTableLayout sharedLayout,
  required int columnsCount,
  required List<double?> userWordColumnWidths,
}) {
  return List.generate(columnsCount, (groupIndex) {
    final groupRows = lexiconRowsForColumnGroup(
      rows: rowsForLayout,
      groupIndex: groupIndex,
      columnsCount: columnsCount,
    );
    final autoWord = groupRows.isEmpty
        ? sharedLayout.wordWidth
        : computeLexiconWordColumnWidth(
            metrics: metrics,
            rows: groupRows,
          );
    final userWord = groupIndex < userWordColumnWidths.length
        ? userWordColumnWidths[groupIndex]
        : null;
    final wordWidth = (userWord ?? autoWord).clamp(
      kLexiconWordColumnMin,
      kLexiconWordColumnMax,
    );
    return DictionaryTableLayout(
      wordWidth: wordWidth,
      sourceWidth: sharedLayout.sourceWidth,
      categoryWidth: sharedLayout.categoryWidth,
    );
  });
}

double lexiconGroupsTotalWidth(
  List<DictionaryTableLayout> groupLayouts,
  int columnsCount, {
  double groupSeparatorWidth = kLexiconGroupSeparatorWidth,
}) {
  if (columnsCount <= 0 || groupLayouts.length < columnsCount) return 0;
  var total = 0.0;
  for (var g = 0; g < columnsCount; g++) {
    total += groupLayouts[g].baseTotal;
  }
  if (columnsCount > 1) {
    total += (columnsCount - 1) * groupSeparatorWidth;
  }
  return total;
}

/// Πλάτος dropdown ώστε να χωράει το μεγαλύτερο στοιχείο + βέλος.
double computeDropdownMenuWidth(
  BuildContext context,
  List<String> labels, {
  double trailingPadding = 36,
}) {
  final style = Theme.of(context).textTheme.bodyLarge ?? const TextStyle(fontSize: 16);
  var m = 0.0;
  for (final s in labels) {
    m = math.max(m, dictionaryMeasureTextWidth(s, style));
  }
  return (m + trailingPadding).clamp(64.0, 360.0);
}
